// @effect-diagnostics nodeBuiltinImport:off globalDate:off globalTimers:off cryptoRandomUUID:off globalDateInEffect:off
import * as NodeFS from "node:fs";
import * as NodePath from "node:path";
import {
  configuredArtifactPaths,
  discoverKiCadProject,
  loadVizInspectImagePaths,
  resolveKiCadProjectFile,
} from "./KiCadProject.ts";
import { kiCadModelAction } from "./KiCadModel.ts";
import { afterEach, expect, vi } from "vite-plus/test";
import { it } from "@effect/vitest";
import * as Effect from "effect/Effect";

afterEach(() => vi.restoreAllMocks());

const tempRoot = () => NodePath.join("/tmp", `backplane-kicad-${crypto.randomUUID()}`);

it.effect(
  "discovers source and generated KiCad files recursively, including ignored build output",
  () =>
    Effect.promise(async () => {
      const root = tempRoot();
      NodeFS.mkdirSync(NodePath.join(root, "build", "gerbers"), { recursive: true });
      NodeFS.mkdirSync(NodePath.join(root, ".git"), { recursive: true });
      NodeFS.writeFileSync(NodePath.join(root, "board.kicad_pcb"), "pcb");
      NodeFS.writeFileSync(NodePath.join(root, "board.kicad_sch"), "sch");
      NodeFS.writeFileSync(NodePath.join(root, "build", "gerbers", "board-F_Cu.gtl"), "gerber");
      NodeFS.writeFileSync(NodePath.join(root, "build", "board.step"), "step");
      NodeFS.writeFileSync(NodePath.join(root, ".git", "ignored.gbr"), "ignored");
      for (const directory of [".history", "hardware/.history"]) {
        NodeFS.mkdirSync(NodePath.join(root, directory), { recursive: true });
        for (const extension of ["kicad_pcb", "kicad_sch", "gbr", "glb"])
          NodeFS.writeFileSync(NodePath.join(root, directory, `old.${extension}`), "archived");
      }
      const manifest = await discoverKiCadProject(root);
      expect(await resolveKiCadProjectFile(root, ".history/old.kicad_pcb")).toBeUndefined();
      expect(manifest.files.map((file) => file.path)).toEqual([
        "board.kicad_pcb",
        "board.kicad_sch",
        "build/board.step",
        "build/gerbers/board-F_Cu.gtl",
      ]);
      expect(manifest.files.find((file) => file.kind === "gerber")?.mimeType).toBe(
        "application/octet-stream",
      );
    }),
);

it.effect(
  "changes revision when an inspected file changes and rejects traversal/symlink escapes",
  () =>
    Effect.promise(async () => {
      const root = tempRoot();
      const outside = tempRoot();
      NodeFS.mkdirSync(root, { recursive: true });
      NodeFS.mkdirSync(outside, { recursive: true });
      NodeFS.writeFileSync(NodePath.join(root, "board.kicad_pcb"), "one");
      NodeFS.writeFileSync(NodePath.join(outside, "outside.kicad_pcb"), "secret");
      NodeFS.symlinkSync(
        NodePath.join(outside, "outside.kicad_pcb"),
        NodePath.join(root, "link.kicad_pcb"),
      );
      const first = await discoverKiCadProject(root);
      NodeFS.utimesSync(
        NodePath.join(root, "board.kicad_pcb"),
        new Date(),
        new Date(Date.now() + 1000),
      );
      NodeFS.writeFileSync(NodePath.join(root, "board.kicad_pcb"), "two");
      vi.spyOn(Date, "now").mockReturnValue(Date.now() + 350);
      expect((await discoverKiCadProject(root)).revision).not.toBe(first.revision);
      expect(await resolveKiCadProjectFile(root, "../outside.kicad_pcb")).toBeUndefined();
      expect(await resolveKiCadProjectFile(root, "link.kicad_pcb")).toBeUndefined();
    }),
);

