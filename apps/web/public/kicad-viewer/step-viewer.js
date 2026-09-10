import * as THREE from "three";
import { createStepScene } from "./step-scene.js";

/** Parse a STEP buffer into a Three.js scene for the retained model controller. */
export async function parseStepScene(buffer, signal) {
  if (buffer.byteLength > 100 * 1024 * 1024)
    throw new Error("STEP preview is limited to 100 MB per file.");
  const worker = new Worker("/kicad-viewer/step-worker.js");
  const pagehide = () => worker.terminate();
  window.addEventListener("pagehide", pagehide, { once: true });
  let parsed;
  let abort;
  try {
    parsed = await new Promise((resolve, reject) => {
      abort = () => {
        worker.terminate();
        reject(new DOMException("STEP parsing was superseded", "AbortError"));
      };
      if (signal?.aborted) return abort();
      signal?.addEventListener("abort", abort, { once: true });
      worker.onmessage = ({ data }) => (data.error ? reject(new Error(data.error)) : resolve(data));
      worker.onerror = () => reject(new Error("Unable to load the STEP importer."));
      worker.postMessage(buffer, [buffer]);
    });
  } finally {
    if (abort) signal?.removeEventListener("abort", abort);
    worker.terminate();
    window.removeEventListener("pagehide", pagehide);
  }
  return createStepScene(THREE, parsed.meshes, parsed.root);
}

/** Backwards-compatible entry point; rendering is owned by board-model.js. */
export async function showStep(host, url, status) {
  const { createBoardModel } = await import("./board-model.js");
  const viewer = createBoardModel(host, status, { kind: "step" });
  await viewer.update(url);
  return viewer;
}
