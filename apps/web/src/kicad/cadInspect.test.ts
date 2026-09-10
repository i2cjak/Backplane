import { describe, expect, it } from "vite-plus/test";

import {
  CAD_INSPECT_SURFACES,
  KICAD_INNER_TABS,
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
} from "./cadInspect.ts";

describe("cadInspect surfaces", () => {
  it("keeps FreeCAD and Blender as siblings, not KiCad inner tabs", () => {
    expect(CAD_INSPECT_SURFACES.map((surface) => surface.kind)).toEqual([
      "kicad",
      "freecad",
      "blender",
    ]);
    expect(cadInspectViewForKind("freecad")).toBe("enclosure");
    expect(cadInspectViewForKind("blender")).toBe("product");
    expect(cadInspectLabelForKind("freecad")).toBe("FreeCAD");
    expect(isCadInspectKind("files")).toBe(false);
    expect(KICAD_INNER_TABS.map((tab) => tab.id)).toEqual([
      "schematic",
      "pcb",
      "3d",
      "gerbers",
      "step",
    ]);
    expect(KICAD_INNER_TABS.map((tab) => tab.label)).not.toContain("FreeCAD");
    expect(isSiblingInspectView("enclosure")).toBe(true);
    expect(isSiblingInspectView("pcb")).toBe(false);
    expect(inspectSurfaceKind("product")).toBe("blender");
    expect(inspectSurfaceKind("step")).toBe("kicad");
  });

  it("switches sibling inspect via hash or search without falling back to PCB", () => {
    expect(readViewerView("#view=enclosure")).toBe("enclosure");
    expect(readViewerView("#view=product")).toBe("product");
    expect(readViewerView("", "?view=enclosure")).toBe("enclosure");
    expect(readViewerView("#view=enclosure", "?view=pcb")).toBe("enclosure");
    expect(cadInspectViewerSearch("enclosure")).toBe("view=enclosure");
    expect(cadInspectOpenHint("enclosure")).toBe(
      "Open this viewer from the project's FreeCAD panel.",
    );
  });

  it("lists Blender 3D solids separately from named material stills", () => {
    expect(preferredInspectSolid({ BASE: "mech/BASE.stl", PCB: "mech/board.glb" })).toBe("PCB");
    const product = {
      solids: { PRODUCT: "mech/product.glb", ENCLOSURE: "mech/enclosure.step" },
      still: "mech/product-render.png",
      renders: { aluminum: "mech/load-viz-aluminum.png", resin: "mech/load-viz-resin.png" },
    };
    expect(productInspectSolids(product).map((item) => item.preview)).toEqual(["model", "step"]);
    expect(productInspectStills(product).map((item) => item.label)).toEqual([
      "product",
      "aluminum",
      "resin",
    ]);
    expect(productInspectItems(product).length).toBe(5);
  });
});
