import { describe, expect, it } from "vite-plus/test";

import {
  CAD_INSPECT_SURFACES,
  cadInspectLabelForKind,
  cadInspectViewForKind,
  isCadInspectKind,
  preferredInspectSolid,
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

  it("keeps FreeCAD and Blender hash views instead of falling back to PCB", () => {
    expect(viewerHashView("enclosure")).toBe("enclosure");
    expect(viewerHashView("product")).toBe("product");
    expect(viewerHashView("pcb")).toBe("pcb");
    expect(viewerHashView("nope")).toBeUndefined();
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
});
