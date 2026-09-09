// @effect-diagnostics nodeBuiltinImport:off
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import * as NodeCrypto from "node:crypto";
import { Schema } from "effect";
import { parse as parseYaml } from "yaml";
import type { ServerProviderSkill } from "@backplane/contracts";
import bundle from "./kistack.bundle.json" with { type: "json" };

const repository = "American-Embedded/kistack";
const source = `https://github.com/${repository}`;
const metadataFileName = ".backplane-kistack.json";
const activeFileName = ".backplane-active.json";
const maxFileBytes = 2_000_000;
const maxTotalBytes = 25_000_000;
const SkillSchema = Schema.Struct({
  name: Schema.String,
  description: Schema.String,
  path: Schema.String,
});
const MetadataSchema = Schema.Struct({
  revision: Schema.String,
  skills: Schema.Array(SkillSchema),
  files: Schema.Array(Schema.String),
});
const CommitSchema = Schema.Struct({ sha: Schema.String });
const TreeSchema = Schema.Struct({
  truncated: Schema.optional(Schema.Boolean),
  tree: Schema.Array(
    Schema.Struct({
      path: Schema.String,
      type: Schema.String,
      mode: Schema.String,
      size: Schema.optional(Schema.Number),
    }),
  ),
});
const FrontmatterSchema = Schema.Struct({ name: Schema.String, description: Schema.String });
const decodeMetadata = Schema.decodeUnknownSync(MetadataSchema);
const decodeCommit = Schema.decodeUnknownSync(CommitSchema);
const decodeTree = Schema.decodeUnknownSync(TreeSchema);
const decodeFrontmatter = Schema.decodeUnknownSync(FrontmatterSchema);
type Metadata = typeof MetadataSchema.Type;
const bundledMetadata: Metadata = {
  revision: bundle.revision,
  skills: bundle.skills,
  files: Object.keys(bundle.files),
};
const bundledSkillNames = new Set(bundledMetadata.skills.map((skill) => skill.name));
const legacyBundledRevisions = new Set(["97934211326a03c0541b784c616c6582cdc14107"]);
const isRevision = (value: string) => /^[0-9a-f]{40}$/.test(value);
function safePath(path: string): boolean {
  return (
    !/[\\:]/.test(path) &&
    !Array.from(path).some((character) => character.charCodeAt(0) < 32) &&
    !path.split("/").some((part) => !part || part === "." || part === "..")
  );
}

function includesBundledCatalog(metadata: Metadata): boolean {
  const skillNames = new Set(metadata.skills.map((skill) => skill.name));
  return [...bundledSkillNames].every((name) => skillNames.has(name));
}

async function installBundledFiles(directory: string): Promise<void> {
  for (const [relative, contents] of Object.entries(bundle.files)) {
    const path = NodePath.join(directory, relative);
    await NodeFSP.mkdir(NodePath.dirname(path), { recursive: true });
    const existing = await NodeFSP.readFile(path, "utf8").catch((cause: unknown) => {
      if (cause && typeof cause === "object" && "code" in cause && cause.code === "ENOENT")
        return undefined;
      throw cause;
    });
    if (existing !== contents) await NodeFSP.writeFile(path, contents);
  }
}

function instructions(metadata: Metadata, directory: string): string {
  return [
    "<kistack_skills>",
    `Backplane includes KiStack by American Embedded (${source}, revision ${metadata.revision}). These skills are always available in every project.`,
    "For relevant electronics work, read the matching SKILL.md before working and follow its workflow. Resolve referenced scripts and documents relative to that skill's directory. User instructions take precedence. Other installed skills remain available.",
    ...metadata.skills.map(
      (skill) =>
        `- ${skill.name}: ${skill.description} Read ${JSON.stringify(NodePath.join(directory, skill.path))}`,
    ),
    "</kistack_skills>",
  ].join("\n");
}

