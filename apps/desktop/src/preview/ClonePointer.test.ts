import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createClonePointerDispatcher } from "./ClonePointer.ts";

afterEach(() => vi.useRealTimers());
describe("remote clone pointer", () => {
  it("preserves CSS coordinates and held buttons through a serialized drag", async () => {
    const send = vi.fn(async (_method: string, _parameters: Record<string, unknown>) => undefined);
    const pointer = createClonePointerDispatcher(send);
    await Promise.all([
      pointer.dispatch({ tabId: "tab", action: "down", x: 23.5, y: 41 }),
      pointer.dispatch({ tabId: "tab", action: "move", x: 90, y: 80 }),
      pointer.dispatch({ tabId: "tab", action: "up", x: 90, y: 80 }),
    ]);
    const events = send.mock.calls.filter(([method]) => method === "Input.dispatchMouseEvent");
    expect(events.map(([, value]) => value)).toEqual([
      { type: "mousePressed", x: 23.5, y: 41, button: "left", buttons: 1, clickCount: 1 },
      { type: "mouseMoved", x: 90, y: 80, button: "left", buttons: 1 },
      { type: "mouseReleased", x: 90, y: 80, button: "left", buttons: 0, clickCount: 1 },
    ]);
    await pointer.dispose();
  });
  it("releases a disconnected viewer's held button", async () => {
    vi.useFakeTimers();
    const send = vi.fn(async (_method: string, _parameters: Record<string, unknown>) => undefined);
    const pointer = createClonePointerDispatcher(send, 100);
    await pointer.dispatch({ tabId: "tab", action: "down", x: 10, y: 20, button: "right" });
    await vi.advanceTimersByTimeAsync(100);
    expect(send).toHaveBeenLastCalledWith("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: 10,
      y: 20,
      button: "right",
      buttons: 0,
      clickCount: 1,
    });
    await pointer.dispose();
  });
  it("does not leave the mouse pressed when dispatch fails", async () => {
    const send = vi.fn(async (_method: string, _parameters: Record<string, unknown>) => undefined);
    const pointer = createClonePointerDispatcher(send);
    await pointer.dispatch({ tabId: "tab", action: "down", x: 10, y: 20 });
    send.mockRejectedValueOnce(new Error("disconnected"));
    await expect(pointer.dispatch({ tabId: "tab", action: "move", x: 40, y: 50 })).rejects.toThrow(
      "disconnected",
    );
    await pointer.dispose();
    expect(send).toHaveBeenLastCalledWith(
      "Input.dispatchMouseEvent",
      expect.objectContaining({ type: "mouseReleased", buttons: 0 }),
    );
  });
});
