// @effect-diagnostics nodeBuiltinImport:off globalDate:off
import * as NodeChildProcess from "node:child_process";
import * as NodeCrypto from "node:crypto";
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import * as NodeUtil from "node:util";
import { resolveKiCadEnvironment, resolveKiCadExecutable } from "./KiCadExecutable.ts";

import { nameKiCadGlbLayers } from "./KiCadGlb.ts";

const execFile = NodeUtil.promisify(NodeChildProcess.execFile);

// GLB export meshes are CPU-heavy (especially tracks, zones, and soldermask).
// Keep a small amount of parallelism so several viewers do not compete for all
// cores while still allowing independent boards to make progress together.
const MAX_MODEL_EXPORT_PROCESSES = 2;
const MAX_MODEL_EXPORT_QUEUE = 8;
let activeModelExports = 0;
const modelExportQueue: Array<() => void> = [];

function runWithModelExportLimit<T>(task: () => Promise<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    const start = () => {
      activeModelExports += 1;
      void task()
        .then(resolve, reject)
        .finally(() => {
          activeModelExports -= 1;
          modelExportQueue.shift()?.();
        });
    };

    if (activeModelExports < MAX_MODEL_EXPORT_PROCESSES) start();
    else if (modelExportQueue.length >= MAX_MODEL_EXPORT_QUEUE)
      reject(new Error("Too many 3D previews are queued; try again shortly."));
    else modelExportQueue.push(start);
  });
}

export function kiCadGlbExportArgs(board: string, output: string): readonly string[] {
  return [
    "pcb",
    "export",
    "glb",
    "--subst-models",
    "--include-tracks",
    "--include-pads",
    "--include-zones",
    "--include-silkscreen",
    "--include-soldermask",
    "--cut-vias-in-body",
    "--output",
    output,
    board,
  ];
}

const exportModel = async (board: string, output: string) => {
  const env = { ...process.env };
  // Electron AppImage paths must not redirect system KiCad's library lookup.
  delete env.APPDIR;
  delete env.APPIMAGE;
  await execFile(resolveKiCadExecutable(env), kiCadGlbExportArgs(board, output), {
    cwd: NodePath.dirname(board),
    env: resolveKiCadEnvironment(env),
    timeout: 120_000,
    windowsHide: true,
  });
  await NodeFSP.writeFile(output, nameKiCadGlbLayers(await NodeFSP.readFile(output)));
};

export interface KiCadModelRevisionOptions {
  /** Project files which may provide variables or variant settings to KiCad. */
  readonly projectFiles?: readonly string[];
}

const MODEL_SUBSTITUTION_EXTENSIONS = [
  "stp",
  "step",
  "STP",
  "STEP",
  "Stp",
  "Step",
  "stpz",
  "stpZ",
  "STPZ",
  "step.gz",
  "stp.gz",
  "iges",
  "IGES",
  "igs",
  "IGS",
] as const;

function referencedModelPaths(
  board: string,
  content: string,
  variables: NodeJS.ProcessEnv,
): string[] {
  const boardDirectory = NodePath.dirname(board);
  const paths = new Set<string>();
  const modelPattern = /\(\s*model\s+"((?:\\.|[^"])*)"/g;
  for (const match of content.matchAll(modelPattern)) {
    const raw = match[1];
    if (!raw) continue;
    const unescaped = raw.replaceAll('\\"', '"').replaceAll("\\\\", "\\");
    let expanded = unescaped;
    for (let pass = 0; pass < 8 && expanded.includes("${"); pass++) {
      const next = expanded.replace(/\$\{([^}]+)\}/g, (whole, name: string) => {
        if (name === "KIPRJMOD") return boardDirectory;
        return variables[name] ?? whole;
      });
      if (next === expanded) break;
      expanded = next;
    }
    if (expanded.includes("${")) continue;
    const resolved = NodePath.resolve(
      NodePath.isAbsolute(expanded) ? expanded : NodePath.join(boardDirectory, expanded),
    );
    paths.add(resolved);
    if (/\.(?:wrl|wrz)$/i.test(resolved)) {
      const base = resolved.replace(/\.(?:wrl|wrz)$/i, "");
      for (const extension of MODEL_SUBSTITUTION_EXTENSIONS) paths.add(`${base}.${extension}`);
    }
  }
  return [...paths].sort();
}

