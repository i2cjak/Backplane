import { useEffect, useRef, useState } from "react";
import { preferredInspectSolid } from "./cadInspect";

export type InspectConfig = {
  enclosure?: { params?: string; solids?: Record<string, string> };
  product?: { scene?: string; still?: string; loadViz?: string };
};

function Notice({ text }: { text: string }) {
  return (
    <div
      className="flex h-full items-center justify-center p-6 text-center text-xs text-muted-foreground"
      role="status"
    >
      {text}
    </div>
  );
}

function workspaceRelative(root: string, value: string): string | undefined {
  const normalized = value.replaceAll("\\", "/");
  if (!normalized.startsWith("/")) return normalized;
  const prefix = `${root.replace(/\/$/, "")}/`;
  if (normalized.startsWith(prefix)) return normalized.slice(prefix.length);
  return undefined;
}

function StlFrame({ url, title }: { url: string; title: string }) {
  const ref = useRef<HTMLIFrameElement>(null);
  const origin = location.origin === "null" ? "*" : location.origin;
  useEffect(() => {
    const send = (event: MessageEvent) => {
      if (
        event.source === ref.current?.contentWindow &&
        event.origin === location.origin &&
        event.data?.type === "backplane-runtime-ready"
      ) {
        ref.current?.contentWindow?.postMessage(
          { type: "backplane-snapshot", kind: "stl", url },
          origin,
        );
      }
    };
    window.addEventListener("message", send);
    return () => window.removeEventListener("message", send);
  }, [origin, url]);
  useEffect(() => {
    ref.current?.contentWindow?.postMessage(
      { type: "backplane-snapshot", kind: "stl", url },
      origin,
    );
  }, [origin, url]);
  return (
    <iframe
      ref={ref}
      title={title}
      src="/kicad-viewer/stl-runtime.html"
      allow="webgl"
      className="block h-full w-full border-0"
    />
  );
}

function SnapshotFrame({
  url,
  title,
  kind,
  src,
}: {
  url: string;
  title: string;
  kind: "model" | "step" | "stl";
  src: string;
}) {
  const ref = useRef<HTMLIFrameElement>(null);
  const origin = location.origin === "null" ? "*" : location.origin;
  useEffect(() => {
    const send = (event: MessageEvent) => {
      if (
        event.source === ref.current?.contentWindow &&
        event.origin === location.origin &&
        event.data?.type === "backplane-runtime-ready"
      ) {
        ref.current?.contentWindow?.postMessage({ type: "backplane-snapshot", kind, url }, origin);
      }
    };
    window.addEventListener("message", send);
    return () => window.removeEventListener("message", send);
  }, [kind, origin, url]);
  useEffect(() => {
    ref.current?.contentWindow?.postMessage({ type: "backplane-snapshot", kind, url }, origin);
  }, [kind, origin, url]);
  return (
    <iframe
      ref={ref}
      title={title}
      src={src}
      allow="webgl"
      className="block h-full w-full border-0"
    />
  );
}

function GlbFrame({ url, title }: { url: string; title: string }) {
  const ref = useRef<HTMLIFrameElement>(null);
  const origin = location.origin === "null" ? "*" : location.origin;
  useEffect(() => {
    const send = (event: MessageEvent) => {
      if (
        event.source === ref.current?.contentWindow &&
        event.origin === location.origin &&
        event.data?.type === "backplane-runtime-ready"
      ) {
        ref.current?.contentWindow?.postMessage(
          { type: "backplane-snapshot", kind: "model", url },
          origin,
        );
      }
    };
    window.addEventListener("message", send);
    return () => window.removeEventListener("message", send);
  }, [origin, url]);
  useEffect(() => {
    ref.current?.contentWindow?.postMessage(
      { type: "backplane-snapshot", kind: "model", url },
      origin,
    );
  }, [origin, url]);
  return (
    <iframe
      ref={ref}
      title={title}
      src="/kicad-viewer/runtime.html"
      allow="webgl"
      className="block h-full w-full border-0"
    />
  );
}

