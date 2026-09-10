import { indexNativeSources } from "./native-source-index.js";
import { installNativeLayerCache } from "./native-layer-cache.js";
import { hydrateSchematicPinInstances } from "./schematic-compatibility.js";
import { collectSchematicNet } from "./schematic-net.js";
import { resolveBoardNetAtPoint } from "./board-net-selection.js";

const sectionFor = (name) => {
  if (/\.cu$/i.test(name)) return "Copper";
  if (/silk/i.test(name)) return "Silkscreen";
  if (/mask/i.test(name)) return "Solder mask";
  if (/paste|adhes|fab|crtyd|courtyard/i.test(name)) return "Fabrication";
  return "Board and documentation";
};

function glowOffsetsFor(core) {
  const zoom = Number(core?.viewport?.camera?.zoom);
  const radius = zoom > 0 ? 3 / zoom : 0.18;
  const diagonal = radius * 0.72;
  return [
    [-radius, 0],
    [radius, 0],
    [0, -radius],
    [0, radius],
    [-diagonal, -diagonal],
    [diagonal, -diagonal],
    [-diagonal, diagonal],
    [diagonal, diagonal],
  ];
}

function visibleBoardLayer(core, name) {
  if (!name) return false;
  const layer = core?.layers?.by_name?.(name);
  return layer ? layer.visible !== false : true;
}

function copperPadLayers(core, pattern) {
  const available = [...(core?.layers?.in_order?.() ?? [])]
    .map((layer) => layer?.name)
    .filter((name) => typeof name === "string" && /\.Cu$/.test(name));
  if (pattern === "*.Cu") {
    return available.length ? available : ["F.Cu", "B.Cu"];
  }
  return available.filter((name) => name === "F.Cu" || name === "B.Cu").length
    ? available.filter((name) => name === "F.Cu" || name === "B.Cu")
    : ["F.Cu", "B.Cu"];
}

function padHasVisibleLayer(core, pad) {
  const names = [];
  for (const name of Array.isArray(pad?.layers) ? pad.layers : []) {
    if (name === "*.Mask") names.push("F.Mask", "B.Mask");
    else if (name === "*.Paste") names.push("F.Paste", "B.Paste");
    else if (name === "*.Cu" || name === "F&B.Cu") names.push(...copperPadLayers(core, name));
    else names.push(name);
  }
  return names.length === 0 || names.some((name) => visibleBoardLayer(core, name));
}

function visibleFootprintGlowItems(core, footprint) {
  const items = [];
  for (const item of footprint?.items?.() ?? []) {
    if (item?.typeId === "Pad") {
      if (padHasVisibleLayer(core, item)) items.push(item);
      continue;
    }
    // Text, properties, zones, and fabrication/courtyard geometry are useful
    // in the normal board view but make a selection glow look like a bbox.
    if (!["FpLine", "FpCircle", "FpArc", "FpPoly", "FpRect"].includes(item?.constructor?.name))
      continue;
    const name = typeof item.layer === "string" ? item.layer : item.layer?.name;
    if (!/^(?:F|B)\.(?:Cu|SilkS)$/.test(name ?? "")) continue;
    if (visibleBoardLayer(core, name)) items.push(item);
  }
  return items;
}

function footprintGlowProxy(core, footprint) {
  const items = visibleFootprintGlowItems(core, footprint);
  // Keep the mature FootprintPainter and its transforms/custom-pad support,
  // but restrict its child iteration to visible physical board geometry.
  const proxy = Object.create(footprint);
  proxy.items = () => items;
  return proxy;
}

function footprintAncestor(item) {
  let current = item;
  for (let depth = 0; current && depth < 8; depth++) {
    if (current.typeId === "Footprint") return current;
    current = current.parent;
  }
  return undefined;
}

function decorativeFootprint(footprint) {
  const reference = String(footprint?.reference ?? "").trim();
  return !reference || /^(?:G|REF)(?:\*+|\?+)$/i.test(reference);
}