/** One cache per server, with injectable I/O for offline verification. */
export function createKiStackSkills(options: {
  cacheDirectory: string;
  fetchImpl?: (url: string, init?: RequestInit) => Promise<Response>;
  timeoutMs?: number;
  now?: () => number;
}) {
  const root = options.cacheDirectory;
  const fetchImpl = options.fetchImpl ?? fetch;
  const now = options.now ?? Date.now;
  let active: Metadata = bundledMetadata;
  let installation: Promise<void> | undefined;
  let inFlight: Promise<boolean> | undefined;
  let etag: string | undefined;
  let retryAt = 0;
  const directory = () => NodePath.join(root, active.revision);

  async function loadSnapshot(revision: string): Promise<Metadata | undefined> {
    if (!isRevision(revision)) return undefined;
    try {
      const base = NodePath.join(root, revision);
      const metadata = decodeMetadata(
        JSON.parse(await NodeFSP.readFile(NodePath.join(base, metadataFileName), "utf8")),
      );
      if (
        metadata.revision !== revision ||
        !metadata.skills.length ||
        !metadata.files.includes("LICENSE") ||
        metadata.files.some((path) => !safePath(path)) ||
        metadata.skills.some(
          (skill) =>
            !metadata.files.includes(skill.path) || !/^skills\/[^/]+\/SKILL\.md$/.test(skill.path),
        )
      )
        return undefined;
      for (const file of metadata.files) {
        if (!(await NodeFSP.lstat(NodePath.join(base, file))).isFile()) return undefined;
      }
      return metadata;
    } catch {
      return undefined;
    }
  }

  async function activate(metadata: Metadata): Promise<void> {
    const temporary = NodePath.join(root, `.active-${NodeCrypto.randomUUID()}`);
    try {
      await NodeFSP.writeFile(temporary, JSON.stringify({ sha: metadata.revision }));
      await NodeFSP.rename(temporary, NodePath.join(root, activeFileName));
      active = metadata;
    } finally {
      await NodeFSP.rm(temporary, { force: true });
    }
  }

  async function initialize(): Promise<void> {
    await NodeFSP.mkdir(root, { recursive: true });
    try {
      const pointer = decodeCommit(
        JSON.parse(await NodeFSP.readFile(NodePath.join(root, activeFileName), "utf8")),
      );
      const cached = await loadSnapshot(pointer.sha);
      if (
        cached &&
        (!legacyBundledRevisions.has(cached.revision) || includesBundledCatalog(cached))
      ) {
        active = cached;
        return;
      }
    } catch {
      /* First start or incomplete cache: the bundled copy is always available. */
    }
    await installBundledFiles(NodePath.join(root, bundle.revision));
    await NodeFSP.writeFile(
      NodePath.join(root, bundle.revision, metadataFileName),
      JSON.stringify(bundledMetadata),
    );
    await activate(bundledMetadata);
  }
  const install = () =>
    (installation ??= initialize().catch((error: unknown) => {
      installation = undefined;
      throw error;
    }));

  async function refreshOnce(): Promise<boolean> {
    await install();
    if (now() < retryAt) return false;
    // One deadline covers response bodies and the whole snapshot, not just headers.
    const signal = AbortSignal.timeout(options.timeoutMs ?? 30_000);
    async function request(url: string, headers?: Record<string, string>) {
      const response = await fetchImpl(url, {
        signal,
        headers: { "user-agent": "Backplane", ...headers },
      });
      if (response.status === 403 || response.status === 429) {
        const seconds = Number(response.headers.get("retry-after"));
        const reset = Number(response.headers.get("x-ratelimit-reset")) * 1000;
        retryAt = seconds > 0 ? now() + seconds * 1000 : reset > now() ? reset : now() + 60_000;
      }
      if (!response.ok && response.status !== 304)
        throw new Error(`KiStack download failed (${response.status})`);
      return response;
    }
    async function read(response: Response): Promise<Buffer> {
      const reader = response.body?.getReader();
      if (!reader) throw new Error("KiStack response has no body");
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > maxFileBytes) throw new Error("KiStack file is too large");
          chunks.push(value);
        }
        return Buffer.concat(chunks);
      } finally {
        await reader.cancel();
      }
    }
    const response = await request(
      `https://api.github.com/repos/${repository}/commits/HEAD`,
      etag ? { "if-none-match": etag } : undefined,
    );
    if (response.status === 304) return false;
    const revision = decodeCommit(JSON.parse((await read(response)).toString("utf8"))).sha;
    if (!isRevision(revision)) throw new Error("Invalid KiStack revision");
    const nextEtag = response.headers.get("etag") ?? undefined;
    if (revision === active.revision) {
      etag = nextEtag;
      return false;
    }
    const cached = await loadSnapshot(revision);
    if (cached) {
      await activate(cached);
      etag = nextEtag;
      return true;
    }
    const tree = decodeTree(
      JSON.parse(
        (
          await read(
            await request(
              `https://api.github.com/repos/${repository}/git/trees/${revision}?recursive=1`,
            ),
          )
        ).toString("utf8"),
      ),
    );
    if (tree.truncated) throw new Error("KiStack tree is incomplete");
    const entries = tree.tree.filter(
      (entry) =>
        entry.path === "LICENSE" || (entry.path.startsWith("skills/") && entry.type !== "tree"),
    );
    if (
      entries.length > 1000 ||
      !entries.some((entry) => entry.path === "LICENSE") ||
      entries.some(
        (entry) =>
          !safePath(entry.path) ||
          entry.type !== "blob" ||
          !["100644", "100755"].includes(entry.mode) ||
          (entry.size ?? 0) > maxFileBytes,
      )
    )
      throw new Error("Invalid KiStack file tree");
    const temporary = await NodeFSP.mkdtemp(NodePath.join(root, ".download-"));
    try {
      const skills: Array<typeof SkillSchema.Type> = [];
      let total = 0;
      // A few concurrent CDN downloads avoid a request per file in series.
      let next = 0;
      const workers = await Promise.allSettled(
        Array.from({ length: 4 }, async () => {
          while (next < entries.length) {
            const entry = entries[next++]!;
            const urlPath = entry.path.split("/").map(encodeURIComponent).join("/");
            const bytes = await read(
              await request(
                `https://raw.githubusercontent.com/${repository}/${revision}/${urlPath}`,
              ),
            );
            total += bytes.length;
            if (total > maxTotalBytes) throw new Error("KiStack snapshot is too large");
            if (/^skills\/[^/]+\/SKILL\.md$/.test(entry.path)) {
              const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(
                bytes.toString("utf8"),
              );
              if (!frontmatter) throw new Error("KiStack skill is missing frontmatter");
              const skill = decodeFrontmatter(parseYaml(frontmatter[1]!));
              if (!skill.name.trim() || !skill.description.trim())
                throw new Error("Invalid KiStack skill metadata");
              skills.push({
                name: skill.name.trim(),
                description: skill.description.replaceAll(/\s+/g, " ").trim(),
                path: entry.path,
              });
            }
            const path = NodePath.join(temporary, entry.path);
            await NodeFSP.mkdir(NodePath.dirname(path), { recursive: true });
            await NodeFSP.writeFile(path, bytes, { mode: entry.mode === "100755" ? 0o755 : 0o644 });
          }
        }),
      );
      for (const worker of workers) if (worker.status === "rejected") throw worker.reason;
      if (!skills.length || new Set(skills.map((skill) => skill.name)).size !== skills.length)
        throw new Error("KiStack snapshot has no skills or duplicate names");
      const metadata: Metadata = {
        revision,
        skills: skills.sort((a, b) => a.path.localeCompare(b.path)),
        files: entries.map((entry) => entry.path),
      };
      await NodeFSP.writeFile(NodePath.join(temporary, metadataFileName), JSON.stringify(metadata));
      try {
        await NodeFSP.rename(temporary, NodePath.join(root, revision));
      } catch (error) {
        if (!(await loadSnapshot(revision))) throw error;
      }
      await activate(metadata);
      // Cache the ETag only after activation; failed downloads must retry the same commit.
      etag = nextEtag;
      return true;
    } finally {
      await NodeFSP.rm(temporary, { recursive: true, force: true });
    }
  }
  return {
    install,
    refresh(): Promise<boolean> {
      return (inFlight ??= refreshOnce().finally(() => {
        inFlight = undefined;
      }));
    },
    get revision() {
      return active.revision;
    },
    get directory() {
      return directory();
    },
    get skills() {
      return active.skills;
    },
    buildInstructions: () => instructions(active, directory()),
  };
}

