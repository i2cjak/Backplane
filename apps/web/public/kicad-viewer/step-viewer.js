import * as THREE from "three";

/** Parse a STEP buffer into a Three.js scene for the retained model controller. */
export async function parseStepScene(buffer, signal) {
  if (buffer.byteLength > 100 * 1024 * 1024)
    throw new Error("STEP preview is limited to 100 MB per file.");
  const worker = new Worker("/kicad-viewer/step-worker.js");
  const pagehide = () => worker.terminate();
  window.addEventListener("pagehide", pagehide, { once: true });
  let meshes;
  let abort;
  try {
    meshes = await new Promise((resolve, reject) => {
      abort = () => {
        worker.terminate();
        reject(new DOMException("STEP parsing was superseded", "AbortError"));
      };
      if (signal?.aborted) return abort();
      signal?.addEventListener("abort", abort, { once: true });
      worker.onmessage = ({ data }) =>
        data.error ? reject(new Error(data.error)) : resolve(data.meshes);
      worker.onerror = () => reject(new Error("Unable to load the STEP importer."));
      worker.postMessage(buffer, [buffer]);
    });
  } finally {
    if (abort) signal?.removeEventListener("abort", abort);
    worker.terminate();
    window.removeEventListener("pagehide", pagehide);
  }
  const group = new THREE.Group();
  for (const mesh of meshes) {
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute(
      "position",
      new THREE.Float32BufferAttribute(mesh.attributes.position.array, 3),
    );
    geometry.setIndex(mesh.index.array);
    if (mesh.attributes.normal)
      geometry.setAttribute(
        "normal",
        new THREE.Float32BufferAttribute(mesh.attributes.normal.array, 3),
      );
    else geometry.computeVertexNormals();
    const opacity = Number.isFinite(mesh.opacity) ? mesh.opacity : 1;
    const material = new THREE.MeshBasicMaterial({
      color: mesh.color ? new THREE.Color(...mesh.color) : new THREE.Color("#a8b5bf"),
      opacity,
      transparent: mesh.transparent === true || opacity < 1,
      toneMapped: false,
      side: THREE.DoubleSide,
    });
    const object = new THREE.Mesh(geometry, material);
    object.name = mesh.name;
    group.add(object);
  }
  return group;
}

/** Backwards-compatible entry point; rendering is owned by board-model.js. */
export async function showStep(host, url, status) {
  const { createBoardModel } = await import("./board-model.js");
  const viewer = createBoardModel(host, status, { kind: "step" });
  await viewer.update(url);
  return viewer;
}
