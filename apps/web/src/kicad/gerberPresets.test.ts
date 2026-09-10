import { expect, it } from "vite-plus/test";
import { gerberFamily, gerberLayerInfo, gerberPresetPaths } from "./gerberPresets";
import { commitGerberLayer } from "./gerberResources";

it("keeps presets within a fabrication set and separates top and bottom assembly artwork", () => {
  const paths = [
    "fab/board-F_Cu.gtl",
    "fab/board-B_Cu.gbl",
    "fab/board-In1_Cu.g1",
    "fab/board-F_SilkS.gto",
    "fab/board-B_SilkS.gbo",
    "fab/board-F_Paste.gtp",
    "fab/board-Edge_Cuts.gm1",
    "fab/other-F_Cu.gtl",
    "old/board-F_Cu.gtl",
  ];
  expect(gerberPresetPaths(paths, paths[0]!, "front")).toEqual([paths[3], paths[5], paths[6]]);
  expect(gerberPresetPaths(paths, paths[0]!, "copper")).toEqual([
    paths[0],
    paths[1],
    paths[2],
    paths[6],
  ]);
  expect(gerberPresetPaths(paths, paths[0]!, "back")).toEqual([paths[4], paths[6]]);
});

it("recognizes generic extensions and returns no matching placement rather than unrelated artwork", () => {
  const paths = ["out/main-F_Cu.gbr", "out/main-B_Cu.gbr", "out/main-PTH.drl"];
  expect(gerberPresetPaths(paths, paths[0]!, "copper")).toEqual(paths);
  expect(gerberPresetPaths(["unclassified.gbr"], "unclassified.gbr", "front")).toEqual([]);
});

it("groups the plotted package into useful viewer sections", () => {
  expect(gerberLayerInfo("build/board-F_Cu.gtl")).toMatchObject({
    label: "Front copper",
    section: "front",
    kind: "front-copper",
  });
  expect(gerberLayerInfo("build/board-In2_Cu.g2").section).toBe("inner");
  expect(gerberLayerInfo("build/board-In2_Cu.g2").label).toBe("Inner 2 copper");
  expect(gerberLayerInfo("build/tinytapeout-demo-F_Silkscreen.gbr").label).toBe("Front silkscreen");
  expect(gerberLayerInfo("build/tinytapeout-demo-B_Mask.gbr").label).toBe("Back solder mask");
  expect(gerberLayerInfo("build/board-User_2.gbr").label).toBe("User 2");
  expect(gerberLayerInfo("build/board-NPTH.drl").label).toBe("NPTH drills");
  expect(gerberLayerInfo("build/board-Edge_Cuts.gm1").label).toBe("Edge cuts");
  expect(gerberLayerInfo("build/board-NPTH.drl").section).toBe("drill");
  expect(gerberLayerInfo("build/board-Edge_Cuts.gm1").section).toBe("board");
  expect(gerberLayerInfo("build/board-F_Silkscreen.gbr").section).toBe("front");
  expect(gerberLayerInfo("build/board-F_Mask.gbr").section).toBe("front");
  expect(gerberFamily("build/board-User_2.gbr")).toBe("build/board");
});

it("retains untouched layer resources and rejects stale responses", () => {
  const original = {
    top: { revision: "one", svg: "top-svg" },
    bottom: { revision: "one", svg: "bottom-svg" },
  };
  const retained = commitGerberLayer(original, "top", "two", "two", "top-svg");
  expect(retained.top).not.toBe(original.top);
  expect(retained.top?.svg).toBe("top-svg");
  expect(retained.bottom).toBe(original.bottom);
  expect(commitGerberLayer(retained, "bottom", "one", "two", "old-response")).toBe(retained);
  const changed = commitGerberLayer(retained, "top", "two", "two", "new-top-svg");
  expect(changed.top?.svg).toBe("new-top-svg");
  expect(changed.bottom).toBe(original.bottom);
});
