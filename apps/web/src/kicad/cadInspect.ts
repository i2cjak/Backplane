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
