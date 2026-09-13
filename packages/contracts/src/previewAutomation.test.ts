import { describe, expect, it } from "vite-plus/test";
import * as Schema from "effect/Schema";

import {
  PreviewAutomationFrame,
  PreviewAutomationOperation,
  PreviewCloneInvokeInput,
} from "./previewAutomation.ts";

const isOperation = Schema.is(PreviewAutomationOperation);
const decodeFrame = Schema.decodeUnknownSync(PreviewAutomationFrame);
const decodeClone = Schema.decodeUnknownSync(PreviewCloneInvokeInput);

describe("preview cloning frame contract", () => {
  it("accepts bounded JPEG frames and advertises captureFrame", () => {
    expect(isOperation("captureFrame")).toBe(true);
    expect(
      decodeFrame({
        data: "ZmFrZQ==",
        mimeType: "image/jpeg",
        width: 640,
        height: 480,
        viewportWidth: 640,
        viewportHeight: 480,
        capturedAt: 1,
      }),
    ).toMatchObject({ mimeType: "image/jpeg", width: 640 });
  });

  it("rejects frames without viewport mapping dimensions", () => {
    expect(() =>
      decodeFrame({
        data: "ZmFrZQ==",
        mimeType: "image/jpeg",
        width: 640,
        height: 480,
        capturedAt: 1,
      }),
    ).toThrow();
  });
});

describe("clone input validation", () => {
  const base = {
    environmentId: "env",
    threadId: "thread",
    cloneId: "viewer",
    tabId: "tab",
    clientId: "desktop",
    connectionId: "connection",
  };
  it("requires captured host pins before accepting input", () => {
    const decode = decodeClone;
    expect(() =>
      decode({
        environmentId: "env",
        threadId: "thread",
        cloneId: "viewer",
        tabId: "tab",
        operation: "pointer",
        input: { tabId: "tab", action: "down", x: 0, y: 0 },
      }),
    ).toThrow();
    expect(() =>
      decode({
        ...base,
        operation: "pointer",
        input: { tabId: "tab", action: "down", x: 0, y: 0 },
      }),
    ).not.toThrow();
  });
  it("rejects mismatched actions, cross-tab input, and non-finite coordinates", () => {
    const decode = decodeClone;
    expect(() =>
      decode({ ...base, operation: "text", input: { tabId: "tab", action: "down", x: 0, y: 0 } }),
    ).toThrow();
    expect(() =>
      decode({
        ...base,
        operation: "pointer",
        input: { tabId: "other", action: "down", x: 0, y: 0 },
      }),
    ).toThrow();
    expect(() =>
      decode({
        ...base,
        operation: "pointer",
        input: { tabId: "tab", action: "down", x: Infinity, y: 0 },
      }),
    ).toThrow();
  });
  it("requires explicit phone text for paste and bounds its size", () => {
    const decode = decodeClone;
    expect(() =>
      decode({
        ...base,
        operation: "clipboardPaste",
        input: { tabId: "tab", action: "clipboardPaste" },
      }),
    ).toThrow();
    expect(() =>
      decode({
        ...base,
        operation: "clipboardPaste",
        input: { tabId: "tab", action: "clipboardPaste", text: "from phone" },
      }),
    ).not.toThrow();
    expect(() =>
      decode({
        ...base,
        operation: "text",
        input: { tabId: "tab", action: "text", text: "x".repeat(64_001) },
      }),
    ).toThrow();
  });
});