function footprintArea(footprint, hit) {
  const bbox = footprint?.bbox ?? hit?.bbox;
  const width = Number(bbox?.w ?? bbox?.width);
  const height = Number(bbox?.h ?? bbox?.height);
  return Number.isFinite(width) && Number.isFinite(height) ? Math.abs(width * height) : Infinity;
}

function bboxContains(value, position) {
  const width = Number(value?.w ?? value?.width);
  const height = Number(value?.h ?? value?.height);
  const x = Number(value?.x);
  const y = Number(value?.y);
  return (
    Number.isFinite(width) &&
    Number.isFinite(height) &&
    Number.isFinite(x) &&
    Number.isFinite(y) &&
    position.x >= x &&
    position.x <= x + width &&
    position.y >= y &&
    position.y <= y + height
  );
}

function footprintHasGeometryAt(core, footprint, position) {
  // Select the body between visible pads/silkscreen too. The vendor's wider
  // footprint bbox includes property text, which can cover unrelated routes.
  const bounds = visibleFootprintGlowItems(core, footprint)
    .map((item) => item?.bbox)
    .filter((value) => [value?.x, value?.y, value?.w, value?.h].every(Number.isFinite));
  if (!bounds.length) return false;
  const x = Math.min(...bounds.map((value) => value.x));
  const y = Math.min(...bounds.map((value) => value.y));
  return bboxContains(
    {
      x,
      y,
      w: Math.max(...bounds.map((value) => value.x + value.w)) - x,
      h: Math.max(...bounds.map((value) => value.y + value.h)) - y,
    },
    position,
  );
}

function chooseFootprintHit(core, hits, position) {
  const candidates = new Map();
  for (const hit of hits) {
    const footprint = footprintAncestor(hit?.item);
    if (
      footprint &&
      !decorativeFootprint(footprint) &&
      footprintHasGeometryAt(core, footprint, position) &&
      !candidates.has(footprint)
    )
      candidates.set(footprint, hit);
  }
  if (!candidates.size) return undefined;
  const entries = [...candidates.entries()];
  entries.sort(
    ([a, hitA], [b, hitB]) =>
      footprintArea(a, hitA) - footprintArea(b, hitB) ||
      String(a.reference ?? "").localeCompare(String(b.reference ?? "")),
  );
  const [footprint, hit] = entries[0];
  // Keep a pad's net on a footprint selection so the H shortcut can still
  // highlight the connected net after the component wins the hit test.
  return { ...hit, item: footprint };
}

function installFootprintClickResolver(core) {
  if (
    !core?.board ||
    core.__backplaneFootprintClickResolver ||
    typeof core.on_click !== "function" ||
    typeof core.find_items_under_pos !== "function"
  )
    return;
  const originalOnClick = core.on_click.bind(core);
  const findItems = core.find_items_under_pos.bind(core);
  core.on_click = (position, ...args) => {
    const selected = chooseFootprintHit(core, findItems(position), position);
    const physicalNet = resolveBoardNetAtPoint(core.board, position, {
      isLayerVisible: (name) => visibleBoardLayer(core, name),
    });
    if (selected) {
      const originalFindItems = core.find_items_under_pos;
      const footprintSelection = { ...selected };
      // The native normalizer promotes any hit carrying `net` to a net
      // selection. Keep the footprint as the selected item and pass the
      // connected net through the retained-viewer event listener for H.
      delete footprintSelection.net;
      delete footprintSelection.netCode;
      core.__backplanePendingFootprintNet =
        physicalNet?.kind === "pad" && footprintAncestor(physicalNet.item) === selected.item
          ? physicalNet
          : undefined;
      core.find_items_under_pos = () => [footprintSelection];
      try {
        return originalOnClick(position, ...args);
      } finally {
        delete core.__backplanePendingFootprintNet;
        core.find_items_under_pos = originalFindItems;
      }
    }
    if (physicalNet?.item) {
      const originalFindItems = core.find_items_under_pos;
      core.find_items_under_pos = () => [{ item: physicalNet.item }];
      try {
        return originalOnClick(position, ...args);
      } finally {
        core.find_items_under_pos = originalFindItems;
      }
    }
    return originalOnClick(position, ...args);
  };
  core.__backplaneFootprintClickResolver = true;
}

