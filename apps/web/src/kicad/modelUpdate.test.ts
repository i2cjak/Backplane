import { expect, it } from "vite-plus/test";

// Exercise the shipped renderer modules and real Three.js objects without a GPU.
const base = new URL("../../public/kicad-viewer/", import.meta.url).href;
const {
  Group,
  Mesh,
  BoxGeometry,
  SphereGeometry,
  MeshStandardMaterial,
  OrthographicCamera,
  Vector3,
} = await import(/* @vite-ignore */ `${base}three/three.module.js`);
const { flattenModel, reconcileModel } = await import(/* @vite-ignore */ `${base}model-update.js`);
const { fitOrthographicCamera, resizeOrthographicCamera } = await import(
  /* @vite-ignore */ `${base}orthographic-camera.js`
);

function board(position = 0, width = 1) {
  const root = new Group();
  const body = new Mesh(new BoxGeometry(10, 1, 10), new MeshStandardMaterial({ color: 0x225533 }));
  body.name = "PCB";
  const component = new Mesh(new BoxGeometry(width, 1, 1), new MeshStandardMaterial());
  component.name = "U1";
  component.position.x = position;
  root.add(body, component);
  return flattenModel(root);
}

it("retains unchanged meshes and GPU resources while smoothly moving one component", () => {
  const before = board();
  const [body, component] = before.children;
  const geometry = component.geometry;
  const material = component.material;
  const next = board(5);
  const update = reconcileModel(before, next, true);
  expect(next.children).toContain(body);
  expect(next.children).toContain(component);
  expect(component.geometry).toBe(geometry);
  expect(component.material).toBe(material);
  expect(component.position.x).toBe(0);
  update.step(0.5);
  expect(component.position.x).toBe(2.5);
  update.finish();
  expect(component.position.x).toBe(5);
  expect(update.stats).toEqual({ retained: 2, changed: 1, added: 0, removed: 0 });
});

it("morphs compatible changed geometry and restores the final exporter geometry", () => {
  const before = board();
  const next = board(0, 2);
  const component = next.children[1];
  const target = component.geometry;
  const start = before.children[1].geometry.attributes.position.array[0];
  const end = target.attributes.position.array[0];
  const update = reconcileModel(before, next, true);
  expect(component.geometry).not.toBe(target);
  expect(component.geometry.attributes.position.array[0]).toBe(start);
  update.step(0.5);
  expect(component.geometry.attributes.position.array[0]).toBe((start + end) / 2);
  update.finish();
  expect(component.geometry).toBe(target);
});

it("dissolves incompatible topology locally while leaving the board material untouched", () => {
  const before = board();
  const body = before.children[0];
  const material = body.material;
  const oldComponent = before.children[1];
  const next = board();
  const newComponent = next.children[1];
  newComponent.geometry = new SphereGeometry();
  const update = reconcileModel(before, next, true);
  expect(body.material).toBe(material);
  expect(material.opacity).toBe(1);
  expect(newComponent.material.opacity).toBe(0);
  expect(oldComponent.material.opacity).toBe(1);
  update.step(0.5);
  expect(newComponent.material.opacity).toBe(0.5);
  expect(oldComponent.material.opacity).toBe(0.5);
  update.finish();
  expect(next.children).not.toContain(oldComponent);
  expect(newComponent.material.opacity).toBe(1);
});

it("commits additions and removals immediately when reduced motion is requested", () => {
  const before = board();
  const next = board();
  next.children[1].userData.renderKey = "U2";
  const update = reconcileModel(before, next, false);
  expect(update.animated).toBe(false);
  expect(update.stats).toEqual({ retained: 1, changed: 0, added: 1, removed: 1 });
  expect(next.children).toHaveLength(2);
  expect(next.children[0].material.opacity).toBe(1);
});

it("does not retain geometry when material groups or draw range change", () => {
  const before = board();
  const next = board();
  const oldGeometry = before.children[1].geometry;
  const nextGeometry = next.children[1].geometry;
  oldGeometry.clearGroups();
  oldGeometry.addGroup(0, 3, 0);
  nextGeometry.clearGroups();
  nextGeometry.addGroup(0, 6, 0);
  nextGeometry.setDrawRange(0, 6);
  const update = reconcileModel(before, next, false);
  expect(update.stats).toEqual({ retained: 1, changed: 1, added: 0, removed: 0 });
  const nextComponent = next.children.find((child: { name?: string }) => child.name === "U1");
  expect(nextComponent?.geometry).toBe(nextGeometry);
  expect(nextComponent?.geometry).not.toBe(oldGeometry);
  update.finish();
});

it("fits orthographic models and preserves zoom and pan across resize", () => {
  const camera = new OrthographicCamera(-1, 1, 1, -1, 0.001, 1000);
  const direction = new Vector3(1, 2, 1);
  fitOrthographicCamera(camera, 10, 2, direction);
  expect(camera.isOrthographicCamera).toBe(true);
  expect(camera.zoom).toBeCloseTo(1 / 11.5);
  expect(camera.position.distanceTo(new Vector3())).toBeCloseTo(40);
  const zoom = camera.zoom;
  camera.position.x += 3;
  const pan = camera.position.clone();
  resizeOrthographicCamera(camera, 0.5);
  expect(camera.left).toBe(-0.5);
  expect(camera.right).toBe(0.5);
  expect(camera.zoom).toBe(zoom);
  expect(camera.position).toEqual(pan);
});
