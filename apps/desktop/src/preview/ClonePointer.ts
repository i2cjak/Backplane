// @effect-diagnostics globalTimers:off -- This Promise-based CDP adapter owns its cancellable abandoned-drag watchdog outside the Effect runtime.
import type { PreviewCloneInput } from "@backplane/contracts";

type PointerInput = Extract<PreviewCloneInput, { action: "down" | "move" | "up" | "wheel" }>;
type Send = (method: string, parameters: Record<string, unknown>) => Promise<unknown>;

/** Keeps drag state across RPCs; releases abandoned presses after a disconnected viewer. */
export function createClonePointerDispatcher(send: Send, releaseAfterMs = 15_000) {
  let held: { button: "left" | "middle" | "right"; x: number; y: number } | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let queue = Promise.resolve();
  let disposed = false;
  const release = async () => {
    clearTimeout(timer);
    const previous = held;
    held = null;
    if (previous)
      await send("Input.dispatchMouseEvent", {
        type: "mouseReleased",
        ...previous,
        buttons: 0,
        clickCount: 1,
      });
  };
  const scheduleRelease = () => {
    clearTimeout(timer);
    if (!held) return;
    timer = setTimeout(() => {
      queue = queue.then(release).catch(() => undefined);
    }, releaseAfterMs);
    timer.unref?.();
  };
  return {
    dispatch(input: PointerInput) {
      const next = queue.then(async () => {
        if (disposed) throw new Error("Browser clone pointer is closed.");
        await send("Input.setIgnoreInputEvents", { ignore: false });
        if (input.action === "down") {
          await release();
          held = { button: input.button ?? "left", x: input.x, y: input.y };
        } else if (held) held = { ...held, x: input.x, y: input.y };
        if (input.action === "up") {
          await release();
          return;
        }
        const button = held?.button ?? "none";
        const buttons =
          button === "left" ? 1 : button === "right" ? 2 : button === "middle" ? 4 : 0;
        await send("Input.dispatchMouseEvent", {
          type:
            input.action === "down"
              ? "mousePressed"
              : input.action === "wheel"
                ? "mouseWheel"
                : "mouseMoved",
          x: input.x,
          y: input.y,
          button,
          buttons,
          ...(input.action === "down" ? { clickCount: 1 } : {}),
          ...(input.action === "wheel"
            ? { deltaX: input.deltaX ?? 0, deltaY: input.deltaY ?? 0 }
            : {}),
        });
        scheduleRelease();
      });
      queue = next.catch(async () => {
        await release().catch(() => undefined);
      });
      return next;
    },
    dispose() {
      disposed = true;
      clearTimeout(timer);
      queue = queue.then(release);
      return queue;
    },
  };
}