function installClickPointerSync(core) {
  const canvas = core?.canvas;
  if (!canvas || core.__backplaneClickPointerSync || typeof core.on_mouse_change !== "function")
    return;
  // The mature click listener reads its last mousemove position. Capture the
  // click first so direct/touch clicks without a preceding mousemove resolve
  // the actual world coordinate instead of the initial (0, 0).
  canvas.addEventListener("click", (event) => core.on_mouse_change(event), { capture: true });
  core.__backplaneClickPointerSync = true;
}

function cacheContext(core, sourceIndex) {
  // Schematic sheets share source files but have different instance transforms
  // and layer bboxes. Keep those presentations in separate cache domains.
  return `${sourceIndex.context}\nscene:${core?.scene_cache_context ?? ""}`;
}

function installSchematicHydration(core, beforePaint) {
  if (!core?.schematic || core.__backplaneHydratePaint) return;
  const paint = core.paint.bind(core);
  core.paint = (...args) => {
    hydrateSchematicPinInstances(core);
    beforePaint?.(core);
    return paint(...args);
  };
  core.__backplaneHydratePaint = true;
}

function paintGeometryGlow(
  core,
  painter,
  layer,
  item,
  color,
  offsets,
  alpha,
  blend = 1,
  paintLayer = layer,
  items = [item],
) {
  const gfx = painter.gfx ?? core.renderer;
  layer.clear();
  gfx.start_layer(layer.name);
  const previousTransform = gfx.color_transform;
  gfx.color_transform = (source) => {
    const tinted = typeof source.mix === "function" ? source.mix(color, blend) : color;
    return tinted.with_alpha(Math.min(1, source.a * alpha));
  };
  try {
    for (const [x, y] of offsets) {
      gfx.state.push();
      gfx.state.matrix.translate_self(x, y);
      try {
        for (const target of items) painter.paint_item(paintLayer, target);
      } finally {
        gfx.state.pop();
      }
    }
  } finally {
    gfx.color_transform = previousTransform;
  }
  layer.graphics = gfx.end_layer();
  // Canvas2D can brighten the finite offset passes. WebGL's mature renderer
  // intentionally keeps source-over because its blend mode is subtractive.
  layer.graphics.composite_operation = core.renderer.ctx2d ? "lighter" : "source-over";
}

function paintSchematicGlow(core, painter, layer, color, offsets, alpha, blend, items) {
  const targets = [];
  for (const item of items) {
    const itemPainter = painter.painters?.get(item?.constructor);
    for (const name of itemPainter?.layers_for?.(item) ?? []) {
      // Interactive is a hit-test presentation. PropertyPainter draws a
      // white bounding rectangle there, so it must never be used for glow.
      if (name === ":Interactive" || name === ":Symbol:Field") continue;
      targets.push({ layer: { name, color }, item });
    }
  }
  if (!targets.length) return;
  const gfx = painter.gfx ?? core.renderer;
  layer.clear();
  gfx.start_layer(layer.name);
  const previousTransform = gfx.color_transform;
  gfx.color_transform = (source) => {
    const tinted = typeof source.mix === "function" ? source.mix(color, blend) : color;
    return tinted.with_alpha(Math.min(1, source.a * alpha));
  };
  try {
    for (const target of targets) painter.paint_item(target.layer, target.item);
  } finally {
    gfx.color_transform = previousTransform;
  }
  const graphics = gfx.end_layer();
  graphics.composite_operation = core.renderer.ctx2d ? "lighter" : "source-over";
  const render = graphics.render.bind(graphics);
  graphics.render = (matrix, depth, opacity = 1) => {
    for (const [x, y] of offsets) {
      const translation = matrix.constructor.translation(x, y);
      render(matrix.multiply(translation), depth, opacity / offsets.length);
    }
  };
  layer.graphics = graphics;
}

