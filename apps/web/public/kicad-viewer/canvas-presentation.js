const presentations = new WeakMap();
const fitted = new WeakSet();
let themePromise;
const darkFallback = {
  board: {
    background: "rgb(30, 30, 30)",
    grid: "rgb(50, 50, 50)",
    grid_axes: "rgb(80, 80, 80)",
    copper: { f: "rgb(224, 122, 95)", b: "rgb(126, 184, 218)" },
    f_silks: "rgb(220, 220, 220)",
    b_silks: "rgb(143, 188, 187)",
  },
  schematic: {
    background: "rgb(30, 30, 30)",
    sheet_background: "rgba(60, 65, 70, 0.600)",
    component_body: "rgb(50, 50, 55)",
    component_outline: "rgb(224, 122, 95)",
    fields: "rgb(143, 188, 187)",
    reference: "rgb(200, 200, 200)",
    value: "rgb(143, 188, 187)",
    wire: "rgb(143, 188, 187)",
    pin: "rgb(224, 122, 95)",
    pin_name: "rgb(200, 200, 200)",
    pin_number: "rgb(224, 122, 95)",
    grid: "rgb(50, 50, 50)",
    grid_axes: "rgb(50, 50, 50)",
  },
};

function loadTheme() {
  return (themePromise ??= fetch(new URL("./american-embedded-dark.json", import.meta.url))
    .then((response) => {
      if (!response.ok)
        throw new Error(`Unable to load the bundled KiCad theme (${response.status})`);
      return response.json();
    })
    .catch(() => darkFallback));
}

function convertPalette(value, Color) {
  if (typeof value === "string") return Color.from_css(value);
  if (Array.isArray(value)) return value.map((item) => convertPalette(item, Color));
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, convertPalette(item, Color)]),
    );
  return value;
}

/** Apply the bundled American Embedded dark palette after the renderer initializes. */
export async function installCanvasPresentation(element) {
  const definition = await loadTheme();
  document.documentElement.dataset.colorScheme = "dark";
  for (const name of ["kc-board-app", "kc-schematic-app"]) {
    const viewer = element.shadowRoot?.querySelector(name)?.viewer;
    if (!viewer || presentations.has(viewer)) continue;
    const color = viewer.renderer.background_color.constructor;
    const section = name === "kc-board-app" ? "board" : "schematic";
    viewer.theme = {
      ...viewer.theme,
      ...convertPalette(definition?.[section] ?? darkFallback[section], color),
    };
    viewer.__backplaneLayerCache?.clear();
    if (!viewer.__backplaneHiddenWorksheet) {
      const paint = viewer.paint.bind(viewer);
      const hidePaper = () => {
        const names =
          section === "board"
            ? [":DrawingSheet", ":DrawingSheet:Background"]
            : [":DrawingSheet:Background"];
        for (const name of names) {
          const paper = viewer.layers?.by_name?.(name);
          if (paper) paper.visible = false;
        }
      };
      viewer.paint = (...args) => {
        const result = paint(...args);
        hidePaper();
        return result;
      };
      viewer.__backplaneHiddenWorksheet = true;
    }
    viewer.renderer.background_color = viewer.theme.background;
    if (viewer.renderer.gl) viewer.renderer.gl.clearColor(...viewer.theme.background.to_array());
    if (!fitted.has(viewer)) {
      const fit = viewer.zoom_fit_top_item.bind(viewer);
      viewer.zoom_fit_top_item = () => {
        fit();
        // Leave room for pads and mounting features that extend beyond the board outline.
        viewer.viewport.camera.zoom *= 0.88;
        viewer.draw();
      };
      viewer.zoom_fit_top_item();
      fitted.add(viewer);
    }
    viewer.paint();
    const names =
      section === "board"
        ? [":DrawingSheet", ":DrawingSheet:Background"]
        : [":DrawingSheet:Background"];
    for (const name of names) {
      const paper = viewer.layers?.by_name?.(name);
      if (paper) paper.visible = false;
    }
    viewer.draw();
    presentations.set(viewer, true);
  }
  if (element.parentElement.querySelector(".canvas-actions")) return;
  const bar = document.createElement("div");
  bar.className = "canvas-actions";
  bar.setAttribute("role", "toolbar");
  bar.setAttribute("aria-label", "Canvas navigation");
  const activeViewer = () =>
    ["kc-board-app", "kc-schematic-app"]
      .map((name) => element.shadowRoot?.querySelector(name)?.viewer)
      .find((viewer) => viewer?.active);
  for (const [label, text, action] of [
    [
      "Zoom out",
      "−",
      (viewer) => {
        viewer.viewport.camera.zoom /= 1.25;
        viewer.draw();
      },
    ],
    ["Fit design", "Fit design", (viewer) => viewer.zoom_fit_top_item()],
    [
      "Zoom in",
      "+",
      (viewer) => {
        viewer.viewport.camera.zoom *= 1.25;
        viewer.draw();
      },
    ],
  ]) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = text;
    button.setAttribute("aria-label", label);
    button.addEventListener("click", () => {
      const viewer = activeViewer();
      if (viewer) action(viewer);
    });
    bar.appendChild(button);
  }
  element.parentElement.appendChild(bar);
}
