import { installCanvasPresentation } from "./canvas-presentation.js";
import { installSchematicSizing } from "./schematic-sizing.js";
import { installNativeTouch } from "./native-touch.js";
import { installMobileProperties } from "./properties-mobile.js";

// A frame owns each renderer's workers and GPU lifetime.
const host = document.getElementById("viewer");
const error = document.getElementById("error");
let viewer;
let chain = Promise.resolve();
let revision;
let probeId;
let model;
const send = (message) =>
  parent.postMessage(message, location.origin === "null" ? "*" : location.origin);
window.addEventListener("message", (event) => {
  if (
    event.source !== parent ||
    event.origin !== location.origin ||
    event.data?.type !== "backplane-snapshot"
  )
    return;
  const snapshot = event.data;
  if (snapshot.kind === "model" || snapshot.kind === "step") {
    void (async () => {
      if (!model) {
        model = import("./board-model.js").then(({ createBoardModel }) =>
          createBoardModel(host, error, { kind: snapshot.kind }),
        );
      }
      const renderer = await model;
      renderer.setActive(snapshot.active !== false);
      if (snapshot.active !== false) await renderer.update(snapshot.url);
    })().catch((cause) => {
      error.textContent = cause.message || String(cause);
    });
    return;
  }
  chain = chain
    .then(async () => {
      error.textContent = "";
      {
        if (!viewer) {
          host.style.visibility = "hidden";
          await import("./ecad-viewer.js");
          const { RetainedNativeViewer } = await import("./retained-native-viewer.js");
          viewer = new RetainedNativeViewer(host);
          viewer.addEventListener("selection", (event) =>
            send({ type: "backplane-selection", selection: event.detail }),
          );
          viewer.addEventListener("crossprobe", (event) =>
            send({ type: "backplane-crossprobe", selection: event.detail }),
          );
          viewer.addEventListener("layers", (event) =>
            send({ type: "backplane-layers", layers: event.detail }),
          );
        }
        if (revision !== snapshot.revision) {
          error.classList.toggle("refresh-status", Boolean(viewer.current));
          error.textContent = viewer.current ? "Updating preview…" : "Loading preview…";
          await viewer.replaceSources({
            revisionKey: snapshot.revision,
            sources: snapshot.sources,
            layerVisibility: snapshot.layerVisibility,
          });
          revision = snapshot.revision;
          error.textContent = "";
        }
        await viewer.ready;
        if (snapshot.layerVisibility) {
          for (const [name, visible] of Object.entries(snapshot.layerVisibility))
            viewer.setLayerVisibility(name, Boolean(visible));
        }
        viewer.setActive(snapshot.active !== false);
        if (snapshot.active !== false) {
          viewer.resize();
          const native = viewer.current;
          if (native) {
            await installCanvasPresentation(native);
            viewer.reseedLayerCache();
            viewer.enhanceGeometrySelection();
            viewer.publishLayers();
            host.style.visibility = "visible";
            installSchematicSizing(native);
            installNativeTouch(native);
            installMobileProperties(native);
          }
          if (snapshot.probe && probeId !== snapshot.probe.id) {
            probeId = snapshot.probe.id;
            const found = viewer.requestCrossProbe(snapshot.probe);
            send({ type: "backplane-probe-result", found, value: snapshot.probe.value });
          }
        }
      }
    })
    .catch((cause) => {
      error.textContent = cause.message || String(cause);
    });
});
parent.postMessage(
  { type: "backplane-runtime-ready" },
  location.origin === "null" ? "*" : location.origin,
);
