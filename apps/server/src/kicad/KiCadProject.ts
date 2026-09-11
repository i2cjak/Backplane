/* eslint-disable backplane/namespace-node-imports */
// @effect-diagnostics nodeBuiltinImport:off globalDate:off
import * as NodeCrypto from "node:crypto";
import * as NodeFSP from "node:fs/promises";
import type { Dirent } from "node:fs";
import * as NodePath from "node:path";

export type KiCadFileKind =
  | "gerber"
  | "pcb"
  | "schematic"
  | "model"
  | "project"
  | "footprint"
  | "symbol"
  | "image";

export interface KiCadProjectFile {
  readonly path: string;
  readonly kind: KiCadFileKind;
  readonly mimeType: string;
  readonly size: number;
  readonly mtimeMs: number;
}

export interface KiCadProjectManifest {
  readonly root: string;
  readonly revision: string;
  readonly files: readonly KiCadProjectFile[];
  readonly config?: KiCadProjectConfig;
  readonly warnings: readonly string[];
}
export interface KiCadEnclosureConfig {
  readonly solids?: Readonly<Record<string, string>>;
}
export interface KiCadProductConfig {
  readonly still?: string;
  readonly renders?: Readonly<Record<string, string>>;
  readonly solids?: Readonly<Record<string, string>>;
}
export interface KiCadProjectConfig {
  readonly analysisUrl?: string;
  readonly pcb?: string;
  readonly schematic?: string;
  readonly gerbers?: readonly string[];
  readonly symbol?: string;
  readonly symbolMember?: string;
  readonly footprint?: string;
  readonly enclosure?: KiCadEnclosureConfig;
  readonly product?: KiCadProductConfig;
}

const manifestCache = new Map<
  string,
  { readonly expiresAt: number; readonly manifest: KiCadProjectManifest }
>();

const MIME_TYPES: Record<string, string> = {
  ".gbr": "application/octet-stream",
  ".ger": "application/octet-stream",
  ".drl": "application/octet-stream",
  ".xln": "application/octet-stream",
  ".kicad_mod": "application/x-kicad-footprint",
  ".kicad_sym": "application/x-kicad-symbol",
  ".kicad_pcb": "application/x-kicad-pcb",
  ".kicad_sch": "application/x-kicad-schematic",
  ".step": "model/step",
  ".stp": "model/step",
  ".wrl": "model/vrml",
  ".glb": "model/gltf-binary",
  ".gltf": "model/gltf+json",
  ".obj": "text/plain",
  ".stl": "model/stl",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".kicad_pro": "application/json",
  ".kicad_wks": "application/x-kicad-workbook",
};
const GERBER_EXTENSIONS = new Set([
  ".gbr",
  ".ger",
  ".gtl",
  ".gbl",
  ".gts",
  ".gbs",
  ".gta",
  ".gba",
  ".gto",
  ".gbo",
  ".gtp",
  ".gbp",
  ".gm1",
  ".gm2",
  ".gm3",
  ".gm13",
  ".gko",
  ".g1",
  ".g2",
  ".g3",
  ".g4",
  ".gbrjob",
  ".drl",
  ".xln",
]);
const MODEL_EXTENSIONS = new Set([".step", ".stp", ".wrl", ".glb", ".gltf", ".obj", ".stl"]);
const IGNORED_DIRECTORIES = new Set([".git", ".history", "node_modules"]);

function fileKind(extension: string): KiCadFileKind | undefined {
  if (extension === ".kicad_mod") return "footprint";
  if (extension === ".kicad_sym") return "symbol";
  if (extension === ".kicad_pcb") return "pcb";
  if (extension === ".kicad_sch") return "schematic";
  if (extension === ".kicad_pro" || extension === ".kicad_wks") return "project";
  if (GERBER_EXTENSIONS.has(extension) || /^\.g\d+$/.test(extension)) return "gerber";
  if (MODEL_EXTENSIONS.has(extension)) return "model";
  return undefined;
}

function configuredKind(extension: string): KiCadFileKind | undefined {
  const walked = fileKind(extension);
  if (walked) return walked;
  if (
    extension === ".png" ||
    extension === ".jpg" ||
    extension === ".jpeg" ||
    extension === ".webp"
  )
    return "image";
  return undefined;
}

