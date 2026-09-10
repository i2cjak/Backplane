import {
  DataTexture,
  Mesh,
  MeshToonMaterial,
  RGBAFormat,
  NearestFilter,
  UnsignedByteType,
} from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";

// A shared, nearest-filtered ramp makes every surface use the same restrained
// four-band cel treatment. Keeping one texture avoids a material-sized lookup
// allocation for the thousands of component meshes in a typical board model.
const CEL_RAMP = new DataTexture(
  new Uint8Array([76, 84, 94, 255, 142, 151, 162, 255, 198, 205, 211, 255, 236, 240, 242, 255]),
  4,
  1,
  RGBAFormat,
  UnsignedByteType,
);
CEL_RAMP.magFilter = NearestFilter;
CEL_RAMP.minFilter = NearestFilter;
CEL_RAMP.generateMipmaps = false;
CEL_RAMP.needsUpdate = true;
CEL_RAMP.userData.shared = true;

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

// KiCad's exporter already supplies the display colors and alpha. Toon
// materials keep those values while adding fixed, banded graphic lighting;
// there is no environment, shadow map, or PBR work per retained mesh.
export function prepareBoardModel(content) {
  batchBoardSurfaces(content);
  const replacements = new Map();
  const flat = (source) => {
    if (replacements.has(source)) return replacements.get(source);
    const parameters = {
      color: source.color,
      map: source.map ?? null,
      alphaMap: source.alphaMap ?? null,
      opacity: source.opacity,
      transparent: source.transparent,
      alphaTest: source.alphaTest,
      depthWrite: source.depthWrite,
      side: source.side,
      vertexColors: source.vertexColors === true,
      wireframe: source.wireframe === true,
      gradientMap: CEL_RAMP,
    };
    if (source.emissive?.isColor) parameters.emissive = source.emissive;
    if (source.emissiveMap?.isTexture) parameters.emissiveMap = source.emissiveMap;
    if (source.emissiveIntensity !== undefined)
      parameters.emissiveIntensity = source.emissiveIntensity;
    const material = new MeshToonMaterial(parameters);
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
