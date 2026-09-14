import * as NodeAssert from "node:assert/strict";
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import * as NodeTest from "node:test";
import { supplementKiCadGlibcFromRoot, supplementKiCadGlibc } from "./supplement-kicad-glibc.mjs";

const files = [
  "libc.so.6",
  "ld-linux-x86-64.so.2",
  "libm.so.6",
  "libdl.so.2",
  "libpthread.so.0",
  "librt.so.1",
  "libmvec.so.1",
];

async function fixture(t) {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-glibc-test-"));
  t.after(() => NodeFSP.rm(root, { recursive: true, force: true }));
  const runtime = NodePath.join(root, "runtime");
  const extracted = NodePath.join(root, "package");
  await Promise.all([
    NodeFSP.mkdir(NodePath.join(runtime, "lib"), { recursive: true }),
    NodeFSP.mkdir(NodePath.join(extracted, "usr/lib/x86_64-linux-gnu"), { recursive: true }),
  ]);
  for (const name of files) {
    await NodeFSP.writeFile(
      NodePath.join(extracted, "usr/lib/x86_64-linux-gnu", name),
      `matching-${name}`,
    );
    if (name === "libc.so.6" || name === "ld-linux-x86-64.so.2" || name === "libm.so.6")
      await NodeFSP.writeFile(NodePath.join(runtime, "lib", name), `matching-${name}`);
  }
  return { root, runtime, extracted };
}

NodeTest.test("copies only missing libc6 companions after matching ABI files", async (t) => {
  const { runtime, extracted } = await fixture(t);
  NodeAssert.deepEqual(await supplementKiCadGlibcFromRoot(runtime, extracted), files.slice(3));
  for (const name of files)
    NodeAssert.equal(
      await NodeFSP.readFile(NodePath.join(runtime, "lib", name), "utf8"),
      `matching-${name}`,
    );
  NodeAssert.deepEqual(await supplementKiCadGlibcFromRoot(runtime, extracted), []);
});

NodeTest.test("refuses a mixed libc package before copying companions", async (t) => {
  const { runtime, extracted } = await fixture(t);
  await NodeFSP.writeFile(NodePath.join(runtime, "lib/libc.so.6"), "different-libc");
  await NodeAssert.rejects(
    supplementKiCadGlibcFromRoot(runtime, extracted),
    /does not match libc6 package for libc\.so\.6/,
  );
  await NodeAssert.rejects(NodeFSP.access(NodePath.join(runtime, "lib/libdl.so.2")));
});

NodeTest.test("validates every companion before changing the runtime", async (t) => {
  const { runtime, extracted } = await fixture(t);
  await NodeFSP.rm(NodePath.join(extracted, "usr/lib/x86_64-linux-gnu/libmvec.so.1"));
  await NodeAssert.rejects(supplementKiCadGlibcFromRoot(runtime, extracted), /missing libmvec/);
  await NodeAssert.rejects(NodeFSP.access(NodePath.join(runtime, "lib/libdl.so.2")));
});

NodeTest.test("refuses conflicting existing companions without overwriting them", async (t) => {
  const { runtime, extracted } = await fixture(t);
  const target = NodePath.join(runtime, "lib/libmvec.so.1");
  await NodeFSP.writeFile(target, "different-companion");
  await NodeAssert.rejects(
    supplementKiCadGlibcFromRoot(runtime, extracted),
    /does not match.*libmvec/,
  );
  NodeAssert.equal(await NodeFSP.readFile(target, "utf8"), "different-companion");
  await NodeAssert.rejects(NodeFSP.access(NodePath.join(runtime, "lib/libdl.so.2")));
});

NodeTest.test("rejects a corrupt download before invoking the package extractor", async (t) => {
  const { root, runtime } = await fixture(t);
  const deb = NodePath.join(root, "libc6.deb");
  await NodeFSP.writeFile(deb, "not a Debian package");
  await NodeAssert.rejects(
    supplementKiCadGlibc(runtime, deb, {
      package: "libc6",
      architecture: "amd64",
      version: "2.39-0ubuntu8.8",
      sha256: "0".repeat(64),
    }),
    /checksum mismatch/,
  );
  await NodeAssert.rejects(NodeFSP.access(NodePath.join(runtime, "lib/libdl.so.2")));
});
