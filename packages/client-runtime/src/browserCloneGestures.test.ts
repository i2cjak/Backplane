import { describe, expect, it } from "vite-plus/test";
import { createCloneGestureController, type CloneGestureInput } from "./browserCloneGestures.ts";

function setup() {
  const inputs: CloneGestureInput[] = [];
  const controller = createCloneGestureController((input) => inputs.push(input));
  controller.setLayout({ width: 400, height: 600, viewportWidth: 1200, viewportHeight: 600 });
  return { controller, inputs };
}
describe("browser clone gestures", () => {
  it("maps letterboxed phone taps to CSS pixels and ignores the letterbox", () => {
    const { controller, inputs } = setup();
    controller.down(1, { x: 200, y: 100 }, 0);
    controller.up(1, 100);
    expect(inputs).toEqual([]);
    controller.down(1, { x: 200, y: 300 }, 200);
    controller.up(1, 300);
    expect(inputs).toEqual([{ type: "click", point: { x: 600, y: 300 } }]);
  });
  it("releases a drag on cancellation without generating a click", () => {
    const { controller, inputs } = setup();
    controller.down(1, { x: 200, y: 300 }, 0);
    controller.move(1, { x: 220, y: 310 });
    controller.cancel();
    controller.up(1, 100);
    expect(inputs.map((input) => input.type)).toEqual(["down", "move", "up"]);
  });
  it("scrolls with two fingers without clicking on release", () => {
    const { controller, inputs } = setup();
    controller.down(1, { x: 190, y: 300 }, 0);
    controller.down(2, { x: 210, y: 300 }, 0);
    controller.move(1, { x: 190, y: 308 });
    controller.move(2, { x: 210, y: 308 });
    controller.move(1, { x: 190, y: 316 });
    controller.move(2, { x: 210, y: 316 });
    controller.up(1, 100);
    controller.up(2, 100);
    expect(inputs.length).toBeGreaterThan(0);
    expect(inputs.every((input) => input.type === "scroll")).toBe(true);
  });
  it("pinches locally, then pans without scrolling the desktop", () => {
    const { controller, inputs } = setup();
    controller.down(1, { x: 150, y: 300 }, 0);
    controller.down(2, { x: 250, y: 300 }, 0);
    controller.move(1, { x: 100, y: 300 });
    controller.move(2, { x: 300, y: 300 });
    controller.up(1, 100);
    controller.up(2, 100);
    expect(controller.presentation.zoom).toBe(2);
    expect(inputs).toEqual([]);
    controller.down(1, { x: 180, y: 300 }, 200);
    controller.down(2, { x: 220, y: 300 }, 200);
    controller.move(1, { x: 180, y: 308 });
    controller.move(2, { x: 220, y: 308 });
    controller.up(1, 300);
    controller.up(2, 300);
    expect(inputs).toEqual([]);
  });
  it("right clicks on two finger taps and long presses", () => {
    const { controller, inputs } = setup();
    controller.down(1, { x: 200, y: 300 }, 0);
    controller.down(2, { x: 210, y: 300 }, 10);
    controller.up(1, 100);
    controller.up(2, 100);
    controller.down(1, { x: 200, y: 300 }, 200);
    controller.up(1, 800);
    expect(inputs.map((input) => input.type)).toEqual(["rightClick", "rightClick"]);
  });
  it("moves the trackpad cursor without dragging; double tap holds to drag", () => {
    const { controller, inputs } = setup();
    controller.setTrackpad(true);
    controller.down(1, { x: 200, y: 300 }, 0);
    controller.move(1, { x: 210, y: 300 });
    controller.up(1, 100);
    expect(inputs.map((input) => input.type)).toEqual(["move"]);
    controller.down(1, { x: 200, y: 300 }, 200);
    controller.up(1, 250);
    controller.down(1, { x: 200, y: 300 }, 350);
    controller.move(1, { x: 220, y: 300 });
    controller.up(1, 450);
    expect(inputs.map((input) => input.type)).toEqual(["move", "click", "down", "move", "up"]);
  });
});
