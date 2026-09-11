import { useCallback, useEffect, useRef, useState, type ComponentProps } from "react";
import { Maximize, Minus, Plus } from "lucide-react";
import type { KiCadPanelizationPreview } from "@backplane/contracts";

import { PanelizationDetailLayer } from "./PanelizationDetailLayer";
import { readPanelizationTheme, themePanelizationSvg } from "./panelizationTheme";

type PanelizationResult = KiCadPanelizationPreview;

const cache = new Map<string, PanelizationResult>();

export function extractPanelizationOutline(svg: string): string | undefined {
  const root = svg.match(/<svg\b([^>]*)>/i);
  const opening = svg.search(/<g\b[^>]*class=["'][^"']*backplane-panel-outline[^"']*["'][^>]*>/i);
  const bodyStart = opening < 0 ? -1 : svg.indexOf(">", opening) + 1;
  const bodyEnd = bodyStart < 0 ? -1 : svg.lastIndexOf("</g>");
  if (!root || opening < 0 || bodyStart <= 0 || bodyEnd <= bodyStart) return undefined;
  const attrs = (root[1] ?? "")
    .replace(/\s(?:xmlns|width|height)=(?:"[^"]*"|'[^']*')/gi, "")
    .trim();
  const styleStart = svg.lastIndexOf("<style>", opening);
  const styleEnd = svg.indexOf("</style>", styleStart);
  const style = styleStart >= 0 && styleEnd < opening ? svg.slice(styleStart, styleEnd + 8) : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" ${attrs}>${style}<g class="backplane-panel-outline">${svg.slice(bodyStart, bodyEnd)}</g></svg>`;
}

export function panelizationRasterSize(width: number, height: number) {
  const maxSide = 8192;
  const maxPixels = 16_000_000;
  const factor = Math.min(
    maxSide / Math.max(width, height),
    Math.sqrt(maxPixels / (width * height)),
  );
  return {
    width: Math.max(1, Math.floor(width * factor)),
    height: Math.max(1, Math.floor(height * factor)),
  };
}

async function rasterizePanelizationSvg(fallbackUrl: string, image: HTMLImageElement) {
  const width = image.naturalWidth || 1;
  const height = image.naturalHeight || 1;
  const raster = panelizationRasterSize(width, height);
  if (typeof document === "undefined") return { url: fallbackUrl, width, height };
  const canvas = document.createElement("canvas");
  if (!("toBlob" in canvas) || !canvas.getContext) return { url: fallbackUrl, width, height };
  canvas.width = raster.width;
  canvas.height = raster.height;
  const context = canvas.getContext("2d");
  if (!context) return { url: fallbackUrl, width, height };
  context.drawImage(image, 0, 0, raster.width, raster.height);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/png"));
  if (!blob) return { url: fallbackUrl, width, height };
  return { url: URL.createObjectURL(blob), width, height };
}

export function PanelizationView(props: ComponentProps<typeof PanelizationContent>) {
  return (
    <PanelizationContent
      key={JSON.stringify([props.scope, props.path, props.presetPath])}
      {...props}
    />
  );
}

function PanelizationContent({
  path,
  revision,
  scope,
  presetPath,
  visible,
  load,
}: {
  path: string | undefined;
  revision: string;
  scope: string;
  presetPath: string | undefined;
  visible: boolean;
  load: (path: string, revision: string, signal: AbortSignal) => Promise<PanelizationResult>;
}) {
  const [theme, setTheme] = useState(() =>
    typeof document === "undefined" ? undefined : readPanelizationTheme(),
  );
  useEffect(() => {
    if (typeof document === "undefined") return;
    const updateTheme = () => {
      const next = readPanelizationTheme(viewportRef.current ?? document.documentElement);
      setTheme((old) => (JSON.stringify(old) === JSON.stringify(next) ? old : next));
    };
    updateTheme();
    const observer = new MutationObserver(updateTheme);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class", "style"],
    });
    return () => observer.disconnect();
  }, []);
  const [result, setResult] = useState<PanelizationResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [camera, setCamera] = useState({ scale: 1, x: 0, y: 0 });
  const [imageSize, setImageSize] = useState({ width: 1, height: 1 });
  const [viewportSize, setViewportSize] = useState({ width: 1, height: 1 });
  const viewportRef = useRef<HTMLDivElement>(null);
  const zoom = useCallback((factor: number, x = 0, y = 0) => {
    setCamera((old) => {
      const scale = Math.max(0.2, Math.min(64, old.scale * factor));
      const ratio = scale / old.scale;
      return { scale, x: x - (x - old.x) * ratio, y: y - (y - old.y) * ratio };
    });
  }, []);
  useEffect(() => {
    const viewport = viewportRef.current;
    if (!viewport) return;
    const resize = () =>
      setViewportSize({ width: viewport.clientWidth, height: viewport.clientHeight });
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(viewport);
    const wheel = (event: WheelEvent) => {
      event.preventDefault();
      const box = viewport.getBoundingClientRect();
      const delta =
        event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? box.height : 1);
      zoom(
        Math.exp(-Math.max(-500, Math.min(500, delta)) * 0.002),
        event.clientX - box.left - box.width / 2,
        event.clientY - box.top - box.height / 2,
      );
    };
    viewport.addEventListener("wheel", wheel, { passive: false });
    return () => {
      observer.disconnect();
      viewport.removeEventListener("wheel", wheel);
    };
  }, [zoom]);
  const [dragging, setDragging] = useState(false);
  const drag = useRef({ x: 0, y: 0, ox: 0, oy: 0 });
  const [detailSvg, setDetailSvg] = useState<string>();
  const [imageUrl, setImageUrl] = useState<string | undefined>();
  const outlineUrlRef = useRef<string | undefined>(undefined);
  const [outlineUrl, setOutlineUrl] = useState<string | undefined>();
  const imageUrlRef = useRef<string | undefined>(undefined);
  const urls = useRef(new Set<string>());

  useEffect(() => {
    if (!path || !visible) return;
    const key = JSON.stringify([scope, path, presetPath, revision]);
    const cached = cache.get(key);
    if (cached) {
      setResult(cached);
      setError(null);
      setLoading(false);
      return;
    }
    const controller = new AbortController();
    setLoading(true);
    void load(path, revision, controller.signal).then(
      (next) => {
        if (controller.signal.aborted) return;
        cache.set(key, next);
        if (cache.size > 8) cache.delete(cache.keys().next().value!);
        setResult(next);
        setError(null);
        setLoading(false);
      },
      (cause) => {
        if (controller.signal.aborted) return;
        setError(cause instanceof Error ? cause.message : String(cause));
        setLoading(false);
      },
    );
    return () => controller.abort();
  }, [load, path, presetPath, revision, scope, visible]);

  useEffect(() => {
    if (!result?.svg) return;
    const themedSvg = theme ? themePanelizationSvg(result.svg, theme) : result.svg;
    const url = URL.createObjectURL(new Blob([themedSvg], { type: "image/svg+xml" }));
    urls.current.add(url);
    let alive = true;
    const image = new Image();
    image.src = url;
    void (typeof image.decode === "function" ? image.decode() : Promise.resolve()).then(
      () => {
        if (!alive) return;
        const old = imageUrlRef.current;
        void rasterizePanelizationSvg(url, image).then(
          (next) => {
            if (!alive) {
              if (next.url !== url) URL.revokeObjectURL(next.url);
              return;
            }
            if (next.url !== url) urls.current.add(next.url);
            imageUrlRef.current = next.url;
            setImageUrl(next.url);
            setDetailSvg(themedSvg);
            setImageSize({ width: next.width, height: next.height });
            if (outlineUrlRef.current) {
              URL.revokeObjectURL(outlineUrlRef.current);
              urls.current.delete(outlineUrlRef.current);
              outlineUrlRef.current = undefined;
            }
            const outline = extractPanelizationOutline(themedSvg);
            if (outline) {
              const outlineBlob = URL.createObjectURL(
                new Blob([outline], { type: "image/svg+xml" }),
              );
              urls.current.add(outlineBlob);
              outlineUrlRef.current = outlineBlob;
              setOutlineUrl(outlineBlob);
            } else {
              setOutlineUrl(undefined);
            }
            if (old && old !== next.url) {
              URL.revokeObjectURL(old);
              urls.current.delete(old);
            }
            if (url !== next.url) {
              URL.revokeObjectURL(url);
              urls.current.delete(url);
            }
          },
          () => {
            if (alive) {
              setError("The panelization preview could not be rasterized.");
              setLoading(false);
            }
          },
        );
      },
      () => {
        URL.revokeObjectURL(url);
        urls.current.delete(url);
        if (alive) {
          setError("The panelization SVG could not be decoded.");
          setLoading(false);
        }
      },
    );
    return () => {
      alive = false;
      URL.revokeObjectURL(url);
      urls.current.delete(url);
    };
  }, [result, theme]);
  useEffect(
    () => () => {
      for (const url of urls.current) URL.revokeObjectURL(url);
      urls.current.clear();
    },
    [],
  );

  const reset = useCallback(() => {
    setCamera({ scale: 1, x: 0, y: 0 });
  }, []);
  if (!path) {
    return (
      <div className="panelization-empty" role="status">
        <h2>Panelization needs a PCB</h2>
        <p>
          Assign a project PCB in <code>.backplane.json</code> to preview a panel.
        </p>
      </div>
    );
  }
  const image = result?.svg ? imageUrl : undefined;
  const fit =
    0.92 * Math.min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height);
  return (
    <div className="panelization-surface">
      <div className="panelization-toolbar" aria-label="Panelization controls">
        <span className="panelization-label">{presetPath ?? "panelize.json"}</span>
        {result && <span className="panelization-meta">{result.durationMs} ms</span>}
        {loading && <span className="panelization-status">Building…</span>}
        <span className="panelization-toolbar-spacer" />
        <button
          type="button"
          className="kicad-icon-button"
          onClick={() => zoom(1.25)}
          aria-label="Zoom in"
        >
          <Plus size={15} />
        </button>
        <button
          type="button"
          className="kicad-icon-button"
          onClick={() => zoom(1 / 1.25)}
          aria-label="Zoom out"
        >
          <Minus size={15} />
        </button>
        <button
          type="button"
          className="kicad-icon-button"
          onClick={reset}
          aria-label="Fit panelization"
        >
          <Maximize size={15} />
        </button>
      </div>
      {error && (
        <div className="panelization-error" role="status">
          {error}
          {result && " Showing the last successful panel."}
        </div>
      )}
      <div
        className="panelization-viewport"
        ref={viewportRef}
        onPointerDown={(event) => {
          event.currentTarget.setPointerCapture(event.pointerId);
          drag.current = { x: event.clientX, y: event.clientY, ox: camera.x, oy: camera.y };
          setDragging(true);
        }}
        onPointerMove={(event) => {
          if (!dragging) return;
          const x = drag.current.ox + event.clientX - drag.current.x;
          const y = drag.current.oy + event.clientY - drag.current.y;
          setCamera((old) => ({ ...old, x, y }));
        }}
        onPointerUp={() => setDragging(false)}
        onPointerCancel={() => setDragging(false)}
      >
        {image ? (
          <>
            <img
              className="panelization-image"
              src={image}
              alt="Panelization preview"
              draggable={false}
              style={{
                width: imageSize.width * fit * camera.scale,
                height: imageSize.height * fit * camera.scale,
                transform: `translate(-50%, -50%) translate(${camera.x}px, ${camera.y}px)`,
              }}
            />
            {detailSvg && typeof document !== "undefined" && (
              <PanelizationDetailLayer
                key={image}
                svg={detailSvg}
                camera={camera}
                viewport={viewportSize}
                image={imageSize}
                fit={fit}
                minScale={
                  (0.8 * panelizationRasterSize(imageSize.width, imageSize.height).width) /
                  (imageSize.width * fit * Math.min(window.devicePixelRatio || 1, 3))
                }
              />
            )}
            {outlineUrl && (
              <img
                className="panelization-outline"
                src={outlineUrl}
                alt=""
                aria-hidden="true"
                draggable={false}
                style={{
                  width: imageSize.width * fit * camera.scale,
                  height: imageSize.height * fit * camera.scale,
                  transform: `translate(-50%, -50%) translate(${camera.x}px, ${camera.y}px)`,
                }}
              />
            )}
          </>
        ) : !loading ? (
          <p className="panelization-empty-copy">
            No panel preview yet. Edit <code>{presetPath ?? "panelize.json"}</code> and save it; the
            preview updates automatically.
          </p>
        ) : null}
      </div>
    </div>
  );
}
