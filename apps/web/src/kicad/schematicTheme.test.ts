import { afterEach, describe, expect, it, vi } from "vite-plus/test";

const adapterUrl = new URL("../../public/kicad-viewer/", import.meta.url).href;
const { schematicTheme } = await import(/* @vite-ignore */ `${adapterUrl}schematic-theme.js`);
const { installSchematicContrast } = await import(
  /* @vite-ignore */ `${adapterUrl}schematic-contrast.js`
);

function rgba(css: string): number[] {
  const values = css.match(/[\d.]+/g)?.map(Number);
  if (!values || values.length < 3) throw new Error(`Unsupported color: ${css}`);
  return [...values.slice(0, 3).map((value) => value / 255), values[3] ?? 1];
}

function luminance(color: number[]) {
  return color.slice(0, 3).reduce((sum, channel, index) => {
    const linear = channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    return sum + linear * [0.2126, 0.7152, 0.0722][index]!;
  }, 0);
}

function contrast(foreground: string, background: string) {
  const fg = rgba(foreground);
  const bg = rgba(background);
  const composite = fg
    .slice(0, 3)
    .map((channel, index) => channel * fg[3]! + bg[index]! * (1 - fg[3]!));
  const a = luminance(composite);
  const b = luminance(bg);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.resetModules();
});

describe("schematic presentation", () => {
  it("keeps DNP text and outlines readable across repaints without brightening fills", () => {
    const theme = Object.fromEntries(
      Object.entries(schematicTheme).flatMap(([key, css]) =>
        typeof css === "string" ? [[key, { css }]] : [],
      ),
    );
    const nativeDim = { css: "rgb(98, 98, 98)" };
    class ItemPainter {
      is_dimmed = true;
      dim_color(_color: { css: string }) {
        return nativeDim;
      }
      dim_if_needed(color: { css: string }) {
        return this.is_dimmed ? this.dim_color(color) : color;
      }
    }
    const create = () => ({ painters: new Map([[ItemPainter, new ItemPainter()]]) });
    const viewer = { theme, create_painter: create, painter: create() };
    installSchematicContrast(viewer);
    for (const painter of [viewer.painter, viewer.create_painter()]) {
      const item = painter.painters.get(ItemPainter)!;
      for (const role of ["reference", "value", "component_outline", "pin", "sheet_fields"]) {
        const rendered = item.dim_if_needed(theme[role]!);
        for (const surface of ["background", "component_body", "sheet_background"]) {
          expect(contrast(rendered.css, schematicTheme[surface])).toBeGreaterThanOrEqual(4.5);
        }
      }
      expect(item.dim_if_needed(theme.component_body!)).toBe(nativeDim);
      expect(item.dim_if_needed(theme.sheet_background!)).toBe(nativeDim);
      item.is_dimmed = false;
      expect(item.dim_if_needed(theme.reference!)).toBe(theme.reference);
      expect(item.dim_if_needed(theme.dnp_marker!)).toBe(theme.dnp_marker);
    }
  });

  it("meets WCAG AA for every foreground on the canvas, symbol body, and sheet fill", () => {
    // Fills and decorative grids are backgrounds, not text or essential graphics.
    const backgrounds = new Set([
      "background",
      "component_body",
      "sheet_background",
      "note_background",
      "grid",
      "grid_axes",
      "page_limits",
    ]);
    for (const [role, value] of Object.entries(schematicTheme)) {
      if (backgrounds.has(role) || typeof value !== "string") continue;
      for (const surface of ["background", "component_body", "sheet_background"]) {
        expect(
          contrast(value, schematicTheme[surface]),
          `${role} on ${surface}`,
        ).toBeGreaterThanOrEqual(4.5);
      }
    }
  });

  it.each([true, false])(
    "applies the complete palette and drawing defaults (theme fetch succeeds: %s)",
    async (ok) => {
      class Color {
        constructor(readonly css: string) {}
        static from_css(css: string) {
          return new Color(css);
        }
        to_array() {
          return rgba(this.css);
        }
      }
      const initial = new Color("rgb(132, 0, 0)");
      const painted: Color[] = [];
      const core = {
        theme: { background: initial, note: initial },
        renderer: { background_color: initial, state: { fill: initial, stroke: initial } },
        layers: { by_name: () => undefined },
        viewport: { camera: { zoom: 1 } },
        zoom_fit_top_item: vi.fn(),
        paint() {
          painted.push(this.renderer.state.stroke);
        },
        draw: vi.fn(),
      };
      const element = {
        shadowRoot: {
          querySelector: (name: string) => (name === "kc-schematic-app" ? { viewer: core } : null),
        },
        parentElement: { querySelector: () => ({}) },
      };
      vi.stubGlobal("document", { documentElement: { dataset: {} } });
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => ({ ok, status: ok ? 200 : 503, json: async () => ({}) })),
      );
      const { installCanvasPresentation } = await import(
        /* @vite-ignore */ `${adapterUrl}canvas-presentation.js`
      );
      await installCanvasPresentation(element);
      expect(core.renderer.background_color.css).toBe(schematicTheme.background);
      expect(core.renderer.state.fill.css).toBe(schematicTheme.note);
      expect(painted.map((color) => color.css)).toEqual([schematicTheme.note]);
      expect(core.theme).toMatchObject(
        Object.fromEntries(
          Object.entries(schematicTheme).map(([key, value]) => [
            key,
            typeof value === "string" ? new Color(value) : value,
          ]),
        ),
      );
      await installCanvasPresentation(element);
      expect(painted).toHaveLength(1);
    },
  );
});
