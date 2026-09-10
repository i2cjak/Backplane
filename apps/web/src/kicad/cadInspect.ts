/** First-class inspect surfaces that sit beside KiCad in the right panel. Extra domains stay in `.backplane.json` drivers. */
export const CAD_INSPECT_KINDS = ["kicad", "freecad", "blender"] as const;
export type CadInspectKind = (typeof CAD_INSPECT_KINDS)[number];
export type CadInspectView = "pcb" | "enclosure" | "product";

export interface CadInspectSurface {
  readonly kind: CadInspectKind;
  readonly label: string;
  readonly view: CadInspectView;
  readonly shortcut: string;
  readonly description: string;
}

export const CAD_INSPECT_SURFACES: readonly CadInspectSurface[] = [
  {
    kind: "kicad",
    label: "KiCad",
    view: "pcb",
    shortcut: "K",
    description: "Inspect the current electronics project.",
  },
  {
    kind: "freecad",
    label: "FreeCAD",
    view: "enclosure",
    shortcut: "E",
    description: "Inspect saved enclosure solids.",
  },
  {
    kind: "blender",
    label: "Blender",
    view: "product",
    shortcut: "V",
    description: "Inspect saved product stills.",
  },
];

export function cadInspectViewForKind(kind: string): CadInspectView | undefined {
  const surface = CAD_INSPECT_SURFACES.find((entry) => entry.kind === kind);
  return surface?.view;
}

export function cadInspectLabelForKind(kind: string): string | undefined {
  return CAD_INSPECT_SURFACES.find((entry) => entry.kind === kind)?.label;
}

export function isCadInspectKind(kind: string): kind is CadInspectKind {
  return CAD_INSPECT_SURFACES.some((entry) => entry.kind === kind);
}

/** KiCad's own viewer tabs. FreeCAD/Blender are sibling panels, never rows in this list. */
export const KICAD_INNER_TABS = [
  { id: "schematic", label: "Schematic" },
  { id: "pcb", label: "PCB" },
  { id: "3d", label: "3D" },
  { id: "gerbers", label: "Gerbers" },
  { id: "step", label: "STEP" },
] as const;

export const KICAD_OPTIONAL_TABS = [
  { id: "bom", label: "BOM" },
  { id: "footprint", label: "Footprints" },
  { id: "symbol", label: "Symbols" },
  { id: "analysis", label: "Analysis" },
] as const;

export function isSiblingInspectView(
  view: string | null | undefined,
): view is "enclosure" | "product" {
  return view === "enclosure" || view === "product";
}

export function inspectSurfaceKind(view: string | null | undefined): CadInspectKind {
  if (view === "enclosure") return "freecad";
  if (view === "product") return "blender";
  return "kicad";
}

export function viewerHashView(
  value: string | null,
): CadInspectView | "schematic" | "3d" | "step" | "gerbers" | undefined {
  if (
    value === "pcb" ||
    value === "enclosure" ||
    value === "product" ||
    value === "schematic" ||
    value === "3d" ||
    value === "step" ||
    value === "gerbers"
  )
    return value;
  return undefined;
}

function viewParam(source: string, leading: "#" | "?"): string | null {
  const body = source.startsWith(leading) ? source.slice(1) : source;
  return new URLSearchParams(body).get("view");
}

/** Hash wins so sibling iframes stay compatible; search is the reload key when switching panels. */
export function readViewerView(hash: string, search = ""): string | undefined {
  const value = viewParam(hash, "#") ?? viewParam(search, "?");
  if (!value) return undefined;
  if (isSiblingInspectView(value)) return value;
  if (
    KICAD_INNER_TABS.some((tab) => tab.id === value) ||
    KICAD_OPTIONAL_TABS.some((tab) => tab.id === value)
  )
    return value;
  return viewerHashView(value);
}

export function cadInspectViewerSearch(view: CadInspectView): string {
  return new URLSearchParams({ view }).toString();
}

export function cadInspectOpenHint(view: string | null | undefined): string {
  const label = cadInspectLabelForKind(inspectSurfaceKind(view)) ?? "KiCad";
  return `Open this viewer from the project's ${label} panel.`;
}

/** Prefer GLB/STEP so FreeCAD inspect uses the working 3D runtime, not a nested STL iframe. */
export function preferredInspectSolid(
  solids: Readonly<Record<string, string>> | undefined,
): string | undefined {
  if (!solids) return undefined;
  const entries = Object.entries(solids);
  const ranked =
    entries.find(([, path]) => /\.(?:glb|gltf)$/i.test(path)) ??
    entries.find(([, path]) => /\.(?:step|stp)$/i.test(path)) ??
    entries[0];
  return ranked?.[0];
}
