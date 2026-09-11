import { useEffect, useRef, useState } from "react";
import { preferredInspectSolid, productInspectSolids, productInspectStills } from "./cadInspect";

export type InspectConfig = {
  enclosure?: { solids?: Record<string, string> };
  product?: {
    still?: string;
    renders?: Record<string, string>;
    solids?: Record<string, string>;
  };
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

function SnapshotFrame({
  url,
  title,
  kind,
}: {
  url: string;
  title: string;
  kind: "model" | "step";
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
}: {
  config: InspectConfig;
  revision: string;
  modelUrl: (path: string) => string;
}) {
  const solids = Object.entries(config.enclosure?.solids ?? {});
  const preferred = preferredInspectSolid(config.enclosure?.solids) ?? solids[0]?.[0] ?? "";
  const [selected, setSelected] = useState(preferred);
  const active = solids.some(([name]) => name === selected) ? selected : preferred;
  const path = config.enclosure?.solids?.[active];
  if (!solids.length) {
    return <Notice text="No enclosure inspect files. Set enclosure.solids in .backplane.json." />;
  }
  const extension = path ? path.slice(path.lastIndexOf(".")).toLowerCase() : "";
  const kind =
    extension === ".glb" || extension === ".gltf"
      ? "model"
      : extension === ".step" || extension === ".stp"
        ? "step"
        : null;
  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-3 py-1.5 text-xs">
        <label className="flex min-w-0 flex-1 items-center gap-2">
          Solid
          <select
            aria-label="FreeCAD solid"
            className="min-w-0 flex-1 rounded border border-border bg-background px-1.5 py-1"
            value={active}
            onChange={(event) => setSelected(event.target.value)}
          >
            {solids.map(([name, solidPath]) => (
              <option key={name} value={name}>
                {name} ({solidPath})
              </option>
            ))}
          </select>
        </label>
        <span className="text-muted-foreground">Saved files</span>
      </div>
      <div className="min-h-0 flex-1">
        {!path ? (
          <Notice text="Select a solid from enclosure.solids." />
        ) : kind ? (
          <SnapshotFrame
            key={`${path}:${revision}`}
            kind={kind}
            url={modelUrl(path)}
            title={`Enclosure ${active}`}
          />
        ) : (
          <Notice text="FreeCAD inspect previews GLB, GLTF, STEP, or STP." />
        )}
      </div>
    </div>
  );
}

export function ProductView({
  config,
  revision,
  assetUrl,
  modelUrl,
}: {
  config: InspectConfig;
  revision: string;
  assetUrl: (path: string) => string;
  modelUrl: (path: string) => string;
}) {
  const solids = productInspectSolids(config.product);
  const stills = productInspectStills(config.product);
  const preferredSolid = solids.find((item) => item.preview === "step")?.id ?? solids[0]?.id ?? "";
  const [solidId, setSolidId] = useState(preferredSolid);
  const [stillId, setStillId] = useState(stills[0]?.id ?? "");
  const solid = solids.find((item) => item.id === solidId) ?? solids[0];
  const still = stills.find((item) => item.id === stillId) ?? stills[0];
  if (!solids.length && !stills.length) {
    return (
      <Notice text="No product inspect files. Set product.solids, product.still, or product.renders in .backplane.json." />
    );
  }
  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-3 py-1.5 text-xs">
        {solids.length ? (
          <label className="flex min-w-0 flex-1 items-center gap-2">
            3D
            <select
              aria-label="Blender product solid"
              className="min-w-0 flex-1 rounded border border-border bg-background px-1.5 py-1"
              value={solid?.id ?? ""}
              onChange={(event) => setSolidId(event.target.value)}
            >
              {solids.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.label}
                </option>
              ))}
            </select>
          </label>
        ) : null}
        {stills.length ? (
          <label className="flex min-w-0 flex-1 items-center gap-2">
            Render
            <select
              aria-label="Blender product still"
              className="min-w-0 flex-1 rounded border border-border bg-background px-1.5 py-1"
              value={still?.id ?? ""}
              onChange={(event) => setStillId(event.target.value)}
            >
              {stills.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.label}
                </option>
              ))}
            </select>
          </label>
        ) : null}
        <span className="text-muted-foreground">Saved files</span>
      </div>
      <div className={`grid min-h-0 flex-1 ${solid && still ? "grid-rows-2" : "grid-rows-1"}`}>
        {solid && (solid.preview === "model" || solid.preview === "step") ? (
          <SnapshotFrame
            key={`${solid.path}:${revision}`}
            kind={solid.preview}
            url={modelUrl(solid.path)}
            title={`Product ${solid.label}`}
          />
        ) : null}
        {still ? (
          <div className="flex min-h-0 items-center justify-center overflow-auto p-3">
            <img
              alt={`Blender ${still.label}`}
              className="max-h-full max-w-full rounded border border-border bg-black object-contain"
              src={`${assetUrl(still.path)}&revision=${revision}`}
            />
          </div>
        ) : null}
      </div>
    </div>
  );
}
