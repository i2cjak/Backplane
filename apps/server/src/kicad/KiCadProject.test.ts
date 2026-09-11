// @effect-diagnostics nodeBuiltinImport:off globalDate:off globalTimers:off cryptoRandomUUID:off globalDateInEffect:off
import * as NodeFS from "node:fs";
import * as NodePath from "node:path";
import { discoverKiCadProject, resolveKiCadProjectFile } from "./KiCadProject.ts";
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

it.effect(
  "tracks creation, edits, and removal of the panelization preset without listing JSON as a board",
  () =>
    Effect.promise(async () => {
      const root = tempRoot();
      NodeFS.mkdirSync(root, { recursive: true });
      NodeFS.writeFileSync(NodePath.join(root, "board.kicad_pcb"), "pcb");
      const clock = Date.now();
      const now = vi.spyOn(Date, "now");
      const first = await discoverKiCadProject(root);
      const preset = NodePath.join(root, "panelize.json");
      NodeFS.writeFileSync(preset, '{"layout":{"rows":2}}');
      now.mockReturnValue(clock + 400);
      const created = await discoverKiCadProject(root);
      expect(created.revision).not.toBe(first.revision);
      expect(created.files.map((file) => file.path)).toEqual(["board.kicad_pcb"]);
      NodeFS.writeFileSync(preset, '{"layout":{"rows":20}}');
      now.mockReturnValue(clock + 800);
      const edited = await discoverKiCadProject(root);
      expect(edited.revision).not.toBe(created.revision);
      NodeFS.unlinkSync(preset);
      now.mockReturnValue(clock + 1200);
      expect((await discoverKiCadProject(root)).revision).toBe(first.revision);
      NodeFS.rmSync(root, { recursive: true });
    }),
);

it.effect("tracks a configured preset and ignores unrelated JSON edits", () =>
  Effect.promise(async () => {
    const root = tempRoot();
    NodeFS.mkdirSync(NodePath.join(root, "hardware"), { recursive: true });
    NodeFS.writeFileSync(
      NodePath.join(root, ".backplane.json"),
      '{"panelization":"hardware/panel.json"}',
    );
    const preset = NodePath.join(root, "hardware/panel.json");
    NodeFS.writeFileSync(preset, "{}");
    const clock = Date.now();
    const now = vi.spyOn(Date, "now");
    const first = await discoverKiCadProject(root);
    expect(first.config?.panelization).toBe("hardware/panel.json");
    NodeFS.writeFileSync(NodePath.join(root, "unrelated.json"), "{}");
    now.mockReturnValue(clock + 400);
    expect((await discoverKiCadProject(root)).revision).toBe(first.revision);
    NodeFS.writeFileSync(preset, '{"layout":{"cols":3}}');
    now.mockReturnValue(clock + 800);
    expect((await discoverKiCadProject(root)).revision).not.toBe(first.revision);
    NodeFS.rmSync(root, { recursive: true });
  }),
);
