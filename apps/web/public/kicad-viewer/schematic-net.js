/*
 * Electrical connectivity for the mature schematic model.
 *
 * Connectivity is derived from wire segments and transformed pin anchors. A
 * bbox is presentation data and is intentionally never used here: it can
 * include the symbol body, fields, or the wrong sheet instance.
 */

const LABEL_TYPES = new Set([
  "Label",
  "NetLabel",
  "GlobalLabel",
  "HierarchicalLabel",
  "HierarchicalSheetPin",
]);
const EPSILON = 1e-6;

function typeName(item) {
  return item?.typeId ?? item?.constructor?.name ?? "";
}

function pointKey(point) {
  return point && Number.isFinite(point.x) && Number.isFinite(point.y)
    ? `${Math.round(point.x * 10000)}:${Math.round(point.y * 10000)}`
    : undefined;
}

function asPoint(point) {
  return point && Number.isFinite(point.x) && Number.isFinite(point.y)
    ? { x: point.x, y: point.y }
    : undefined;
}

function pointOnSegment(point, start, end) {
  const p = asPoint(point);
  const a = asPoint(start);
  const b = asPoint(end);
  if (!p || !a || !b) return false;
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const length = Math.hypot(dx, dy);
  if (length <= EPSILON) return pointKey(p) === pointKey(a);
  if (Math.abs((p.x - a.x) * dy - (p.y - a.y) * dx) > EPSILON * length) return false;
  return (
    p.x >= Math.min(a.x, b.x) - EPSILON &&
    p.x <= Math.max(a.x, b.x) + EPSILON &&
    p.y >= Math.min(a.y, b.y) - EPSILON &&
    p.y <= Math.max(a.y, b.y) + EPSILON
  );
}

function itemLabel(item) {
  if (LABEL_TYPES.has(typeName(item))) return String(item.text ?? item.name ?? "").trim();
  return undefined;
}

function transformPoint(transform, point) {
  if (!point) return undefined;
  if (typeof transform?.transform === "function") return asPoint(transform.transform(point));
  if (typeof transform?.transform_point === "function")
    return asPoint(transform.transform_point(point));
  return asPoint(point);
}

function pinAnchor(pin) {
  const local = pin?.definition?.at?.position;
  if (!local) return undefined;
  return transformPoint(pin.parent?.get_symbol_transform?.(), local);
}

function symbolPins(symbol) {
  const pins = symbol?.unit_pins ?? symbol?.pins ?? [];
  return [...pins].filter((pin) => pin?.definition?.at?.position);
}

function isWire(item) {
  return typeName(item) === "Wire" && Array.isArray(item.pts) && item.pts.length > 1;
}

function isJunction(item) {
  return typeName(item) === "Junction" && Boolean(item.at?.position);
}

function isPowerSymbol(item) {
  return Boolean(item?.lib_symbol?.power) && symbolPins(item).length > 0;
}