async function readProjectTextVariables(
  projectFiles: readonly string[],
): Promise<Record<string, string>> {
  const variables: Record<string, string> = {};
  for (const path of projectFiles) {
    try {
      const parsed = JSON.parse(await NodeFSP.readFile(path, "utf8")) as {
        text_variables?: Record<string, unknown>;
      };
      for (const [name, value] of Object.entries(parsed.text_variables ?? {}))
        if (typeof value === "string") variables[name] = value;
    } catch {
      // A project file can be mid-save or use an older format; its stat still
      // remains in the revision so a later successful save retries the export.
    }
  }
  return variables;
}

/**
 * Build a revision from files which can affect a board's GLB output.
 *
 * The project manifest revision intentionally covers every KiCad artifact,
 * but using it for 3D previews caused a Gerber or schematic save to rerun the
 * expensive exporter. Read the board once to discover model references, then
 * key on the board, its per-board metadata, associated project files, and the
 * referenced model stats.
 */
export async function resolveKiCadModelRevision(
  board: string,
  options: KiCadModelRevisionOptions = {},
): Promise<string> {
  const projectFiles = resolveAssociatedProjectFiles(board, options.projectFiles ?? []);
  const projectVariables = await readProjectTextVariables(projectFiles);
  const variables = { ...resolveKiCadEnvironment({ ...process.env }), ...projectVariables };
  const boardContent = await NodeFSP.readFile(board, "utf8");
  const candidates = new Set<string>([
    board,
    `${board}.backplane.json`,
    ...projectFiles,
    ...referencedModelPaths(board, boardContent, variables),
  ]);
  const fingerprints = await Promise.all(
    [...candidates].sort().map(async (path) => {
      try {
        const stat = await NodeFSP.stat(path);
        return `${path}\0${stat.size}\0${stat.mtimeMs}`;
      } catch {
        return `${path}\0missing`;
      }
    }),
  );
  return NodeCrypto.createHash("sha256").update(fingerprints.join("\n")).digest("hex").slice(0, 16);
}

function resolveAssociatedProjectFiles(board: string, projectFiles: readonly string[]): string[] {
  const boardDirectory = NodePath.dirname(board);
  const boardStem = NodePath.basename(board).replace(/\.kicad_pcb$/i, "");
  const sameDirectory = projectFiles.filter((path) => NodePath.dirname(path) === boardDirectory);
  const matchingStem = sameDirectory.filter(
    (path) => NodePath.basename(path).replace(/\.kicad_pro$/i, "") === boardStem,
  );
  if (matchingStem.length > 0) return matchingStem;
  if (sameDirectory.length === 1) return sameDirectory;
  return projectFiles.filter((path) => NodePath.basename(path) === `${boardStem}.kicad_pro`);
}

/** Shares in-flight exports across viewers and retains only a small temporary preview cache. */
export function createKiCadModelCache(runExport = exportModel) {
  const entries = new Map<
    string,
    { result: Promise<string>; directory: string | undefined; expiresAt: number; settled: boolean }
  >();
  const remove = async (key: string) => {
    const entry = entries.get(key);
    entries.delete(key);
    if (entry?.directory) await NodeFSP.rm(entry.directory, { recursive: true, force: true });
  };
  return {
    get(board: string, revision: string): Promise<string> {
      const key = `${board}\0${revision}`;
      const existing = entries.get(key);
      if (existing && (!existing.settled || existing.expiresAt > Date.now()))
        return existing.result;
      const entry = {
        result: Promise.resolve(""),
        directory: undefined as string | undefined,
        expiresAt: Date.now() + 600_000,
        settled: false,
      };
      const result = (async () => {
        if (existing) await remove(key);
        for (const [oldKey, old] of entries) {
          if (old.settled && (old.expiresAt <= Date.now() || entries.size >= 8))
            await remove(oldKey);
        }
        if (entries.size >= 8)
          throw new Error("3D preview is busy. Try again after another export finishes.");
        entry.directory = await NodeFSP.mkdtemp(
          NodePath.join(NodeOS.tmpdir(), "backplane-kicad-glb-"),
        );
        const output = NodePath.join(entry.directory, "board.glb");
        try {
          await runWithModelExportLimit(() => runExport(board, output));
          entry.settled = true;
          return output;
        } catch (cause) {
          await NodeFSP.rm(entry.directory, { recursive: true, force: true });
          throw cause;
        }
      })();
      entry.result = result.catch((cause) => {
        if (entries.get(key) === entry) entries.delete(key);
        throw cause;
      });
      entries.set(key, entry);
      return entry.result;
    },
    async dispose() {
      await Promise.allSettled([...entries.values()].map((entry) => entry.result));
      await Promise.all([...entries.keys()].map(remove));
    },
  };
}

export const kiCadModelCache = createKiCadModelCache();
