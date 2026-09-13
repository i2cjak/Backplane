import { describe, expect, it } from "vite-plus/test";
import {
  EnvironmentId,
  ThreadId,
  type PreviewCloneInvokeInput,
  type PreviewCloneResponse,
} from "@backplane/contracts";
import { createBrowserCloneSession } from "./browserCloneSession.ts";

const target = {
  environmentId: EnvironmentId.make("env"),
  threadId: ThreadId.make("thread"),
  tabId: "tab",
  cloneId: "viewer",
};
const frame = {
  data: "jpeg",
  mimeType: "image/jpeg" as const,
  width: 800,
  height: 400,
  viewportWidth: 1200,
  viewportHeight: 600,
  capturedAt: 1,
};
const respond = (input: PreviewCloneInvokeInput): PreviewCloneResponse => ({
  clientId: "desktop",
  connectionId: "connection",
  result: input.operation === "capture" ? frame : { tabId: "tab", ok: true },
});

describe("browser clone session", () => {
  it("releases a mouse-down that completes after the viewer closes", async () => {
    let finishDown: (() => void) | undefined;
    let observeUp: (() => void) | undefined;
    const pendingDown = new Promise<void>((resolve) => {
      finishDown = resolve;
    });
    const released = new Promise<void>((resolve) => {
      observeUp = resolve;
    });
    const requests: PreviewCloneInvokeInput[] = [];
    const session = createBrowserCloneSession(target, async (input) => {
      requests.push(input);
      if (input.input.action === "down") await pendingDown;
      if (input.input.action === "up") observeUp!();
      return respond(input);
    });
    await session.capture();
    const down = session.gesture({ type: "down", point: { x: 10, y: 20 } });
    session.dispose();
    finishDown!();
    await down;
    await released;
    expect(requests.at(-1)?.input).toMatchObject({ action: "up", x: 10, y: 20 });
  });
  it("requires a captured frame before input and carries exact host pins thereafter", async () => {
    const requests: PreviewCloneInvokeInput[] = [];
    const session = createBrowserCloneSession(target, async (input) => {
      requests.push(input);
      return respond(input);
    });
    await session.gesture({ type: "click", point: { x: 60, y: 70 } });
    expect(requests).toHaveLength(0);
    expect(await session.capture()).toEqual(frame);
    await session.gesture({ type: "rightClick", point: { x: 60, y: 70 } });
    expect(requests.map((request) => request.input.action)).toEqual(["capture", "down", "up"]);
    expect(
      requests
        .slice(1)
        .every(
          (request) => request.clientId === "desktop" && request.connectionId === "connection",
        ),
    ).toBe(true);
    expect(requests[1]?.input).toEqual({
      tabId: "tab",
      action: "down",
      x: 60,
      y: 70,
      button: "right",
    });
    await session.capture();
    expect(requests.at(-1)?.connectionId).toBe("connection");
    session.dispose();
  });
  it("coalesces backed-up pointer moves without dropping the release", async () => {
    const requests: PreviewCloneInvokeInput[] = [];
    let release: (() => void) | undefined;
    const stalled = new Promise<void>((resolve) => {
      release = resolve;
    });
    const session = createBrowserCloneSession(target, async (input) => {
      requests.push(input);
      if (input.input.action === "down") await stalled;
      return respond(input);
    });
    await session.capture();
    const down = session.gesture({ type: "down", point: { x: 1, y: 1 } });
    const move1 = session.gesture({ type: "move", point: { x: 2, y: 2 } });
    const move2 = session.gesture({ type: "move", point: { x: 3, y: 3 } });
    const up = session.gesture({ type: "up", point: { x: 3, y: 3 } });
    release!();
    await Promise.all([down, move1, move2, up]);
    expect(requests.map((request) => request.input.action)).toEqual([
      "capture",
      "down",
      "move",
      "up",
    ]);
    expect(requests[2]?.input).toMatchObject({ x: 3, y: 3 });
    session.dispose();
  });
  it("ignores frames arriving after the viewer closes", async () => {
    let finish: ((response: PreviewCloneResponse) => void) | undefined;
    const session = createBrowserCloneSession(
      target,
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    const capture = session.capture();
    session.dispose();
    finish!({ clientId: "desktop", connectionId: "connection", result: frame });
    expect(await capture).toBeNull();
  });
  it("does not silently drop host pins after failure", async () => {
    const requests: PreviewCloneInvokeInput[] = [];
    const session = createBrowserCloneSession(target, async (input) => {
      requests.push(input);
      if (requests.length > 1) throw new Error("host disconnected");
      return respond(input);
    });
    await session.capture();
    await expect(session.capture()).rejects.toThrow("host disconnected");
    await expect(session.capture()).rejects.toThrow("host disconnected");
    expect(requests.slice(1).every((request) => request.connectionId === "connection")).toBe(true);
    session.dispose();
  });
});
