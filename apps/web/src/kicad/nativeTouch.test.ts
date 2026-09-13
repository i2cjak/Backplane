import { expect, it, vi } from "vite-plus/test";

const { findSheetAtPoint, installNativeTouch } = await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}native-touch.js`
);

const box = (x: number, y: number, width: number, height: number) => ({
  contains_point: (point: { x: number; y: number }) =>
    point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height,
});

it("resolves a tappable hierarchical sheet only inside its box", () => {
  const sheet = { sheetfile: "child.kicad_sch", bbox: box(10, 20, 30, 40) };
  const viewer = { document: { sheets: [sheet] } };

  expect(findSheetAtPoint(viewer, { x: 20, y: 30 })).toBe(sheet);
  expect(findSheetAtPoint(viewer, { x: 5, y: 30 })).toBeUndefined();
});

it("ignores sheets without a linked schematic file", () => {
  const viewer = {
    document: { sheets: [{ bbox: box(0, 0, 100, 100) }] },
  };

  expect(findSheetAtPoint(viewer, { x: 50, y: 50 })).toBeUndefined();
});

class Point {
  constructor(
    public x = 0,
    public y = 0,
  ) {}
  copy() {
    return new Point(this.x, this.y);
  }
  set(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

function touchViewer() {
  const canvas = Object.assign(new EventTarget(), {
    style: { touchAction: "" },
    getBoundingClientRect: () => ({ left: 0, top: 0 }),
  });
  const viewer = {
    active: true,
    renderer: { canvas },
    viewport: {
      camera: { center: new Point(), zoom: 1, screen_to_world: (point: Point) => point },
    },
    document: { sheets: [{ sheetfile: "child.kicad_sch", bbox: box(10, 20, 30, 40) }] },
    on_dblclick: vi.fn(),
    notify_viewport_change: vi.fn(),
  };
  installNativeTouch({
    shadowRoot: {
      querySelector: (name: string) => (name === "kc-schematic-app" ? { viewer } : null),
    },
  });
  const touch = (type: string, points: number[][], changed = points) => {
    const coordinates = (values: number[][]) =>
      values.map(([x, y]) => ({ clientX: x, clientY: y }));
    const event = Object.assign(new Event(type, { cancelable: true }), {
      touches: coordinates(points),
      changedTouches: coordinates(changed),
    });
    canvas.dispatchEvent(event);
    return event;
  };
  return { viewer, touch };
}

it("opens a subsheet on one touch and suppresses the synthetic click", () => {
  const { viewer, touch } = touchViewer();
  touch("touchstart", [[20, 30]]);
  expect(touch("touchend", [], [[20, 30]]).defaultPrevented).toBe(true);
  expect(viewer.on_dblclick).toHaveBeenCalledExactlyOnceWith(new Point(20, 30));
});

it("does not navigate after drags, pinches, cancellation, or deactivation", () => {
  for (const gesture of ["drag", "pinch", "cancel", "inactive", "release-moved"]) {
    const { viewer, touch } = touchViewer();
    touch("touchstart", [[20, 30]]);
    if (gesture === "drag") touch("touchmove", [[35, 30]]);
    if (gesture === "pinch") {
      touch("touchstart", [
        [20, 30],
        [30, 30],
      ]);
      touch("touchend", [[20, 30]], [[30, 30]]);
    }
    if (gesture === "inactive") viewer.active = false;
    touch(
      gesture === "cancel" ? "touchcancel" : "touchend",
      [],
      [[gesture === "release-moved" ? 35 : 20, 30]],
    );
    expect(viewer.on_dblclick).not.toHaveBeenCalled();
  }
});

it("leaves ordinary component taps to normal selection", () => {
  const { viewer, touch } = touchViewer();
  touch("touchstart", [[80, 80]]);
  expect(touch("touchend", [], [[80, 80]]).defaultPrevented).toBe(false);
  expect(viewer.on_dblclick).not.toHaveBeenCalled();
});
