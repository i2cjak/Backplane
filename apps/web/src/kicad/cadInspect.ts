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
