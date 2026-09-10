import { expect, it } from "vite-plus/test";

const base = new URL("../../public/kicad-viewer/", import.meta.url).href;
const { BoxGeometry, Mesh, MeshToonMaterial } = await import(
  /* @vite-ignore */ `${base}three/three.module.js`
);
const { applyMaterialOverride, buildSelectionTree, clampOpacity, restoreMaterialOverrides } =
  await import(/* @vite-ignore */ `${base}model-selection.js`);

it("builds a stable nested STEP tree and groups meshes under their assembly", () => {
  const first = new Mesh(new BoxGeometry(1, 1, 1), new MeshToonMaterial());
  first.userData.renderKey = "assembly/u1:0";
  first.userData.stepPath = [
    { id: "assembly", name: "Assembly" },
    { id: "u1", name: "U1" },
  ];
  const second = new Mesh(new BoxGeometry(1, 1, 1), new MeshToonMaterial());
  second.userData.renderKey = "assembly/u2:0";
  second.userData.stepPath = [
    { id: "assembly", name: "Assembly" },
    { id: "u2", name: "U2" },
  ];

  const tree = buildSelectionTree([first, second]);
  const assembly = tree.children.get("/assembly");
  expect(assembly?.label).toBe("Assembly");
  expect(assembly?.children.get("/assembly/u1")?.meshKeys).toEqual(["assembly/u1:0"]);
  expect(assembly?.meshKeys).toEqual(["assembly/u1:0", "assembly/u2:0"]);
  expect(first.userData.selectionNodeKey).toBe("/assembly/u1");
});

it("restores original shared materials after a temporary opacity highlight", () => {
  const material = new MeshToonMaterial({ opacity: 1 });
  const mesh = new Mesh(new BoxGeometry(1, 1, 1), material);
  const overrides = new Map();
  applyMaterialOverride(mesh, 0, true, overrides);
  expect(mesh.material).not.toBe(material);
  expect(mesh.material.opacity).toBeGreaterThan(0);
  expect(material.opacity).toBe(1);
  restoreMaterialOverrides(overrides);
  expect(mesh.material).toBe(material);
  expect(overrides.size).toBe(0);
});

it("clamps persisted opacity values to the slider range", () => {
  expect(clampOpacity(-1)).toBe(0);
  expect(clampOpacity(0.42)).toBe(0.42);
  expect(clampOpacity(4)).toBe(1);
  expect(clampOpacity(Number.NaN)).toBe(1);
});
