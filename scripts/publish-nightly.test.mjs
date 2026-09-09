import { createHash } from "node:crypto";
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const script = fileURLToPath(new URL("./publish-nightly.mjs", import.meta.url));
const identity = {
  GITHUB_REPOSITORY: "i2cjak/Backplane",
  GITHUB_SHA: "0123456789abcdef0123456789abcdef01234567",
  RELEASE_TAG: "v1.2.4-nightly.20260909.7",
  RELEASE_VERSION: "1.2.4-nightly.20260909.7",
};

async function fixture(files, run) {
  const root = await mkdtemp(join(tmpdir(), "backplane-publish-nightly-"));
  try {
    await mkdir(join(root, "release-publish"));
    for (const [name, contents] of files) {
      await writeFile(join(root, "release-publish", name), contents);
    }
    await run(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("publishes the Linux AppImage, Linux feed, and Android APK set", async () => {
  await fixture(
    [
      ["Backplane-x64.AppImage", "appimage"],
      ["nightly-linux.yml", "feed"],
      ["Backplane-android.apk", "apk"],
    ],
    async (cwd) => {
      const bin = join(cwd, "bin");
      await mkdir(bin);
      const log = join(cwd, "gh.log");
      await writeFile(
        join(bin, "gh"),
        `#!/bin/sh\nprintf '%s\\n' "$*" >> "$GH_TEST_LOG"\nif [ "$2" = view ]; then exit 1; fi\n`,
        { mode: 0o755 },
      );
      await execFileAsync(process.execPath, [script], {
        cwd,
        env: {
          ...process.env,
          ...identity,
          RUNNER_TEMP: cwd,
          GH_TEST_LOG: log,
          PATH: `${bin}:${process.env.PATH}`,
        },
      });
      const sums = await readFile(join(cwd, "release-publish/SHA256SUMS"), "utf8");
      const expected =
        [
          ["Backplane-android.apk", "apk"],
          ["Backplane-x64.AppImage", "appimage"],
          ["nightly-linux.yml", "feed"],
        ]
          .map(
            ([name, contents]) => `${createHash("sha256").update(contents).digest("hex")}  ${name}`,
          )
          .join("\n") + "\n";
      assert.equal(sums, expected);
      const notes = await readFile(join(cwd, "backplane-nightly-notes.md"), "utf8");
      assert.ok(notes.includes("\n\nDownload the Linux"));
      assert.ok(!notes.includes("\\n"));
      assert.match(await readFile(join(cwd, "gh.log"), "utf8"), /release create/);
    },
  );
});

const requiredFiles = [
  ["Backplane-x64.AppImage", "appimage"],
  ["Backplane-android.apk", "apk"],
  ["nightly-linux.yml", "feed"],
];
for (const [missing] of requiredFiles) {
  test(`refuses a nightly without ${missing}`, async () => {
    await fixture(
      requiredFiles.filter(([name]) => name !== missing),
      async (cwd) => {
        await assert.rejects(
          execFileAsync(process.execPath, [script], {
            cwd,
            env: { ...process.env, ...identity },
          }),
          /Incomplete nightly: missing/,
        );
      },
    );
  });
}
