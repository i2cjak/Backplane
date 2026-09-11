// @effect-diagnostics nodeBuiltinImport:off globalDate:off
import * as NodeChildProcess from "node:child_process";
import * as NodeCrypto from "node:crypto";
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import * as NodeUtil from "node:util";
import type { KiCadPanelizationPreview } from "@backplane/contracts";
import { resolveKiCadEnvironment, resolveKiCadExecutable } from "./KiCadExecutable.ts";

type Run = (command: string, args: string[], cwd: string) => Promise<void>;
const execFile = NodeUtil.promisify(NodeChildProcess.execFile);

const runKiCad: Run = async (command, args, cwd) => {
  try {
    const env = { ...process.env };
    delete env.APPDIR;
    delete env.APPIMAGE;
    const executable = command === "kicad-cli" ? resolveKiCadExecutable(env) : command;
    await execFile(executable, args, {
      cwd,
      env: resolveKiCadEnvironment(env),
      timeout: 120_000,
      windowsHide: true,
    });
  } catch (error) {
    const e = error as NodeJS.ErrnoException & {
      stderr?: string;
      stdout?: string;
      code?: string | number;
    };
    if (e.code === "ENOENT")
      throw new Error(`${command} is not installed or is not on PATH.`, { cause: error });
    const detail = (e.stderr || e.stdout || e.message || "KiKit failed").trim();
    throw new Error(`KiKit panelization failed: ${detail.slice(-2_000)}`, { cause: error });
  }
};

const hash = (value: string | Buffer) =>
  NodeCrypto.createHash("sha256").update(value).digest("hex");

// Plot the profile last so copper and fabrication graphics cannot cover it.
// A separate layer export identifies geometry independently of the user's theme.
export function emphasizeEdgeCuts(svg: string, edgeSvg?: string): string {
  if (!edgeSvg || !svg.includes("</svg>")) return svg;
  const root = edgeSvg.match(/<svg\b[^>]*>/)?.[0];
  if (!root) throw new Error("KiCad returned an invalid outline SVG.");
  if (root.endsWith("/>")) return svg;
  const bodyStart = edgeSvg.indexOf(root) + root.length;
  const bodyEnd = edgeSvg.lastIndexOf("</svg>");
  if (bodyEnd < bodyStart) throw new Error("KiCad returned an invalid outline SVG.");
  const viewBox = (source: string) => source.match(/<svg\b[^>]*\bviewBox="([^"]+)"/)?.[1];
  if (viewBox(svg) !== viewBox(edgeSvg))
    throw new Error("KiCad outline and board preview bounds do not match.");
  const body = edgeSvg.slice(bodyStart, bodyEnd);
  return `${svg.slice(0, svg.lastIndexOf("</svg>"))}
<style>.backplane-panel-outline path, .backplane-panel-outline line, .backplane-panel-outline polyline, .backplane-panel-outline polygon, .backplane-panel-outline circle, .backplane-panel-outline ellipse, .backplane-panel-outline rect { stroke: #161616; stroke-width: 1.25px; vector-effect: non-scaling-stroke; fill: none; }</style>
<g class="backplane-panel-outline">${body}</g>
</svg>`;
}

async function confinedFile(
  root: string,
  requested: string,
  label: string,
): Promise<{ path: string; content: string }> {
  const rootReal = await NodeFSP.realpath(root);
  const candidate = NodePath.resolve(rootReal, requested);
  const relative = NodePath.relative(rootReal, candidate);
  if (relative.startsWith("..") || NodePath.isAbsolute(relative))
    throw new Error(`${label} must be inside the project workspace.`);
  let cursor = rootReal;
  for (const part of relative.split(NodePath.sep)) {
    cursor = NodePath.join(cursor, part);
    try {
      if ((await NodeFSP.lstat(cursor)).isSymbolicLink())
        throw new Error(`${label} cannot be a symbolic link.`);
    } catch (error) {
      if (error instanceof Error && error.message.includes("cannot be a symbolic link"))
        throw error;
      throw new Error(`${label} was not found.`, { cause: error });
    }
  }
  let real: string;
  try {
    real = await NodeFSP.realpath(candidate);
  } catch {
    throw new Error(`${label} was not found.`);
  }
  const realRelative = NodePath.relative(rootReal, real);
  if (realRelative.startsWith("..") || NodePath.isAbsolute(realRelative))
    throw new Error(`${label} must be inside the project workspace.`);
  const stat = await NodeFSP.stat(real);
  if (!stat.isFile()) throw new Error(`${label} must be a file.`);
  return { path: real, content: await NodeFSP.readFile(real, "utf8") };
}

// KiKit intentionally supports Python plugins and script snippets in presets.
// A preview request is allowed the declarative preset sections only.
function validatePreset(value: unknown, path = "preset"): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("Panelization preset must be a JSON object.");
  const walk = (item: unknown, at: string): void => {
    if (Array.isArray(item)) return item.forEach((v, i) => walk(v, `${at}[${i}]`));
    if (!item || typeof item !== "object") return;
    for (const [key, val] of Object.entries(item as Record<string, unknown>)) {
      const lower = key.toLowerCase();
      if (
        ["extends", "include", "import", "file", "filepath", "script", "scriptarg"].includes(lower)
      ) {
        if (val !== "" && val !== "none" && val !== null)
          throw new Error(`Preset ${at}.${key} is not allowed in a preview.`);
      }
      if ((lower === "plugin" || lower === "code") && val !== "none" && val !== "")
        throw new Error(`Preset ${at}.${key} cannot load plugins or scripts.`);
      walk(val, `${at}.${key}`);
    }
  };
  walk(value, path);
  return value as Record<string, unknown>;
}