function asStringRecord(value: unknown): Record<string, string> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const entries = Object.entries(value).filter(
    (entry): entry is [string, string] => typeof entry[1] === "string" && entry[1].length > 0,
  );
  return entries.length ? Object.fromEntries(entries) : undefined;
}

function parseEnclosure(value: unknown): KiCadEnclosureConfig | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const solids = asStringRecord((value as Record<string, unknown>).solids);
  return solids ? { solids } : undefined;
}

function parseProduct(value: unknown): KiCadProductConfig | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const record = value as Record<string, unknown>;
  const still =
    typeof record.still === "string" && record.still.length > 0 ? record.still : undefined;
  const renders = asStringRecord(record.renders);
  const solids = asStringRecord(record.solids);
  if (!still && !renders && !solids) return undefined;
  return {
    ...(still ? { still } : {}),
    ...(renders ? { renders } : {}),
    ...(solids ? { solids } : {}),
  };
}

export function workspaceRelativeInspectPath(root: string, value: string): string | undefined {
  const normalized = value.replaceAll("\\", "/");
  const rootNorm = NodePath.resolve(root).replaceAll("\\", "/").replace(/\/$/, "");
  if (normalized.startsWith(`${rootNorm}/`)) return normalized.slice(rootNorm.length + 1);
  if (normalized.startsWith("/")) return undefined;
  return normalized.replace(/^\.\//, "");
}

function inspectImageOrModel(path: string): "image" | "model" | undefined {
  const extension = NodePath.extname(path).toLowerCase();
  if (configuredKind(extension) === "image") return "image";
  if (MODEL_EXTENSIONS.has(extension)) return "model";
  return undefined;
}

/** Named stills from a sidecar JSON (`outputs` plus `product`). */
export function loadVizRenderPaths(root: string, payload: unknown): Record<string, string> {
  if (!payload || typeof payload !== "object") return {};
  const record = payload as Record<string, unknown>;
  const renders: Record<string, string> = {};
  if (typeof record.product === "string") {
    const relative = workspaceRelativeInspectPath(root, record.product);
    if (relative && inspectImageOrModel(relative) === "image") renders.product = relative;
  }
  if (record.outputs && typeof record.outputs === "object" && !Array.isArray(record.outputs)) {
    for (const [name, value] of Object.entries(record.outputs)) {
      if (typeof value !== "string") continue;
      const relative = workspaceRelativeInspectPath(root, value);
      if (relative && inspectImageOrModel(relative) === "image") renders[name] = relative;
    }
  }
  return renders;
}

/** GLB/STEP from a Blender scene sidecar (`pcb_source`). */
export function sceneSolidPath(root: string, payload: unknown): string | undefined {
  if (!payload || typeof payload !== "object") return undefined;
  const source = (payload as Record<string, unknown>).pcb_source;
  if (typeof source !== "string") return undefined;
  const relative = workspaceRelativeInspectPath(root, source);
  return relative && inspectImageOrModel(relative) === "model" ? relative : undefined;
}

/** Prefer a mechanical STEP/GLB over a board GLB so Blender 3D is not PCB-only. */
export function enclosureProductSolid(
  solids: Readonly<Record<string, string>> | undefined,
): { readonly name: string; readonly path: string } | undefined {
  if (!solids) return undefined;
  const entries = Object.entries(solids);
  const named =
    entries.find(([name, path]) => name === "ENCLOSURE" && inspectImageOrModel(path) === "model") ??
    entries.find(([, path]) => /\.(?:step|stp)$/i.test(path)) ??
    entries.find(([name, path]) => name !== "PCB" && inspectImageOrModel(path) === "model");
  return named ? { name: named[0], path: named[1] } : undefined;
}

export function configuredArtifactPaths(config: KiCadProjectConfig | undefined): string[] {
  if (!config) return [];
  const paths = [
    ...(config.enclosure?.solids ? Object.values(config.enclosure.solids) : []),
    ...(config.product?.solids ? Object.values(config.product.solids) : []),
    config.product?.still,
    ...(config.product?.renders ? Object.values(config.product.renders) : []),
  ].filter((path): path is string => typeof path === "string" && path.length > 0);
  return [...new Set(paths.map((path) => path.replaceAll("\\", "/")))];
}

/** Walks the project without consulting ignore files: generated fabrication output is often ignored. */
export async function discoverKiCadProject(root: string): Promise<KiCadProjectManifest> {
  const projectRoot = NodePath.resolve(root);
  const cached = manifestCache.get(projectRoot);
  if (cached && cached.expiresAt > Date.now()) return cached.manifest;
  const files: KiCadProjectFile[] = [];
  const metadataRevisions: string[] = [];
  let visited = 0;
  let scanLimitWarningAdded = false;
  let config: KiCadProjectConfig | undefined;
  const warnings: string[] = [];
  try {
    const parsed = JSON.parse(
      await NodeFSP.readFile(NodePath.join(projectRoot, ".backplane.json"), "utf8"),
    ) as Record<string, unknown>;
    const enclosure = parseEnclosure(parsed.enclosure);
    let product = parseProduct(parsed.product);
    const productRecord =
      parsed.product && typeof parsed.product === "object" && !Array.isArray(parsed.product)
        ? (parsed.product as Record<string, unknown>)
        : undefined;
    if (productRecord) {
      const renders = { ...(product?.renders ?? {}) };
      const solids = { ...(product?.solids ?? {}) };
      const loadViz = typeof productRecord.loadViz === "string" ? productRecord.loadViz : undefined;
      const scene = typeof productRecord.scene === "string" ? productRecord.scene : undefined;
      if (loadViz) {
        try {
          Object.assign(
            renders,
            loadVizRenderPaths(
              projectRoot,
              JSON.parse(await NodeFSP.readFile(NodePath.join(projectRoot, loadViz), "utf8")),
            ),
          );
        } catch {
          warnings.push(`Unable to read product stills: ${loadViz}`);
        }
      }
      if (scene) {
        try {
          const solid = sceneSolidPath(
            projectRoot,
            JSON.parse(await NodeFSP.readFile(NodePath.join(projectRoot, scene), "utf8")),
          );
          if (solid && !solids.PCB) solids.PCB = solid;
        } catch {
          warnings.push(`Unable to read product scene: ${scene}`);
        }
      }
      const enclosureSolid = enclosureProductSolid(enclosure?.solids);
      if (enclosureSolid && !Object.values(solids).includes(enclosureSolid.path)) {
        solids[enclosureSolid.name] = enclosureSolid.path;
      }
      product = parseProduct({
        still: product?.still,
        renders: Object.keys(renders).length ? renders : undefined,
        solids: Object.keys(solids).length ? solids : undefined,
      });
    }
    config = {
      ...(typeof parsed.analysisUrl === "string" ? { analysisUrl: parsed.analysisUrl } : {}),
      ...(typeof parsed.pcb === "string" ? { pcb: parsed.pcb } : {}),
      ...(typeof parsed.schematic === "string" ? { schematic: parsed.schematic } : {}),
      ...(Array.isArray(parsed.gerbers)
        ? { gerbers: parsed.gerbers.filter((value): value is string => typeof value === "string") }
        : {}),
      ...(typeof parsed.symbol === "string" ? { symbol: parsed.symbol } : {}),
      ...(typeof parsed.symbolMember === "string" ? { symbolMember: parsed.symbolMember } : {}),
      ...(typeof parsed.footprint === "string" ? { footprint: parsed.footprint } : {}),
      ...(enclosure ? { enclosure } : {}),
      ...(product ? { product } : {}),
    };
  } catch {
    try {
      if ((await NodeFSP.stat(NodePath.join(projectRoot, ".backplane.json"))).isFile())
        warnings.push("Unable to parse .backplane.json");
    } catch {
      /* configuration is optional */
    }
  }
  const walk = async (directory: string): Promise<void> => {
    if (++visited > 50_000) {
      if (!scanLimitWarningAdded) {
        warnings.push("KiCad project scan limit reached");
        scanLimitWarningAdded = true;
      }
      return;
    }
    let entries: Dirent<string>[];
    try {
      entries = await NodeFSP.readdir(directory, { withFileTypes: true, encoding: "utf8" });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!IGNORED_DIRECTORIES.has(entry.name) && entry.name !== ".venv")
          await walk(NodePath.join(directory, entry.name));
        continue;
      }
      const extension = entry.name.slice(entry.name.lastIndexOf(".")).toLowerCase();
      const kind = fileKind(extension);
      const metadata = /\.kicad_(?:pcb|sch|mod|sym)\.backplane\.json$/i.test(entry.name);
      if (!kind && !metadata) continue;
      const absolute = NodePath.join(directory, entry.name);
      try {
        const info = await NodeFSP.lstat(absolute);
        if (info.isSymbolicLink()) continue;
        if (!info.isFile()) continue;
        if (metadata) {
          metadataRevisions.push(
            `${NodePath.relative(projectRoot, absolute)}\0${info.size}\0${info.mtimeMs}`,
          );
          continue;
        }
        if (!kind) continue;
        files.push({
          path: NodePath.relative(projectRoot, absolute).split(NodePath.sep).join("/"),
          kind,
          mimeType: MIME_TYPES[extension] ?? "application/octet-stream",
          size: info.size,
          mtimeMs: info.mtimeMs,
        });
      } catch {
        /* files can disappear while an agent is writing them */
      }
    }
  };
  await walk(projectRoot);
  const includeInspectFile = async (relative: string): Promise<void> => {
    if (files.some((file) => file.path === relative)) return;
    const absolute = NodePath.join(projectRoot, relative);
    const extension = NodePath.extname(relative).toLowerCase();
    const kind = configuredKind(extension);
    if (!kind) {
      warnings.push(`Configured inspect file is not a supported artifact: ${relative}`);
      return;
    }
    try {
      const info = await NodeFSP.lstat(absolute);
      if (info.isSymbolicLink() || !info.isFile()) {
        warnings.push(`Configured inspect file not found: ${relative}`);
        return;
      }
      files.push({
        path: relative,
        kind,
        mimeType: MIME_TYPES[extension] ?? "application/octet-stream",
        size: info.size,
        mtimeMs: info.mtimeMs,
      });
    } catch {
      warnings.push(`Configured inspect file not found: ${relative}`);
    }
  };
  for (const relative of configuredArtifactPaths(config)) await includeInspectFile(relative);
  files.sort((a, b) => a.path.localeCompare(b.path));
  if (config?.pcb && !files.some((file) => file.path === config!.pcb))
    warnings.push(`Configured PCB file not found: ${config.pcb}`);
  if (config?.schematic && !files.some((file) => file.path === config!.schematic))
    warnings.push(`Configured schematic file not found: ${config.schematic}`);
  if (
    config?.symbol &&
    !files.some((file) => file.path === config!.symbol && file.kind === "symbol")
  )
    warnings.push(`Configured symbol library not found: ${config.symbol}`);
  if (
    config?.footprint &&
    !files.some((file) => file.path === config!.footprint && file.kind === "footprint")
  )
    warnings.push(`Configured footprint file not found: ${config.footprint}`);
  for (const directory of config?.gerbers ?? [])
    if (
      !files.some(
        (file) =>
          file.kind === "gerber" &&
          (file.path === directory || file.path.startsWith(`${directory.replaceAll("\\", "/")}/`)),
      )
    )
      warnings.push(`Configured Gerber directory not found: ${directory}`);
  const configFingerprint = config ? JSON.stringify(config) : "";
  const revision = NodeCrypto.createHash("sha256")
    .update(
      `${configFingerprint}\n${JSON.stringify(warnings)}\n${files.map((file) => `${file.path}\0${file.size}\0${file.mtimeMs}`).join("\n")}`,
    )
    .update(metadataRevisions.sort().join("\n"))
    .digest("hex")
    .slice(0, 16);
  const manifest = { root: projectRoot, revision, files, ...(config ? { config } : {}), warnings };
  manifestCache.set(projectRoot, { manifest, expiresAt: Date.now() + 300 });
  return manifest;
}

export async function resolveKiCadProjectFile(
  root: string,
  requestedPath: string,
): Promise<{ absolutePath: string; file: KiCadProjectFile } | undefined> {
  const manifest = await discoverKiCadProject(root);
  const normalized = requestedPath.replaceAll("\\", "/");
  const file = manifest.files.find((candidate) => candidate.path === normalized);
  if (!file) return undefined;
  const absolutePath = NodePath.resolve(manifest.root, file.path);
  try {
    const [canonicalRoot, canonicalPath] = await Promise.all([
      NodeFSP.realpath(manifest.root),
      NodeFSP.realpath(absolutePath),
    ]);
    const rootPrefix = canonicalRoot.endsWith(NodePath.sep)
      ? canonicalRoot
      : `${canonicalRoot}${NodePath.sep}`;
    if (!canonicalPath.startsWith(rootPrefix) || !(await NodeFSP.lstat(canonicalPath)).isFile())
      return undefined;
    return { absolutePath: canonicalPath, file };
  } catch {
    return undefined;
  }
}
