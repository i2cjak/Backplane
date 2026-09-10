import { useEffect, useRef, useState } from "react";
import { ArrowLeftRight, Search } from "lucide-react";
import { loadSchematicSources } from "./schematicSources";
import {
  mergeNativeLayerVisibility,
  nativeLayerSections,
  sameNativeLayers,
} from "./nativeLayerState";

type Source = { filename: string; content: string };
export type NativeView = "pcb" | "schematic";
type Selection = {
  sourceContext?: "PCB" | "SCH";
  uuid?: string;
  reference?: string;
  designator?: string;
  net?: string;
  itemType?: string;
  value?: string;
};
type Probe = {
  id: number;
  kind: "net" | "component";
  value: string;
  targetContext: "PCB" | "SCH";
  mode?: "hover";
};
type NetHighlightCommand = {
  id: number;
  targetContext?: "PCB" | "SCH";
  value?: string;
  uuid?: string;
  clear?: boolean;
};
export type NativeLayer = {
  id: string;
  name: string;
  section: string;
  color: string;
  visible: boolean;
};
const origin = location.origin === "null" ? "*" : location.origin;

function NativeFrame({
  view,
  sources,
  revision,
  active,
  probe,
  netHighlight,
  layerVisibility,
  onSelection,
  onProbe,
  onKey,
  onResult,
  onLayers,
}: {
  view: NativeView;
  sources: Source[];
  revision: string;
  active: boolean;
  probe?: Probe | undefined;
  netHighlight?: NetHighlightCommand | undefined;
  layerVisibility: Record<string, boolean>;
  onSelection: (selection: Selection | null, userInitiated: boolean) => void;
  onProbe: (selection: Selection, userInitiated: boolean) => void;
  onKey: (key: string) => void;
  onResult: (found: boolean, value: string) => void;
  onLayers: (layers: NativeLayer[]) => void;
}) {
  const ref = useRef<HTMLIFrameElement>(null);
  const ready = useRef(false);
  const sentRevision = useRef<string | undefined>(undefined);
  const snapshot = {
    type: "backplane-snapshot",
    kind: "native",
    sources,
    revision,
    active,
    probe,
    netHighlight,
    context: view === "pcb" ? "PCB" : "SCH",
    layerVisibility,
  };
  const latest = useRef({ snapshot, onSelection, onProbe, onKey, onResult, onLayers });
  latest.current = { snapshot, onSelection, onProbe, onKey, onResult, onLayers };
  const send = () => {
    if (!ready.current) return;
    const { sources, ...state } = latest.current.snapshot;
    ref.current?.contentWindow?.postMessage(
      sentRevision.current === state.revision ? state : { ...state, sources },
      origin,
    );
    sentRevision.current = state.revision;
  };
  useEffect(() => {
    const receive = (event: MessageEvent) => {
      if (event.source !== ref.current?.contentWindow || event.origin !== location.origin) return;
      if (event.data?.type === "backplane-runtime-ready") {
        ready.current = true;
        sentRevision.current = undefined;
        send();
      }
      if (event.data?.type === "backplane-selection")
        latest.current.onSelection(event.data.selection, event.data.userInitiated === true);
      if (event.data?.type === "backplane-crossprobe")
        latest.current.onProbe(event.data.selection, event.data.userInitiated === true);
      if (event.data?.type === "backplane-native-key" && typeof event.data.key === "string")
        latest.current.onKey(event.data.key);
      if (event.data?.type === "backplane-probe-result")
        latest.current.onResult(Boolean(event.data.found), String(event.data.value));
      if (event.data?.type === "backplane-layers") latest.current.onLayers(event.data.layers ?? []);
    };
    window.addEventListener("message", receive);
    return () => window.removeEventListener("message", receive);
  }, []);
  useEffect(() => {
    send();
  }, [sources, revision, active, probe, netHighlight, layerVisibility]);
  return (
    <iframe
      ref={ref}
      title={`Fast ${view === "pcb" ? "PCB" : "schematic"} viewer`}
      src="/kicad-viewer/runtime.html"
      className="h-full w-full border-0"
    />
  );
}