export interface KiCadPanelizationOptions {
  readonly run?: Run;
  readonly maxCacheEntries?: number;
  readonly maxConcurrent?: number;
}

export function createKiCadPanelizationCache(options: KiCadPanelizationOptions = {}) {
  const run = options.run ?? runKiCad;
  const maxEntries = options.maxCacheEntries ?? 8;
  const maxConcurrent = options.maxConcurrent ?? 2;
  const cache = new Map<string, KiCadPanelizationPreview>();
  const pending = new Map<string, Promise<KiCadPanelizationPreview>>();
  let active = 0;
  const queue: Array<() => void> = [];
  const maxQueued = Math.max(4, maxConcurrent * 4);
  const schedule = <T>(task: () => Promise<T>): Promise<T> =>
    new Promise((resolve, reject) => {
      const start = () => {
        active++;
        task()
          .then(resolve, reject)
          .finally(() => {
            active--;
            queue.shift()?.();
          });
      };
      if (active < maxConcurrent) start();
      else if (queue.length < maxQueued) queue.push(start);
      else
        reject(
          new Error("Too many KiKit previews are already being generated; try again shortly."),
        );
    });
  const get = async (
    root: string,
    boardPath: string,
    presetPath: string,
  ): Promise<KiCadPanelizationPreview> => {
    const board = await confinedFile(root, boardPath, "Board");
    const preset = await confinedFile(root, presetPath, "Preset");
    let json: unknown;
    try {
      json = JSON.parse(preset.content);
    } catch {
      throw new Error("Panelization preset is not valid JSON.");
    }
    const config = validatePreset(json);
    const cuts = config.cuts as { layer?: unknown } | undefined;
    const cutLayer = cuts?.layer;
    if (cutLayer !== undefined && typeof cutLayer !== "string")
      throw new Error("Use a KiCad layer name for cuts.layer in the preview preset.");
    const layers = [
      ...new Set([
        "Edge.Cuts",
        "F.Cu",
        "B.Cu",
        "F.Fab",
        "B.Fab",
        "F.SilkS",
        "B.SilkS",
        "Cmts.User",
        ...(cutLayer ? [cutLayer] : []),
      ]),
    ].join(",");
    const revision = hash(`${hash(board.content)}\0${hash(preset.content)}`);
    const key = `${board.path}\0${preset.path}\0${revision}`;
    const hit = cache.get(key);
    if (hit) return hit;
    const existing = pending.get(key);
    if (existing) return existing;
    const promise = schedule(async () => {
      const started = Date.now();
      const dir = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-kikit-"));
      try {
        const stagedBoard = NodePath.join(dir, "input.kicad_pcb");
        const stagedPreset = NodePath.join(dir, "preset.json");
        const panel = NodePath.join(dir, "panel.kicad_pcb");
        const svg = NodePath.join(dir, "panel.svg");
        const edgeSvg = NodePath.join(dir, "edge-cuts.svg");
        await NodeFSP.writeFile(stagedBoard, board.content);
        await NodeFSP.writeFile(stagedPreset, JSON.stringify(json));
        await run("kikit", ["panelize", "-p", stagedPreset, stagedBoard, panel], dir);
        await run(
          "kicad-cli",
          [
            "pcb",
            "export",
            "svg",
            "--mode-single",
            "--output",
            svg,
            "--layers",
            layers,
            "--sketch-pads-on-fab-layers",
            "--drill-shape-opt",
            "2",
            "--page-size-mode",
            "2",
            "--exclude-drawing-sheet",
            panel,
          ],
          dir,
        );
        await run(
          "kicad-cli",
          [
            "pcb",
            "export",
            "svg",
            "--mode-single",
            "--output",
            edgeSvg,
            "--layers",
            "Edge.Cuts",
            "--black-and-white",
            "--page-size-mode",
            "2",
            "--exclude-drawing-sheet",
            panel,
          ],
          dir,
        );
        const result: KiCadPanelizationPreview = {
          svg: emphasizeEdgeCuts(
            await NodeFSP.readFile(svg, "utf8"),
            await NodeFSP.readFile(edgeSvg, "utf8"),
          ),
          revision,
          presetPath,
          durationMs: Date.now() - started,
        };
        cache.set(key, result);
        while (cache.size > maxEntries) cache.delete(cache.keys().next().value!);
        return result;
      } finally {
        await NodeFSP.rm(dir, { recursive: true, force: true });
      }
    }).finally(() => pending.delete(key));
    pending.set(key, promise);
    return promise;
  };
  return { get, clear: () => cache.clear() };
}

export const kiCadPanelizationCache = createKiCadPanelizationCache();
export function getKiCadPanelization(
  root: string,
  boardPath: string,
  presetPath: string,
): Promise<KiCadPanelizationPreview> {
  return kiCadPanelizationCache.get(root, boardPath, presetPath);
}
