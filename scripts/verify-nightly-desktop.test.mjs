import assert from "node:assert/strict";
import { chmod, mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { validateResources } from "./verify-nightly-desktop.mjs";

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "backplane-verify-test-"));
  const source = join(root, "source");
  const resources = join(root, "resources");
  const directories = [
    "python-runtime/bin",
    "python-runtime/LICENSES",
    "kicad-runtime/bin",
    "kicad-runtime/share/kicad/symbols",
    "kicad-runtime/share/kicad/footprints",
    "kicad-runtime/share/kicad/3dmodels",
    "kicad-runtime/share/kicad/template",
    "kicad-runtime/licenses/kicad-libraries/kicad-symbols",
    "kicad-runtime/licenses/kicad-libraries/kicad-footprints",
    "kicad-runtime/licenses/kicad-libraries/kicad-packages3D",
    "kicad-runtime/licenses/kicad-libraries/kicad-templates",
    "python/bin",
    "python/LICENSES",
    "kicad/bin",
    "kicad/share/kicad/symbols",
    "kicad/share/kicad/footprints",
    "kicad/share/kicad/3dmodels",
    "kicad/share/kicad/template",
  ];
  for (const directory of directories) {
    await mkdir(join(source, directory), { recursive: true });
    await mkdir(
      join(
        resources,
        directory.replace("python-runtime", "python").replace("kicad-runtime", "kicad"),
      ),
      { recursive: true },
    );
  }
  const pythonMetadata = { version: "3.13.15" };
  const kicadManifest = {
    sourceRepository: "https://example.invalid/kicad",
    sourceCommit: "abc",
    version: "1",
    license: "MIT",
  };
  await writeFile(join(source, "python-runtime/PYTHON.json"), JSON.stringify(pythonMetadata));
  await writeFile(join(resources, "python/PYTHON.json"), JSON.stringify(pythonMetadata));
  await writeFile(join(source, "kicad-runtime/manifest.json"), JSON.stringify(kicadManifest));
  await writeFile(join(resources, "kicad/manifest.json"), JSON.stringify(kicadManifest));
  for (const base of [join(source, "kicad-runtime"), join(resources, "kicad")]) {
    for (const file of [
      "share/kicad/symbols/a.kicad_sym",
      "share/kicad/footprints/a.kicad_mod",
      "share/kicad/3dmodels/a.step",
      "share/kicad/template/a.kicad_pro",
      "share/kicad/sym-lib-table",
      "share/kicad/fp-lib-table",
      "share/kicad/template/sym-lib-table",
      "share/kicad/template/fp-lib-table",
    ])
      await writeFile(join(base, file), "fixture");
  }
  for (const file of ["python/LICENSES/LICENSE.test.txt", "python/LICENSES/SOURCE.txt"])
    await writeFile(join(resources, file), "fixture");
  for (const library of [
    "kicad-symbols",
    "kicad-footprints",
    "kicad-packages3D",
    "kicad-templates",
  ])
    await writeFile(
      join(source, `kicad-runtime/licenses/kicad-libraries/${library}/BACKPLANE_SOURCE.txt`),
      "fixture",
    );
  for (const executable of [
    join(resources, "python/bin/python3"),
    join(resources, "kicad/bin/kicad-cli"),
  ]) {
    await writeFile(executable, "#!/bin/sh\necho fixture");
    await chmod(executable, 0o755);
  }
  return { root, source, resources };
}

test("accepts complete packaged runtime provenance and executable checks", async () => {
  if (process.platform === "win32") return;
  const paths = await fixture();
  try {
    await validateResources(paths.resources, paths.source, "linux");
  } finally {
    await rm(paths.root, { recursive: true, force: true });
  }
});

test("rejects packaged KiCad provenance drift", async () => {
  if (process.platform === "win32") return;
  const paths = await fixture();
  try {
    await writeFile(
      join(paths.resources, "kicad/manifest.json"),
      JSON.stringify({
        sourceRepository: "wrong",
        sourceCommit: "abc",
        version: "1",
        license: "MIT",
      }),
    );
    await assert.rejects(
      validateResources(paths.resources, paths.source, "linux"),
      /manifest differs from source/,
    );
  } finally {
    await rm(paths.root, { recursive: true, force: true });
  }
});
