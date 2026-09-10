import { memo, useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown, Maximize, Minus, Plus } from "lucide-react";

import { paneLayout, useBoardViewport, type BoardRect } from "./vendor/fabrication-viewport";
import type { GerberLayerInfo } from "./gerberPresets";
import { Tooltip, TooltipPopup, TooltipTrigger } from "../components/ui/tooltip";

export interface GerberRenderedLayer {
  path: string;
  svg: string;
  info: GerberLayerInfo;
}

function svgBounds(svg: string): BoardRect | null {
  const root = new DOMParser().parseFromString(svg, "image/svg+xml").documentElement;
  if (root.getAttribute("data-empty") === "true") return null;
  const values = root.getAttribute("viewBox")?.split(/\s+/).map(Number);
  if (!values || values.length !== 4 || values.some((value) => !Number.isFinite(value)))
    return null;
  return { x: values[0]!, y: values[1]!, width: values[2]!, height: values[3]! };
}

/** A single retained layer resource. React keeps this node mounted by path. */
const GerberLayerImage = memo(function GerberLayerImage({
  layer,
  board,
  view,
  pane,
}: {
  layer: GerberRenderedLayer;
  board: BoardRect;
  view: ReturnType<typeof useBoardViewport>["view"];
  pane: { width: number; height: number };
}) {
  const bounds = useMemo(() => svgBounds(layer.svg), [layer.svg]);
  const [asset, setAsset] = useState<{
    current?: { url: string; bounds: BoardRect };
    previous?: { url: string; bounds: BoardRect };
  }>({});
  const assetRef = useRef(asset);
  const urls = useRef(new Set<string>());
  const transitionTimers = useRef(new Set<number>());
  useEffect(() => {
    assetRef.current = asset;
  }, [asset]);
  useEffect(() => {
    const next = URL.createObjectURL(new Blob([layer.svg], { type: "image/svg+xml" }));
    urls.current.add(next);
    let alive = true;
    if (!bounds) {
      setAsset({});
      for (const url of urls.current) URL.revokeObjectURL(url);
      urls.current.clear();
      return () => {
        alive = false;
      };
    }
    const preload = new Image();
    preload.src = next;
    const discard = () => {
      URL.revokeObjectURL(next);
      urls.current.delete(next);
    };
    const decoded = typeof preload.decode === "function" ? preload.decode() : Promise.resolve();
    void decoded.then(
      () => {
        if (!alive) {
          discard();
          return;
        }
        setAsset((old) => {
          if (!old.current) return { current: { url: next, bounds } };
          return { current: { url: next, bounds }, previous: old.current };
        });
      },
      () => {
        discard();
      },
    );
    return () => {
      alive = false;
    };
  }, [bounds, layer.svg]);
  useEffect(() => {
    const previous = asset.previous;
    if (!previous) return;
    let finished = false;
    const timer = window.setTimeout(() => {
      transitionTimers.current.delete(timer);
      const current = assetRef.current;
      if (current.previous?.url !== previous.url) return;
      finished = true;
      setAsset(current.current ? { current: current.current } : {});
      URL.revokeObjectURL(previous.url);
      urls.current.delete(previous.url);
    }, 180);
    transitionTimers.current.add(timer);
    return () => {
      window.clearTimeout(timer);
      transitionTimers.current.delete(timer);
      if (!finished && assetRef.current.previous?.url !== previous.url) {
        URL.revokeObjectURL(previous.url);
        urls.current.delete(previous.url);
      }
    };
  }, [asset.previous]);
  useEffect(
    () => () => {
      for (const timer of transitionTimers.current) window.clearTimeout(timer);
      transitionTimers.current.clear();
      for (const value of urls.current) URL.revokeObjectURL(value);
      urls.current.clear();
    },
    [],
  );
  if (!bounds || !asset.current) return null;
  const layout = paneLayout(asset.current.bounds, board, view, pane);
  const previousLayout = asset.previous
    ? paneLayout(asset.previous.bounds, board, view, pane)
    : null;
  return (
    <>
      {asset.previous && (
        <img
          key={asset.previous.url}
          src={asset.previous.url}
          alt=""
          aria-hidden="true"
          draggable={false}
          className="gerber-layer-image gerber-layer-image-previous"
          style={{
            width: previousLayout?.width,
            height: previousLayout?.height,
            left: previousLayout?.left,
            top: previousLayout?.top,
          }}
        />
      )}
      <img
        key={asset.current.url}
        src={asset.current.url}
        alt={layer.info.label}
        draggable={false}
        className="gerber-layer-image gerber-layer-image-current"
        style={{ width: layout.width, height: layout.height, left: layout.left, top: layout.top }}
      />
    </>
  );
});

