import { describe, expect, it } from "vite-plus/test";
import { mergeNativeLayerVisibility, nativeLayerSections } from "./nativeLayerState";

const layer = (id: string, section: string, visible = true) => ({
  id,
  name: id,
  section,
  color: "#fff",
  visible,
});

describe("native layer state", () => {
  it("retains user visibility while accepting newly discovered layers", () => {
    expect(
      mergeNativeLayerVisibility(
        [layer("F.Cu", "Copper"), layer("B.Cu", "Copper"), layer("Edge.Cuts", "Board")],
        { "F.Cu": false },
      ),
    ).toEqual({ "F.Cu": false, "B.Cu": true, "Edge.Cuts": true });
  });

  it("keeps renderer layer order inside grouped sections", () => {
    expect(
      nativeLayerSections([
        layer("F.Cu", "Copper"),
        layer("Edge.Cuts", "Board"),
        layer("B.Cu", "Copper"),
      ]),
    ).toEqual([
      ["Copper", [layer("F.Cu", "Copper"), layer("B.Cu", "Copper")]],
      ["Board", [layer("Edge.Cuts", "Board")]],
    ]);
  });
});
