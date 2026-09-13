import { describe, expect, it } from "vite-plus/test";

const { schematicHopPaths, installSchematicHopOvers } = await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}schematic-hop-overs.js`
);

class Point {
  constructor(
    public x: number,
    public y: number,
  ) {}
  copy() {
    return new Point(this.x, this.y);
  }
  set(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}
class Wire {
  pts: Point[];
  constructor(...points: [number, number][]) {
    this.pts = points.map(([x, y]) => new Point(x, y));
  }
}

describe("schematic hop overs", () => {
  it("replaces an unconnected crossing with a bridge without changing source points", () => {
    const wire = new Wire([0, 0], [10, 0]);
    const paths = schematicHopPaths({ wires: [wire, new Wire([5, -5], [5, 5])] });
    const path = paths.get(wire) as Point[];
    expect(path[0]).toEqual(new Point(0, 0));
    expect(path.at(-1)).toEqual(new Point(10, 0));
    expect(path.find((point) => Math.abs(point.x - 5) < 1e-6)?.y).toBeCloseTo(-0.635);
    expect(wire.pts).toEqual([new Point(0, 0), new Point(10, 0)]);
  });

  it("preserves junctions, T connections and crossings connected by a third endpoint", () => {
    const wires = [new Wire([0, 0], [10, 0]), new Wire([5, -5], [5, 5])];
    expect(
      schematicHopPaths({ wires, junctions: [{ at: { position: new Point(5, 0) } }] }).size,
    ).toBe(0);
    expect(schematicHopPaths({ wires: [wires[0], new Wire([5, 0], [5, 5])] }).size).toBe(0);
    expect(schematicHopPaths({ wires: [...wires, new Wire([5, 0], [7, 2])] }).size).toBe(0);
  });

  it("ignores disjoint, parallel, and diagonal segments", () => {
    const wire = new Wire([0, 0], [10, 0]);
    for (const other of [
      new Wire([12, -5], [12, 5]),
      new Wire([5, 1], [5, 5]),
      new Wire([0, 2], [10, 2]),
      new Wire([3, -2], [7, 2]),
    ])
      expect(schematicHopPaths({ wires: [wire, other] }).size).toBe(0);
  });

  it("keeps reversed wires and closely spaced bridges ordered", () => {
    const wire = new Wire([10, 0], [0, 0]);
    const path = schematicHopPaths({
      wires: [wire, new Wire([5, -5], [5, 5]), new Wire([5.2, -5], [5.2, 5])],
    }).get(wire) as Point[];
    expect(path.every((point, index) => index === 0 || point.x <= path[index - 1]!.x)).toBe(true);
  });

  it("rebuilds painter geometry after changing sheets or adding a junction", () => {
    const wire = new Wire([0, 0], [10, 0]);
    const painted: Wire[] = [];
    const schematic = {
      wires: [wire, new Wire([5, -5], [5, 5])],
      junctions: [] as { at: { position: Point } }[],
    };
    const core = {
      schematic,
      create_painter: () => ({
        painters: new Map([[Wire, { paint: (_layer: unknown, item: Wire) => painted.push(item) }]]),
      }),
    };
    expect(installSchematicHopOvers(core)).toBe(true);
    core.create_painter().painters.get(Wire)!.paint({}, wire);
    expect(painted[0]!.pts.length).toBeGreaterThan(2);
    schematic.junctions.push({ at: { position: new Point(5, 0) } });
    core.create_painter().painters.get(Wire)!.paint({}, wire);
    expect(painted[1]).toBe(wire);
    expect(installSchematicHopOvers(core)).toBe(false);
  });
});