export const kiStackCacheDirectory = NodePath.join(
  NodeOS.homedir(),
  ".cache",
  "backplane",
  "kistack",
);
const defaultSkills = createKiStackSkills({ cacheDirectory: kiStackCacheDirectory });
export let kiStackSkillsDirectory = defaultSkills.directory;
export const getKiStackRevision = () => defaultSkills.revision;

export async function installKiStackSkills(directory?: string): Promise<void> {
  if (directory !== undefined) return installBundledFiles(directory);
  await defaultSkills.install();
  kiStackSkillsDirectory = defaultSkills.directory;
}
export async function refreshKiStackSkills(): Promise<void> {
  await defaultSkills.refresh();
  kiStackSkillsDirectory = defaultSkills.directory;
}

function providerSkills(
  skills: ReadonlyArray<Metadata["skills"][number]>,
  directory: string,
): ReadonlyArray<ServerProviderSkill> {
  return skills.map((skill) => ({
    name: skill.name,
    description: skill.description,
    path: NodePath.join(directory, skill.path),
    scope: "system",
    enabled: true,
  }));
}

/** The app-owned KiStack catalog exposed alongside each provider's skills. */
export function getKiStackProviderSkills(): ReadonlyArray<ServerProviderSkill> {
  return providerSkills(defaultSkills.skills, defaultSkills.directory);
}

export function isKiStackProviderSkill(
  skill: Pick<ServerProviderSkill, "path" | "scope">,
): boolean {
  return (
    skill.scope === "system" && skill.path.replaceAll("\\", "/").includes("/backplane/kistack/")
  );
}

export function mergeKiStackProviderSkills(
  skills: ReadonlyArray<ServerProviderSkill>,
): ReadonlyArray<ServerProviderSkill> {
  const nativeSkills = skills.filter((skill) => !isKiStackProviderSkill(skill));
  const names = new Set(nativeSkills.map((skill) => skill.name.trim().toLowerCase()));
  return [
    ...nativeSkills,
    ...getKiStackProviderSkills().filter((skill) => !names.has(skill.name.toLowerCase())),
  ];
}

export function buildKiStackInstructions(directory?: string): string {
  return directory === undefined
    ? defaultSkills.buildInstructions()
    : instructions(bundledMetadata, directory);
}