function highlightSchematicNet(core, selection) {
  const selectedItems = collectSchematicNet(core.schematic, selection).items;
  if (!selectedItems.size) return false;
  const color = core.layers.selection_fg.color.constructor.from_css("#40a9ff");
  const items = [...selectedItems];
  core.layers.selection_bg.clear();
  core.layers.selection_fg.clear();
  paintSchematicGlow(
    core,
    core.painter,
    core.layers.selection_bg,
    color,
    glowOffsetsFor(core),
    0.12,
    0.75,
    items,
  );
  paintSchematicGlow(
    core,
    core.painter,
    core.layers.selection_fg,
    color,
    [[0, 0]],
    0.4,
    0.5,
    items,
  );
  core.draw();
  return true;
}

export function collectBoardNetItems(board, net) {
  const items = [];
  for (const item of board?.items?.() ?? []) {
    if (item.typeId === "Footprint") {
      for (const child of item.items?.() ?? []) {
        if (child.typeId === "Pad" && child.net?.number === net) items.push(child);
      }
      continue;
    }
    if (item.net === net) items.push(item);
  }
  return items;
}

function boardNetPaintItems(board, net) {
  const items = [];
  for (const item of board?.items?.() ?? []) {
    if (item.typeId === "Footprint") {
      const pads = [...(item.items?.() ?? [])].filter(
        (child) => child.typeId === "Pad" && child.net?.number === net,
      );
      if (pads.length) {
        const proxy = Object.create(item);
        proxy.items = () => pads;
        items.push(proxy);
      }
      continue;
    }
    if (item.net === net) items.push(item);
  }
  return items;
}

function highlightBoardNet(core, selection, net) {
  const items = boardNetPaintItems(core.board, net);
  if (!items.length || !core.painter) return false;
  const color = core.layers.selection_fg.color.constructor.from_css("#40a9ff");
  for (const layer of [core.layers.selection_bg, core.layers.selection_fg]) layer.clear();
  const paintItems = (layer, offsets, alpha, blend) => {
    const gfx = core.painter.gfx ?? core.renderer;
    gfx.start_layer(layer.name);
    const previousTransform = gfx.color_transform;
    gfx.color_transform = (source) => {
      const tinted = typeof source.mix === "function" ? source.mix(color, blend) : color;
      return tinted.with_alpha(Math.min(1, source.a * alpha));
    };
    try {
      for (const [x, y] of offsets) {
        gfx.state.push();
        gfx.state.matrix.translate_self(x, y);
        try {
          for (const item of items) core.painter.paint_item(layer, item);
        } finally {
          gfx.state.pop();
        }
      }
    } finally {
      gfx.color_transform = previousTransform;
    }
    layer.graphics = gfx.end_layer();
    layer.graphics.composite_operation = core.renderer.ctx2d ? "lighter" : "source-over";
  };
  paintItems(core.layers.selection_bg, glowOffsetsFor(core), 0.12, 0.75);
  paintItems(core.layers.selection_fg, [[0, 0]], 0.55, 0.5);
  core.draw();
  return true;
}

/** Retain the mature KiCanvas geometry engine, camera, and GPU context across saves. */
export class RetainedNativeViewer extends EventTarget {
  constructor(host) {
    super();
    this.host = host;
    this.host.style.position = "relative";
    this.current = null;
    this.active = true;
    this.ready = Promise.resolve();
    this.visibility = {};
    this.index = undefined;
    this.selection = undefined;
    this.cache = undefined;
    this.overlay = undefined;
    this.transition = undefined;
    this.pendingSnapshot = undefined;
    this.replacing = false;
    this.pendingIndex = undefined;
    this.disposed = false;
    this.generation = 0;
    this.programmaticProbeDepth = 0;
  }