it.effect("invalidates revision for companion metadata without listing it as a native file", () =>
  Effect.promise(async () => {
    const root = tempRoot();
    NodeFS.mkdirSync(root, { recursive: true });
    const board = NodePath.join(root, "board.kicad_pcb");
    const metadata = `${board}.backplane.json`;
    NodeFS.writeFileSync(board, "pcb");

    const first = await discoverKiCadProject(root);
    expect(first.files.map((file) => file.path)).toEqual(["board.kicad_pcb"]);

    const clock = Date.now();
    const now = vi.spyOn(Date, "now");
    now.mockReturnValue(clock + 400);
    NodeFS.writeFileSync(metadata, '{"custom_properties":{"root":{"key":"one"}}}');
    const second = await discoverKiCadProject(root);
    expect(second.revision).not.toBe(first.revision);
    expect(second.files.map((file) => file.path)).toEqual(["board.kicad_pcb"]);
    expect(await resolveKiCadProjectFile(root, "board.kicad_pcb.backplane.json")).toBeUndefined();

    now.mockReturnValue(clock + 800);
    NodeFS.writeFileSync(metadata, '{"custom_properties":{"root":{"key":"updated"}}}');
    const third = await discoverKiCadProject(root);
    expect(third.revision).not.toBe(second.revision);
    expect(third.files.map((file) => file.path)).toEqual(["board.kicad_pcb"]);
  }),
);

it.effect("reports malformed project configuration without preventing discovery", () =>
  Effect.promise(async () => {
    const root = tempRoot();
    NodeFS.mkdirSync(root, { recursive: true });
    NodeFS.writeFileSync(NodePath.join(root, ".backplane.json"), "{broken");
    NodeFS.writeFileSync(NodePath.join(root, "board.kicad_pro"), "{}");
    const manifest = await discoverKiCadProject(root);
    expect(manifest.files[0]?.kind).toBe("project");
    expect(manifest.warnings).toContain("Unable to parse .backplane.json");
  }),
);

it.effect("discovers library assets and preserves the optional analysis dashboard", () =>
  Effect.promise(async () => {
    const root = tempRoot();
    NodeFS.mkdirSync(NodePath.join(root, "parts.pretty"), { recursive: true });
    NodeFS.writeFileSync(
      NodePath.join(root, "parts.pretty", "antenna.kicad_mod"),
      '(footprint "antenna")',
    );
    NodeFS.writeFileSync(NodePath.join(root, "parts.kicad_sym"), "(kicad_symbol_lib)");
    NodeFS.writeFileSync(
      NodePath.join(root, ".backplane.json"),
      '{"analysisUrl":"https://analysis.example.test/"}',
    );
    const manifest = await discoverKiCadProject(root);
    expect(manifest.files.map(({ kind }) => kind).sort()).toEqual(["footprint", "symbol"]);
    expect(manifest.config?.analysisUrl).toBe("https://analysis.example.test/");
    expect((await resolveKiCadProjectFile(root, "parts.pretty/antenna.kicad_mod"))?.file.kind).toBe(
      "footprint",
    );
  }),
);

it.effect("reads explicit library assignments and reports missing assigned assets", () =>
  Effect.promise(async () => {
    const root = tempRoot();
    NodeFS.mkdirSync(root, { recursive: true });
    NodeFS.writeFileSync(NodePath.join(root, "parts.kicad_sym"), "(kicad_symbol_lib)");
    NodeFS.writeFileSync(
      NodePath.join(root, ".backplane.json"),
      '{"symbol":"parts.kicad_sym","symbolMember":"Controller","footprint":"generated/controller.kicad_mod"}',
    );
    const manifest = await discoverKiCadProject(root);
    expect(manifest.config).toMatchObject({
      symbol: "parts.kicad_sym",
      symbolMember: "Controller",
      footprint: "generated/controller.kicad_mod",
    });
    expect(manifest.warnings).toContain(
      "Configured footprint file not found: generated/controller.kicad_mod",
    );
  }),
);

