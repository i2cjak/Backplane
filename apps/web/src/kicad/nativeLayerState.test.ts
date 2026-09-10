import { describe, expect, it } from "vite-plus/test";
import {
  mergeNativeLayerVisibility,
  nativeLayerSections,
  sameNativeLayers,
} from "./nativeLayerState";

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

  it("returns the previous visibility object when a layer report is unchanged", () => {
    const previous = { "F.Cu": false, "B.Cu": true };
    expect(
      mergeNativeLayerVisibility(
        [layer("F.Cu", "Copper", true), layer("B.Cu", "Copper")],
        previous,
      ),
    ).toBe(previous);
  });

  it("recognizes identical layer reports even when the arrays are new", () => {
    expect(sameNativeLayers([layer("F.Cu", "Copper")], [layer("F.Cu", "Copper")])).toBe(true);
    expect(sameNativeLayers([layer("F.Cu", "Copper")], [layer("F.Cu", "Copper", false)])).toBe(
      false,
    );
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