/** Each native context retains its camera and parsed project when switching tabs. */
export function NativeProjectViews({
  view,
  pcb,
  schematic,
  sheets,
  revision,
  read,
  onView,
}: {
  view: NativeView | null;
  pcb: string | undefined;
  schematic: string | undefined;
  sheets: string[];
  revision: string;
  read: (path: string, signal: AbortSignal) => Promise<string>;
  onView: (view: NativeView) => void;
}) {
  const [loaded, setLoaded] = useState<
    Partial<Record<NativeView, { key: string; sources: Source[] }>>
  >({});
  const [errors, setErrors] = useState<Partial<Record<NativeView, string>>>({});
  const [selection, setSelection] = useState<Selection | null>(null);
  const [query, setQuery] = useState("");
  const [net, setNet] = useState(false);
  const [probe, setProbe] = useState<Probe>();
  const [netHighlight, setNetHighlight] = useState<NetHighlightCommand>();
  const [crossProbeEnabled, setCrossProbeEnabled] = useState(false);
  const [status, setStatus] = useState("");
  const [visited, setVisited] = useState(new Set<NativeView>());
  const [layers, setLayers] = useState<NativeLayer[]>([]);
  const [mobileLayersOpen, setMobileLayersOpen] = useState(false);
  const [layerVisibility, setLayerVisibility] = useState<Record<string, boolean>>({});
  const selectionRef = useRef(selection);
  selectionRef.current = selection;
  const viewRef = useRef(view);
  viewRef.current = view;
  useEffect(() => {
    setLayers([]);
    setLayerVisibility({});
  }, [pcb]);
  useEffect(() => {
    if (view) setVisited((old) => (old.has(view) ? old : new Set([...old, view])));
  }, [view]);
  const requestId = useRef(0);
  const readRef = useRef(read);
  readRef.current = read;
  const sheetsKey = JSON.stringify(sheets);
  useEffect(() => {
    const controller = new AbortController();
    setErrors({});
    for (const [context, path] of [
      ["pcb", pcb],
      ["schematic", schematic],
    ] as const) {
      if (!path) continue;
      const readFile = (filename: string) => readRef.current(filename, controller.signal);
      const load =
        context === "schematic"
          ? loadSchematicSources(path, sheets, readFile)
          : readFile(path).then((content) => [{ filename: path, content }]);
      void load
        .then((sources) => {
          if (!controller.signal.aborted)
            setLoaded((old) => ({ ...old, [context]: { key: `${revision}:${path}`, sources } }));
        })
        .catch((error: unknown) => {
          if (!controller.signal.aborted)
            setErrors((old) => ({ ...old, [context]: String(error) }));
        });
    }
    return () => controller.abort();
  }, [pcb, schematic, revision, sheetsKey]);
  const runProbe = (
    value: string,
    kind: "net" | "component",
    target: NativeView,
    mode?: "hover",
  ) => {
    if (!value.trim()) return;
    setStatus(`Finding ${value}…`);
    setProbe({
      id: ++requestId.current,
      value: value.trim(),
      kind,
      targetContext: target === "pcb" ? "PCB" : "SCH",
      ...(mode ? { mode } : {}),
    });
    onView(target);
  };
  const handleCrossProbeShortcut = (key: string) => {
    if (!viewRef.current) return;
    if (key === "x" || key === "X") setCrossProbeEnabled((current) => !current);
    else if (key === "Escape") {
      setCrossProbeEnabled(false);
      setNetHighlight({ id: ++requestId.current, clear: true });
    } else if (key === "h" || key === "H") {
      const current = selectionRef.current;
      const value = current?.net?.trim();
      const uuid = current?.uuid;
      const currentView = viewRef.current;
      if ((value || uuid) && (current?.sourceContext || currentView)) {
        setNetHighlight({
          id: ++requestId.current,
          ...(value ? { value } : {}),
          ...(uuid ? { uuid } : {}),
          targetContext: current?.sourceContext ?? (currentView === "pcb" ? "PCB" : "SCH"),
        });
      } else {
        setStatus("Select a pad, track, wire, or net label first.");
      }
    }
  };
  useEffect(() => {
    const keyboard = (event: KeyboardEvent) => {
      const target = event.target;
      if (
        event.repeat ||
        event.defaultPrevented ||
        event.ctrlKey ||
        event.metaKey ||
        event.altKey ||
        (target instanceof HTMLElement &&
          (target.isContentEditable || /^(?:INPUT|TEXTAREA|SELECT)$/.test(target.tagName)))
      )
        return;
      handleCrossProbeShortcut(event.key);
    };
    window.addEventListener("keydown", keyboard);
    return () => window.removeEventListener("keydown", keyboard);
  }, []);
  const crossProbe = (item: Selection) => {
    const value =
      item.itemType === "net" ? item.net : (item.reference ?? item.designator ?? item.net);
    if (!value) {
      setStatus("Select a component or net to cross-probe.");
      return;
    }
    const kind =
      item.itemType === "net" || !(item.reference ?? item.designator) ? "net" : "component";
    runProbe(value, kind, item.sourceContext === "PCB" ? "schematic" : "pcb", "hover");
  };
  return (
    <div className="flex h-full min-h-0 flex-col">
      <form
        className="design-inspectbar"
        onSubmit={(event) => {
          event.preventDefault();
          if (view) runProbe(query, net ? "net" : "component", view);
        }}
      >
        <div className="design-search">
          <Search size={14} />
          <input
            aria-label="Find component or net"
            placeholder={net ? "Net name" : "Reference, e.g. U1"}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            className="min-w-0 flex-1 bg-transparent px-1 py-1 outline-none"
          />
        </div>
        <label>
          <input type="checkbox" checked={net} onChange={(event) => setNet(event.target.checked)} />
          Net
        </label>
        <button type="submit" className="design-text-button">
          Find
        </button>
        <button
          type="button"
          disabled={!selection || !pcb || !schematic}
          onClick={() => selection && crossProbe(selection)}
          className="design-text-button"
          aria-label={`Show selection in ${view === "pcb" ? "schematic" : "PCB"}`}
        >
          <ArrowLeftRight size={14} />
          <span className="design-crossprobe-label">
            Show in {view === "pcb" ? "schematic" : "PCB"}
          </span>
        </button>
        <button
          type="button"
          className="design-text-button"
          data-active={crossProbeEnabled}
          aria-pressed={crossProbeEnabled}
          aria-label="Toggle cross-probe mode"
          onClick={() => setCrossProbeEnabled((current) => !current)}
        >
          Cross-probe (X)
        </button>
        <button
          type="button"
          className="design-text-button"
          disabled={!selection?.net?.trim() && !selection?.uuid}
          onClick={() => handleCrossProbeShortcut("h")}
          aria-label="Highlight selected net"
        >
          Highlight net (H)
        </button>
        {view === "pcb" && (
          <button
            type="button"
            className="design-text-button design-layer-toggle"
            aria-expanded={mobileLayersOpen}
            aria-controls="native-pcb-layers"
            onClick={() => setMobileLayersOpen((open) => !open)}
          >
            Layers
          </button>
        )}
      </form>
      {status && (
        <div role="status" className="design-selection-status">
          {status}
        </div>
      )}
      {(["pcb", "schematic"] as const).map((context) => {
        const path = context === "pcb" ? pcb : schematic;
        const data = loaded[context];
        const current = data?.key === `${revision}:${path}`;
        return (
          <div key={context} hidden={view !== context} className="relative min-h-0 flex-1">
            <div className="flex h-full min-h-0">
              <div className="relative min-w-0 flex-1">
                {data && (view === context || visited.has(context)) && (
                  <NativeFrame
                    key={path}
                    view={context}
                    sources={data.sources}
                    revision={data.key}
                    active={view === context}
                    layerVisibility={context === "pcb" ? layerVisibility : {}}
                    probe={
                      probe?.targetContext === (context === "pcb" ? "PCB" : "SCH") && current
                        ? probe
                        : undefined
                    }
                    netHighlight={
                      netHighlight &&
                      (netHighlight.clear ||
                        !netHighlight.targetContext ||
                        netHighlight.targetContext === (context === "pcb" ? "PCB" : "SCH"))
                        ? netHighlight
                        : undefined
                    }
                    onSelection={(item, userInitiated) => {
                      if (view === context) {
                        setSelection(item);
                        setStatus(item?.reference ?? item?.designator ?? item?.net ?? "");
                        if (!item?.net && netHighlight && !netHighlight.clear)
                          setNetHighlight({ id: ++requestId.current, clear: true });
                        if (item && userInitiated && crossProbeEnabled) crossProbe(item);
                      }
                    }}
                    onProbe={(item, userInitiated) => {
                      if (userInitiated && crossProbeEnabled) crossProbe(item);
                    }}
                    onKey={handleCrossProbeShortcut}
                    onLayers={(next) => {
                      if (context !== "pcb") return;
                      setLayers((old) => (sameNativeLayers(old, next) ? old : next));
                      setLayerVisibility((old) => mergeNativeLayerVisibility(next, old));
                    }}
                    onResult={(found, value) =>
                      setStatus(
                        found ? `Located ${value}` : `No match for ${value} in this ${context}.`,
                      )
                    }
                  />
                )}
              </div>
              {context === "pcb" && view === "pcb" && layers.length > 0 && (
                <aside
                  id="native-pcb-layers"
                  className="design-layer-panel"
                  aria-label="PCB layers"
                  data-mobile-open={mobileLayersOpen}
                >
                  <div className="design-layer-title">Layers</div>
                  {nativeLayerSections(layers).map(([section, sectionLayers]) => (
                    <section key={section} className="design-layer-section">
                      <h2>{section}</h2>
                      {sectionLayers.map((layer) => (
                        <label key={layer.id} className="design-layer-row">
                          <input
                            type="checkbox"
                            checked={layerVisibility[layer.id] !== false}
                            onChange={(event) =>
                              setLayerVisibility((old) => ({
                                ...old,
                                [layer.id]: event.target.checked,
                              }))
                            }
                          />
                          <i style={{ backgroundColor: layer.color }} aria-hidden="true" />
                          <span>{layer.name}</span>
                        </label>
                      ))}
                    </section>
                  ))}
                </aside>
              )}
            </div>
            {!data && (
              <div
                role="status"
                className="absolute inset-0 flex items-center justify-center bg-background p-4 text-center text-xs text-muted-foreground"
              >
                {path
                  ? (errors[context] ?? "Loading saved project…")
                  : `Choose a ${context === "pcb" ? "PCB" : "schematic"} with Browse to open this view.`}
              </div>
            )}
            {data && !current && !errors[context] && (
              <div className="design-update-badge" role="status">
                Updating saved files…
              </div>
            )}
            {data && errors[context] && (
              <div className="design-update-badge design-update-error" role="status">
                Saved-file update failed; showing the last good view.
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
