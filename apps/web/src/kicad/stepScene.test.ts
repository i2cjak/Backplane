import { expect, it } from "vite-plus/test";

const base = new URL("../../public/kicad-viewer/", import.meta.url).href;
const THREE = await import(/* @vite-ignore */ `${base}three/three.module.js`);
const { createStepScene } = await import(/* @vite-ignore */ `${base}step-scene.js`);

it("keeps OCCT assembly paths while mapping STEP Z-up to viewer Y-up", () => {
  const meshes = [
    {
      name: "plate",
      attributes: {
        position: { array: new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 1]) },
        normal: { array: new Float32Array([0, 0, 1, 0, 0, 1, 0, 0, 1]) },
      },
      index: { array: new Uint16Array([0, 1, 2]) },
      color: [0.4, 0.5, 0.6],
    },
  ];
  const tree = {
    name: "assembly",
    meshes: [],
    children: [{ name: "cover", meshes: [0], children: [] }],
  };
  const scene = createStepScene(THREE, meshes, tree);
  scene.updateMatrixWorld(true);
  const cover = scene.children[0];
  const plate = cover.children[0];
  const bounds = new THREE.Box3().setFromObject(scene);

  expect(cover.name).toBe("cover");
  expect(plate.name).toBe("plate");
  expect(plate.userData.stepPath).toBe("/cover:0");
  expect(scene.userData.stepTree).toBe(tree);
  expect(scene.rotation.x).toBeCloseTo(-Math.PI / 2);
  expect(bounds.min.y).toBeCloseTo(0);
  expect(bounds.max.y).toBeCloseTo(1);
  expect(bounds.min.z).toBeCloseTo(-1);
  expect(bounds.max.z).toBeCloseTo(0);
});
