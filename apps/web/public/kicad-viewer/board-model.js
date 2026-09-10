import * as THREE from "three";
import { TrackballControls } from "three/addons/controls/TrackballControls.js";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { prepareBoardModel } from "./model-appearance.js";
import { createCelOutlinePass } from "./cel-renderer.js";
import { flattenModel, reconcileModel } from "./model-update.js";
import { fitOrthographicCamera, resizeOrthographicCamera } from "./orthographic-camera.js";

function disposeModel(root, retained) {
  const geometries = new Set();
  const materials = new Set();
  const textures = new Set();
  root.traverse((object) => {
    if (object.geometry) geometries.add(object.geometry);
    for (const material of [object.material].flat().filter(Boolean)) {
      materials.add(material);
      for (const value of Object.values(material)) {
        if (value?.isTexture && !value.userData?.shared) textures.add(value);
      }
    }
  });
  retained?.traverse((object) => {
    geometries.delete(object.geometry);
    for (const material of [object.material].flat().filter(Boolean)) {
      materials.delete(material);
      for (const value of Object.values(material))
        if (value?.isTexture && !value.userData?.shared) textures.delete(value);
    }
  });
  for (const value of [...geometries, ...materials, ...textures]) value.dispose();
}

/** One camera and GPU context survive saves. Only complete, prepared models become visible. */
export function createBoardModel(host, status, options = {}) {
  const kind = options.kind ?? "model";
  const scene = new THREE.Scene();
  scene.background = new THREE.Color("#101214");
  const ambientLight = new THREE.AmbientLight("#ffffff", 0.38);
  scene.add(ambientLight);
  const keyLight = new THREE.DirectionalLight("#ffffff", 1.3);
  keyLight.position.set(4, 7, 5);
  scene.add(keyLight);
  const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.001, 1000);
  camera.position.set(4, 6, 4);
  camera.lookAt(0, 0, 0);
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.domElement.style.cssText = "display:block;touch-action:none;width:100%;height:100%";
  renderer.domElement.setAttribute("aria-label", "3D board model");
  host.appendChild(renderer.domElement);
  const controls = new TrackballControls(camera, renderer.domElement);
  controls.rotateSpeed = 1.6;
  controls.zoomSpeed = 1.05;
  controls.panSpeed = 0.42;
  controls.staticMoving = true;
  controls.minZoom = 0.00001;
  controls.maxZoom = 10000;
  const loader = new GLTFLoader();
  const celPass = createCelOutlinePass(renderer);
  const warmup = new THREE.WebGLRenderTarget(1, 1);
  let content;
  let radius = 1;
  let currentUrl;
  let pending;
  let generation = 0;
  let disposed = false;
  let active = true;
  let frame = 0;
  let transition;
  let transitionStart = 0;
  let center;
  let aspect = 1;
  let controlsDirty = false;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const visibility = new Map();

  const draw = () => {
    frame = 0;
    if (controlsDirty) {
      controlsDirty = false;
      controls.update();
    }
    if (transition) {
      const progress = reducedMotion.matches
        ? 1
        : Math.min(1, (performance.now() - transitionStart) / 420);
      transition.step(progress);
      if (progress === 1) finishTransition();
      else invalidate();
    }
    if (!disposed && active && host.clientWidth && host.clientHeight) celPass.render(scene, camera);
  };
  const invalidate = () => {
    if (!frame && !disposed && active) frame = requestAnimationFrame(draw);
  };
  const finishTransition = () => {
    if (!transition) return;
    transition.finish();
    disposeModel(transition.discarded, content);
    transition = undefined;
  };
  const updateControls = () => {
    if (disposed || !active) return;
    controlsDirty = true;
    invalidate();
  };
  controls.addEventListener("start", updateControls);
  renderer.domElement.addEventListener("pointermove", updateControls);
  renderer.domElement.addEventListener("wheel", updateControls, { passive: true });
  const fit = (direction = new THREE.Vector3(1, 1.5, 1), up) => {
    if (up) camera.up.copy(up);
    fitOrthographicCamera(camera, radius, aspect, direction);
    controls.target.set(0, 0, 0);
    controls.update();
    invalidate();
  };
  const resize = () => {
    const width = host.clientWidth;
    const height = host.clientHeight;
    if (!width || !height || disposed) return;
    renderer.setSize(width, height, false);
    controls.handleResize();
    celPass.resize(width, height);
    aspect = width / height;
    resizeOrthographicCamera(camera, aspect);
    invalidate();
  };
  const observer = new ResizeObserver(resize);
  observer.observe(host);
  resize();

  const actions = document.createElement("div");
  actions.className = "canvas-actions";
  for (const [label, action] of [
    ["Fit model", () => fit()],
    ["Top", () => fit(new THREE.Vector3(0, 1, 0.001), new THREE.Vector3(0, 0, 1))],
    ["Bottom", () => fit(new THREE.Vector3(0, -1, 0.001), new THREE.Vector3(0, 0, -1))],
  ]) {
    const button = document.createElement("button");
    button.textContent = label;
    button.onclick = action;
    actions.appendChild(button);
  }
  host.appendChild(actions);
  const layers = document.createElement("details");
  layers.className = "model-layers";
  layers.innerHTML = "<summary>Model layers</summary><div></div>";
  host.appendChild(layers);
  const layerBody = layers.querySelector("div");
  const category = (name) => {
    if (/_soldermask(?:_|$)/i.test(name)) return "Soldermask";
    if (/_silkscreen(?:_|$)/i.test(name)) return "Silkscreen";
    if (/_(?:copper|pad|via)(?:_|$)/i.test(name)) return "Copper";
    if (/_PCB(?:_|$)/i.test(name)) return "Board";
    return "Components";
  };
  const collectLayers = (root) => {
    const groups = new Map();
    const visit = (object, inherited) => {
      const own = object.userData.modelLayer ?? category(object.name);
      const group = own === "Components" ? (inherited ?? own) : own;
      if (object.isMesh) {
        object.userData.modelLayer = group;
        const meshes = groups.get(group) ?? [];
        meshes.push(object);
        groups.set(group, meshes);
        object.visible = visibility.get(group) !== false;
      }
      for (const child of object.children) visit(child, group);
    };
    visit(root);
    return groups;
  };
  const showLayers = (groups) => {
    layerBody.replaceChildren();
    for (const [name, meshes] of groups) {
      const label = document.createElement("label");
      const input = document.createElement("input");
      input.type = "checkbox";
      input.checked = visibility.get(name) !== false;
      input.onchange = () => {
        visibility.set(name, input.checked);
        for (const mesh of meshes) mesh.visible = input.checked;
        invalidate();
      };
      label.append(input, document.createTextNode(name));
      layerBody.appendChild(label);
    }
  };

  const update = async (url) => {
    if (disposed || currentUrl === url) return;
    currentUrl = url;
    pending?.abort();
    pending = new AbortController();
    const signal = pending.signal;
    const ticket = ++generation;
    status.classList.toggle("refresh-status", Boolean(content));
    const label = kind === "step" ? "STEP" : "3D";
    status.textContent = content ? `Updating ${label} preview…` : `Generating ${label} preview…`;
    let next;
    try {
      const response = await fetch(url, { signal });
      if (!response.ok) throw new Error((await response.text()).slice(0, 700));
      const data = await response.arrayBuffer();
      if (signal.aborted) return;
      if (kind === "step") {
        const { parseStepScene } = await import("./step-viewer.js");
        next = await parseStepScene(data, signal);
      } else {
        const gltf = await loader.parseAsync(data, "");
        next = gltf.scene;
      }
      if (!next) throw new Error("The model has no viewable scene.");
      if (disposed || ticket !== generation) return;
      prepareBoardModel(next);
      const bounds = new THREE.Box3().setFromObject(next);
      const nextRadius = bounds.getSize(new THREE.Vector3()).length() / 2;
      if (!Number.isFinite(nextRadius) || nextRadius <= 0)
        throw new Error("The model has no viewable geometry.");
      center ??= bounds.getCenter(new THREE.Vector3());
      next.position.sub(center);
      collectLayers(next);
      next = flattenModel(next);
      const staging = new THREE.Scene();
      staging.add(ambientLight.clone(), keyLight.clone());
      staging.add(next);
      await renderer.compileAsync(staging, camera);
      if (disposed || ticket !== generation) return;
      const previous = content;
      finishTransition();
      const update = reconcileModel(previous, next, !reducedMotion.matches);
      // Reconcile first so unchanged meshes keep their uploaded buffers. No
      // await separates reconciliation, changed-buffer upload and scene commit.
      renderer.setRenderTarget(warmup);
      try {
        renderer.render(staging, camera);
      } finally {
        renderer.setRenderTarget(null);
      }
      if (previous) scene.remove(previous);
      content = next;
      next = undefined;
      radius = nextRadius;
      const distance = camera.position.distanceTo(controls.target);
      camera.near = Math.max(0.001, distance - radius * 2);
      camera.far = Math.max(distance + radius * 2, radius * 20, 1);
      camera.updateProjectionMatrix();
      controls.maxDistance = radius * 30;
      scene.add(content);
      if (!previous) fit();
      showLayers(collectLayers(content));
      status.textContent = "";
      host.dataset.modelRevision = String(ticket);
      host.dataset.modelChanges = JSON.stringify(update.stats);
      if (update.animated) {
        transition = update;
        transitionStart = performance.now();
      } else {
        update.finish();
        disposeModel(update.discarded, content);
      }
      draw();
      if (previous) disposeModel(previous, content);
    } catch (cause) {
      if (!disposed && ticket === generation && !signal.aborted) {
        currentUrl = undefined;
        status.textContent = `${content ? "Preview update failed: " : ""}${cause.message || String(cause)}`;
      }
    } finally {
      if (next) disposeModel(next);
    }
  };
  const dispose = () => {
    if (disposed) return;
    disposed = true;
    generation++;
    pending?.abort();
    cancelAnimationFrame(frame);
    observer.disconnect();
    controls.dispose();
    controls.removeEventListener("start", updateControls);
    renderer.domElement.removeEventListener("pointermove", updateControls);
    renderer.domElement.removeEventListener("wheel", updateControls);
    finishTransition();
    if (content) disposeModel(content);
    warmup.dispose();
    celPass.dispose();
    renderer.dispose();
  };
  window.addEventListener("pagehide", dispose, { once: true });
  return {
    update,
    setActive(value) {
      // A hidden viewer has no render loop to advance the soft morph. Commit
      // it before parking the surface so temporary cloned materials and
      // geometries do not stay alive until the tab becomes visible again.
      if (!value) finishTransition();
      active = value;
      controls.enabled = value;
      if (active) resize();
    },
    dispose,
  };
}