  core() {
    return this.current?.shadowRoot?.querySelector("kc-board-app, kc-schematic-app")?.viewer;
  }

  createElement() {
    const viewer = document.createElement("ecad-viewer");
    viewer.setAttribute("source-mode", "host");
    viewer.setAttribute("show-header", "false");
    viewer.style.cssText = "display:block;width:100%;height:100%";
    viewer.addEventListener("ecad-viewer:selection", (event) => {
      const pendingNet =
        this.core()?.__backplanePendingFootprintNet && event.detail?.itemType === "footprint"
          ? this.core().__backplanePendingFootprintNet
          : undefined;
      const detail = pendingNet
        ? { ...event.detail, net: pendingNet.net, netCode: pendingNet.netCode }
        : event.detail;
      if (!detail?.itemType) {
        if (this.replacing) return;
        this.selection = undefined;
        this.dispatchEvent(new CustomEvent("selection", { detail: null }));
        return;
      } else {
        const kind =
          detail.itemType === "net" || (!detail.reference && detail.net) ? "net" : "component";
        const value = kind === "net" ? detail.net : (detail.reference ?? detail.designator);
        this.selection = value
          ? { ...detail, kind, value, targetContext: detail.sourceContext }
          : undefined;
      }
      const selection =
        detail && typeof detail === "object"
          ? { ...detail, userInitiated: this.programmaticProbeDepth === 0 && !this.replacing }
          : detail;
      this.dispatchEvent(new CustomEvent("selection", { detail: selection }));
    });
    viewer.addEventListener("ecad-viewer:crossprobe", (event) => {
      const detail = event.detail;
      const selection =
        detail && typeof detail === "object"
          ? { ...detail, userInitiated: this.programmaticProbeDepth === 0 && !this.replacing }
          : detail;
      this.dispatchEvent(new CustomEvent("crossprobe", { detail: selection }));
    });
    this.host.appendChild(viewer);
    this.current = viewer;
    return viewer;
  }

  publishLayers() {
    const layers = this.current?.getPcbViewState?.()?.layers ?? [];
    this.dispatchEvent(
      new CustomEvent("layers", {
        detail: layers.map((layer) => ({
          id: layer.name,
          name: layer.name,
          section: sectionFor(layer.name),
          color: layer.color,
          visible: layer.visible,
        })),
      }),
    );
  }

  // Theme repainting clears the renderer cache because cached graphics contain
  // the old palette. Seed the current source signatures again once the theme
  // has been painted so the next file update can still reuse unchanged layers.
  reseedLayerCache() {
    const core = this.core();
    if (this.cache && this.index && core)
      this.cache.setSignatures(this.index.signatures, cacheContext(core, this.index), {
        active: true,
      });
  }