export function EnclosureView({
  config,
  revision,
  modelUrl,
  readJson,
}: {
  config: InspectConfig;
  workspace: string;
  revision: string;
  modelUrl: (path: string) => string;
  readJson: (path: string) => Promise<unknown>;
}) {
  const solids = Object.entries(config.enclosure?.solids ?? {});
  const [selected, setSelected] = useState(
    preferredInspectSolid(config.enclosure?.solids) ?? solids[0]?.[0] ?? "",
  );
  const [params, setParams] = useState<Record<string, unknown> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const path = config.enclosure?.solids?.[selected];
  useEffect(() => {
    if (!solids.some(([name]) => name === selected)) setSelected(solids[0]?.[0] ?? "");
  }, [selected, solids]);
  useEffect(() => {
    const paramsPath = config.enclosure?.params;
    if (!paramsPath) {
      setParams(null);
      return;
    }
    let cancelled = false;
    void readJson(paramsPath)
      .then((value) => {
        if (!cancelled)
          setParams(value && typeof value === "object" ? (value as Record<string, unknown>) : null);
      })
      .catch((cause: unknown) => {
        if (!cancelled) setError(cause instanceof Error ? cause.message : String(cause));
      });
    return () => {
      cancelled = true;
    };
  }, [config.enclosure?.params, readJson, revision]);
  if (!solids.length && !config.enclosure?.params) {
    return (
      <Notice text="No enclosure inspect files. Set enclosure.solids and enclosure.params in .backplane.json." />
    );
  }
  const extension = path ? path.slice(path.lastIndexOf(".")).toLowerCase() : "";
  const remaining =
    params && typeof params.remaining_bay === "object" && params.remaining_bay
      ? (params.remaining_bay as Record<string, unknown>)
      : undefined;
  const pcb =
    params && typeof params.pcb === "object" && params.pcb
      ? (params.pcb as Record<string, unknown>)
      : undefined;
  const plate =
    params && typeof params.plate === "object" && params.plate
      ? (params.plate as Record<string, unknown>)
      : undefined;
  const loadCell =
    params && typeof params.load_cell === "object" && params.load_cell
      ? (params.load_cell as Record<string, unknown>)
      : undefined;
  const clearance = params?.clearance_mm ?? plate?.clearance_mm;
  const stopGap = params?.stop_gap_mm ?? loadCell?.stop_gap_mm;
  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-3 py-1.5 text-xs">
        <label className="flex min-w-0 flex-1 items-center gap-2">
          Solid
          <select
            aria-label="FreeCAD solid"
            className="min-w-0 flex-1 rounded border border-border bg-background px-1.5 py-1"
            value={selected}
            onChange={(event) => setSelected(event.target.value)}
          >
            {!solids.length && <option value="">No solids</option>}
            {solids.map(([name, solidPath]) => (
              <option key={name} value={name}>
                {name} ({solidPath})
              </option>
            ))}
          </select>
        </label>
        <span className="text-muted-foreground">Saved files</span>
      </div>
      {error ? <div className="px-3 py-2 text-xs text-muted-foreground">{error}</div> : null}
      <div className="min-h-0 flex-1">
        {!path ? (
          <Notice text="Select a solid from enclosure.solids." />
        ) : extension === ".glb" || extension === ".gltf" ? (
          <GlbFrame
            key={`${path}:${revision}`}
            url={modelUrl(path)}
            title={`Enclosure ${selected}`}
          />
        ) : extension === ".step" || extension === ".stp" ? (
          <SnapshotFrame
            key={`${path}:${revision}`}
            kind="step"
            src="/kicad-viewer/runtime.html"
            url={modelUrl(path)}
            title={`Enclosure ${selected}`}
          />
        ) : (
          <StlFrame
            key={`${path}:${revision}`}
            url={modelUrl(path)}
            title={`Enclosure ${selected}`}
          />
        )}
      </div>
      <dl className="grid shrink-0 grid-cols-2 gap-x-3 gap-y-1 border-t border-border px-3 py-2 text-[11px] sm:grid-cols-4">
        <div>
          <dt className="text-muted-foreground">clearance_mm</dt>
          <dd>{String(clearance ?? "-")}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">stop_gap_mm</dt>
          <dd>{String(stopGap ?? "-")}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">PCB</dt>
          <dd>
            {pcb?.width_mm != null && pcb?.height_mm != null
              ? `${pcb.width_mm} x ${pcb.height_mm} mm`
              : "-"}
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">remaining bay</dt>
          <dd>
            {remaining?.width_mm != null && remaining?.depth_mm != null
              ? `${remaining.width_mm} x ${remaining.depth_mm} mm`
              : "-"}
          </dd>
        </div>
      </dl>
    </div>
  );
}

