// The web's 3D camera and wheel handling (src/web/solid.js), no page needed:
//   bun test/tools/orbit_test.ts
// A drag turns the model under the pointer with it, a pan moves it with the
// pointer, a zoom keeps the point under the pointer still, and a touchpad's
// scroll is told from a mouse wheel.
import { Orbit, wheelKind } from "../../src/web/solid.js";

let failed = false;
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)}`);
  if (!ok) failed = true;
};
const dot = (a: number[], b: number[]) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const near = (a: number, b: number, e = 1e-6) => Math.abs(a - b) < e;

// a point on screen: right and up of the view's centre, and how far ahead
const screen = (o: Orbit, p: number[]) => {
  const e = o.eye(), d = [p[0] - e[0], p[1] - e[1], p[2] - e[2]];
  const z = dot(d, o.f);
  return { x: dot(d, o.r) / z, y: dot(d, o.u) / z, z };
};

const fresh = () => { const o = new Orbit().aim(-0.6, 0.5); o.dist = 10; o.home = 10; return o; };

{
  const o = fresh();
  check("the view's axes are orthonormal", near(dot(o.r, o.u), 0) && near(dot(o.u, o.f), 0) && near(dot(o.r, o.f), 0) && near(dot(o.f, o.f), 1));
  const front = o.pivot.map((c, i) => c - o.f[i] * 2); // the model's side facing the eye
  const before = screen(o, front);
  o.spin(10, 0);
  check("a drag right turns the near side right", screen(o, front).x > before.x, [before.x, screen(o, front).x]);
  const o2 = fresh(), b2 = screen(o2, front);
  o2.spin(0, 10);
  check("a drag down turns the near side down", screen(o2, front).y < b2.y, [b2.y, screen(o2, front).y]);
  for (let i = 0; i < 500; i += 1) o.spin(7, -3);
  check("turning many times keeps the axes square", near(dot(o.r, o.u), 0, 1e-9) && near(dot(o.f, o.f), 1, 1e-9));
}
{
  const o = fresh(), p = [0, 0, 0], before = screen(o, p);
  o.pan(20, 10, o.unit(500));
  const after = screen(o, p);
  check("a pan moves the model with the pointer", after.x > before.x && after.y < before.y, [before, after]);
}
{
  const o = fresh(), h = 500, s = o.unit(h);
  // the point under a pointer 100 px right of and 50 px above the centre, at the pivot's depth
  const t = o.target(), under = t.map((c, i) => c + o.r[i] * 100 * s + o.u[i] * 50 * s);
  const before = screen(o, under);
  o.zoom(2, 100 * s, 50 * s);
  const after = screen(o, under);
  check("a zoom keeps the point under the pointer", near(before.x, after.x, 1e-9) && near(before.y, after.y, 1e-9) && near(o.dist, 5), [before, after, o.dist]);
  for (let i = 0; i < 100; i += 1) o.zoom(2, 0, 0);
  check("zooming in stops at a sixtieth of the fitted distance", near(o.dist, 10 / 60));
  for (let i = 0; i < 100; i += 1) o.zoom(0.5, 0, 0);
  check("zooming out stops at twenty times it", near(o.dist, 200));
}
{
  const at = (deltaX: number, deltaY: number, more = {}) => ({ deltaX, deltaY, deltaMode: 0, ctrlKey: false, timeStamp: 1000, ...more });
  check("a mouse wheel notch zooms", wheelKind(at(0, 120), null) === "wheel");
  check("a wheel in lines zooms", wheelKind(at(0, 3, { deltaMode: 1 }), null) === "wheel");
  check("a touchpad's small steps move", wheelKind(at(0, 6), null) === "pad");
  check("a touchpad's sideways scroll moves", wheelKind(at(-30, 50), null) === "pad");
  check("a pinch zooms", wheelKind(at(0, 4, { ctrlKey: true }), null) === "pinch");
  check("a touchpad's fast flick stays a move", wheelKind(at(0, 120, { timeStamp: 1100 }), { kind: "pad", t: 1000 }) === "pad");
  check("a wheel after a pause is a wheel again", wheelKind(at(0, 120, { timeStamp: 2000 }), { kind: "pad", t: 1000 }) === "wheel");
}

process.exit(failed ? 1 : 0);