  enhanceGeometrySelection() {
    const core = this.core();
    if (!core?.painter) return;
    installClickPointerSync(core);
    if (core.board) {
      const enhanceBoardPainter = (painter) => {
        if (!painter || painter.__backplaneHighlight) return;
        const paintFootprintGlow = (footprint) => {
          painter.clear_interactive();
          const color = core.layers.selection_fg.color.constructor.from_css("#80dcff");
          const visibleFootprint = footprintGlowProxy(core, footprint);
          paintGeometryGlow(
            core,
            painter,
            core.layers.selection_bg,
            visibleFootprint,
            color,
            glowOffsetsFor(core),
            0.12,
            0.75,
          );
          paintGeometryGlow(
            core,
            painter,
            core.layers.selection_fg,
            visibleFootprint,
            color,
            [[0, 0]],
            0.34,
            0.5,
          );
        };
        // Both normal clicks (outline_footprint) and cross-probes
        // (paint_footprint) use the same precise footprint geometry.
        painter.paint_footprint = paintFootprintGlow;
        painter.outline_footprint = paintFootprintGlow;
        // Keep the selected item's underglow stable while the pointer moves.
        core.on_hover = () => {};
        painter.__backplaneHighlight = true;
      };
      if (!core.__backplaneCreatePainter) {
        const createPainter = core.create_painter.bind(core);
        core.create_painter = (...args) => {
          const painter = createPainter(...args);
          enhanceBoardPainter(painter);
          return painter;
        };
        core.__backplaneCreatePainter = true;
      }
      installFootprintClickResolver(core);
      enhanceBoardPainter(core.painter);
    }
    if (core.schematic && !core.__backplaneHighlight) {
      // The bbox is used only to resolve the source item, never as selection artwork.
      core.paint_selected = (bbox) => {
        core.layers.selection_bg.clear();
        const selection = core.layers.selection_fg;
        selection.clear();
        const item = bbox?.context;
        if (item) {
          const highlight = selection.color.constructor.from_css("#40a9ff");
          const items = [item, ...(item.unit_pins ?? [])];
          paintSchematicGlow(
            core,
            core.painter,
            core.layers.selection_bg,
            highlight,
            glowOffsetsFor(core),
            0.12,
            0.75,
            items,
          );
          paintSchematicGlow(core, core.painter, selection, highlight, [[0, 0]], 0.4, 0.5, items);
        }
        core.draw();
      };
      core.layers.overlay.clear();
      core.on_hover = () => {};
      core.__backplaneHighlight = true;
    }
  }

  applyVisibility() {
    const state = this.current?.getPcbViewState?.();
    for (const layer of state?.layers ?? []) {
      const visible = this.visibility[layer.name];
      if (visible !== undefined && visible !== layer.visible)
        this.current.setPcbLayerVisibility(layer.name, visible);
    }
  }

  capture() {
    if (this.pendingSnapshot) return this.pendingSnapshot;
    this.finishTransition();
    const core = this.core();
    if (!core?.canvas || !this.active) return undefined;
    core.draw_now();
    const source = document.createElement("canvas");
    source.width = core.canvas.width;
    source.height = core.canvas.height;
    source.getContext("2d").drawImage(core.canvas, 0, 0);
    const rect = core.canvas.getBoundingClientRect();
    const parent = this.host.getBoundingClientRect();
    const overlay = document.createElement("canvas");
    overlay.width = source.width;
    overlay.height = source.height;
    overlay.style.cssText = `position:absolute;pointer-events:none;z-index:15;left:${rect.left - parent.left}px;top:${rect.top - parent.top}px;width:${rect.width}px;height:${rect.height}px`;
    overlay.getContext("2d").drawImage(source, 0, 0);
    this.host.appendChild(overlay);
    this.overlay = overlay;
    this.pendingSnapshot = { source, overlay, width: rect.width, height: rect.height };
    return this.pendingSnapshot;
  }

  bounds(ids) {
    const core = this.core();
    const result = [];
    if (!core?.layers) return result;
    for (const layer of core.layers.in_display_order()) {
      if (!layer.visible) continue;
      for (const [item, bbox] of layer.bboxes) {
        const id = item?.uuid ?? item?.tstamp;
        if (!ids.has(id) || !bbox) continue;
        const a = core.viewport.camera.world_to_screen(bbox.top_left);
        const b = core.viewport.camera.world_to_screen(bbox.bottom_right);
        result.push({
          x: Math.min(a.x, b.x) - 8,
          y: Math.min(a.y, b.y) - 8,
          width: Math.abs(b.x - a.x) + 16,
          height: Math.abs(b.y - a.y) + 16,
        });
      }
    }
    return result;
  }

