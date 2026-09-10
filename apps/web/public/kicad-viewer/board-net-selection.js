/*
 * Resolve the electrical item under a PCB click without trusting the viewer's
 * footprint bounding boxes. The compact viewer uses those boxes for fast
 * selection, but a large footprint can cover every nearby track. This resolver
 * walks the board's public pads, routes, vias, and zone polygons instead.
 */

function point(value) {
  return value && Number.isFinite(value.x) && Number.isFinite(value.y)
    ? { x: value.x, y: value.y }
    : undefined;
}

function distanceToSegment(p, a, b) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lengthSquared = dx * dx + dy * dy;
  if (!lengthSquared) return Math.hypot(p.x - a.x, p.y - a.y);
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared));
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

function arcPoints(start, mid, end) {
  const determinant =
    2 * (start.x * (mid.y - end.y) + mid.x * (end.y - start.y) + end.x * (start.y - mid.y));
  if (Math.abs(determinant) < 1e-9) return [start, end];
  const startSquared = start.x * start.x + start.y * start.y;
  const midSquared = mid.x * mid.x + mid.y * mid.y;
  const endSquared = end.x * end.x + end.y * end.y;
  const center = {
    x:
      (startSquared * (mid.y - end.y) +
        midSquared * (end.y - start.y) +
        endSquared * (start.y - mid.y)) /
      determinant,
    y:
      (startSquared * (end.x - mid.x) +
        midSquared * (start.x - end.x) +
        endSquared * (mid.x - start.x)) /
      determinant,
  };
  const radius = Math.hypot(start.x - center.x, start.y - center.y);
  const angle = (value) => Math.atan2(value.y - center.y, value.x - center.x);
  const normalize = (value) => (value + Math.PI * 2) % (Math.PI * 2);
  const startAngle = angle(start);
  const midAngle = angle(mid);
  const endAngle = angle(end);
  const ccw = normalize(endAngle - startAngle);
  const midCcw = normalize(midAngle - startAngle);
  const direction = midCcw <= ccw + 1e-7 ? 1 : -1;
  const sweep = direction === 1 ? ccw : normalize(startAngle - endAngle);
  const steps = Math.min(128, Math.max(4, Math.ceil((sweep * radius) / 0.25)));
  return Array.from({ length: steps + 1 }, (_, index) => {
    const current = startAngle + (direction * (sweep * index)) / steps;
    return { x: center.x + Math.cos(current) * radius, y: center.y + Math.sin(current) * radius };
  });
}

function distanceToPath(path, target) {
  let distance = Infinity;
  for (let index = 1; index < path.length; index++)
    distance = Math.min(distance, distanceToSegment(target, path[index - 1], path[index]));
  return distance;
}

function box(value) {
  if (!value) return undefined;
  if (Number.isFinite(value.x) && Number.isFinite(value.y)) {
    const width = Number(value.w ?? value.width);
    const height = Number(value.h ?? value.height);
    if (Number.isFinite(width) && Number.isFinite(height))
      return { x: value.x, y: value.y, width, height };
  }
  const topLeft = point(value.top_left);
  const bottomRight = point(value.bottom_right);
  if (topLeft && bottomRight)
    return {
      x: Math.min(topLeft.x, bottomRight.x),
      y: Math.min(topLeft.y, bottomRight.y),
      width: Math.abs(bottomRight.x - topLeft.x),
      height: Math.abs(bottomRight.y - topLeft.y),
    };
  return undefined;
}

function padHit(pad, target, tolerance) {
  const bounds = box(pad?.bbox);
  if (!bounds) return Infinity;
  const center = { x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 };
  if (pad.shape === "circle") {
    return Math.max(
      0,
      Math.hypot(target.x - center.x, target.y - center.y) -
        Math.min(bounds.width, bounds.height) / 2,
    );
  }
  if (pad.shape === "oval") {
    const rx = Math.max(bounds.width / 2, 1e-9);
    const ry = Math.max(bounds.height / 2, 1e-9);
    return (
      Math.max(0, Math.hypot((target.x - center.x) / rx, (target.y - center.y) / ry) - 1) *
      Math.min(rx, ry)
    );
  }
  const dx = Math.max(Math.abs(target.x - center.x) - bounds.width / 2, 0);
  const dy = Math.max(Math.abs(target.y - center.y) - bounds.height / 2, 0);
  return Math.hypot(dx, dy);
}

function pointInPolygon(target, points) {
  let inside = false;
  for (let index = 0, previous = points.length - 1; index < points.length; previous = index++) {
    const current = points[index];
    const prior = points[previous];
    if (
      current.y > target.y !== prior.y > target.y &&
      target.x <
        ((prior.x - current.x) * (target.y - current.y)) / (prior.y - current.y) + current.x
    )
      inside = !inside;
  }
  return inside;
}