/** Retained Gerber surface: independent layers share one board camera. */
export function GerberView({
  layers,
  footprintKey,
}: {
  layers: readonly GerberRenderedLayer[];
  footprintKey: string;
}) {
  const footprintState = useRef<{ key: string; board: BoardRect | null }>({
    key: footprintKey,
    board: null,
  });
  if (footprintState.current.key !== footprintKey) {
    footprintState.current = { key: footprintKey, board: null };
  }
  const boxes = useMemo(
    () =>
      layers
        .map((layer) => svgBounds(layer.svg))
        .filter((value): value is BoardRect => value !== null),
    [layers],
  );
  const boardSignature = boxes
    .map((box) => `${box.x},${box.y},${box.width},${box.height}`)
    .join(";");
  const observedBoard = useMemo<BoardRect | null>(() => {
    if (!boxes.length) return null;
    return {
      x: Math.min(...boxes.map((box) => box.x)),
      y: Math.min(...boxes.map((box) => box.y)),
      width:
        Math.max(...boxes.map((box) => box.x + box.width)) - Math.min(...boxes.map((box) => box.x)),
      height:
        Math.max(...boxes.map((box) => box.y + box.height)) -
        Math.min(...boxes.map((box) => box.y)),
    };
  }, [boardSignature]);
  const board = useMemo<BoardRect | null>(() => {
    const previous = footprintState.current.board;
    if (!observedBoard) return previous;
    if (!previous) return observedBoard;
    const x = Math.min(previous.x, observedBoard.x);
    const y = Math.min(previous.y, observedBoard.y);
    const right = Math.max(previous.x + previous.width, observedBoard.x + observedBoard.width);
    const bottom = Math.max(previous.y + previous.height, observedBoard.y + observedBoard.height);
    return x === previous.x &&
      y === previous.y &&
      right === previous.x + previous.width &&
      bottom === previous.y + previous.height
      ? previous
      : { x, y, width: right - x, height: bottom - y };
  }, [observedBoard]);
  footprintState.current.board = board;
  const viewport = useBoardViewport(board);
  const ref = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    const observer = new ResizeObserver(([entry]) => {
      if (entry) setSize({ width: entry.contentRect.width, height: entry.contentRect.height });
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const label = layers.map((layer) => layer.info.label).join(", ");
  return (
    <div className="gerber-surface">
      <div className="gerber-surface-toolbar">
        <span className="gerber-surface-label" aria-label={label}>
          {label}
        </span>
        <button
          className="kicad-icon-button"
          aria-label="Zoom out"
          onClick={() => viewport.zoomBy(1 / 1.4)}
        >
          <Minus size={14} />
        </button>
        <button
          className="kicad-icon-button"
          aria-label="Fit Gerber layers"
          onClick={viewport.reset}
        >
          <Maximize size={14} />
        </button>
        <button
          className="kicad-icon-button"
          aria-label="Zoom in"
          onClick={() => viewport.zoomBy(1.4)}
        >
          <Plus size={14} />
        </button>
      </div>
      <div ref={ref} className="gerber-surface-canvas" {...viewport.handlers}>
        {board && size.width > 0 && size.height > 0 && (
          <div className="gerber-layer-plane">
            {layers.map((layer) => (
              <GerberLayerImage
                key={layer.path}
                layer={layer}
                board={board}
                view={viewport.view}
                pane={size}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export function GerberLayerPanel({
  layers,
  activePaths,
  onToggle,
}: {
  layers: readonly GerberLayerInfo[];
  activePaths: ReadonlySet<string>;
  onToggle: (path: string) => void;
}) {
  const [isNarrow, setIsNarrow] = useState(
    () => typeof window !== "undefined" && window.matchMedia("(max-width: 42rem)").matches,
  );
  const [mobileOpen, setMobileOpen] = useState(false);
  useEffect(() => {
    const query = window.matchMedia("(max-width: 42rem)");
    const update = () => setIsNarrow(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  const groups = useMemo(() => {
    const result = new Map<string, GerberLayerInfo[]>();
    for (const layer of layers) {
      const list = result.get(layer.section) ?? [];
      list.push(layer);
      result.set(layer.section, list);
    }
    return result;
  }, [layers]);
  const labels: Record<string, string> = {
    front: "Front",
    back: "Back",
    inner: "Inner copper",
    board: "Board definition",
    drill: "Drill files",
    other: "Other",
  };
  const open = !isNarrow || mobileOpen;
  return (
    <aside className="gerber-layer-panel" data-open={open} aria-label="Gerber layers">
      <button
        type="button"
        className="gerber-layer-panel-title gerber-layer-panel-toggle"
        aria-expanded={open}
        aria-controls="gerber-layer-panel-content"
        onClick={() => {
          if (isNarrow) setMobileOpen((current) => !current);
        }}
      >
        <span>Layers</span>
        <ChevronDown size={13} aria-hidden="true" />
      </button>
      <div id="gerber-layer-panel-content" hidden={!open}>
        {["front", "back", "inner", "board", "drill", "other"].map((section) => {
          const group = groups.get(section);
          if (!group?.length) return null;
          return (
            <section key={section} className="gerber-layer-group">
              <h2>{labels[section]}</h2>
              {group.map((layer) => (
                <Tooltip key={layer.path}>
                  <TooltipTrigger
                    render={
                      <label
                        className="gerber-layer-row"
                        aria-label={`${layer.label}: ${layer.path}`}
                      />
                    }
                  >
                    <input
                      type="checkbox"
                      checked={activePaths.has(layer.path)}
                      onChange={() => onToggle(layer.path)}
                    />
                    <span className="gerber-layer-swatch" data-kind={layer.kind} />
                    <span className="gerber-layer-name">{layer.label}</span>
                  </TooltipTrigger>
                  <TooltipPopup side="right" className="max-w-64 break-words">
                    {layer.path}
                  </TooltipPopup>
                </Tooltip>
              ))}
            </section>
          );
        })}
      </div>
    </aside>
  );
}