export function ProductView({
  config,
  workspace,
  revision,
  assetUrl,
  readJson,
}: {
  config: InspectConfig;
  workspace: string;
  revision: string;
  assetUrl: (path: string) => string;
  readJson: (path: string) => Promise<unknown>;
}) {
  const [scene, setScene] = useState<Record<string, unknown> | null>(null);
  const [viz, setViz] = useState<Record<string, unknown> | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      if (config.product?.scene) {
        const value = await readJson(config.product.scene);
        if (!cancelled)
          setScene(value && typeof value === "object" ? (value as Record<string, unknown>) : null);
      } else setScene(null);
      if (config.product?.loadViz) {
        const value = await readJson(config.product.loadViz);
        if (!cancelled)
          setViz(value && typeof value === "object" ? (value as Record<string, unknown>) : null);
      } else setViz(null);
    };
    void load().catch((cause: unknown) => {
      if (!cancelled) setError(cause instanceof Error ? cause.message : String(cause));
    });
    return () => {
      cancelled = true;
    };
  }, [config.product?.loadViz, config.product?.scene, readJson, revision]);
  if (!config.product?.still && !config.product?.scene && !config.product?.loadViz) {
    return (
      <Notice text="No product inspect files. Set product.still, product.scene, and product.loadViz in .backplane.json." />
    );
  }
  const required = Array.isArray(scene?.required) ? scene.required.map(String) : [];
  const outputs =
    viz && typeof viz.outputs === "object" && viz.outputs
      ? Object.entries(viz.outputs as Record<string, unknown>)
          .map(([name, value]) =>
            typeof value === "string"
              ? ([name, workspaceRelative(workspace, value)] as const)
              : null,
          )
          .filter((entry): entry is readonly [string, string] => Boolean(entry?.[1]))
      : [];
  return (
    <div className="flex h-full min-h-0 flex-col overflow-auto">
      {error ? <div className="px-3 py-2 text-xs text-muted-foreground">{error}</div> : null}
      <div className="grid min-h-0 flex-1 gap-3 p-3 lg:grid-cols-2">
        <figure className="min-h-0">
          <figcaption className="mb-1 text-[11px] text-muted-foreground">Product still</figcaption>
          {config.product?.still ? (
            <img
              alt="Blender product still"
              className="max-h-[48vh] w-full rounded border border-border bg-black object-contain"
              src={`${assetUrl(config.product.still)}&revision=${revision}`}
            />
          ) : (
            <Notice text="Set product.still in .backplane.json." />
          )}
        </figure>
        <div>
          <p className="mb-1 text-[11px] text-muted-foreground">Scene required objects</p>
          {required.length ? (
            <ul className="text-xs">
              {required.map((name) => (
                <li key={name}>{name}</li>
              ))}
            </ul>
          ) : (
            <p className="text-xs text-muted-foreground">No blender-scene.json required list.</p>
          )}
        </div>
        {outputs.map(([name, path]) => (
          <figure key={name}>
            <figcaption className="mb-1 text-[11px] text-muted-foreground">
              load-viz {name}
            </figcaption>
            <img
              alt={`${name} load visualization`}
              className="max-h-56 w-full rounded border border-border bg-black object-contain"
              src={`${assetUrl(path)}&revision=${revision}`}
            />
          </figure>
        ))}
      </div>
    </div>
  );
}
