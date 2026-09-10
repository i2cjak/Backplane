import { describe, expect, it } from "vite-plus/test";

import {
  CAD_INSPECT_SURFACES,
  KICAD_INNER_TABS,
  KICAD_OPTIONAL_TABS,
  cadInspectLabelForKind,
  cadInspectOpenHint,
  cadInspectViewForKind,
  cadInspectViewerSearch,
  inspectSurfaceKind,
  isCadInspectKind,
  isSiblingInspectView,
  preferredInspectSolid,
  productInspectItems,
  productInspectSolids,
  productInspectStills,
  readViewerView,
  viewerHashView,
} from "./cadInspect.ts";

describe("cadInspect surfaces", () => {
  it("maps sibling panel kinds to inspect views without embedding them in KiCad tabs", () => {
    expect(cadInspectViewForKind("kicad")).toBe("pcb");
    expect(cadInspectViewForKind("freecad")).toBe("enclosure");
    expect(cadInspectViewForKind("blender")).toBe("product");
    expect(cadInspectViewForKind("terminal")).toBeUndefined();
  });

  it("exposes FreeCAD and Blender as labeled peers of KiCad", () => {
    expect(CAD_INSPECT_SURFACES.map((surface) => surface.kind)).toEqual([
      "kicad",
      "freecad",
      "blender",
    ]);
    expect(cadInspectLabelForKind("freecad")).toBe("FreeCAD");
    expect(cadInspectLabelForKind("blender")).toBe("Blender");
    expect(isCadInspectKind("kicad")).toBe(true);
    expect(isCadInspectKind("files")).toBe(false);
  });

  it("keeps FreeCAD and Blender out of the KiCad inner tab list", () => {
    expect(KICAD_INNER_TABS.map((tab) => tab.id)).toEqual([
      "schematic",
      "pcb",
      "3d",
      "gerbers",
      "step",
    ]);
    expect(KICAD_INNER_TABS.map((tab) => tab.label)).toEqual([
      "Schematic",
      "PCB",
      "3D",
      "Gerbers",
      "STEP",
    ]);
    expect(KICAD_OPTIONAL_TABS.map((tab) => tab.id)).toEqual([
      "bom",
      "footprint",
      "symbol",
      "analysis",
    ]);
    const labels = [...KICAD_INNER_TABS, ...KICAD_OPTIONAL_TABS].map((tab) => tab.label);
    expect(labels).not.toContain("FreeCAD");
    expect(labels).not.toContain("Blender");
    expect(isSiblingInspectView("enclosure")).toBe(true);
    expect(isSiblingInspectView("product")).toBe(true);
    expect(isSiblingInspectView("pcb")).toBe(false);
    expect(isSiblingInspectView("3d")).toBe(false);
    expect(inspectSurfaceKind("enclosure")).toBe("freecad");
    expect(inspectSurfaceKind("product")).toBe("blender");
    expect(inspectSurfaceKind("pcb")).toBe("kicad");
    expect(inspectSurfaceKind("step")).toBe("kicad");
  });

  it("keeps FreeCAD and Blender hash views instead of falling back to PCB", () => {
    expect(viewerHashView("enclosure")).toBe("enclosure");
    expect(viewerHashView("product")).toBe("product");
    expect(viewerHashView("pcb")).toBe("pcb");
    expect(viewerHashView("nope")).toBeUndefined();
  });

  it("reads sibling views from hash or search so switching panels does not reuse KiCad tabs", () => {
    expect(readViewerView("#view=enclosure")).toBe("enclosure");
    expect(readViewerView("#view=product")).toBe("product");
    expect(readViewerView("", "?view=enclosure")).toBe("enclosure");
    expect(readViewerView("#view=enclosure", "?view=pcb")).toBe("enclosure");
    expect(readViewerView("#view=pcb")).toBe("pcb");
    expect(cadInspectViewerSearch("enclosure")).toBe("view=enclosure");
    expect(cadInspectViewerSearch("product")).toBe("view=product");
    expect(cadInspectViewerSearch("pcb")).toBe("view=pcb");
    expect(cadInspectOpenHint("enclosure")).toBe(
      "Open this viewer from the project's FreeCAD panel.",
    );
    expect(cadInspectOpenHint("product")).toBe(
      "Open this viewer from the project's Blender panel.",
    );
    expect(cadInspectOpenHint("pcb")).toBe("Open this viewer from the project's KiCad panel.");
  });

  it("prefers a GLB enclosure solid over the first STL", () => {
    expect(
      preferredInspectSolid({
        BASE: "mech/BASE.stl",
        PCB: "mech/board.glb",
        PLATE: "mech/PLATE.stl",
      }),
    ).toBe("PCB");
    expect(preferredInspectSolid({ BASE: "mech/BASE.stl" })).toBe("BASE");
  });

  it("lists Blender 3D solids then named material stills", () => {
    const product = {
      solids: { PRODUCT: "mech/product.glb", ENCLOSURE: "mech/enclosure.step" },
      still: "mech/product-render.png",
      renders: {
        aluminum: "mech/load-viz-aluminum.png",
        resin: "mech/load-viz-resin.png",
      },
    };
    expect(productInspectSolids(product).map((item) => [item.label, item.preview])).toEqual([
      ["PRODUCT", "model"],
      ["ENCLOSURE", "step"],
    ]);
    expect(productInspectStills(product).map((item) => item.label)).toEqual([
      "product",
      "aluminum",
      "resin",
    ]);
    expect(productInspectItems(product).every((item) => item.path.length > 0)).toBe(true);
    expect(productInspectStills(product).every((item) => item.preview === "image")).toBe(true);
  });
});
