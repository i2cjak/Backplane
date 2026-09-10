import { expect, it } from "vite-plus/test";
const { resolveBoardNetAtPoint } = await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}board-net-selection.js`
);

const visibleCopper = new Set(["F.Cu"]);
const board = {
  nets: [
    { number: 1, name: "GND" },
    { number: 2, name: "/USB_D+" },
  ],
  layers: [{ canonical_name: "F.Cu" }, { canonical_name: "B.Cu" }],
  segments: [
    {
      typeId: "LineSegment",
      start: { x: 10, y: 10 },
      end: { x: 30, y: 10 },
      width: 0.2,
      layer: "F.Cu",
      net: 2,
    },
    {
      typeId: "ArcSegment",
      start: { x: 30, y: 10 },
      mid: { x: 35, y: 15 },
      end: { x: 40, y: 10 },
      width: 0.2,
      layer: "F.Cu",
      net: 2,
    },
    {
      typeId: "LineSegment",
      start: { x: 10, y: 10 },
      end: { x: 10, y: 20 },
      width: 0.2,
      layer: "B.Cu",
      net: 1,
    },
    {
      typeId: "LineSegment",
      start: { x: 50, y: 50 },
      end: { x: 60, y: 50 },
      width: 0.2,
      layer: "F.Cu",
      net: 0,
    },
  ],
  vias: [
    {
      typeId: "Via",
      at: { position: { x: 20, y: 10 } },
      size: 0.8,
      layers: ["F.Cu", "B.Cu"],
      net: 2,
    },
  ],
  footprints: [
    {
      typeId: "Footprint",
      bbox: { x: 0, y: 0, w: 100, h: 100 },
      pads: [
        {
          typeId: "Pad",
          shape: "circle",
          bbox: { x: 70, y: 70, w: 2, h: 2 },
          layers: ["F.Cu"],
          net: { number: 1, name: "GND" },
        },
      ],
    },
  ],
  zones: [
    {
      typeId: "Zone",
      layer: "F.Cu",
      polygons: [
        {
          points: [
            { x: 80, y: 80 },
            { x: 90, y: 80 },
            { x: 90, y: 90 },
            { x: 80, y: 90 },
          ],
        },
      ],
      net: 1,
    },
  ],
};

it("resolves tracks and arcs instead of a covering footprint bounding box", () => {
  expect(
    resolveBoardNetAtPoint(board, { x: 25, y: 10 }, { visibleLayers: visibleCopper })?.netName,
  ).toBe("/USB_D+");
  expect(
    resolveBoardNetAtPoint(board, { x: 35, y: 15 }, { visibleLayers: visibleCopper })?.kind,
  ).toBe("arc");
});

it("resolves a physical pad or zone geometry independently", () => {
  expect(
    resolveBoardNetAtPoint(board, { x: 71, y: 71 }, { visibleLayers: visibleCopper })?.kind,
  ).toBe("pad");
  expect(
    resolveBoardNetAtPoint(board, { x: 85, y: 85 }, { visibleLayers: visibleCopper })?.kind,
  ).toBe("zone");
  expect(
    resolveBoardNetAtPoint(board, { x: 95, y: 95 }, { visibleLayers: visibleCopper }),
  ).toBeUndefined();
});

it("ignores hidden-layer and unconnected geometry", () => {
  expect(
    resolveBoardNetAtPoint(board, { x: 10, y: 15 }, { visibleLayers: visibleCopper }),
  ).toBeUndefined();
  expect(
    resolveBoardNetAtPoint(board, { x: 55, y: 50 }, { visibleLayers: visibleCopper }),
  ).toBeUndefined();
});
