const installed = new WeakSet();

/** Keep DNP parts neutral and readable; their cross marks still identify them. */
export function installSchematicContrast(viewer) {
  if (!viewer?.create_painter || installed.has(viewer)) return;
  const decorate = (painter) => {
    const fills = new Set([
      viewer.theme.background,
      viewer.theme.component_body,
      viewer.theme.sheet_background,
      viewer.theme.note_background,
    ]);
    for (const item of new Set(painter.painters?.values() ?? [])) {
      if (typeof item.dim_color !== "function") continue;
      const dim = item.dim_color.bind(item);
      // The native half-background mix makes references and values unreadable.
      // Use the palette's checked neutral foreground, retaining native fill dimming.
      item.dim_color = (color) => (fills.has(color) ? dim(color) : viewer.theme.hidden);
    }
    return painter;
  };
  const create = viewer.create_painter.bind(viewer);
  viewer.create_painter = (...args) => decorate(create(...args));
  if (viewer.painter) decorate(viewer.painter);
  installed.add(viewer);
}
