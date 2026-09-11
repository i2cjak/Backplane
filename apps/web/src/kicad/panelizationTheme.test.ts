import { describe, expect, it, vi } from "vite-plus/test";
import { readPanelizationTheme, themePanelizationSvg } from "./panelizationTheme";

describe("panelization theme", () => {
  it("maps KiCad plot colors to the active semantic palette", () => {
    const svg =
      '<svg><path stroke="#000000"/><path fill="#DCB4AA"/><path fill="#E07A5F"/><path fill="#FFFFFF"/></svg>';
    expect(
      themePanelizationSvg(svg, {
        background: "#101010",
        foreground: "#f4f4f4",
        muted: "#888888",
        accent: "#66cc99",
        highlight: "#ffcc55",
      }),
    ).toBe(
      '<svg><path stroke="#f4f4f4"/><path fill="#66cc99"/><path fill="#ffcc55"/><path fill="#101010"/></svg>',
    );
  });

  it("reads semantic variables and retains fallbacks", () => {
    vi.stubGlobal("getComputedStyle", () => ({
      getPropertyValue: (name: string) =>
        name === "--background" ? "#222" : name === "--foreground" ? "#eee" : "",
    }));
    expect(readPanelizationTheme({} as Element)).toMatchObject({
      background: "#222",
      foreground: "#eee",
    });
    vi.unstubAllGlobals();
  });
});
