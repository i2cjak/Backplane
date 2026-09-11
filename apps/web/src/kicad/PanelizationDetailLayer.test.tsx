import { act } from "react";
import { create, type ReactTestRenderer } from "react-test-renderer";
import { afterEach, expect, it, vi } from "vite-plus/test";
import { PanelizationDetailLayer } from "./PanelizationDetailLayer";

vi.mock("./panelizationDetail", () => ({
  preparePanelizationDetail: () => ({
    viewBox: { x: 0, y: 0, width: 100, height: 100 },
    crop: () => "<svg/>",
  }),
}));
let renderer: ReactTestRenderer | undefined;
afterEach(async () => {
  await act(() => renderer?.unmount());
  renderer = undefined;
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

it("ignores a stale detail decode after zoom moves and releases its URL", async () => {
  vi.useFakeTimers();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("window", { devicePixelRatio: 2 });
  let sequence = 0;
  const revoke = vi.fn();
  vi.stubGlobal("URL", {
    createObjectURL: () => `blob:detail-${++sequence}`,
    revokeObjectURL: revoke,
  });
  const decodes: (() => void)[] = [];
  vi.stubGlobal(
    "Image",
    class {
      src = "";
      decode() {
        return new Promise<void>((resolve) => decodes.push(resolve));
      }
    },
  );
  const props = {
    svg: "source",
    viewport: { width: 600, height: 600 },
    image: { width: 100, height: 100 },
    fit: 1,
  };
  await act(() => {
    renderer = create(<PanelizationDetailLayer {...props} camera={{ scale: 8, x: 0, y: 0 }} />);
  });
  await act(() => vi.advanceTimersByTime(180));
  await act(() => {
    renderer!.update(<PanelizationDetailLayer {...props} camera={{ scale: 16, x: 0, y: 0 }} />);
  });
  await act(() => decodes[0]!());
  expect(renderer!.root.findAllByType("img")).toHaveLength(0);
  expect(revoke).toHaveBeenCalledWith("blob:detail-1");
  await act(() => vi.advanceTimersByTime(180));
  await act(() => decodes[1]!());
  expect(renderer!.root.findByType("img").props.src).toBe("blob:detail-2");
});
