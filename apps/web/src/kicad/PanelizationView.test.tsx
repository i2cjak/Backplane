import { act } from "react";
import { create, type ReactTestRenderer } from "react-test-renderer";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import {
  PanelizationView,
  extractPanelizationOutline,
  panelizationRasterSize,
} from "./PanelizationView";
import type { KiCadPanelizationPreview } from "@backplane/contracts";

let renderer: ReactTestRenderer | null = null;
let blobNumber = 0;

const preview = (svg: string): KiCadPanelizationPreview => ({
  svg,
  revision: "revision",
  presetPath: "panelize.json",
  durationMs: 3,
});

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (cause: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function props(
  load: (path: string, revision: string, signal: AbortSignal) => Promise<KiCadPanelizationPreview>,
  scope = "test",
) {
  return {
    path: "board.kicad_pcb",
    revision: "one",
    scope,
    presetPath: undefined,
    visible: true,
    load,
  };
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("URL", {
    createObjectURL: vi.fn(() => `blob:test-${++blobNumber}`),
    revokeObjectURL: vi.fn(),
  });
  vi.stubGlobal(
    "Image",
    class {
      src = "";
      decode() {
        return Promise.resolve();
      }
    },
  );
});

afterEach(async () => {
  await act(() => renderer?.unmount());
  renderer = null;
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("PanelizationView", () => {
  it("aborts an obsolete build and ignores its late response", async () => {
    const first = deferred<KiCadPanelizationPreview>();
    const second = deferred<KiCadPanelizationPreview>();
    const loads: AbortSignal[] = [];
    const load = vi.fn((path: string, revision: string, signal: AbortSignal) => {
      loads.push(signal);
      return revision === "one" ? first.promise : second.promise;
    });
    await act(() => {
      renderer = create(<PanelizationView {...props(load, "obsolete")} />);
    });
    await act(() => {
      renderer?.update(<PanelizationView {...props(load, "obsolete")} revision="two" />);
    });
    expect(loads[0]?.aborted).toBe(true);
    await act(() => first.resolve(preview("old")));
    expect(renderer?.root.findAllByProps({ alt: "Panelization preview" })).toHaveLength(0);
    await act(() => second.resolve(preview("new")));
    await act(async () => undefined);
    expect(renderer?.root.findByProps({ alt: "Panelization preview" }).props.src).toBe(
      "blob:test-1",
    );
  });

  it("keeps the last successful image visible when a rebuild fails", async () => {
    const first = deferred<KiCadPanelizationPreview>();
    const load = vi.fn((_path: string, revision: string) =>
      revision === "one" ? first.promise : Promise.reject(new Error("KiKit failed")),
    );
    await act(() => {
      renderer = create(<PanelizationView {...props(load, "failure")} />);
    });
    await act(() => first.resolve(preview("good")));
    await act(async () => undefined);
    const image = renderer?.root.findByProps({ alt: "Panelization preview" });
    await act(async () => {
      renderer?.update(<PanelizationView {...props(load, "failure")} revision="two" />);
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(renderer?.root.findByProps({ alt: "Panelization preview" }).props.src).toBe(
      image?.props.src,
    );
    expect(renderer?.root.findByProps({ role: "status" }).children.join("")).toContain(
      "KiKit failed",
    );
  });

  it("does not request a preview while hidden", async () => {
    const load = vi.fn(() => Promise.resolve(preview("unused")));
    await act(() => {
      renderer = create(<PanelizationView {...props(load)} visible={false} />);
    });
    expect(load).not.toHaveBeenCalled();
  });
});

it("zooms through the cached raster without rerasterizing", async () => {
  vi.useFakeTimers();
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
  vi.stubGlobal(
    "Image",
    class {
      src = "";
      naturalWidth = 300;
      naturalHeight = 1200;
      decode() {
        return Promise.resolve();
      }
    },
  );
  const viewport = {
    clientWidth: 600,
    clientHeight: 600,
    addEventListener() {},
    removeEventListener() {},
  };
  await act(async () => {
    renderer = create(<PanelizationView {...props(async () => preview("<svg/>"), "zoom")} />, {
      createNodeMock: (element) =>
        (element.props as { className?: string }).className === "panelization-viewport"
          ? viewport
          : null,
    });
  });
  const image = () => renderer!.root.findByProps({ alt: "Panelization preview" });
  const fitted = { ...image().props.style };
  expect(fitted.height).toBeLessThan(viewport.clientHeight);
  expect(fitted.width / fitted.height).toBe(0.25);
  await act(() => renderer!.root.findByProps({ "aria-label": "Zoom in" }).props.onClick());
  expect(image().props.src).toBeDefined();
  expect(image().props.style.width).toBeCloseTo(fitted.width * 1.25);
  await act(() => vi.advanceTimersByTime(100));
  await act(() => renderer!.root.findByProps({ "aria-label": "Zoom in" }).props.onClick());
  await act(() => vi.advanceTimersByTime(100));
  expect(image().props.style.width).toBeCloseTo(fitted.width * 1.5625);
  expect(image().props.style.height).toBeCloseTo(fitted.height * 1.5625);
  expect(URL.createObjectURL).toHaveBeenCalledTimes(1);
  await act(() => renderer!.root.findByProps({ "aria-label": "Fit panelization" }).props.onClick());
  expect(image().props.style).toEqual(fitted);
});

it("bounds cached raster memory while retaining detail for a tall panel", () => {
  for (const [width, height] of [
    [741, 2948],
    [10000, 10000],
    [100, 50000],
  ]) {
    const size = panelizationRasterSize(width!, height!);
    expect(Math.max(size.width, size.height)).toBeLessThanOrEqual(8192);
    expect(size.width * size.height).toBeLessThanOrEqual(16_000_000);
  }
  expect(panelizationRasterSize(741, 2948).height).toBeGreaterThan(7900);
});

it("extracts all nested outline groups and preserves the theme stroke style", () => {
  const style =
    "<style>.backplane-panel-outline path { stroke: #e6e9de; stroke-width: 1.25px; vector-effect: non-scaling-stroke; }</style>";
  const groups = '<g><path d="M0 0L10 10"/></g><g><circle cx="2" cy="3" r="1"/></g>';
  const result = extractPanelizationOutline(
    `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="300" viewBox="0 0 20 30"><path id="artwork"/>${style}<g class="backplane-panel-outline">${groups}</g></svg>`,
  )!;
  expect(result).toContain(style);
  expect(result).toContain(groups);
  expect(result).toContain('viewBox="0 0 20 30"');
  expect(result).not.toContain('id="artwork"');
  expect(result.match(/<g[ >]/g)).toHaveLength(3);
  expect(result.match(/<\/g>/g)).toHaveLength(3);
});
