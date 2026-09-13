import type {
  PreviewAutomationFrame,
  PreviewCloneInput,
  PreviewCloneInvokeInput,
  PreviewCloneResponse,
  PreviewCloneResult,
  ScopedThreadRef,
} from "@backplane/contracts";
import type { CloneGestureInput } from "./browserCloneGestures.ts";

export type CloneInvoke = (input: PreviewCloneInvokeInput) => Promise<PreviewCloneResponse>;

/** A visible viewer owns one session; changing tabs creates a new one. */
export function createBrowserCloneSession(
  target: ScopedThreadRef & { readonly tabId: string; readonly cloneId: string },
  invoke: CloneInvoke,
) {
  let pins: Pick<PreviewCloneResponse, "clientId" | "connectionId"> | null = null;
  let disposed = false;
  let running = false;
  let pressed: { x: number; y: number; button?: "left" | "middle" | "right" } | null = null;
  type Pending = {
    input: PreviewCloneInput;
    resolve: (result: PreviewCloneResult | null) => void;
    reject: (error: unknown) => void;
  };
  const queue: Pending[] = [];
  const request = async (input: PreviewCloneInput) => {
    const operation =
      input.action === "down" ||
      input.action === "move" ||
      input.action === "up" ||
      input.action === "wheel"
        ? "pointer"
        : input.action;
    return invoke({ ...target, operation, input, timeoutMs: 10_000, ...pins });
  };
  const drain = async () => {
    if (running) return;
    running = true;
    try {
      while (queue.length) {
        const pending = queue.shift()!;
        if (disposed || !pins) {
          pending.resolve(null);
          continue;
        }
        try {
          const response = await request(pending.input);
          if (pending.input.action === "down")
            pressed = {
              x: pending.input.x,
              y: pending.input.y,
              button: pending.input.button ?? "left",
            };
          if (pending.input.action === "move" && pressed)
            pressed = { ...pressed, x: pending.input.x, y: pending.input.y };
          if (pending.input.action === "up") pressed = null;
          pending.resolve(response.result);
        } catch (error) {
          pending.reject(error);
          for (const remaining of queue.splice(0)) remaining.resolve(null);
        }
      }
    } finally {
      running = false;
    }
  };
  const send = (input: PreviewCloneInput): Promise<PreviewCloneResult | null> => {
    if (disposed || !pins) return Promise.resolve(null);
    return new Promise((resolve, reject) => {
      const previous = queue.at(-1);
      if (previous && input.action === "move" && previous.input.action === "move") {
        queue.pop();
        previous.resolve(null);
      }
      if (previous && input.action === "wheel" && previous.input.action === "wheel") {
        queue.pop();
        input = {
          ...input,
          deltaX: (input.deltaX ?? 0) + (previous.input.deltaX ?? 0),
          deltaY: (input.deltaY ?? 0) + (previous.input.deltaY ?? 0),
        };
        previous.resolve(null);
      }
      queue.push({ input, resolve, reject });
      void drain();
    });
  };
  return {
    async capture(): Promise<PreviewAutomationFrame | null> {
      if (disposed) return null;
      const response = await request({ tabId: target.tabId, action: "capture" });
      if (disposed) return null;
      if (!("data" in response.result))
        throw new Error("The desktop did not return a browser frame.");
      pins = { clientId: response.clientId, connectionId: response.connectionId };
      return response.result;
    },
    send,
    async gesture(input: CloneGestureInput) {
      const base = { tabId: target.tabId, x: input.point.x, y: input.point.y };
      if (input.type === "click" || input.type === "rightClick") {
        const button = input.type === "rightClick" ? "right" : "left";
        await Promise.all([
          send({ ...base, action: "down", button }),
          send({ ...base, action: "up", button }),
        ]);
      } else if (input.type === "scroll") {
        await send({ ...base, action: "wheel", deltaX: input.deltaX, deltaY: input.deltaY });
      } else await send({ ...base, action: input.type });
    },
    dispose() {
      disposed = true;
      for (const pending of queue.splice(0)) pending.resolve(null);
      // A request already in flight can complete after the viewer closes.
      // Queue its release behind it; the desktop watchdog covers disconnection.
      if (pins) {
        const release = () =>
          pressed
            ? request({ tabId: target.tabId, action: "up", ...pressed }).catch(() => undefined)
            : Promise.resolve();
        if (running)
          queue.push({
            input: { tabId: target.tabId, action: "up", x: 0, y: 0 },
            resolve: () => {
              void release();
            },
            reject: () => {
              void release();
            },
          });
        else void release();
      }
    },
  };
}
