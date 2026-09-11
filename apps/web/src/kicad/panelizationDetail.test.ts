import { expect, it } from "vite-plus/test";
import { preparePanelizationDetail } from "./panelizationDetail";

it("culls distant geometry while retaining nested styles, invisible glyph paths, and exact viewport", () => {
  const index = preparePanelizationDetail(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g style="stroke:red;fill:none"><g stroke-width="0.2"><path d="M1 1L2 2"/><path d="M90 90L95 95"/></g><text opacity="0">hidden</text><path d="M3 3L4 4"/></g></svg>',
  );
  const crop = index.crop({ x: -1, y: -1, width: 10, height: 10 }, { width: 500, height: 500 });
  expect(crop).toContain('viewBox="-1 -1 10 10"');
  expect(crop).toContain('style="stroke:red;fill:none"');
  expect(crop).toContain('stroke-width="0.2"');
  expect(crop).toContain("M1 1L2 2");
  expect(crop).toContain("M3 3L4 4");
  expect(crop).not.toContain("M90 90");
  expect(crop).not.toContain("hidden");
});

it("retains transformed and unsupported paths conservatively", () => {
  const index = preparePanelizationDetail(
    '<svg viewBox="0 0 100 100"><g transform="translate(-90 -90)"><path d="M90 90L95 95"/></g><path d="M80 80A90 90 0 0 0 2 2"/></svg>',
  );
  const crop = index.crop({ x: 0, y: 0, width: 10, height: 10 }, { width: 500, height: 500 });
  expect(crop).toContain('transform="translate(-90 -90)"');
  expect(crop).toContain("M90 90L95 95");
  expect(crop).toContain("A90 90");
});
