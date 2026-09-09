import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const script = fileURLToPath(new URL("./collect-nightly-assets.mjs", import.meta.url));
async function fixture(files, run) {
  const dir = await mkdtemp(join(tmpdir(), "backplane-assets-"));
  try {
    await mkdir(join(dir, "release"));
    for (const name of files) await writeFile(join(dir, "release", name), "fixture");
    await run(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
test("requires both mac installers and retains a separate Intel updater manifest", async () => {
  await fixture(
    ["Backplane-x64.dmg", "Backplane-x64.zip", "nightly-mac.yml", "builder-debug.yml"],
    async (cwd) => {
      execFileSync(process.execPath, [script, "--platform", "mac", "--arch", "x64"], { cwd });
      assert.deepEqual((await readdir(join(cwd, "release-publish"))).sort(), [
        "Backplane-x64.dmg",
        "Backplane-x64.zip",
        "nightly-mac-x64.yml",
      ]);
    },
  );
});
test("refuses a partial macOS release", async () => {
  await fixture(["Backplane-x64.dmg"], async (cwd) => {
    assert.throws(
      () =>
        execFileSync(process.execPath, [script, "--platform", "mac", "--arch", "x64"], {
          cwd,
          stdio: "pipe",
        }),
      /Missing .zip installer/,
    );
  });
});
