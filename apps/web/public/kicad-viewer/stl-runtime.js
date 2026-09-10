import {
  AmbientLight,
  BufferAttribute,
  BufferGeometry,
  Color,
  DirectionalLight,
  Mesh,
  MeshStandardMaterial,
  PerspectiveCamera,
  Scene,
  Vector3,
  WebGLRenderer,
} from "three";
import { TrackballControls } from "three/addons/controls/TrackballControls.js";

const host = document.getElementById("viewer");
const error = document.getElementById("error");

const parseStl = (buffer) => {
  const bytes = new Uint8Array(buffer);
  const asText = new TextDecoder("latin1").decode(bytes.slice(0, 80));
  const positions = [];
  if (asText.startsWith("solid") && asText.includes("facet")) {
    const text = new TextDecoder().decode(bytes);
    const matches = text.matchAll(/facet\s+normal[\s\S]*?endfacet/g);
    for (const match of matches) {
      const vertices = [...match[0].matchAll(/vertex\s+([-\d.eE]+)\s+([-\d.eE]+)\s+([-\d.eE]+)/g)];
      if (vertices.length !== 3) continue;
      for (const vertex of vertices)
        positions.push(Number(vertex[1]), Number(vertex[2]), Number(vertex[3]));
    }
  } else {
    const view = new DataView(buffer);
    const count = view.getUint32(80, true);
    for (let index = 0; index < count; index += 1) {
      const offset = 84 + index * 50;
      for (let vertex = 0; vertex < 3; vertex += 1) {
        const base = offset + 12 + vertex * 12;
        positions.push(
          view.getFloat32(base, true),
          view.getFloat32(base + 4, true),
          view.getFloat32(base + 8, true),
        );
      }
    }
  }
  const geometry = new BufferGeometry();
  geometry.setAttribute("position", new BufferAttribute(new Float32Array(positions), 3));
  geometry.computeVertexNormals();
  geometry.computeBoundingSphere();
  return geometry;
};

let renderer;
let controls;
const scene = new Scene();
scene.background = new Color(0x101214);
const camera = new PerspectiveCamera(45, 1, 0.01, 10_000);
scene.add(new AmbientLight(0xffffff, 0.6));
const key = new DirectionalLight(0xffffff, 0.9);
key.position.set(2, 4, 3);
scene.add(key);

const fit = (geometry) => {
  const sphere = geometry.boundingSphere;
  if (!sphere) return;
  const mesh = new Mesh(
    geometry,
    new MeshStandardMaterial({ color: 0x8aa0b8, metalness: 0.15, roughness: 0.45 }),
  );
  scene.add(mesh);
  camera.position.copy(new Vector3(1, 0.8, 1).multiplyScalar(Math.max(sphere.radius * 3.2, 1)));
  camera.lookAt(sphere.center);
  controls.target.copy(sphere.center);
  controls.update();
};

const resize = () => {
  if (!renderer) return;
  const width = host.clientWidth || 1;
  const height = host.clientHeight || 1;
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  renderer.setSize(width, height, false);
};

window.addEventListener("message", (event) => {
  if (
    event.source !== parent ||
    event.origin !== location.origin ||
    event.data?.type !== "backplane-snapshot" ||
    event.data.kind !== "stl"
  )
    return;
  error.textContent = "Loading solid…";
  void fetch(event.data.url)
    .then(async (response) => {
      if (!response.ok) throw new Error((await response.text()).slice(0, 700));
      return response.arrayBuffer();
    })
    .then((buffer) => {
      while (scene.children.length > 2) scene.remove(scene.children[2]);
      if (!renderer) {
        renderer = new WebGLRenderer({ antialias: true });
        renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
        host.appendChild(renderer.domElement);
        controls = new TrackballControls(camera, renderer.domElement);
        const frame = () => {
          controls.update();
          renderer.render(scene, camera);
          requestAnimationFrame(frame);
        };
        frame();
        window.addEventListener("resize", resize);
      }
      fit(parseStl(buffer));
      resize();
      error.textContent = "";
    })
    .catch((cause) => {
      error.textContent = cause.message || String(cause);
    });
});

parent.postMessage(
  { type: "backplane-runtime-ready" },
  location.origin === "null" ? "*" : location.origin,
);
