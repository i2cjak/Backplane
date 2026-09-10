import type { NativeLayer } from "./NativeProjectViews";

export function mergeNativeLayerVisibility(
  layers: NativeLayer[],
  previous: Record<string, boolean>,
): Record<string, boolean> {
  return Object.fromEntries(layers.map((layer) => [layer.id, previous[layer.id] ?? layer.visible]));
}

export function nativeLayerSections(layers: NativeLayer[]): Array<[string, NativeLayer[]]> {
  const grouped = new Map<string, NativeLayer[]>();
  for (const layer of layers)
    grouped.set(layer.section, [...(grouped.get(layer.section) ?? []), layer]);
  return [...grouped.entries()];
}
