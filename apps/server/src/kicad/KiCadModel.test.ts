// @effect-diagnostics nodeBuiltinImport:off
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import { expect, it } from "vite-plus/test";
import {
  createKiCadModelCache,
  kiCadGlbExportArgs,
  kiCadModelAction,
  resolveKiCadModelRevision,
} from "./KiCadModel.ts";

it("exports PCB boards through kicad-cli and serves saved solids as-is", () => {
  expect(kiCadModelAction({ kind: "pcb" })).toBe("export-glb");
  expect(kiCadModelAction({ kind: "model" })).toBe("serve-existing");
  expect(kiCadModelAction({ kind: "image" })).toBe("reject");
});

it("uses the fork-compatible full-fidelity GLB export options", () => {
  const args = kiCadGlbExportArgs("board.kicad_pcb", "/tmp/board.glb");
  for (const option of [
    "--subst-models",
    "--include-tracks",
    "--include-pads",
    "--include-zones",
    "--include-silkscreen",
    "--include-soldermask",
    "--cut-vias-in-body",
  ])
    expect(args).toContain(option);
  expect(args.at(-2)).toBe("/tmp/board.glb");
  expect(args.at(-1)).toBe("board.kicad_pcb");
});

it("revisions only change for a board's project, metadata, and model dependencies", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-model-revision-"));
  const board = NodePath.join(root, "board.kicad_pcb");
  const project = NodePath.join(root, "board.kicad_pro");
  const model = NodePath.join(root, "part.step");
  const unrelated = NodePath.join(root, "unrelated.kicad_sch");
  await NodeFSP.writeFile(board, '(kicad_pcb (model "${KIPRJMOD}/part.step"))');
  await NodeFSP.writeFile(project, "project-a");
  await NodeFSP.writeFile(model, "model-a");
  await NodeFSP.writeFile(unrelated, "schematic-a");
  try {
    const options = { projectFiles: [project] };
    const initial = await resolveKiCadModelRevision(board, options);
    await NodeFSP.writeFile(unrelated, "schematic-bigger");
    expect(await resolveKiCadModelRevision(board, options)).toBe(initial);
    await NodeFSP.writeFile(model, "model-bigger");
    expect(await resolveKiCadModelRevision(board, options)).not.toBe(initial);
    const afterModel = await resolveKiCadModelRevision(board, options);
    await NodeFSP.writeFile(project, "project-bigger");
    expect(await resolveKiCadModelRevision(board, options)).not.toBe(afterModel);
    await NodeFSP.writeFile(`${board}.backplane.json`, '{"layerPreset":"all"}');
    expect(await resolveKiCadModelRevision(board, options)).not.toBe(afterModel);
  } finally {
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});

it("tracks STEP/IGES siblings selected for WRL substitution and project variables", async () => {
  const root = await NodeFSP.mkdtemp(
    NodePath.join(NodeOS.tmpdir(), "backplane-model-substitution-"),
  );
  const board = NodePath.join(root, "board.kicad_pcb");
  const project = NodePath.join(root, "board.kicad_pro");
  const modelDirectory = NodePath.join(root, "models");
  const wrl = NodePath.join(modelDirectory, "part.wrl");
  const step = NodePath.join(modelDirectory, "part.step");
  await NodeFSP.mkdir(modelDirectory);
  await NodeFSP.writeFile(board, '(kicad_pcb (model "${MODEL_DIR}/part.wrl"))');
  await NodeFSP.writeFile(project, '{"text_variables":{"MODEL_DIR":"${KIPRJMOD}/models"}}');
  await NodeFSP.writeFile(wrl, "vrml");
  await NodeFSP.writeFile(step, "step-a");
  try {
    const options = { projectFiles: [project] };
    const initial = await resolveKiCadModelRevision(board, options);
    await NodeFSP.writeFile(step, "step-bigger");
    expect(await resolveKiCadModelRevision(board, options)).not.toBe(initial);
    const afterStep = await resolveKiCadModelRevision(board, options);
    await NodeFSP.writeFile(wrl, "vrml-bigger");
    expect(await resolveKiCadModelRevision(board, options)).not.toBe(afterStep);
  } finally {
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});

it("shares concurrent exports and never writes outputs beside the source", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-model-test-"));
  const board = NodePath.join(root, "board.kicad_pcb");
  await NodeFSP.writeFile(board, "saved board");
  let calls = 0;
  const cache = createKiCadModelCache(async (source, output) => {
    calls += 1;
    expect(source).toBe(board);
    expect(NodePath.dirname(output)).not.toBe(root);
    await NodeFSP.writeFile(output, "glb");
  });
  try {
    const [first, second] = await Promise.all([cache.get(board, "a"), cache.get(board, "a")]);
    expect(first).toBe(second);
    expect(calls).toBe(1);
    expect(await NodeFSP.readFile(board, "utf8")).toBe("saved board");
    expect(await NodeFSP.readdir(root)).toEqual(["board.kicad_pcb"]);
    await cache.get(board, "b");
    expect(calls).toBe(2);
    await cache.dispose();
    await expect(NodeFSP.stat(NodePath.dirname(first))).rejects.toThrow();
  } finally {
    await cache.dispose();
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});

it("cleans failed exports and allows a fresh retry", async () => {
  let directory = "";
  const cache = createKiCadModelCache(async (_source, output) => {
    directory = NodePath.dirname(output);
    throw new Error("CLI failed");
  });
  await expect(cache.get("board.kicad_pcb", "a")).rejects.toThrow("CLI failed");
  await expect(NodeFSP.stat(directory)).rejects.toThrow();
  await expect(cache.get("board.kicad_pcb", "a")).rejects.toThrow("CLI failed");
  await cache.dispose();
});

it("limits concurrent GLB exports while allowing queued boards to drain", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-model-queue-"));
  const board = NodePath.join(root, "board.kicad_pcb");
  await NodeFSP.writeFile(board, "saved board");
  let running = 0;
  let maximum = 0;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  let resolveStarted!: () => void;
  const started = new Promise<void>((resolve) => {
    resolveStarted = resolve;
  });
  const cache = createKiCadModelCache(async (_source, output) => {
    running += 1;
    maximum = Math.max(maximum, running);
    if (running === 2) resolveStarted();
    await gate;
    await NodeFSP.writeFile(output, "glb");
    running -= 1;
  });
  try {
    const exports = Array.from({ length: 6 }, (_, index) => cache.get(board, String(index)));
    await started;
    expect(maximum).toBe(2);
    release();
    await Promise.all(exports);
    expect(maximum).toBe(2);
  } finally {
    release();
    await cache.dispose();
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});
