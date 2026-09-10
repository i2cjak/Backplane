import { orientStepScene } from "./step-orientation.js";

/** Build a selectable Three.js hierarchy from OCCT's mesh-index tree. */
export function createStepScene(THREE, meshes, tree) {
  const objects = meshes.map((mesh) => {
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
    return object;
  });
  const fallback = { name: "STEP", meshes: objects.map((_, index) => index), children: [] };
  const source = tree && typeof tree === "object" ? tree : fallback;
  const used = new Set();
  const build = (node, path) => {
    const group = new THREE.Group();
    group.name = node.name || (path ? "Assembly" : "STEP");
    group.userData.stepPath = path;
    for (const index of node.meshes ?? []) {
      const object = objects[index];
      if (!object || used.has(index)) continue;
      used.add(index);
      object.userData.stepPath = path;
      group.add(object);
    }
    for (const [index, child] of (node.children ?? []).entries())
      if (child && typeof child === "object")
        group.add(build(child, `${path}/${child.name || "Assembly"}:${index}`));
    return group;
  };
  const scene = build(source, "");
  scene.userData.stepTree = tree ?? fallback;
  for (const [index, object] of objects.entries()) {
    if (!used.has(index)) {
      object.userData.stepPath = "";
      scene.add(object);
    }
  }
  return orientStepScene(scene);
}