  animate(snapshot, regions, globalChanged) {
    if (!snapshot) return;
    if (!this.active || matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.finishTransition();
      return;
    }
    const { source, overlay, width, height } = snapshot;
    if (!globalChanged && regions.length) {
      const context = overlay.getContext("2d");
      context.clearRect(0, 0, overlay.width, overlay.height);
      const sx = overlay.width / width,
        sy = overlay.height / height;
      for (const region of regions) {
        const x = Math.max(0, region.x * sx),
          y = Math.max(0, region.y * sy);
        const w = Math.min(region.width * sx, overlay.width - x),
          h = Math.min(region.height * sy, overlay.height - y);
        if (w > 0 && h > 0) context.drawImage(source, x, y, w, h, x, y, w, h);
      }
    }
    this.transition = overlay.animate(
      [
        { opacity: 1, filter: "blur(0px)" },
        { opacity: 0.55, filter: "blur(1.2px)", offset: 0.45 },
        { opacity: 0, filter: "blur(0px)" },
      ],
      { duration: 360, easing: "cubic-bezier(.22,.7,.3,1)" },
    );
    const animation = this.transition;
    void animation.finished.then(
      () => {
        if (this.transition === animation) this.finishTransition();
      },
      () => {},
    );
  }

  finishTransition() {
    this.transition?.cancel();
    this.transition = undefined;
    this.overlay?.remove();
    this.overlay = undefined;
  }

  async replaceSources({ revisionKey, sources, layerVisibility = {} }) {
    if (this.disposed) return this.ready;
    const generation = ++this.generation;
    this.visibility = { ...this.visibility, ...layerVisibility };
    const next = indexNativeSources(sources, this.index);
    if (this.current && this.index && !next.changed.size && !next.globalChanged) {
      this.revision = revisionKey;
      this.index = next;
      this.applyVisibility();
      return;
    }
    const core = this.core();
    const camera = core?.viewport?.camera;
    const view = camera ? { x: camera.center.x, y: camera.center.y, zoom: camera.zoom } : undefined;
    const regions = this.bounds(next.changed);
    const snapshot = this.capture();
    this.current ??= this.createElement();
    const current = this.current;
    this.pendingIndex = next;
    this.cache?.setSignatures(next.signatures, cacheContext(this.core(), next));
    const pending = (async () => {
      this.replacing = true;
      try {
        current.setActive(false);
        await current.replaceSources({ revisionKey, sources });
        await current.ready;
        if (generation !== this.generation || this.disposed || this.current !== current) return;
        const loaded = this.core();
        // ecad-viewer resolves its host replacement before the mature
        // DocumentViewer's deferred `load()` fit pass. Wait for that barrier
        // so restoring the user's camera is the final camera write.
        if (loaded?.loaded && typeof loaded.loaded.then === "function") await loaded.loaded;
        if (generation !== this.generation || this.disposed || this.current !== current) return;
        const cache = loaded ? installNativeLayerCache(loaded) : undefined;
        const cacheChanged = Boolean(cache && cache !== this.cache);
        if (cache) this.cache = cache;
        installSchematicHydration(loaded, (paintedCore) => {
          const sourceIndex = this.replacing ? this.pendingIndex : this.index;
          if (this.cache && sourceIndex)
            this.cache.setSignatures(
              sourceIndex.signatures,
              cacheContext(paintedCore, sourceIndex),
            );
        });
        const hydration = loaded?.schematic
          ? hydrateSchematicPinInstances(loaded)
          : { hydrated: 0 };
        if (hydration.hydrated > 0) {
          cache?.clear();
          loaded.paint?.();
          loaded.draw_now?.();
        }
        if ((cacheChanged || hydration.hydrated > 0) && cache)
          cache.setSignatures(next.signatures, cacheContext(loaded, next), { active: true });
        if (view && loaded?.viewport?.camera) {
          loaded.viewport.camera.center.set(view.x, view.y);
          loaded.viewport.camera.zoom = view.zoom;
        }
        this.enhanceGeometrySelection();
        this.applyVisibility();
        current.setActive(this.active);
        current.resize();
        if (this.selection) {
          const restored = current.requestCrossProbe({ ...this.selection, mode: "hover" });
          if (!restored) {
            // A saved component or net may have been deleted while the file
            // was being edited. Do not keep sending stale probes on every
            // subsequent replacement or leave the host showing dead state.
            this.selection = undefined;
            this.dispatchEvent(new CustomEvent("selection", { detail: null }));
          }
        }
        loaded?.draw_now();
        regions.push(...this.bounds(next.changed));
        this.index = next;
        this.revision = revisionKey;
        this.publishLayers();
        this.host.dataset.nativeRevision = revisionKey;
        this.host.dataset.nativeChangedItems = String(next.changed.size);
        this.animate(snapshot, regions, next.globalChanged);
        this.pendingSnapshot = undefined;
      } catch (cause) {
        // Keep the captured saved drawing visible if parsing a partial save fails.
        if (generation === this.generation && !this.disposed && this.current === current)
          current.setActive(this.active);
        throw cause;
      } finally {
        if (generation === this.generation) {
          this.replacing = false;
          this.pendingIndex = undefined;
        }
      }
    })();
    this.ready = pending;
    return pending;
  }

