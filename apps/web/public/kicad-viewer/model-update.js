import { Group, Matrix4 } from "./three/three.module.js";

function arrayEqual(a, b) {
  if (a === b) return true;
  if (!a || !b || a.constructor !== b.constructor || a.length !== b.length) return false;
  for (let index = 0; index < a.length; index++) if (a[index] !== b[index]) return false;
  return true;
}

function geometryEqual(a, b) {
  if (!arrayEqual(a.index?.array, b.index?.array)) return false;
  const keys = Object.keys(a.attributes);
  if (
    keys.length !== Object.keys(b.attributes).length ||
    !keys.every(
      (key) =>
        a.attributes[key].itemSize === b.attributes[key]?.itemSize &&
        a.attributes[key].normalized === b.attributes[key]?.normalized &&
        a.attributes[key].array.constructor === b.attributes[key]?.array.constructor &&
        arrayEqual(a.attributes[key].array, b.attributes[key].array),
    )
  )
    return false;
  if (
    a.groups.length !== b.groups.length ||
    !a.groups.every((group, index) => {
      const other = b.groups[index];
      return (
        group.start === other.start &&
        group.count === other.count &&
        group.materialIndex === other.materialIndex
      );
    })
  )
    return false;
  if (a.drawRange.start !== b.drawRange.start || a.drawRange.count !== b.drawRange.count)
    return false;
  const morphKeys = new Set(Object.keys(a.morphAttributes));
  for (const key of Object.keys(b.morphAttributes)) morphKeys.add(key);
  for (const key of morphKeys) {
    const before = a.morphAttributes[key] ?? [];
    const after = b.morphAttributes[key] ?? [];
    if (
      before.length !== after.length ||
      !before.every(
        (attribute, index) =>
          attribute.itemSize === after[index]?.itemSize &&
          attribute.normalized === after[index]?.normalized &&
          attribute.array.constructor === after[index]?.array.constructor &&
          arrayEqual(attribute.array, after[index]?.array),
      )
    )
      return false;
  }
  return true;
}

function materialEqual(a, b) {
  const before = [a].flat();
  const after = [b].flat();
  const fields = [
    "type",
    "opacity",
    "transparent",
    "side",
    "depthWrite",
    "alphaTest",
    "vertexColors",
    "wireframe",
    "fog",
    "toneMapped",
  ];
  return (
    before.length === after.length &&
    before.every((material, index) => {
      const other = after[index];
      return (
        fields.every((field) => material[field] === other[field]) &&
        ((!material.color && !other.color) ||
          (Boolean(material.color) &&
            Boolean(other.color) &&
            material.color.equals(other.color))) &&
        ((!material.emissive && !other.emissive) ||
          (Boolean(material.emissive) &&
            Boolean(other.emissive) &&
            material.emissive.equals(other.emissive))) &&
        ["map", "alphaMap", "lightMap", "aoMap", "specularMap", "envMap"].every(
          (key) => material[key] === other[key],
        )
      );
    })
  );
}

/** Flatten exporter hierarchy into stable named instances with world-space transforms. */
export function flattenModel(source) {
  const root = new Group();
  const meshes = [];
  source.updateMatrixWorld(true);
  const walk = (object, path) => {
    if (object.isMesh) {
      object.userData.renderKey = path;
      meshes.push({ object, matrix: object.matrixWorld.clone() });
    }
    const occurrences = new Map();
    for (const child of object.children) {
      const name = child.name || child.type;
      const occurrence = occurrences.get(name) ?? 0;
      occurrences.set(name, occurrence + 1);
      walk(child, `${path}/${name}:${occurrence}`);
    }
  };
  walk(source, "");
  for (const { object, matrix } of meshes) {
    root.add(object);
    matrix.decompose(object.position, object.quaternion, object.scale);
    object.updateMatrix();
  }
  return root;
}

