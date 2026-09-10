/*
 * Reuse complete KiCanvas layer graphics across source replacements.
 *
 * Graphics are tied to one renderer/context, so this cache deliberately lives
 * on one core viewer. It never shares buffers between viewers, sheets, or
 * documents. Call setSignatures with the source scanner's UUID -> raw
 * expression map immediately before loading the next document. If a layer
 * contains an item without a UUID/raw expression, that layer falls back to the
 * normal painter and remains fully correct.
 */

function itemId(item) {
  const id = item?.uuid ?? item?.tstamp;
  return typeof id === "string" && id.length > 0 ? id : undefined;
}

function layerSignature(layer, sourceSignatures) {
  if (!(sourceSignatures instanceof Map)) return null;
  const values = [];
  const seen = new Set();
  for (const item of layer?.items ?? []) {
    const id = itemId(item);
    if (!id) return null;
    if (seen.has(id)) return null;
    seen.add(id);
    const source = sourceSignatures.get(id);
    if (typeof source !== "string") return null;
    values.push([id, source]);
  }
  // KiCanvas paints layer items in this order. Reordering equal geometry can
  // change z-order, so it must invalidate the retained graphics too.
  return JSON.stringify(values);
}

function captureLayers(layers, sourceSignatures, contextKey) {
  const result = new Map();
  if (!layers || contextKey === undefined) return result;
  for (const layer of layers.in_order?.() ?? []) {
    const signature = layerSignature(layer, sourceSignatures);
    if (!signature || !layer.graphics) continue;
    const bboxes = new Map();
    for (const item of layer.items ?? []) {
      const id = itemId(item);
      const bbox = layer.bboxes?.get(item);
      if (!id || !bbox) {
        bboxes.clear();
        break;
      }
      bboxes.set(id, { bbox, item });
    }
    if (layer.items?.length && !bboxes.size) continue;
    result.set(layer.name, {
      layer,
      graphics: layer.graphics,
      signature,
      bboxes,
      contextKey,
      reused: false,
    });
  }
  return result;
}

function detachGraphics(entry) {
  // ViewLayer.dispose() disposes layer.graphics. Detaching first lets the
  // cache own the renderer object without monkey-patching the layer lifecycle.
  entry.layer.graphics = undefined;
}

function rebindBBox(entry, item) {
  const saved = entry.bboxes.get(itemId(item));
  if (!saved) return undefined;
  const { bbox, item: oldItem } = saved;
  // A bbox with another context may belong to a child primitive that is no
  // longer represented by this layer item. Reusing it would break hit tests;
  // repaint that layer when we cannot prove the context is the root item.
  if (bbox.context !== undefined && bbox.context !== oldItem) return undefined;
  let rebound;
  try {
    rebound = typeof bbox.copy === "function" ? bbox.copy() : { ...bbox };
  } catch {
    return undefined;
  }
  // KiCanvas BBox exposes a writable context; assigning unconditionally also
  // keeps lightweight test/fallback bbox implementations safe to query.
  if (!rebound || typeof rebound !== "object") return undefined;
  rebound.context = item;
  return rebound;
}

export function installNativeLayerCache(core) {
  if (!core || core.__backplaneLayerCache) return core?.__backplaneLayerCache;
  const state = {
    activeSignatures: new Map(),
    nextSignatures: new Map(),
    activeContext: undefined,
    nextContext: undefined,
    previous: new Map(),
  };
  const originalCreatePainter = core.create_painter?.bind(core);
  const originalPaint = core.paint?.bind(core);
  if (!originalCreatePainter || !originalPaint) return undefined;

  const wrapPainter = (painter) => {
    const originalPaintLayer = painter.paint_layer?.bind(painter);
    if (!originalPaintLayer) return painter;
    painter.paint_layer = (layer) => {
      const cached = state.previous.get(layer.name);
      const signature = layerSignature(layer, state.nextSignatures);
      if (cached && cached.contextKey === state.nextContext && signature === cached.signature) {
        const remapped = new Map();
        let complete = true;
        for (const item of layer.items ?? []) {
          const id = itemId(item);
          const bbox = id ? rebindBBox(cached, item) : undefined;
          if (!bbox) {
            complete = false;
            break;
          }
          remapped.set(item, bbox);
        }
        if (complete) {
          layer.graphics = cached.graphics;
          layer.bboxes = remapped;
          cached.reused = true;
          return;
        }
      }
      originalPaintLayer(layer);
    };
    return painter;
  };

  core.create_painter = (...args) => wrapPainter(originalCreatePainter(...args));
  core.paint = (...args) => {
    state.previous = captureLayers(core.layers, state.activeSignatures, state.activeContext);
    for (const entry of state.previous.values()) detachGraphics(entry);
    let completed = false;
    try {
      const result = originalPaint(...args);
      completed = true;
      return result;
    } finally {
      for (const entry of state.previous.values()) {
        if (!completed || !entry.reused) entry.graphics.dispose?.();
      }
      if (!completed) {
        // The old layer set has already been detached/disposed by core.paint;
        // discard signatures so the next successful paint takes the safe path.
        state.activeSignatures = new Map();
        state.activeContext = undefined;
      } else {
        state.activeSignatures = state.nextSignatures;
        state.activeContext = state.nextContext;
      }
      state.previous = new Map();
    }
  };
  const api = {
    setSignatures(signatures, contextKey, options = {}) {
      state.nextSignatures = signatures instanceof Map ? new Map(signatures) : new Map();
      state.nextContext = contextKey;
      if (options.active === true) {
        state.activeSignatures = new Map(state.nextSignatures);
        state.activeContext = contextKey;
      }
    },
    clear() {
      state.activeSignatures = new Map();
      state.nextSignatures = new Map();
      state.activeContext = undefined;
      state.nextContext = undefined;
    },
  };
  core.__backplaneLayerCache = api;
  return api;
}

export { itemId, layerSignature };
