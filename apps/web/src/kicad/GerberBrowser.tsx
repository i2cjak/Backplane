import { useEffect, useMemo, useRef, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { GerberLayerPanel, GerberView, type GerberRenderedLayer } from "./GerberView";
import {
  gerberFamily,
  gerberLayerInfo,
  gerberPresetPaths,
  type GerberPreset,
} from "./gerberPresets";
import { commitGerberLayer, type GerberLayerResources } from "./gerberResources";
import "./gerber-viewer.css";

const presets = [
  ["layer", "Single layer"],
  ["copper", "Copper stack"],
  ["front", "Front fabrication"],
  ["back", "Back fabrication"],
  ["all", "All layers"],
] as const;

export function GerberBrowser({
  paths,
  selected,
  revision,
  revisionByPath,
  onSelect,
  url,
  read,
}: {
  paths: string[];
  selected: string;
  revision: string;
  revisionByPath?: (path: string) => string;
  onSelect: (path: string) => void;
  url: (paths: string[]) => string;
  read: (url: string, signal: AbortSignal) => Promise<Response>;
}) {
  const [preset, setPreset] = useState<GerberPreset>("layer");
  const [activePaths, setActivePaths] = useState<string[]>(() =>
    gerberPresetPaths(paths, selected, "layer"),
  );
  const [rendered, setRendered] = useState<GerberLayerResources>({});
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [pending, setPending] = useState<ReadonlySet<string>>(new Set());
  const cache = useRef(
    new Map<
      string,
      { promise: Promise<string>; controller: AbortController; consumers: number; settled: boolean }
    >(),
  );
  const [renderedLayerCache] = useState(
    () => new Map<string, { svg: string; layer: GerberRenderedLayer }>(),
  );
  const visiblePaths = useMemo(
    () => paths.filter((path) => activePaths.includes(path)),
    [activePaths, paths],
  );
  const layerInfo = useMemo(() => paths.map(gerberLayerInfo), [paths]);
  const index = paths.indexOf(selected);
  const step = (direction: number) => {
    const path = paths[(index + direction + paths.length) % paths.length];
    if (path) {
      setActivePaths(gerberPresetPaths(paths, path, preset));
      onSelect(path);
    }
  };
  const layerRevision = (path: string) => revisionByPath?.(path) ?? revision;

  // The file browser can change the selected layer without going through the
  // arrow controls. Keep that selection visible while preserving manual
  // visibility choices made in the layer panel.
  useEffect(() => {
    setActivePaths((current) => {
      const retained = current.filter((path) => paths.includes(path));
      if (retained.includes(selected)) return retained;
      const presetSelection = gerberPresetPaths(paths, selected, preset).filter((path) =>
        paths.includes(path),
      );
      return retained.length ? [...retained, selected] : presetSelection;
    });
  }, [paths, preset, selected]);

  useEffect(() => {
    const keyboard = (event: KeyboardEvent) => {
      if (
        event.target instanceof HTMLElement &&
        event.target.closest("input,select,textarea,button")
      )
        return;
      if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
        event.preventDefault();
        step(event.key === "ArrowLeft" ? -1 : 1);
      }
    };
    window.addEventListener("keydown", keyboard);
    return () => window.removeEventListener("keydown", keyboard);
  }, [selected, paths]);

  useEffect(() => {
    let alive = true;
    const acquired = new Set<string>();
    const load = (path: string, requestedRevision: string) => {
      const cacheKey = `${requestedRevision}:${path}`;
      let entry = cache.current.get(cacheKey);
      if (!entry) {
        const controller = new AbortController();
        const promise = read(
          url([path]),
          AbortSignal.any([controller.signal, AbortSignal.timeout(60_000)]),
        ).then(async (response) => {
          if (!response.ok) throw new Error(`Gerber rendering failed (${response.status})`);
          return response.text();
        });
        entry = { promise, controller, consumers: 0, settled: false };
        cache.current.set(cacheKey, entry);
        void promise.then(
          () => {
            entry!.settled = true;
          },
          () => {
            entry!.settled = true;
            if (cache.current.get(cacheKey) === entry) cache.current.delete(cacheKey);
          },
        );
        while (cache.current.size > 24) {
          const oldestKey = cache.current.keys().next().value;
          if (oldestKey === undefined) break;
          const oldest = cache.current.get(oldestKey);
          if (oldest?.consumers === 0) cache.current.delete(oldestKey);
          else break;
        }
      }
      entry.consumers += 1;
      acquired.add(cacheKey);
      return entry.promise;
    };
    const release = () => {
      for (const cacheKey of acquired) {
        const entry = cache.current.get(cacheKey);
        if (!entry) continue;
        entry.consumers -= 1;
        if (entry.consumers <= 0 && !entry.settled) {
          cache.current.delete(cacheKey);
          entry.controller.abort();
        }
      }
      acquired.clear();
    };
    const uncached = visiblePaths.filter(
      (path) => rendered[path]?.revision !== layerRevision(path),
    );
    setPending((current) => {
      const visible = new Set(visiblePaths.map((path) => `${layerRevision(path)}:${path}`));
      return new Set([...current].filter((key) => visible.has(key)));
    });
    if (!uncached.length) return;
    setPending((current) => {
      const visible = new Set(visiblePaths.map((path) => `${layerRevision(path)}:${path}`));
      return new Set(
        [...current]
          .filter((key) => visible.has(key))
          .concat(uncached.map((path) => `${layerRevision(path)}:${path}`)),
      );
    });
    for (const path of uncached) {
      const requestedRevision = layerRevision(path);
      void load(path, requestedRevision)
        .then((value) => {
          if (!alive) return;
          setRendered((current) =>
            commitGerberLayer(current, path, requestedRevision, layerRevision(path), value),
          );
          setErrors((current) => {
            if (!(path in current)) return current;
            const next = { ...current };
            delete next[path];
            return next;
          });
          setPending((current) => {
            const next = new Set(current);
            next.delete(`${requestedRevision}:${path}`);
            return next;
          });
        })
        .catch((cause: unknown) => {
          if (!alive) return;
          setErrors((current) => ({
            ...current,
            [path]: cause instanceof Error ? cause.message : String(cause),
          }));
          setPending((current) => {
            const next = new Set(current);
            next.delete(`${requestedRevision}:${path}`);
            return next;
          });
        });
    }
    return () => {
      alive = false;
      release();
    };
  }, [revision, revisionByPath, visiblePaths]);

  const togglePath = (path: string) => {
    setActivePaths((current) =>
      current.includes(path) ? current.filter((item) => item !== path) : [...current, path],
    );
  };

  const renderedLayers = useMemo<GerberRenderedLayer[]>(
    () =>
      visiblePaths.flatMap((path) => {
        const value = rendered[path];
        if (!value) return [];
        const existing = renderedLayerCache.get(path);
        if (existing?.svg === value.svg) return [existing.layer];
        const next = { path, svg: value.svg, info: gerberLayerInfo(path) };
        renderedLayerCache.set(path, { svg: value.svg, layer: next });
        while (renderedLayerCache.size > 64)
          renderedLayerCache.delete(renderedLayerCache.keys().next().value!);
        return [next];
      }),
    [rendered, visiblePaths],
  );
  const error = visiblePaths.map((path) => errors[path]).find(Boolean);
  const hasPending = visiblePaths.some((path) => pending.has(`${layerRevision(path)}:${path}`));

  return (
    <div className="gerber-browser">
      <div className="gerber-browser-toolbar">
        <button
          type="button"
          className="kicad-icon-button"
          aria-label="Previous Gerber layer"
          onClick={() => step(-1)}
        >
          <ChevronLeft size={14} />
        </button>
        <span className="gerber-browser-count">
          {Math.max(index + 1, 0)} / {paths.length}
        </span>
        <button
          type="button"
          className="kicad-icon-button"
          aria-label="Next Gerber layer"
          onClick={() => step(1)}
        >
          <ChevronRight size={14} />
        </button>
        <select
          aria-label="Gerber inspection preset"
          value={preset}
          onChange={(event) => {
            const next = event.target.value as GerberPreset;
            setActivePaths(gerberPresetPaths(paths, selected, next));
            setPreset(next);
          }}
          className="gerber-browser-preset"
        >
          {presets.map(([id, label]) => (
            <option key={id} value={id}>
              {label}
            </option>
          ))}
        </select>
        <span className="gerber-browser-status" aria-live="polite">
          {visiblePaths.length} visible
        </span>
      </div>
      <div className="gerber-browser-body">
        <GerberLayerPanel
          layers={layerInfo}
          activePaths={new Set(activePaths)}
          onToggle={togglePath}
        />
        <div className="gerber-browser-stage">
          {renderedLayers.length > 0 && (
            <GerberView footprintKey={gerberFamily(selected)} layers={renderedLayers} />
          )}
          {error && (
            <div className="gerber-browser-update-error" role="status">
              {error}
            </div>
          )}
          {!renderedLayers.length && !visiblePaths.length && (
            <div className="gerber-browser-empty" role="status">
              Select a layer to inspect.
            </div>
          )}
          {!renderedLayers.length && visiblePaths.length > 0 && !error && (
            <div className="gerber-browser-empty" role="status">
              Loading Gerber layers…
            </div>
          )}
          {hasPending && visiblePaths.length > 0 && (
            <div className="gerber-browser-updating" role="status">
              Updating preview…
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
