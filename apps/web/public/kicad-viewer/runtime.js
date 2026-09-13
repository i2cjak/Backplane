import { installCanvasPresentation } from "./canvas-presentation.js";
import { installSchematicSizing } from "./schematic-sizing.js";
import { installNativeTouch } from "./native-touch.js";
import { installMobileProperties } from "./properties-mobile.js";
import { installSchematicHierarchy } from "./schematic-hierarchy.js";

// A frame owns each renderer's workers and GPU lifetime.
const host = document.getElementById("viewer");
const error = document.getElementById("error");
let viewer;
let chain = Promise.resolve();
let revision;
let probeId;
let netHighlightId;
let model;
let nativeActive = false;
const send = (message) =>
  parent.postMessage(message, location.origin === "null" ? "*" : location.origin);
const editableTarget = (target) =>
  target instanceof Element &&
  (target.isContentEditable || /^(?:INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
window.addEventListener("keydown", (event) => {
  if (
    !nativeActive ||
    event.repeat ||
    event.defaultPrevented ||
    event.ctrlKey ||
    event.metaKey ||
    event.altKey ||
    event.composedPath().some(editableTarget)
  )
    return;
  if (
    event.key === "x" ||
    event.key === "X" ||
    event.key === "h" ||
    event.key === "H" ||
    event.key === "Escape"
  )
    send({ type: "backplane-native-key", key: event.key });
});
window.addEventListener("message", (event) => {
  if (
    event.source !== parent ||
    event.origin !== location.origin ||
    event.data?.type !== "backplane-snapshot"
  )
    return;
  const snapshot = event.data;
  if (snapshot.kind === "model" || snapshot.kind === "step") {
    nativeActive = false;
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
  nativeActive = snapshot.active !== false;
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
            send({
              type: "backplane-selection",
              selection: event.detail,
              userInitiated: event.detail?.userInitiated === true,
            }),
          );
          viewer.addEventListener("crossprobe", (event) =>
            send({
              type: "backplane-crossprobe",
              selection: event.detail,
              userInitiated: event.detail?.userInitiated === true,
            }),
          );
          viewer.addEventListener("layers", (event) =>
            send({ type: "backplane-layers", layers: event.detail }),
          );
        }
        if (revision !== snapshot.revision) {
          netHighlightId = undefined;
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
            if (snapshot.context === "SCH") installSchematicHierarchy(host, native);
            else host.querySelector(".schematic-hierarchy-panel")?.__backplaneHierarchy?.dispose();
          }
          if (snapshot.probe && probeId !== snapshot.probe.id) {
            probeId = snapshot.probe.id;
            const found = viewer.requestCrossProbe(snapshot.probe);
            send({ type: "backplane-probe-result", found, value: snapshot.probe.value });
          }
          if (snapshot.netHighlight && netHighlightId !== snapshot.netHighlight.id) {
            netHighlightId = snapshot.netHighlight.id;
            const applies =
              !snapshot.netHighlight.targetContext ||
              snapshot.netHighlight.targetContext === snapshot.context;
            viewer.requestNetHighlight?.(
              applies || snapshot.netHighlight.clear
                ? snapshot.netHighlight
                : { ...snapshot.netHighlight, clear: true },
            );
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
