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
  | "image"
  | "json";

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
  readonly params?: string;
  readonly solids?: Readonly<Record<string, string>>;
}
export interface KiCadProductConfig {
  readonly scene?: string;
  readonly still?: string;
  readonly loadViz?: string;
}
/** Open map of MCP servers the agent uses to mutate CAD. Inspect never launches them. Extra domain keys are allowed. */
export interface KiCadDriverConfig {
  readonly mcp: string;
  readonly reference?: string;
  readonly mutations?: readonly string[];
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
  readonly drivers?: Readonly<Record<string, KiCadDriverConfig>>;
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
  ".json": "application/json",
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
  if (extension === ".json") return "json";
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
  const record = value as Record<string, unknown>;
  const params = typeof record.params === "string" ? record.params : undefined;
  const solids = asStringRecord(record.solids);
  if (!params && !solids) return undefined;
  return { ...(params ? { params } : {}), ...(solids ? { solids } : {}) };
}

function parseProduct(value: unknown): KiCadProductConfig | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const record = value as Record<string, unknown>;
  const scene = typeof record.scene === "string" ? record.scene : undefined;
  const still = typeof record.still === "string" ? record.still : undefined;
  const loadViz = typeof record.loadViz === "string" ? record.loadViz : undefined;
  if (!scene && !still && !loadViz) return undefined;
  return {
    ...(scene ? { scene } : {}),
    ...(still ? { still } : {}),
    ...(loadViz ? { loadViz } : {}),
  };
}

function parseDriver(value: unknown): KiCadDriverConfig | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const record = value as Record<string, unknown>;
  if (typeof record.mcp !== "string" || record.mcp.length === 0) return undefined;
  const reference =
    typeof record.reference === "string" && record.reference.length > 0
      ? record.reference
      : undefined;
  const mutations = Array.isArray(record.mutations)
    ? record.mutations.filter((item): item is string => typeof item === "string" && item.length > 0)
    : undefined;
  return {
    mcp: record.mcp,
    ...(reference ? { reference } : {}),
    ...(mutations && mutations.length ? { mutations } : {}),
  };
}

export function parseDrivers(
  value: unknown,
): Readonly<Record<string, KiCadDriverConfig>> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const drivers: Record<string, KiCadDriverConfig> = {};
  for (const [key, entry] of Object.entries(value)) {
    const parsed = parseDriver(entry);
    if (parsed) drivers[key] = parsed;
  }
  return Object.keys(drivers).length ? drivers : undefined;
}

export function configuredArtifactPaths(config: KiCadProjectConfig | undefined): string[] {
  if (!config) return [];
  const paths = [
    config.enclosure?.params,
    ...(config.enclosure?.solids ? Object.values(config.enclosure.solids) : []),
    config.product?.scene,
    config.product?.still,
    config.product?.loadViz,
  ].filter((path): path is string => typeof path === "string" && path.length > 0);
  return [...new Set(paths.map((path) => path.replaceAll("\\", "/")))];
}

export function workspaceRelativeInspectPath(root: string, value: string): string | undefined {
  const normalized = value.replaceAll("\\", "/");
  const rootNorm = NodePath.resolve(root).replaceAll("\\", "/").replace(/\/$/, "");
  if (normalized.startsWith(`${rootNorm}/`)) return normalized.slice(rootNorm.length + 1);
  if (normalized.startsWith("/")) return undefined;
  return normalized.replace(/^\.\//, "");
}

export function loadVizInspectImagePaths(root: string, payload: unknown): string[] {
  if (!payload || typeof payload !== "object") return [];
  const record = payload as Record<string, unknown>;
  const values: string[] = [];
  if (typeof record.product === "string") values.push(record.product);
  if (record.outputs && typeof record.outputs === "object" && !Array.isArray(record.outputs)) {
    for (const value of Object.values(record.outputs)) {
      if (typeof value === "string") values.push(value);
    }
  }
  const images: string[] = [];
  for (const value of values) {
    const relative = workspaceRelativeInspectPath(root, value);
    if (!relative) continue;
    if (configuredKind(NodePath.extname(relative).toLowerCase()) !== "image") continue;
    images.push(relative);
  }
  return [...new Set(images)];
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
      ...(parseEnclosure(parsed.enclosure) ? { enclosure: parseEnclosure(parsed.enclosure) } : {}),
      ...(parseProduct(parsed.product) ? { product: parseProduct(parsed.product) } : {}),
      ...(parseDrivers(parsed.drivers) ? { drivers: parseDrivers(parsed.drivers) } : {}),
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
  if (config?.product?.loadViz) {
    try {
      const text = await NodeFSP.readFile(
        NodePath.join(projectRoot, config.product.loadViz),
        "utf8",
      );
      const extra = loadVizInspectImagePaths(projectRoot, JSON.parse(text));
      for (const relative of extra) await includeInspectFile(relative);
    } catch {
      warnings.push(`Unable to read load-viz inspect images: ${config.product.loadViz}`);
    }
  }
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
