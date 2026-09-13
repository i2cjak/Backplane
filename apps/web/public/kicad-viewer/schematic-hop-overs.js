const epsilon = 1e-6;
const key = (point) => `${Math.round(point.x / epsilon)},${Math.round(point.y / epsilon)}`;

// Only interior orthogonal crossings get a bridge. Endpoints and explicit
// junctions keep their original geometry and electrical meaning.
export function schematicHopPaths(schematic) {
  const blocked = new Set();
  const horizontal = [];
  const vertical = [];
  for (const junction of schematic.junctions ?? []) blocked.add(key(junction.at.position));
  for (const wire of schematic.wires ?? []) {
    const points = wire.pts ?? [];
    for (const point of points) blocked.add(key(point));
    for (let index = 1; index < points.length; index++) {
      const a = points[index - 1];
      const b = points[index];
      if (Math.abs(a.y - b.y) < epsilon && Math.abs(a.x - b.x) > epsilon)
        horizontal.push({ wire, index, a, b, min: Math.min(a.x, b.x), max: Math.max(a.x, b.x) });
      else if (Math.abs(a.x - b.x) < epsilon && Math.abs(a.y - b.y) > epsilon)
        vertical.push({ x: a.x, min: Math.min(a.y, b.y), max: Math.max(a.y, b.y) });
    }
  }
  vertical.sort((a, b) => a.x - b.x);
  const paths = new Map();
  for (const segment of horizontal) {
    let low = 0;
    let high = vertical.length;
    while (low < high) {
      const mid = (low + high) >>> 1;
      if (vertical[mid].x <= segment.min + epsilon) low = mid + 1;
      else high = mid;
    }
    const crossings = new Set();
    for (let index = low; index < vertical.length; index++) {
      const other = vertical[index];
      if (other.x >= segment.max - epsilon) break;
      const point = { x: other.x, y: segment.a.y };
      if (
        point.y > other.min + epsilon &&
        point.y < other.max - epsilon &&
        !blocked.has(key(point))
      )
        crossings.add(point.x);
    }
    if (!crossings.size) continue;
    const xs = [...crossings].sort((a, b) => a - b);
    const points = [];
    for (let index = 0; index < xs.length; index++) {
      const x = xs[index];
      const radius = Math.min(
        0.635,
        (x - (xs[index - 1] ?? segment.min)) / 3,
        ((xs[index + 1] ?? segment.max) - x) / 3,
      );
      // A short polyline uses the renderer's existing wire primitive and hit
      // boxes. It replaces the straight segment instead of covering a wire.
      for (let step = 0; step <= 12; step++) {
        const angle = Math.PI - (step * Math.PI) / 12;
        const point = segment.a.copy();
        point.set(x + Math.cos(angle) * radius, segment.a.y - Math.sin(angle) * radius);
        points.push(point);
      }
    }
    if (segment.a.x > segment.b.x) points.reverse();
    let segments = paths.get(segment.wire);
    if (!segments) paths.set(segment.wire, (segments = new Map()));
    segments.set(segment.index, points);
  }
  const result = new Map();
  for (const [wire, segments] of paths) {
    const points = [wire.pts[0]];
    for (let index = 1; index < wire.pts.length; index++)
      points.push(...(segments.get(index) ?? []), wire.pts[index]);
    result.set(wire, points);
  }
  return result;
}

export function installSchematicHopOvers(core) {
  if (!core?.schematic || core.__backplaneHopOvers) return false;
  const createPainter = core.create_painter.bind(core);
  core.create_painter = (...args) => {
    const painter = createPainter(...args);
    const paths = schematicHopPaths(core.schematic);
    const wirePainters = new Set();
    for (const wire of paths.keys()) {
      const wirePainter = painter.painters.get(wire.constructor);
      if (!wirePainter || wirePainters.has(wirePainter)) continue;
      wirePainters.add(wirePainter);
      const paint = wirePainter.paint.bind(wirePainter);
      wirePainter.paint = (layer, item) => {
        const points = paths.get(item);
        if (!points) return paint(layer, item);
        const proxy = Object.create(item);
        proxy.pts = points;
        return paint(layer, proxy);
      };
    }
    return painter;
  };
  core.__backplaneHopOvers = true;
  return true;
}
