import * as THREE from "./three/three.module.js";

const SELECTION_EMISSIVE = new THREE.Color("#b8f3c4");
const SELECTED_MIN_OPACITY = 0.14;
const PICK_DISTANCE = 6;

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function pathPart(value, fallback) {
  if (typeof value === "string") return { key: value, label: value.replace(/:\d+$/, "") };
  if (!value || typeof value !== "object") return { key: fallback, label: fallback };
  const label = (text(value.label) || text(value.name) || text(value.title) || fallback).replace(
    /:\d+$/,
    "",
  );
  const key = text(value.key) || text(value.id) || text(value.path) || label;
  return { key, label };
}

function pathFromMesh(mesh, index) {
  const data = mesh.userData ?? {};
  const candidate =
    data.selectionPath ??
    data.stepPath ??
    data.stepHierarchyPath ??
    data.assemblyPath ??
    data.modelPath;
  let parts;
  if (Array.isArray(candidate)) parts = candidate;
  else if (typeof candidate === "string") parts = candidate.split(/[\\/>]+/).filter(Boolean);
  if (!parts?.length) parts = [text(mesh.name) || `Part ${index + 1}`];
  return parts.map((part, partIndex) => pathPart(part, `Part ${index + 1}-${partIndex + 1}`));
}

function nodeFor(root, part, index) {
  const key = `${root.key}/${part.key || part.label || index}`;
  let child = root.children.get(key);
  if (!child) {
    child = { key, label: part.label || `Part ${index + 1}`, children: new Map(), meshKeys: [] };
    root.children.set(key, child);
  }
  return child;
}

/** Build a stable, collapsible assembly tree from flattened STEP meshes. */
export function buildSelectionTree(meshes) {
  const root = { key: "", label: "Assembly", children: new Map(), meshKeys: [] };
  for (const [index, mesh] of meshes.entries()) {
    if (!mesh?.isMesh) continue;
    const parts = pathFromMesh(mesh, index);
    let node = root;
    const nodePath = [];
    for (const part of parts) {
      node = nodeFor(node, part, index);
      nodePath.push(node.key);
    }
    const meshKey = mesh.userData?.renderKey ?? `${node.key}/${index}`;
    mesh.userData.selectionNodeKey = node.key;
    mesh.userData.selectionLabel = parts.at(-1)?.label || `Part ${index + 1}`;
    mesh.userData.selectionPathKeys = nodePath;
    let parent = root;
    parent.meshKeys.push(meshKey);
    for (const part of parts) {
      parent = parent.children.get(`${parent.key}/${part.key || part.label || index}`);
      parent.meshKeys.push(meshKey);
    }
  }
  return root;
}

function visibleMesh(mesh, content) {
  for (let object = mesh; object && object !== content; object = object.parent)
    if (!object.visible) return false;
  return true;
}

function materialList(material) {
  return [material].flat().filter(Boolean);
}

function sameMaterial(a, b) {
  if (a === b) return true;
  const before = materialList(a);
  const after = materialList(b);
  return before.length === after.length && before.every((value, index) => value === after[index]);
}

function cloneMaterial(material, ratio, selected) {
  const clone = material.clone();
  const baseOpacity = Number.isFinite(material.opacity) ? material.opacity : 1;
  const effectiveRatio = selected ? Math.max(ratio, SELECTED_MIN_OPACITY) : ratio;
  clone.opacity = baseOpacity * effectiveRatio;
  if (effectiveRatio < 1 || material.transparent) {
    clone.transparent = true;
    clone.depthWrite = false;
  }
  if (selected && clone.emissive?.isColor) {
    clone.emissive.copy(SELECTION_EMISSIVE);
    clone.emissiveIntensity = Math.max(0.8, clone.emissiveIntensity ?? 0);
  }
  clone.needsUpdate = true;
  return clone;
}

function disposeMaterials(material) {
  for (const value of materialList(material)) value.dispose();
}

