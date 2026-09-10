import { describe, expect, it, vi } from "vite-plus/test";

const nativeCache = await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}native-layer-cache.js`
);
const { installNativeLayerCache, layerSignature } = nativeCache;

function layer(name: string, items: Array<Record<string, unknown>>) {
  return {
    name,
    items,
    graphics: undefined as { id: number; dispose?: () => void } | undefined,
    bboxes: new Map<Record<string, unknown>, { id: string; context?: unknown }>(),
    dispose: undefined as (() => void) | undefined,
    in_order: function* () {
      yield this;
    },
  };
}

describe("native layer cache", () => {
  it("reuses unchanged renderer graphics and remaps bboxes to new item objects", () => {
    const oldItem = { uuid: "item-1", shape: "line" };
    const nextItem = { uuid: "item-1", shape: "line" };
    const oldLayer = layer("F.Cu", [oldItem]);
    const oldBBox = {
      id: "old-bbox",
      context: oldItem,
      copy() {
        return { ...this };
      },
    };
    oldLayer.bboxes.set(oldItem, oldBBox);
    const nextLayer = layer("F.Cu", [nextItem]);
    const painted = vi.fn((target: typeof oldLayer) => {
      target.graphics = { id: 2 };
      target.bboxes.set(target.items[0]!, { id: "new-bbox" });
    });
    const core = {
      layers: oldLayer,
      nextLayer: oldLayer,
      create_painter() {
        return { paint_layer: painted };
      },
      paint() {
        const previous = this.layers;
        previous.dispose?.();
        this.layers = this.nextLayer;
        this.create_painter().paint_layer(this.layers);
      },
    };
    const cache = installNativeLayerCache(core);
    cache!.setSignatures(new Map([["item-1", "(segment ...)"]]), "board");
    core.paint();
    expect(painted).toHaveBeenCalledTimes(1);
    oldLayer.bboxes.set(oldItem, { id: "old-bbox" });
    const graphics = oldLayer.graphics;
    core.nextLayer = nextLayer;
    cache!.setSignatures(new Map([["item-1", "(segment ...)"]]), "board");
    core.paint();
    expect(painted).toHaveBeenCalledTimes(1);
    expect(nextLayer.graphics).toBe(graphics);
    expect(nextLayer.bboxes.get(nextItem)).toMatchObject({ id: "old-bbox", context: nextItem });
  });

  it("rejects uncertain items so the normal painter remains the fallback", () => {
    const noUuid = { shape: "unknown" };
    expect(layerSignature(layer("F.Cu", [noUuid]), new Map())).toBeNull();
  });

  it("invalidates when draw order changes even if item signatures do not", () => {
    const first = layer("F.Cu", [{ uuid: "a" }, { uuid: "b" }]);
    const reordered = layer("F.Cu", [{ uuid: "b" }, { uuid: "a" }]);
    const signatures = new Map([
      ["a", "a-source"],
      ["b", "b-source"],
    ]);
    expect(layerSignature(first, signatures)).not.toBe(layerSignature(reordered, signatures));
  });

  it("repaints when a cached bbox belongs to a different child context", () => {
    const oldItem = { uuid: "item-1" };
    const oldLayer = layer("F.Cu", [oldItem]);
    oldLayer.bboxes.set(oldItem, { id: "child-bbox", context: { uuid: "child" } });
    oldLayer.graphics = { id: 1 };
    const nextLayer = layer("F.Cu", [{ uuid: "item-1" }]);
    const painted = vi.fn((target: typeof oldLayer) => {
      target.graphics = { id: 2 };
      target.bboxes.set(target.items[0]!, { id: "fresh-bbox" });
    });
    const core = {
      layers: oldLayer,
      create_painter() {
        return { paint_layer: painted };
      },
      paint() {
        this.layers = nextLayer;
        this.create_painter().paint_layer(this.layers);
      },
    };
    const cache = installNativeLayerCache(core)!;
    const signatures = new Map([["item-1", "same-source"]]);
    cache.setSignatures(signatures, "board", { active: true });
    core.paint();
    expect(painted).toHaveBeenCalledTimes(1);
    expect(nextLayer.graphics).toEqual({ id: 2 });
  });

  it("disposes detached graphics when a changed layer is repainted", () => {
    const oldItem = { uuid: "item-1" };
    const oldLayer = layer("F.Cu", [oldItem]);
    oldLayer.bboxes.set(oldItem, { id: "old-bbox" });
    const nextLayer = layer("F.Cu", [{ uuid: "item-1" }]);
    const dispose = vi.fn();
    oldLayer.graphics = { id: 1, dispose };
    const painted = vi.fn((target: typeof oldLayer) => {
      target.graphics = { id: 2 };
      target.bboxes.set(target.items[0]!, { id: "new-bbox" });
    });
    const core = {
      layers: oldLayer,
      nextLayer,
      create_painter() {
        return { paint_layer: painted };
      },
      paint() {
        this.layers = this.nextLayer;
        this.create_painter().paint_layer(this.layers);
      },
    };
    const cache = installNativeLayerCache(core)!;
    cache.setSignatures(new Map([["item-1", "old-source"]]), "board", { active: true });
    cache.setSignatures(new Map([["item-1", "new-source"]]), "board");
    core.paint();
    expect(painted).toHaveBeenCalledTimes(1);
    expect(dispose).toHaveBeenCalledTimes(1);
  });

  it("can seed the active signature for the first save after installation", () => {
    const oldItem = { uuid: "item-1" };
    const oldLayer = layer("F.Cu", [oldItem]);
    oldLayer.bboxes.set(oldItem, { id: "bbox" });
    oldLayer.graphics = { id: 1 };
    const nextLayer = layer("F.Cu", [{ uuid: "item-1" }]);
    const painted = vi.fn();
    const core = {
      layers: oldLayer,
      create_painter() {
        return { paint_layer: painted };
      },
      paint() {
        this.layers = nextLayer;
        this.create_painter().paint_layer(this.layers);
      },
    };
    const cache = installNativeLayerCache(core)!;
    const signatures = new Map([["item-1", "same-source"]]);
    cache.setSignatures(signatures, "board", { active: true });
    core.paint();
    expect(painted).not.toHaveBeenCalled();
    expect(nextLayer.graphics).toEqual({ id: 1 });
  });

  it("releases detached graphics if the mature painter fails partway through", () => {
    const oldItem = { uuid: "item-1" };
    const oldLayer = layer("F.Cu", [oldItem]);
    oldLayer.bboxes.set(oldItem, { id: "bbox" });
    const dispose = vi.fn();
    oldLayer.graphics = { id: 1, dispose };
    const nextLayer = layer("F.Cu", [{ uuid: "item-1" }]);
    const core = {
      layers: oldLayer,
      create_painter() {
        return {
          paint_layer: (_layer: typeof nextLayer) => {
            throw new Error("paint failed");
          },
        };
      },
      paint() {
        this.layers = nextLayer;
        this.create_painter().paint_layer(this.layers);
      },
    };
    const cache = installNativeLayerCache(core)!;
    cache.setSignatures(new Map([["item-1", "old-source"]]), "board", { active: true });
    cache.setSignatures(new Map([["item-1", "new-source"]]), "board");
    expect(() => core.paint()).toThrow("paint failed");
    expect(dispose).toHaveBeenCalledTimes(1);
  });
});