  setActive(active) {
    this.active = active;
    this.current?.setActive(active);
    if (!active) this.finishTransition();
  }
  resize() {
    this.current?.resize();
  }
  requestCrossProbe(probe) {
    this.enhanceGeometrySelection();
    this.programmaticProbeDepth += 1;
    let found;
    try {
      found = Boolean(this.current?.requestCrossProbe(probe));
    } finally {
      this.programmaticProbeDepth -= 1;
    }
    if (found) {
      this.selection = probe;
      this.dispatchEvent(
        new CustomEvent("selection", {
          detail: {
            sourceContext: probe.targetContext,
            userInitiated: false,
            ...(probe.kind === "net"
              ? { net: probe.value, itemType: "net" }
              : { reference: probe.value, itemType: "component" }),
          },
        }),
      );
    }
    return found;
  }
  setNetHighlight(selection) {
    const core = this.core();
    if (!core || (!selection?.value && !selection?.uuid)) return false;
    if (core.board) {
      if (!selection.value) return false;
      const net =
        selection.netCode ?? core.board.nets.find((item) => item.name === selection.value)?.number;
      if (net === undefined) return false;
      core.painter.filter_net = null;
      core.clear_selection?.();
      return highlightBoardNet(core, selection, net);
    }
    if (core.schematic) return highlightSchematicNet(core, selection);
    return false;
  }
  requestNetHighlight(command) {
    if (command?.clear) {
      this.clearNetHighlight();
      return true;
    }
    return this.setNetHighlight(command);
  }
  clearNetHighlight() {
    const core = this.core();
    if (!core) return;
    if (core.board) core.clear_selection?.();
    else if (core.schematic) {
      core.layers.selection_bg.clear();
      core.layers.selection_fg.clear();
      core.draw();
    }
  }
  setLayerVisibility(id, visible) {
    this.visibility[id] = visible;
    const current = this.current?.getPcbViewState?.()?.layers.find((layer) => layer.name === id);
    return (
      current?.visible === visible || Boolean(this.current?.setPcbLayerVisibility?.(id, visible))
    );
  }
  setLayerHighlight(id) {
    return Boolean(this.current?.setPcbLayerHighlight?.(id));
  }
  fit() {
    this.core()?.zoom_fit_top_item();
  }
  dispose() {
    this.disposed = true;
    this.generation++;
    this.replacing = false;
    this.finishTransition();
    this.pendingSnapshot = undefined;
    this.current?.setActive(false);
    this.current?.remove();
    this.current = null;
  }
}
