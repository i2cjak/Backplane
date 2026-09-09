import { describe, expect, it } from "vite-plus/test";

import {
  deriveAuthClientMetadata,
  isRemoteReachableHost,
  resolveSessionCookieName,
} from "./utils.ts";

describe("deriveAuthClientMetadata", () => {
  it("labels Electron user agents as Electron instead of Chrome", () => {
    const metadata = deriveAuthClientMetadata({
      request: {
        headers: {
          "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) backplane/0.0.15 Chrome/136.0.7103.93 Electron/36.3.2 Safari/537.36",
        },
        source: {
          remoteAddress: "::ffff:127.0.0.1",
        },
      } as never,
    });

    expect(metadata).toMatchObject({
      browser: "Electron",
      deviceType: "desktop",
      ipAddress: "127.0.0.1",
      os: "macOS",
    });
  });

  it("applies client-presented display identity without replacing transport metadata", () => {
    const metadata = deriveAuthClientMetadata({
      request: {
        headers: {
          "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/136.0.7103.93 Electron/36.3.2 Safari/537.36",
        },
        source: {
          remoteAddress: "::ffff:192.168.213.72",
        },
      } as never,
      presented: {
        label: "Backplane Mobile",
        deviceType: "mobile",
        os: "iOS",
      },
    });

    expect(metadata).toMatchObject({
      label: "Backplane Mobile",
      browser: "Electron",
      deviceType: "mobile",
      ipAddress: "192.168.213.72",
      os: "iOS",
    });
    expect(metadata.userAgent).toContain("Electron/36.3.2");
  });
});

describe("session cookie isolation", () => {
  it("isolates loopback web servers by port and server state", () => {
    const first = resolveSessionCookieName({
      mode: "web",
      port: 5775,
      host: "127.0.0.1",
      instanceKey: "/tmp/backplane-agent-one",
      environmentId: "environment-one",
      development: true,
    });
    const second = resolveSessionCookieName({
      mode: "web",
      port: 5775,
      host: "127.0.0.1",
      instanceKey: "/tmp/backplane-agent-two",
      environmentId: "environment-two",
      development: true,
    });

    expect(first).toMatch(/^backplane_session_5775_[a-f0-9]{12}$/);
    expect(second).toMatch(/^backplane_session_5775_[a-f0-9]{12}$/);
    expect(first).not.toBe(second);
  });

  it("isolates remote web servers by server state", () => {
    const first = resolveSessionCookieName({
      mode: "web",
      port: 3773,
      host: "192.168.1.50",
      instanceKey: "/srv/backplane-one",
      environmentId: "environment-one",
      development: false,
    });
    const second = resolveSessionCookieName({
      mode: "web",
      port: 5775,
      host: "192.168.1.50",
      instanceKey: "/srv/backplane-two",
      environmentId: "environment-two",
      development: false,
    });

    expect(first).toMatch(/^backplane_session_[a-f0-9]{12}$/);
    expect(second).toMatch(/^backplane_session_[a-f0-9]{12}$/);
    expect(first).not.toBe(second);
  });

  it("keeps a remote web server cookie stable across port changes", () => {
    const first = resolveSessionCookieName({
      mode: "web",
      port: 8080,
      host: "0.0.0.0",
      instanceKey: "/srv/backplane",
      environmentId: "environment-one",
      development: false,
    });
    const second = resolveSessionCookieName({
      mode: "web",
      port: 9090,
      host: "app.example.com",
      instanceKey: "/srv/backplane",
      environmentId: "environment-one",
      development: false,
    });

    expect(first).toBe(second);
  });

  it("retains desktop port scoping", () => {
    expect(
      resolveSessionCookieName({
        mode: "desktop",
        port: 3773,
        host: "127.0.0.1",
        instanceKey: "/tmp/desktop",
        environmentId: "environment-one",
        development: true,
      }),
    ).toBe("backplane_session_3773");
  });

  it("isolates development servers even when they bind a wildcard host", () => {
    expect(
      resolveSessionCookieName({
        mode: "web",
        port: 5775,
        host: "0.0.0.0",
        instanceKey: "/tmp/backplane-wildcard-dev",
        environmentId: "environment-one",
        development: true,
      }),
    ).toMatch(/^backplane_session_5775_[a-f0-9]{12}$/);
  });

  it("classifies loopback aliases separately from remotely reachable hosts", () => {
    expect(isRemoteReachableHost(undefined)).toBe(false);
    expect(isRemoteReachableHost("localhost")).toBe(false);
    expect(isRemoteReachableHost("127.12.0.1")).toBe(false);
    expect(isRemoteReachableHost("[::1]")).toBe(false);
    expect(isRemoteReachableHost("0.0.0.0")).toBe(true);
    expect(isRemoteReachableHost("192.168.1.50")).toBe(true);
  });
});
