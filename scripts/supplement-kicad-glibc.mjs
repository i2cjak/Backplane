import * as NodeCrypto from "node:crypto";
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import * as NodeChildProcess from "node:child_process";

const REQUIRED = ["libdl.so.2", "libpthread.so.0", "librt.so.1", "libmvec.so.1"];
const MATCH_FILES = ["libc.so.6", "ld-linux-x86-64.so.2", "libm.so.6"];

const packageField = (deb, field) =>
  NodeChildProcess.execFileSync("dpkg-deb", ["-f", deb, field], { encoding: "utf8" }).trim();

async function regularFile(path) {
  try {
    return (await NodeFSP.stat(path)).isFile();
  } catch {
    return false;
  }
}

async function sameBytes(left, right) {
  if (!(await regularFile(left)) || !(await regularFile(right))) return false;
  const [a, b] = await Promise.all([NodeFSP.readFile(left), NodeFSP.readFile(right)]);
  return a.equals(b);
}

/**
 * Complete a Linux KiCad runtime with companions from the exact libc6 package
 * used to build it. Existing ABI files are never replaced.
 */
export async function supplementKiCadGlibcFromRoot(runtime, extracted) {
  const sourceLib = NodePath.join(extracted, "usr/lib/x86_64-linux-gnu");
  const runtimeLib = NodePath.join(runtime, "lib");
  for (const name of MATCH_FILES) {
    const source = NodePath.join(sourceLib, name);
    const target = NodePath.join(runtimeLib, name);
    if (!(await regularFile(source))) throw new Error(`libc6 package is missing ${name}.`);
    if (!(await sameBytes(source, target)))
      throw new Error(`Bundled KiCad glibc does not match libc6 package for ${name}.`);
  }
  const missing = [];
  for (const name of REQUIRED) {
    const source = NodePath.join(sourceLib, name);
    const target = NodePath.join(runtimeLib, name);
    if (!(await regularFile(source))) throw new Error(`libc6 package is missing ${name}.`);
    if (await regularFile(target)) {
      if (!(await sameBytes(source, target)))
        throw new Error(`Bundled KiCad glibc does not match libc6 package for ${name}.`);
      continue;
    }
    missing.push(name);
  }
  // Check the entire package before adding any files to the staged runtime.
  for (const name of missing)
    await NodeFSP.cp(NodePath.join(sourceLib, name), NodePath.join(runtimeLib, name), {
      preserveTimestamps: true,
    });
  return missing;
}

export async function supplementKiCadGlibc(runtime, deb, pin) {
  if (
    pin.package !== "libc6" ||
    pin.architecture !== "amd64" ||
    !pin.version ||
    !/^[a-f0-9]{64}$/.test(pin.sha256)
  )
    throw new Error("Invalid KiCad glibc package pin.");
  if (
    NodeCrypto.createHash("sha256")
      .update(await NodeFSP.readFile(deb))
      .digest("hex") !== pin.sha256
  )
    throw new Error("KiCad glibc package checksum mismatch.");
  if (packageField(deb, "Package") !== "libc6") throw new Error("glibc supplement is not libc6.");
  if (packageField(deb, "Architecture") !== "amd64")
    throw new Error("glibc supplement is not amd64 libc6.");
  const version = packageField(deb, "Version");
  if (version !== pin.version)
    throw new Error(`Unexpected libc6 version: ${version} (expected ${pin.version}).`);
  const extracted = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-libc6-"));
  try {
    NodeChildProcess.execFileSync("dpkg-deb", ["-x", deb, extracted], { stdio: "inherit" });
    return await supplementKiCadGlibcFromRoot(runtime, extracted);
  } finally {
    await NodeFSP.rm(extracted, { recursive: true, force: true });
  }
}