function powerName(symbol) {
  const value = String(symbol?.value ?? "").trim();
  const libraryName = String(symbol?.lib_symbol?.library_item_name ?? "").trim();
  if (/^(?:PWR_FLAG|#FLG)/i.test(value) || /^(?:PWR_FLAG|#FLG)/i.test(libraryName))
    return undefined;
  if (value) return value;
  return libraryName || undefined;
}

class UnionFind {
  constructor(items) {
    this.parent = new Map(items.map((item) => [item, item]));
  }

  find(item) {
    let root = this.parent.get(item);
    if (root === undefined) return undefined;
    while (this.parent.get(root) !== root) root = this.parent.get(root);
    let current = item;
    while (this.parent.get(current) !== current) {
      const next = this.parent.get(current);
      this.parent.set(current, root);
      current = next;
    }
    return root;
  }

  union(first, second) {
    const a = this.find(first);
    const b = this.find(second);
    if (a && b && a !== b) this.parent.set(a, b);
  }
}

function collectItems(schematic) {
  const items = [];
  const seen = new Set();
  const add = (item) => {
    if (!item || seen.has(item)) return;
    seen.add(item);
    items.push(item);
  };
  for (const item of schematic?.items?.() ?? []) {
    add(item);
    if (typeName(item) === "SchematicSymbol") for (const pin of symbolPins(item)) add(pin);
  }
  for (const symbol of schematic?.symbols?.values?.() ?? []) {
    add(symbol);
    for (const pin of symbolPins(symbol)) add(pin);
  }
  return items;
}

function makeGraph(schematic) {
  const all = collectItems(schematic);
  const wires = all.filter(isWire);
  const pins = all.filter((item) => Boolean(item?.definition?.at?.position));
  const labels = all.filter((item) => itemLabel(item) !== undefined);
  const junctions = all.filter(isJunction);
  const powerSymbols = all.filter(isPowerSymbol);
  const graphItems = [...new Set([...wires, ...pins, ...labels, ...junctions, ...powerSymbols])];
  const union = new UnionFind(graphItems);
  const segments = [];
  const vertices = [];
  for (const wire of wires) {
    for (const point of wire.pts) vertices.push({ item: wire, point });
    for (let index = 1; index < wire.pts.length; index++)
      segments.push({ item: wire, start: wire.pts[index - 1], end: wire.pts[index] });
  }

  // A shared endpoint or a wire endpoint on another segment is electrical.
  // Two segment interiors crossing without a marker never enter this loop.
  for (const vertex of vertices) {
    for (const segment of segments) {
      if (pointOnSegment(vertex.point, segment.start, segment.end))
        union.union(vertex.item, segment.item);
    }
  }

  const anchorItems = [
    ...pins.map((item) => ({ item, point: pinAnchor(item) })),
    ...labels.map((item) => ({ item, point: item.at?.position })),
    ...junctions.map((item) => ({ item, point: item.at?.position })),
  ];
  for (const anchor of anchorItems) {
    if (!anchor.point) continue;
    for (const segment of segments)
      if (pointOnSegment(anchor.point, segment.start, segment.end))
        union.union(anchor.item, segment.item);
  }

  // Pins, labels, and junctions can touch directly in a hand-edited or
  // converted schematic. Their shared anchor is electrical even without a
  // wire object between them.
  const anchorsByPoint = new Map();
  for (const anchor of anchorItems) {
    const key = pointKey(anchor.point);
    if (!key) continue;
    const group = anchorsByPoint.get(key) ?? [];
    group.push(anchor.item);
    anchorsByPoint.set(key, group);
  }
  for (const group of anchorsByPoint.values())
    for (let index = 1; index < group.length; index++) union.union(group[0], group[index]);

  // Power symbols are labels attached to their electrical pin anchor.
  for (const symbol of powerSymbols) {
    for (const pin of symbolPins(symbol)) union.union(symbol, pin);
  }

  const labelsByName = new Map();
  for (const label of labels) {
    const name = itemLabel(label);
    if (!name) continue;
    const group = labelsByName.get(name) ?? [];
    group.push(label);
    labelsByName.set(name, group);
  }
  for (const symbol of powerSymbols) {
    const name = powerName(symbol);
    if (!name) continue;
    const group = labelsByName.get(name) ?? [];
    group.push(symbol);
    labelsByName.set(name, group);
  }
  for (const group of labelsByName.values())
    for (let index = 1; index < group.length; index++) union.union(group[0], group[index]);

  return { all, wires, pins, labels, junctions, powerSymbols, union, labelsByName };
}

function selectedSeeds(graph, selection) {
  const seeds = new Set();
  const uuid = selection?.uuid;
  if (uuid) {
    for (const item of graph.all) if (item?.uuid === uuid) seeds.add(item);
  }
  const value = String(selection?.value ?? selection?.net ?? "").trim();
  if (value) {
    for (const item of graph.labels) if (itemLabel(item) === value) seeds.add(item);
    for (const item of graph.powerSymbols) if (powerName(item) === value) seeds.add(item);
  }
  return seeds;
}

export function collectSchematicNet(schematic, selection = {}) {
  const graph = makeGraph(schematic);
  const seeds = selectedSeeds(graph, selection);
  if (!seeds.size) return { items: new Set(), netName: undefined };
  const roots = new Set([...seeds].map((item) => graph.union.find(item)).filter(Boolean));
  const items = new Set();
  for (const item of [...graph.union.parent.keys()])
    if (roots.has(graph.union.find(item))) items.add(item);
  const names = [];
  for (const [name, labels] of graph.labelsByName) {
    if (labels.some((label) => items.has(label))) names.push(name);
  }
  const requested = String(selection?.value ?? selection?.net ?? "").trim();
  return { items, netName: requested || names.sort()[0] };
}

export function collectSchematicNetItems(schematic, selection = {}) {
  return collectSchematicNet(schematic, selection).items;
}

export { pointKey, pointOnSegment, pinAnchor };
