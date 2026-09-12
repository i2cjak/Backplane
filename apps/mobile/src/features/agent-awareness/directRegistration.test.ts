import { beforeEach, expect, it, vi } from "vite-plus/test";
import { EnvironmentId } from "@backplane/contracts";
import type { SavedRemoteConnection } from "../../lib/connection";

const mocks = vi.hoisted(() => ({
  permission: vi.fn(),
  token: vi.fn(),
  fetch: vi.fn(),
}));
vi.mock("expo-constants", () => ({
  default: {
    expoConfig: {
      ios: { bundleIdentifier: "works.backplane.app" },
      extra: { appVariant: "backplane" },
    },
  },
}));
vi.mock("expo-notifications", () => ({
  getPermissionsAsync: mocks.permission,
  getDevicePushTokenAsync: mocks.token,
  IosAuthorizationStatus: { AUTHORIZED: 2, PROVISIONAL: 3, EPHEMERAL: 4 },
}));
vi.mock("../../persistence/imperative", () => ({
  loadOrCreateAgentAwarenessDeviceId: async () => "phone",
}));
const connection: SavedRemoteConnection = {
  environmentId: EnvironmentId.make("one"),
  environmentLabel: "One",
  httpBaseUrl: "https://one.test",
  wsBaseUrl: "wss://one.test",
  bearerToken: "bearer",
  pairingUrl: "https://one.test",
  displayUrl: "https://one.test",
};
beforeEach(() => {
  vi.resetModules();
  vi.clearAllMocks();
  mocks.permission.mockResolvedValue({ granted: true });
  mocks.token.mockResolvedValue({ data: "a".repeat(64) });
  mocks.fetch.mockImplementation(async () => new Response(JSON.stringify({ configured: true })));
  vi.stubGlobal("fetch", mocks.fetch);
});
it("shares the native token request across overlapping environment registrations", async () => {
  const { registerDirectPush } = await import("./directRegistration");
  await Promise.all([
    registerDirectPush({ connection, liveActivitiesEnabled: true }),
    registerDirectPush({
      connection: { ...connection, environmentId: EnvironmentId.make("two") },
      liveActivitiesEnabled: true,
    }),
  ]);
  expect(mocks.token).toHaveBeenCalledTimes(1);
  expect(mocks.fetch).toHaveBeenCalledTimes(2);
  expect(JSON.parse(mocks.fetch.mock.calls[0]![1].body).pushToken).toBe("a".repeat(64));
});
it("still registers a Live Activity when the notification token request fails", async () => {
  mocks.token.mockRejectedValue(new Error("Native APNs unavailable"));
  const { registerDirectPush, getDirectPushStatuses, getDirectPushErrors } =
    await import("./directRegistration");
  await registerDirectPush({
    connection,
    liveActivitiesEnabled: true,
    activityToken: "b".repeat(64),
  });
  expect(JSON.parse(mocks.fetch.mock.calls[0]![1].body).activityToken).toBe("b".repeat(64));
  expect(getDirectPushStatuses().get("one")).toBe("failed");
  expect(getDirectPushErrors().get("one")).toContain("Native APNs unavailable");
});
it("accepts provisional iOS permission instead of disabling delivery", async () => {
  mocks.permission.mockResolvedValue({ granted: false, ios: { status: 3 } });
  const { registerDirectPush } = await import("./directRegistration");
  await registerDirectPush({ connection, liveActivitiesEnabled: true });
  expect(JSON.parse(mocks.fetch.mock.calls[0]![1].body).notificationsEnabled).toBe(true);
});

it("registers ordinary notifications before a failed Live Activity token lookup", async () => {
  const { registerDirectPushWithActivityToken, getDirectPushErrors } =
    await import("./directRegistration");
  await registerDirectPushWithActivityToken({
    connection,
    liveActivitiesEnabled: true,
    activity: { getPushToken: () => Promise.reject(new Error("activity ended")) },
  });
  expect(mocks.fetch).toHaveBeenCalledTimes(1);
  expect(getDirectPushErrors().get("one:activity")).toContain("activity ended");
});

it("refreshes the registration with a Live Activity token after ordinary registration", async () => {
  const { registerDirectPushWithActivityToken } = await import("./directRegistration");
  await registerDirectPushWithActivityToken({
    connection,
    liveActivitiesEnabled: true,
    activity: { getPushToken: () => Promise.resolve("b".repeat(64)) },
  });
  expect(mocks.fetch).toHaveBeenCalledTimes(2);
  expect(JSON.parse(mocks.fetch.mock.calls[1]![1].body).activityToken).toBe("b".repeat(64));
});

it("does not wait for a pending Live Activity token before ordinary registration", async () => {
  const { registerDirectPushWithActivityToken, getDirectPushStatuses } =
    await import("./directRegistration");
  const activityToken = Promise.withResolvers<string>();
  const lookupStarted = Promise.withResolvers<void>();
  const registration = registerDirectPushWithActivityToken({
    connection,
    liveActivitiesEnabled: true,
    activity: {
      getPushToken: async () => {
        lookupStarted.resolve();
        return activityToken.promise;
      },
    },
  });
  await lookupStarted.promise;
  expect(mocks.fetch).toHaveBeenCalledTimes(1);
  expect(JSON.parse(mocks.fetch.mock.calls[0]![1].body).pushToken).toBe("a".repeat(64));
  expect(getDirectPushStatuses().get("one")).toBe("registered");
  activityToken.resolve("c".repeat(64));
  await registration;
  expect(mocks.fetch).toHaveBeenCalledTimes(2);
});
