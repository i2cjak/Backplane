import type { NotificationResponse } from "expo-notifications";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";

import { consumeLastAgentNotificationResponse } from "./notificationResponseConsumer";

import {
  extractAgentNotificationDeepLink,
  extractAgentNotificationThreadTarget,
  routeAgentNotificationResponseOnce,
} from "./notificationPayload";

function responseWithData(data: Record<string, unknown>, identifier = "notification-1") {
  return {
    notification: {
      request: {
        identifier,
        content: {
          data,
        },
      },
    },
  };
}

function remoteResponseWithTriggerPayload(
  payload: Record<string, unknown>,
  identifier = "notification-remote",
) {
  return {
    notification: {
      request: {
        identifier,
        content: { data: null },
        trigger: { payload },
      },
    },
  };
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("consumeLastAgentNotificationResponse", () => {
  it("reports which initial-response operation failed", async () => {
    const cause = new Error("notification lookup unavailable");
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);

    await consumeLastAgentNotificationResponse({
      getLastResponse: () => Promise.reject(cause),
      clearLastResponse: () => Promise.resolve(),
      handleResponse: vi.fn(),
    });

    expect(consoleError).toHaveBeenCalledWith(
      expect.objectContaining({
        _tag: "NotificationNavigationError",
        operation: "read",
      }),
    );
  });

  it("routes a response before reporting a clear failure", async () => {
    const cause = new Error("notification clear unavailable");
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = responseWithData({}, "notification-clear") as NotificationResponse;
    const handleResponse = vi.fn();

    await consumeLastAgentNotificationResponse({
      getLastResponse: () => Promise.resolve(response),
      clearLastResponse: () => Promise.reject(cause),
      handleResponse,
    });

    expect(handleResponse).toHaveBeenCalledWith(response);
    expect(consoleError).toHaveBeenCalledWith(
      expect.objectContaining({
        _tag: "NotificationNavigationError",
        operation: "clear",
        notificationId: "notification-clear",
      }),
    );
  });

  it("reports routing failures before clearing the response", async () => {
    const cause = new Error("notification routing unavailable");
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = responseWithData({}, "notification-route") as NotificationResponse;
    const clearLastResponse = vi.fn(() => Promise.resolve());

    await consumeLastAgentNotificationResponse({
      getLastResponse: () => Promise.resolve(response),
      clearLastResponse,
      handleResponse: () => {
        throw cause;
      },
    });

    expect(clearLastResponse).not.toHaveBeenCalled();
    expect(consoleError).toHaveBeenCalledWith(
      expect.objectContaining({
        _tag: "NotificationNavigationError",
        operation: "route",
        notificationId: "notification-route",
      }),
    );
  });
});

describe("extractAgentNotificationDeepLink", () => {
  it("uses explicit deep links from APNs payload data", () => {
    expect(
      extractAgentNotificationDeepLink(
        responseWithData({
          deepLink: "/threads/env/thread",
          environmentId: "ignored",
          threadId: "ignored",
        }),
      ),
    ).toBe("/threads/env/thread");
  });

  it("normalizes explicit thread deep links from APNs payload data", () => {
    expect(
      extractAgentNotificationDeepLink(
        responseWithData({
          deepLink: "/threads/env%201/thread%2F2",
        }),
      ),
    ).toBe("/threads/env%201/thread%2F2");
  });

  it("falls back to the thread route from environment and thread ids", () => {
    expect(
      extractAgentNotificationDeepLink(
        responseWithData({
          environmentId: "env 1",
          threadId: "thread/2",
        }),
      ),
    ).toBe("/threads/env%201/thread%2F2");
  });

  it("falls back to ids when explicit deep link is not an agent thread route", () => {
    expect(
      extractAgentNotificationDeepLink(
        responseWithData({
          deepLink: "/",
          environmentId: "env",
          threadId: "thread",
        }),
      ),
    ).toBe("/threads/env/thread");
  });

  it("ignores malformed or external links", () => {
    expect(
      extractAgentNotificationDeepLink(responseWithData({ deepLink: "https://example.com" })),
    ).toBeNull();
    expect(
      extractAgentNotificationDeepLink(responseWithData({ deepLink: "/settings" })),
    ).toBeNull();
    expect(
      extractAgentNotificationDeepLink(responseWithData({ deepLink: "//example.com" })),
    ).toBeNull();
    expect(
      extractAgentNotificationDeepLink(responseWithData({ deepLink: "/threads/env/thread?x=1" })),
    ).toBeNull();
    expect(extractAgentNotificationDeepLink({})).toBeNull();
  });
});

describe("extractAgentNotificationThreadTarget", () => {
  it("returns native route params for an encoded deep link", () => {
    expect(
      extractAgentNotificationThreadTarget(
        responseWithData({ deepLink: "/threads/env%201/thread%2F2" }),
      ),
    ).toEqual({ environmentId: "env 1", threadId: "thread/2" });
  });

  it("returns native route params from the APNs data fields", () => {
    expect(
      extractAgentNotificationThreadTarget(
        responseWithData({ environmentId: "environment-1", threadId: "thread-1" }),
      ),
    ).toEqual({ environmentId: "environment-1", threadId: "thread-1" });
  });

  it("reads top-level direct APNs fields from the iOS trigger payload", () => {
    expect(
      extractAgentNotificationThreadTarget(
        remoteResponseWithTriggerPayload({
          environmentId: "environment-1",
          threadId: "thread-1",
        }),
      ),
    ).toEqual({ environmentId: "environment-1", threadId: "thread-1" });
  });
});

describe("routeAgentNotificationResponseOnce", () => {
  it("does not consume a response when navigation fails so a cold start can retry", () => {
    const handledResponseIds = new Set<string>();
    const response = responseWithData(
      { environmentId: "env", threadId: "thread" },
      "notification-retry",
    );
    const navigate = vi
      .fn<(target: { environmentId: string; threadId: string }) => void>()
      .mockImplementationOnce(() => {
        throw new Error("navigation tree is not ready");
      });

    expect(() =>
      routeAgentNotificationResponseOnce({
        handledResponseIds,
        response,
        navigate,
      }),
    ).toThrow("navigation tree is not ready");
    expect(handledResponseIds).toEqual(new Set());

    routeAgentNotificationResponseOnce({
      handledResponseIds,
      response,
      navigate,
    });

    expect(navigate).toHaveBeenNthCalledWith(2, {
      environmentId: "env",
      threadId: "thread",
    });
  });

  it("does not navigate twice when the initial and listener responses refer to one notification", () => {
    const handledResponseIds = new Set<string>();
    const navigations: Array<{ environmentId: string; threadId: string }> = [];
    const response = responseWithData({
      environmentId: "env",
      threadId: "thread",
    });

    routeAgentNotificationResponseOnce({
      handledResponseIds,
      response,
      navigate: (target) => navigations.push(target),
    });
    routeAgentNotificationResponseOnce({
      handledResponseIds,
      response,
      navigate: (target) => navigations.push(target),
    });

    expect(navigations).toEqual([{ environmentId: "env", threadId: "thread" }]);
  });
});
