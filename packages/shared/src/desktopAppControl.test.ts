import { describe, expect, it } from "vite-plus/test";

import { resolveDesktopAppControlAddress } from "./desktopAppControl.ts";

describe("resolveDesktopAppControlAddress", () => {
  it("keeps Unix socket paths short and separates desktop state directories", () => {
    const first = resolveDesktopAppControlAddress({
      stateDir: `/home/user/${"long/".repeat(40)}userdata`,
      platform: "linux",
      tempDir: "/tmp",
      userId: 1000,
      joinPath: (...segments) => segments.join("/"),
    });
    const second = resolveDesktopAppControlAddress({
      stateDir: "/home/user/.backplane/other/userdata",
      platform: "linux",
      tempDir: "/tmp",
      userId: 1000,
      joinPath: (...segments) => segments.join("/"),
    });

    expect(first.directory).toBe("/tmp/backplane-1000");
    expect(first.address.length).toBeLessThan(108);
    expect(first.address).not.toBe(second.address);
  });

  it("uses a Windows named pipe", () => {
    const result = resolveDesktopAppControlAddress({
      stateDir: "C:\\Users\\user\\.backplane\\userdata",
      platform: "win32",
      tempDir: "C:\\Temp",
      userId: undefined,
      joinPath: (...segments) => segments.join("\\"),
    });

    expect(result.directory).toBeNull();
    expect(result.address).toMatch(/^\\\\\.\\pipe\\backplane-app-[a-f0-9]{24}$/);
  });
});
