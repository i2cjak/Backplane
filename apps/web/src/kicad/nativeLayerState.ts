import type { NativeLayer } from "./NativeProjectViews";

const sameNativeLayer = (left: NativeLayer, right: NativeLayer | undefined) =>
  right !== undefined &&
  left.id === right.id &&
  left.name === right.name &&
  left.section === right.section &&
  left.color === right.color &&
  left.visible === right.visible;

export function sameNativeLayers(left: NativeLayer[], right: NativeLayer[]): boolean {
  return (
    left.length === right.length &&
    left.every((layer, index) => sameNativeLayer(layer, right[index]))
  );
}

export function mergeNativeLayerVisibility(
  layers: NativeLayer[],
  previous: Record<string, boolean>,
): Record<string, boolean> {
  const next = Object.fromEntries(
    layers.map((layer) => [layer.id, previous[layer.id] ?? layer.visible]),
  );
  const previousKeys = Object.keys(previous);
  const nextKeys = Object.keys(next);
  if (
    previousKeys.length === nextKeys.length &&
    nextKeys.every((key) => previous[key] === next[key])
  )
    return previous;
  return next;
}

export function nativeLayerSections(layers: NativeLayer[]): Array<[string, NativeLayer[]]> {
  const grouped = new Map<string, NativeLayer[]>();
  for (const layer of layers)
    grouped.set(layer.section, [...(grouped.get(layer.section) ?? []), layer]);
  return [...grouped.entries()];
}
