export interface GerberLayerResource {
  revision: string;
  svg: string;
}

export type GerberLayerResources = Readonly<Record<string, GerberLayerResource>>;

/**
 * Commit one response without replacing resources for untouched layers. A
 * response from an older manifest revision is ignored so a slow request cannot
 * roll a layer back after a newer save has painted.
 */
export function commitGerberLayer(
  resources: GerberLayerResources,
  path: string,
  responseRevision: string,
  currentRevision: string,
  svg: string,
): GerberLayerResources {
  if (responseRevision !== currentRevision) return resources;
  const previous = resources[path];
  if (previous?.revision === responseRevision && previous.svg === svg) return resources;
  if (previous?.svg === svg)
    return { ...resources, [path]: { ...previous, revision: responseRevision } };
  return { ...resources, [path]: { revision: responseRevision, svg } };
}