/** Apply a temporary per-view material without mutating a shared exporter material. */
export function applyMaterialOverride(mesh, ratio, selected, overrides) {
  const original = overrides.get(mesh);
  if (original) {
    if (!sameMaterial(mesh.material, original.material)) disposeMaterials(mesh.material);
    mesh.material = original.material;
    overrides.delete(mesh);
  }
  const source = mesh.material;
  const materials = materialList(source).map((material) =>
    cloneMaterial(material, ratio, selected),
  );
  mesh.material = Array.isArray(source) ? materials : materials[0];
  overrides.set(mesh, { material: source });
}

/** Restore all temporary view material changes before retained-model reconciliation. */
export function restoreMaterialOverrides(overrides) {
  for (const [mesh, entry] of overrides) {
    if (!sameMaterial(mesh.material, entry.material)) disposeMaterials(mesh.material);
    mesh.material = entry.material;
  }
  overrides.clear();
}

export function clampOpacity(value) {
  return Math.max(0, Math.min(1, Number.isFinite(value) ? value : 1));
}

function flattenTree(node) {
  const entries = [node];
  for (const child of node.children.values()) entries.push(...flattenTree(child));
  return entries;
}

/** Add STEP picking, synchronized tree controls, and retained opacity state. */
export function createStepSelectionController({ host, renderer, camera, invalidate }) {
  const opacityByKey = new Map();
  const overrides = new Map();
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  const panel = document.createElement("aside");
  panel.className = "step-selection-panel";
  panel.setAttribute("aria-label", "STEP parts");
  panel.innerHTML =
    '<button type="button" class="step-selection-toggle" aria-expanded="true">Parts</button><div class="step-selection-tree"></div><div class="step-selection-controls" hidden></div>';
  host.appendChild(panel);
  const toggle = panel.querySelector(".step-selection-toggle");
  const treeBody = panel.querySelector(".step-selection-tree");
  const controlsBody = panel.querySelector(".step-selection-controls");
  let content;
  let tree;
  let selectedKey;
  let selectedNode;
  let pointerStart;
  let pointerId;
  let pointerMoved = false;
  const expandedKeys = new Set();

  const meshes = () => {
    const result = [];
    content?.traverse((object) => {
      if (object.isMesh) result.push(object);
    });
    return result;
  };
  const findNode = (key) =>
    flattenTree(tree ?? { children: new Map() }).find((node) => node.key === key);
  const selectedMeshKeys = () => new Set(selectedNode?.meshKeys ?? []);
  const displayOpacity = (meshKeys) => {
    const values = meshKeys.map((key) => opacityByKey.get(key) ?? 1);
    return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 1;
  };
  const renderControls = () => {
    controlsBody.replaceChildren();
    if (!selectedNode) {
      controlsBody.hidden = true;
      return;
    }
    controlsBody.hidden = false;
    const heading = document.createElement("div");
    heading.className = "step-selection-heading";
    const name = document.createElement("span");
    name.textContent = selectedNode.label;
    const output = document.createElement("output");
    output.textContent = `${Math.round(displayOpacity(selectedNode.meshKeys) * 100)}%`;
    heading.append(name, output);
    const slider = document.createElement("input");
    slider.type = "range";
    slider.min = "0";
    slider.max = "100";
    slider.step = "1";
    slider.value = String(Math.round(displayOpacity(selectedNode.meshKeys) * 100));
    slider.setAttribute("aria-label", `${selectedNode.label} opacity`);
    slider.oninput = () => {
      const ratio = clampOpacity(Number(slider.value) / 100);
      for (const key of selectedNode.meshKeys) {
        if (ratio >= 1) opacityByKey.delete(key);
        else opacityByKey.set(key, ratio);
      }
      output.textContent = `${Math.round(ratio * 100)}%`;
      apply(content);
      invalidate();
    };
    const actions = document.createElement("div");
    actions.className = "step-selection-actions";
    const restore = document.createElement("button");
    restore.type = "button";
    restore.textContent = "Restore 100%";
    restore.onclick = () => {
      for (const key of selectedNode.meshKeys) opacityByKey.delete(key);
      slider.value = "100";
      output.textContent = "100%";
      apply(content);
      invalidate();
    };
    const clearButton = document.createElement("button");
    clearButton.type = "button";
    clearButton.textContent = "Clear selection";
    clearButton.onclick = clear;
    actions.append(restore, clearButton);
    controlsBody.append(heading, slider, actions);
  };
  const updateTreeSelection = () => {
    treeBody.querySelectorAll("[data-selection-key]").forEach((element) => {
      element.setAttribute("aria-selected", String(element.dataset.selectionKey === selectedKey));
    });
  };
  const revealAncestors = (key) => {
    const ancestors = new Set();
    for (let ancestor = key; ancestor; ancestor = ancestor.slice(0, ancestor.lastIndexOf("/")))
      if (ancestor) ancestors.add(ancestor);
    treeBody.querySelectorAll(".step-selection-group").forEach((element) => {
      const summary = element.querySelector(":scope > summary");
      if (ancestors.has(summary?.dataset.selectionKey)) {
        element.open = true;
        expandedKeys.add(summary.dataset.selectionKey);
      }
    });
  };
  const select = (key, reveal = false) => {
    const node = findNode(key);
    if (!node) return;
    selectedKey = key;
    selectedNode = node;
    updateTreeSelection();
    if (reveal) revealAncestors(key);
    renderControls();
    apply(content);
    invalidate();
  };
  const renderTreeNode = (node, depth = 0) => {
    const children = [...node.children.values()];
    if (!children.length) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "step-selection-item";
      button.dataset.selectionKey = node.key;
      button.style.setProperty("--step-depth", depth);
      button.textContent = node.label;
      button.setAttribute("aria-selected", String(selectedKey === node.key));
      return button;
    }
    const details = document.createElement("details");
    details.className = "step-selection-group";
    details.open = expandedKeys.has(node.key);
    details.ontoggle = () => {
      if (details.open) expandedKeys.add(node.key);
      else expandedKeys.delete(node.key);
    };
    const summary = document.createElement("summary");
    summary.dataset.selectionKey = node.key;
    summary.style.setProperty("--step-depth", depth);
    summary.textContent = node.label;
    summary.setAttribute("aria-selected", String(selectedKey === node.key));
    details.appendChild(summary);
    const childBody = document.createElement("div");
    for (const child of children) childBody.appendChild(renderTreeNode(child, depth + 1));
    details.appendChild(childBody);
    return details;
  };
  const renderTree = () => {
    treeBody.replaceChildren();
    if (!tree) return;
    for (const child of tree.children.values()) treeBody.appendChild(renderTreeNode(child));
  };
  const apply = (nextContent = content) => {
    restoreMaterialOverrides(overrides);
    content = nextContent;
    if (!content) return;
    const selected = selectedMeshKeys();
    for (const mesh of meshes()) {
      const key = mesh.userData?.renderKey;
      const ratio = opacityByKey.get(key);
      const highlighted = selected.has(key);
      if (ratio !== undefined || highlighted)
        applyMaterialOverride(mesh, ratio ?? 1, highlighted, overrides);
    }
  };
  const sync = () => {
    const selected = selectedMeshKeys();
    for (const [mesh, entry] of overrides) {
      const ratio = opacityByKey.get(mesh.userData?.renderKey) ?? 1;
      const highlighted = selected.has(mesh.userData?.renderKey);
      const effectiveRatio = highlighted ? Math.max(ratio, SELECTED_MIN_OPACITY) : ratio;
      const sourceMaterials = materialList(entry.material);
      const viewMaterials = materialList(mesh.material);
      viewMaterials.forEach((material, index) => {
        const base = sourceMaterials[index];
        if (base)
          material.opacity = (Number.isFinite(base.opacity) ? base.opacity : 1) * effectiveRatio;
        material.transparent = effectiveRatio < 1 || Boolean(base?.transparent);
        if (effectiveRatio < 1) material.depthWrite = false;
      });
    }
  };
  const restore = () => restoreMaterialOverrides(overrides);
  const pick = (event) => {
    if (!content) return;
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const hit = raycaster.intersectObjects(content.children, true).find(({ object }) => {
      const key = object.userData?.renderKey;
      return (
        object.isMesh &&
        visibleMesh(object, content) &&
        (opacityByKey.get(key) !== 0 || selectedMeshKeys().has(key))
      );
    });
    if (hit?.object?.userData?.selectionNodeKey) select(hit.object.userData.selectionNodeKey, true);
    else clear();
  };
  const pointerDown = (event) => {
    if (event.button !== 0) return;
    if (pointerStart) {
      pointerStart = undefined;
      pointerId = undefined;
      pointerMoved = true;
      return;
    }
    pointerStart = { x: event.clientX, y: event.clientY };
    pointerId = event.pointerId;
    pointerMoved = false;
  };
  const pointerMove = (event) => {
    if (!pointerStart || event.pointerId !== pointerId) return;
    if (Math.hypot(event.clientX - pointerStart.x, event.clientY - pointerStart.y) > PICK_DISTANCE)
      pointerMoved = true;
  };
  const pointerUp = (event) => {
    if (!pointerStart || event.pointerId !== pointerId) return;
    const shouldPick = !pointerMoved;
    pointerStart = undefined;
    pointerId = undefined;
    pointerMoved = false;
    if (shouldPick) pick(event);
  };
  const pointerCancel = () => {
    pointerStart = undefined;
    pointerId = undefined;
    pointerMoved = false;
  };
  const clear = () => {
    if (!selectedNode) return;
    selectedKey = undefined;
    selectedNode = undefined;
    updateTreeSelection();
    renderControls();
    apply(content);
    invalidate();
  };
  const treeClick = (event) => {
    const target = event.target.closest?.("[data-selection-key]");
    if (target) select(target.dataset.selectionKey);
  };
  toggle.onclick = () => {
    const collapsed = panel.classList.toggle("is-collapsed");
    toggle.setAttribute("aria-expanded", String(!collapsed));
  };
  if (matchMedia("(max-width: 640px)").matches) {
    panel.classList.add("is-collapsed");
    toggle.setAttribute("aria-expanded", "false");
  }
  renderer.domElement.addEventListener("pointerdown", pointerDown);
  renderer.domElement.addEventListener("pointermove", pointerMove);
  renderer.domElement.addEventListener("pointerup", pointerUp);
  renderer.domElement.addEventListener("pointercancel", pointerCancel);
  treeBody.addEventListener("click", treeClick);
  const keydown = (event) => {
    if (event.key === "Escape") clear();
  };
  window.addEventListener("keydown", keydown);

  return {
    setContent(nextContent) {
      restoreMaterialOverrides(overrides);
      content = nextContent;
      tree = buildSelectionTree(meshes());
      if (selectedKey && !findNode(selectedKey)) {
        selectedKey = undefined;
        selectedNode = undefined;
      } else selectedNode = selectedKey ? findNode(selectedKey) : undefined;
      renderTree();
      renderControls();
      apply(content);
    },
    restore,
    reapply() {
      apply(content);
    },
    sync,
    dispose() {
      restoreMaterialOverrides(overrides);
      renderer.domElement.removeEventListener("pointerdown", pointerDown);
      renderer.domElement.removeEventListener("pointermove", pointerMove);
      renderer.domElement.removeEventListener("pointerup", pointerUp);
      renderer.domElement.removeEventListener("pointercancel", pointerCancel);
      toggle.onclick = null;
      treeBody.removeEventListener("click", treeClick);
      window.removeEventListener("keydown", keydown);
      panel.remove();
    },
  };
}
