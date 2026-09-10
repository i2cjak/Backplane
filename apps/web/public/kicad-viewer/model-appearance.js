import { MeshBasicMaterial, Mesh } from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";

// KiCad emits one primitive per copper face. Batch only static board surfaces;
// component models and their hierarchy are left intact.
function batchBoardSurfaces(content) {
  const groups = [];
  content.traverse((object) => {
    if (object.isGroup && /_(copper|pad|via|silkscreen|PCB)(?:_|$)/i.test(object.name))
      groups.push(object);
  });
  for (const group of groups) {
    const batches = new Map();
    for (const mesh of group.children) {
      if (!mesh.isMesh || Array.isArray(mesh.material) || mesh.isSkinnedMesh) continue;
      const batch = batches.get(mesh.material) ?? [];
      batch.push(mesh);
      batches.set(mesh.material, batch);
    }
    for (const [material, meshes] of batches) {
      if (meshes.length < 2) continue;
      const geometries = meshes.map((mesh) => {
        mesh.updateMatrix();
        return mesh.geometry.clone().applyMatrix4(mesh.matrix);
      });
      const geometry = mergeGeometries(geometries);
      geometries.forEach((item) => item.dispose());
      if (!geometry) continue;
      const merged = new Mesh(geometry, material);
      merged.name = group.name;
      for (const mesh of meshes) {
        group.remove(mesh);
        mesh.geometry.dispose();
      }
      group.add(merged);
    }
  }
}

// KiCad's exporter already supplies the display colors and alpha. Basic
// materials keep those values exact while avoiding lighting, tone mapping,
// and PBR work for every retained mesh.
export function prepareBoardModel(content) {
  batchBoardSurfaces(content);
  const replacements = new Map();
  const flat = (source) => {
    if (source.isMeshBasicMaterial) {
      source.toneMapped = false;
      return source;
    }
    if (replacements.has(source)) return replacements.get(source);
    const material = new MeshBasicMaterial();
    // BasicMaterial.copy preserves color, opacity, alpha maps, side, and
    // the texture maps supported by an unlit material.
    MeshBasicMaterial.prototype.copy.call(material, source);
    material.toneMapped = false;
    replacements.set(source, material);
    return material;
  };
  content.traverse((mesh) => {
    if (!mesh.isMesh || !mesh.material) return;
    mesh.material = Array.isArray(mesh.material) ? mesh.material.map(flat) : flat(mesh.material);
  });
  const retained = new Set();
  content.traverse((mesh) => {
    for (const material of [mesh.material].flat().filter(Boolean)) retained.add(material);
  });
  for (const source of replacements.keys()) {
    if (!retained.has(source)) source.dispose();
  }
}

export function finishBoardModel(element) {
  const viewer = element._viewer_container;
  prepareBoardModel(viewer.content);
  viewer.render();
}
