import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, readdir, stat, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function command(file, args, options = {}) {
  return execFileSync(file, args, { stdio: "inherit", ...options });
}

async function findResources(root) {
  const queue = [{ path: root, depth: 0 }];
  while (queue.length > 0) {
    const current = queue.shift();
    const resources = join(current.path, "resources");
    if ((await isDirectory(resources)) && (await isFile(join(resources, "python", "PYTHON.json"))))
      return resources;
    if (current.depth >= 5) continue;
    for (const entry of await readdir(current.path, { withFileTypes: true })) {
      if (entry.isDirectory() && !entry.name.startsWith("."))
        queue.push({ path: join(current.path, entry.name), depth: current.depth + 1 });
    }
  }
  throw new Error(`Could not find an unpacked resources directory below ${root}`);
}

async function isFile(path) {
  try {
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}
async function isDirectory(path) {
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}
async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function hasFile(root, predicate) {
  const entries = await readdir(root, { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    const path = join(root, entry.name);
    if (entry.isFile() && predicate(entry.name)) return true;
    if (entry.isDirectory() && (await hasFile(path, predicate))) return true;
  }
  return false;
}

export async function validateResources(resources, sourceDir, platform) {
  const pythonName = platform === "win" ? "python.exe" : "python3";
  const kicadName = platform === "win" ? "kicad-cli.exe" : "kicad-cli";
  const python = join(resources, "python", "bin", pythonName);
  const kicad = join(resources, "kicad", "bin", kicadName);
  for (const required of [
    python,
    kicad,
    join(resources, "python", "PYTHON.json"),
    join(resources, "python", "LICENSES", "SOURCE.txt"),
    join(resources, "kicad", "manifest.json"),
  ]) {
    if (!(await isFile(required))) throw new Error(`Packaged runtime is missing ${required}`);
  }
  const sourcePython = join(sourceDir, "python-runtime");
  const sourceKicad = join(sourceDir, "kicad-runtime");
  const packagedPython = await readJson(join(resources, "python", "PYTHON.json"));
  const sourcePythonMetadata = await readJson(join(sourcePython, "PYTHON.json"));
  if (JSON.stringify(packagedPython) !== JSON.stringify(sourcePythonMetadata))
    throw new Error("Packaged Python metadata differs from the staged source");
  const packagedManifest = await readJson(join(resources, "kicad", "manifest.json"));
  const sourceManifest = await readJson(join(sourceKicad, "manifest.json"));
  for (const field of ["sourceRepository", "sourceCommit", "version", "license"]) {
    if (packagedManifest[field] !== sourceManifest[field])
      throw new Error(`Packaged KiCad manifest differs from source for ${field}`);
  }
  const licenseCount = (await readdir(join(resources, "python", "LICENSES"))).filter((name) =>
    /^LICENSE\..+\.txt$/u.test(name),
  ).length;
  if (licenseCount === 0) throw new Error("Packaged Python runtime has no component licenses");
  const libraryChecks = [
    ["symbols", (name) => name.endsWith(".kicad_sym")],
    ["footprints", (name) => name.endsWith(".kicad_mod")],
    ["3dmodels", (name) => /\.(wrl|wrz|step|stp|iges|igs)$/iu.test(name)],
    ["template", (name) => /\.(kicad_pro|pro)$/iu.test(name)],
  ];
  for (const [directory, predicate] of libraryChecks)
    if (!(await hasFile(join(resources, "kicad", "share", "kicad", directory), predicate)))
      throw new Error(`Packaged KiCad runtime is missing a ${directory} library`);
  for (const table of [
    join(resources, "kicad", "share", "kicad", "sym-lib-table"),
    join(resources, "kicad", "share", "kicad", "fp-lib-table"),
    join(resources, "kicad", "share", "kicad", "template", "sym-lib-table"),
    join(resources, "kicad", "share", "kicad", "template", "fp-lib-table"),
  ])
    if (!(await isFile(table))) throw new Error(`Packaged KiCad runtime is missing ${table}`);
  command(python, [
    "-I",
    "-c",
    "import json, math, xml.etree.ElementTree; print('bundled Python ready')",
  ]);
  command(kicad, ["--version"]);
  command(kicad, ["api-server", "--help"]);
  console.log(
    `Verified ${platform} package resources: Python ${packagedPython.python_version ?? "unknown"}, KiCad ${packagedManifest.version}`,
  );
}

async function unpackArtifact(artifact, platform, temp) {
  if (platform === "linux") {
    command(artifact, ["--appimage-extract"], {
      cwd: temp,
      stdio: ["ignore", "ignore", "inherit"],
    });
    return join(temp, "squashfs-root");
  }
  if (platform === "mac") {
    const out = join(temp, "unpacked");
    command(
      process.platform === "darwin" ? "ditto" : "unzip",
      process.platform === "darwin" ? ["-x", "-k", artifact, out] : ["-q", artifact, "-d", out],
    );
    return out;
  }
  const out = join(temp, "installed");
  if (process.platform !== "win32")
    throw new Error(
      "Windows NSIS verification must run on a Windows runner; installing an EXE through Wine is unsupported",
    );
  command(artifact, ["/S", `/D=${out}`]);
  return out;
}

export async function verifyNightlyDesktop({
  platform,
  artifact,
  sourceDir = join(repoRoot, "apps/desktop/prod-resources"),
}) {
  const temp = await mkdtemp(join(tmpdir(), "backplane-nightly-desktop-"));
  try {
    const extractedRoot = await unpackArtifact(resolve(artifact), platform, temp);
    const resources = await findResources(extractedRoot);
    await validateResources(resources, resolve(sourceDir), platform);
    if (platform === "linux")
      command(process.env.PYTHON ?? "python3", [
        join(repoRoot, "scripts/smoke-desktop-release.py"),
        extractedRoot,
        "--headless",
      ]);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const { values } = parseArgs({
    options: {
      platform: { type: "string" },
      artifact: { type: "string" },
      "source-dir": { type: "string" },
    },
  });
  if (!values.platform || !values.artifact || !["linux", "mac", "win"].includes(values.platform))
    throw new Error(
      "Usage: node scripts/verify-nightly-desktop.mjs --platform linux|mac|win --artifact PATH [--source-dir PATH]",
    );
  await verifyNightlyDesktop({
    platform: values.platform,
    artifact: values.artifact,
    sourceDir: values["source-dir"],
  });
}