function polygonHit(target, points, tolerance) {
  if (points.length < 3) return Infinity;
  if (pointInPolygon(target, points)) return 0;
  return distanceToPath([...points, points[0]], target) <= tolerance
    ? distanceToPath([...points, points[0]], target)
    : Infinity;
}

function typeName(item) {
  return item?.typeId ?? item?.constructor?.name ?? "";
}

function layersFor(item) {
  const result = [];
  if (typeof item?.layer === "string") result.push(item.layer);
  for (const layer of Array.isArray(item?.layers) ? item.layers : [])
    if (typeof layer === "string") result.push(layer);
  return [...new Set(result)];
}

function visibleOnLayer(board, item, options) {
  const names = layersFor(item);
  if (!names.length) return true;
  const visible = options.isLayerVisible ?? ((name) => options.visibleLayers?.has(name) ?? true);
  const expanded = names.flatMap((name) => {
    if (name !== "*.Cu" && name !== "F&B.Cu") return [name];
    return (board?.layers ?? [])
      .map((layer) => layer?.canonical_name)
      .filter((layer) => typeof layer === "string" && /\.Cu$/i.test(layer));
  });
  return expanded.some((name) => visible(name));
}

function netDetails(board, item) {
  const raw = item?.net;
  const code = typeof raw === "object" ? raw?.number : Number(raw);
  const netCode = Number.isFinite(code) ? code : Number(item?.net_code);
  if (!Number.isFinite(netCode) || netCode <= 0) return undefined;
  const name =
    (typeof raw === "object" && raw?.name) ||
    item?.net_name ||
    board?.getNetName?.(netCode) ||
    board?.nets?.find?.((net) => net?.number === netCode)?.name ||
    "";
  return { net: String(name), netName: String(name), netCode };
}

function candidate(board, item, kind, distance, priority) {
  const net = netDetails(board, item);
  return net && { ...net, item, kind, distance, priority };
}

function boardPads(board) {
  const result = [];
  const seen = new Set();
  for (const footprint of board?.footprints ?? []) {
    for (const pad of footprint?.pads ?? footprint?.items?.() ?? []) {
      if (typeName(pad) !== "Pad" || seen.has(pad)) continue;
      seen.add(pad);
      result.push(pad);
    }
  }
  return result;
}

function zonePolygons(zone) {
  return [...(zone?.filled_polygons ?? []), ...(zone?.polygons ?? [])]
    .map((polygon) => polygon?.points ?? polygon?.pts)
    .map((points) => (Array.isArray(points) ? points.map(point).filter(Boolean) : []))
    .filter((points) => points.length >= 3);
}

/** Return the physical board item carrying the electrical net at a world point. */
export function resolveBoardNetAtPoint(board, target, options = {}) {
  const pointTarget = point(target);
  if (!pointTarget) return undefined;
  const tolerance = Math.max(0, Number(options.tolerance ?? 0.15));
  const candidates = [];
  const add = (item, kind, distance, priority) => {
    const result = candidate(board, item, kind, distance, priority);
    if (result && distance <= tolerance + (Number(item?.width) || 0) / 2) candidates.push(result);
  };
  for (const segment of board?.segments ?? []) {
    if (!visibleOnLayer(board, segment, options)) continue;
    const start = point(segment.start);
    const end = point(segment.end);
    if (!start || !end) continue;
    const path =
      segment.typeId === "ArcSegment" && point(segment.mid)
        ? arcPoints(start, point(segment.mid), end)
        : [start, end];
    add(
      segment,
      segment.typeId === "ArcSegment" ? "arc" : "segment",
      distanceToPath(path, pointTarget),
      2,
    );
  }
  for (const via of board?.vias ?? []) {
    if (!visibleOnLayer(board, via, options)) continue;
    const center = point(via.at?.position ?? via.at);
    const radius = Number(via.size) / 2;
    if (center && Number.isFinite(radius))
      add(
        via,
        "via",
        Math.max(0, Math.hypot(pointTarget.x - center.x, pointTarget.y - center.y) - radius),
        1,
      );
  }
  for (const pad of boardPads(board)) {
    if (!visibleOnLayer(board, pad, options)) continue;
    add(pad, "pad", padHit(pad, pointTarget, tolerance), 0);
  }
  for (const zone of board?.zones ?? []) {
    if (!visibleOnLayer(board, zone, options)) continue;
    const distance = Math.min(
      ...zonePolygons(zone).map((polygon) => polygonHit(pointTarget, polygon, tolerance)),
    );
    if (Number.isFinite(distance)) add(zone, "zone", distance, 3);
  }
  // Selection is semantic before geometric. A filled zone contains most of
  // the board, so sorting by distance first made it win every time the click
  // was merely a fraction off a pad or track centreline. Keep distance as a
  // tie-breaker within a kind only.
  candidates.sort(
    (left, right) => left.priority - right.priority || left.distance - right.distance,
  );
  return candidates[0];
}