/** Reuse unchanged GPU resources; animate only moved, added, removed or reshaped meshes. */
export function reconcileModel(previous, next, animate = true) {
  const old = new Map(previous?.children.map((mesh) => [mesh.userData.renderKey, mesh]) ?? []);
  const discarded = new Group();
  const transitions = [];
  const stats = { retained: 0, changed: 0, added: 0, removed: 0 };
  const fade = (mesh, direction) => {
    const original = mesh.material;
    const materials = [original].flat().map((source) => {
      const material = source.clone();
      material.transparent = true;
      material.depthWrite = false;
      return material;
    });
    mesh.material = Array.isArray(original) ? materials : materials[0];
    const opacities = [original].flat().map((material) => material.opacity);
    const scale = mesh.scale.clone();
    transitions.push({
      step(t) {
        materials.forEach((material, index) => {
          material.opacity = opacities[index] * (direction > 0 ? t : 1 - t);
        });
        mesh.scale.copy(scale).multiplyScalar(1 + Math.sin(t * Math.PI) * 0.025);
      },
      finish() {
        mesh.scale.copy(scale);
        mesh.material = original;
        materials.forEach((material) => material.dispose());
        if (direction < 0) discarded.add(mesh);
      },
    });
  };
  for (const mesh of next.children.slice()) {
    const before = old.get(mesh.userData.renderKey);
    if (!before) {
      stats.added++;
      if (animate && previous) fade(mesh, 1);
      continue;
    }
    old.delete(mesh.userData.renderKey);
    if (
      geometryEqual(before.geometry, mesh.geometry) &&
      materialEqual(before.material, mesh.material)
    ) {
      stats.retained++;
      const position = mesh.position.clone();
      const quaternion = mesh.quaternion.clone();
      const scale = mesh.scale.clone();
      const moved =
        !before.position.equals(position) ||
        !before.quaternion.equals(quaternion) ||
        !before.scale.equals(scale);
      before.visible = mesh.visible;
      before.userData = mesh.userData;
      discarded.add(mesh);
      next.add(before);
      if (animate && moved) {
        stats.changed++;
        const startPosition = before.position.clone();
        const startQuaternion = before.quaternion.clone();
        const startScale = before.scale.clone();
        transitions.push({
          step(t) {
            before.position.lerpVectors(startPosition, position, t);
            before.quaternion.slerpQuaternions(startQuaternion, quaternion, t);
            before.scale.lerpVectors(startScale, scale, t);
          },
          finish() {
            before.position.copy(position);
            before.quaternion.copy(quaternion);
            before.scale.copy(scale);
          },
        });
      } else {
        before.position.copy(position);
        before.quaternion.copy(quaternion);
        before.scale.copy(scale);
      }
      continue;
    }
    stats.changed++;
    const from = before.geometry.attributes.position;
    const to = mesh.geometry.attributes.position;
    const compatible =
      from &&
      to &&
      from.count === to.count &&
      from.count < 100_000 &&
      arrayEqual(before.geometry.index?.array, mesh.geometry.index?.array) &&
      new Matrix4()
        .compose(before.position, before.quaternion, before.scale)
        .equals(new Matrix4().compose(mesh.position, mesh.quaternion, mesh.scale));
    if (animate && compatible) {
      const original = mesh.geometry;
      mesh.geometry = original.clone();
      const attribute = mesh.geometry.attributes.position;
      const start = from.array;
      const end = to.array;
      mesh.frustumCulled = false;
      transitions.push({
        step(t) {
          for (let i = 0; i < attribute.array.length; i++)
            attribute.array[i] = start[i] + (end[i] - start[i]) * t;
          attribute.needsUpdate = true;
        },
        finish() {
          mesh.geometry.dispose();
          mesh.geometry = original;
          mesh.frustumCulled = true;
        },
      });
    } else if (animate) {
      next.add(before);
      fade(before, -1);
      fade(mesh, 1);
    }
  }
  for (const before of old.values()) {
    stats.removed++;
    if (animate) {
      next.add(before);
      fade(before, -1);
    }
  }
  // Begin the transition before the first visible frame, avoiding a new-item flash.
  for (const transition of transitions) transition.step(0);
  return {
    stats,
    discarded,
    animated: transitions.length > 0,
    step(progress) {
      const t = progress * progress * (3 - 2 * progress);
      for (const transition of transitions) transition.step(t);
    },
    finish() {
      for (const transition of transitions) transition.finish();
    },
  };
}