it.effect("resolves saved FreeCAD and Blender inspect pointers from .backplane.json", () =>
  Effect.promise(async () => {
    const root = tempRoot();
    NodeFS.mkdirSync(NodePath.join(root, "ws", "board"), { recursive: true });
    NodeFS.mkdirSync(NodePath.join(root, "mech"), { recursive: true });
    NodeFS.writeFileSync(NodePath.join(root, "ws", "board", "layout.kicad_pcb"), "pcb");
    NodeFS.writeFileSync(NodePath.join(root, "ws", "board", "layout.kicad_sch"), "sch");
    NodeFS.writeFileSync(NodePath.join(root, "mech", "BASE.stl"), "solid base");
    NodeFS.writeFileSync(NodePath.join(root, "mech", "PLATE.stl"), "solid plate");
    NodeFS.writeFileSync(
      NodePath.join(root, "mech", "enclosure-params.json"),
      '{"clearance_mm":1.2}',
    );
    NodeFS.writeFileSync(
      NodePath.join(root, "mech", "blender-scene.json"),
      '{"required":["PCB","BASE","PLATE"]}',
    );
    NodeFS.writeFileSync(NodePath.join(root, "mech", "product-render.png"), "png-bytes");
    NodeFS.writeFileSync(NodePath.join(root, "mech", "load-viz-aluminum.png"), "al-png");
    NodeFS.writeFileSync(
      NodePath.join(root, "mech", "load-viz-materials.json"),
      JSON.stringify({
        product: NodePath.join(root, "mech", "product-render.png"),
        outputs: { aluminum: NodePath.join(root, "mech", "load-viz-aluminum.png") },
      }),
    );
    NodeFS.writeFileSync(
      NodePath.join(root, ".backplane.json"),
      JSON.stringify({
        pcb: "ws/board/layout.kicad_pcb",
        schematic: "ws/board/layout.kicad_sch",
        enclosure: {
          params: "mech/enclosure-params.json",
          solids: { BASE: "mech/BASE.stl", PLATE: "mech/PLATE.stl" },
        },
        product: {
          scene: "mech/blender-scene.json",
          still: "mech/product-render.png",
          loadViz: "mech/load-viz-materials.json",
        },
        drivers: {
          kicad: {
            mcp: "kicad",
            reference: "https://github.com/mixelpixx/KiCAD-MCP-Server",
            mutations: ["edit-board"],
          },
          freecad: {
            mcp: "freecad",
            reference: "https://github.com/neka-nat/freecad-mcp",
            mutations: ["edit-enclosure"],
          },
          blender: {
            mcp: "blender",
            reference: "https://github.com/ahujasid/blender-mcp",
            mutations: ["edit-scene"],
          },
          skipMe: { reference: "https://example.test/not-enough" },
        },
      }),
    );
    const manifest = await discoverKiCadProject(root);
    expect(configuredArtifactPaths(manifest.config)).toEqual([
      "mech/enclosure-params.json",
      "mech/BASE.stl",
      "mech/PLATE.stl",
      "mech/blender-scene.json",
      "mech/product-render.png",
      "mech/load-viz-materials.json",
    ]);
    expect(manifest.config?.pcb).toBe("ws/board/layout.kicad_pcb");
    expect(manifest.config?.enclosure?.solids?.BASE).toBe("mech/BASE.stl");
    expect(manifest.config?.product?.still).toBe("mech/product-render.png");
    expect(manifest.config?.drivers).toEqual({
      kicad: {
        mcp: "kicad",
        reference: "https://github.com/mixelpixx/KiCAD-MCP-Server",
        mutations: ["edit-board"],
      },
      freecad: {
        mcp: "freecad",
        reference: "https://github.com/neka-nat/freecad-mcp",
        mutations: ["edit-enclosure"],
      },
      blender: {
        mcp: "blender",
        reference: "https://github.com/ahujasid/blender-mcp",
        mutations: ["edit-scene"],
      },
    });
    const base = await resolveKiCadProjectFile(root, "mech/BASE.stl");
    const still = await resolveKiCadProjectFile(root, "mech/product-render.png");
    const aluminum = await resolveKiCadProjectFile(root, "mech/load-viz-aluminum.png");
    const params = await resolveKiCadProjectFile(root, "mech/enclosure-params.json");
    const pcb = await resolveKiCadProjectFile(root, "ws/board/layout.kicad_pcb");
    expect(base?.file.kind).toBe("model");
    expect(still?.file.kind).toBe("image");
    expect(aluminum?.file.kind).toBe("image");
    expect(params?.file.kind).toBe("json");
    expect(kiCadModelAction(base!.file)).toBe("serve-existing");
    expect(kiCadModelAction(pcb!.file)).toBe("export-glb");
    expect(NodeFS.readFileSync(base!.absolutePath, "utf8")).toBe("solid base");
    expect(NodeFS.readFileSync(still!.absolutePath, "utf8")).toBe("png-bytes");
    expect(
      loadVizInspectImagePaths(
        root,
        JSON.parse(
          NodeFS.readFileSync(NodePath.join(root, "mech", "load-viz-materials.json"), "utf8"),
        ),
      ),
    ).toEqual(["mech/product-render.png", "mech/load-viz-aluminum.png"]);
  }),
);
