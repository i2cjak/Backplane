// @effect-diagnostics nodeBuiltinImport:off
import * as NodeFS from "node:fs";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import { expect, it } from "vite-plus/test";

import {
  resolveKiCadEnvironment,
  resolveKiCadExecutable,
  resolveKiCadRuntime,
} from "./KiCadExecutable.ts";

it("honours an explicit Backplane override", () => {
  expect(resolveKiCadExecutable({ BACKPLANE_KICAD_CLI: "/opt/backplane/kicad-cli" })).toBe(
    "/opt/backplane/kicad-cli",
  );
});

it("does not identify an explicit executable override without a verified manifest", () => {
  expect(
    resolveKiCadRuntime({ BACKPLANE_KICAD_CLI: "/opt/custom/kicad-cli" }).fork,
  ).toBeUndefined();
});

it("recognises the selected executable only beside a matching fork manifest", () => {
  const root = NodeFS.mkdtempSync(NodePath.join(NodeOS.tmpdir(), "backplane-kicad-manifest-"));
  const executable = NodePath.join(root, "bin", "kicad-cli");
  NodeFS.mkdirSync(NodePath.dirname(executable), { recursive: true });
  NodeFS.writeFileSync(executable, "");
  NodeFS.writeFileSync(
    NodePath.join(root, "manifest.json"),
    JSON.stringify({
      version: "10.0.6",
      sourceRepository: "https://github.com/i2cjak/Backplane_KiCad",
      sourceCommit: "0123456789abcdef0123456789abcdef01234567",
    }),
  );
  try {
    const fork = resolveKiCadRuntime({ BACKPLANE_KICAD_CLI: executable }).fork;
    expect(fork?.version).toBe("10.0.6");
    expect(fork?.guideUrl).toContain(fork?.sourceCommit ?? "");
  } finally {
    NodeFS.rmSync(root, { recursive: true, force: true });
  }
});

it("prefers the packaged resources runtime", () => {
  const root = NodeFS.mkdtempSync(NodePath.join(NodeOS.tmpdir(), "backplane-resources-"));
  const executable = NodePath.join(root, "kicad", "bin", "kicad-cli");
  NodeFS.mkdirSync(NodePath.dirname(executable), { recursive: true });
  NodeFS.writeFileSync(executable, "#!/bin/sh\n");
  const original = (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath;
  (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath = root;
  try {
    expect(resolveKiCadExecutable({})).toBe(executable);
  } finally {
    if (original === undefined) {
      delete (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath;
    } else {
      (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath = original;
    }
    NodeFS.rmSync(root, { recursive: true, force: true });
  }
});

it("falls back to PATH for development", () => {
  const original = (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath;
  (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath = NodeFS.mkdtempSync(
    NodePath.join(NodeOS.tmpdir(), "backplane-empty-resources-"),
  );
  expect(resolveKiCadExecutable({})).toBe("kicad-cli");
  NodeFS.rmSync((process as NodeJS.Process & { resourcesPath?: string }).resourcesPath!, {
    recursive: true,
    force: true,
  });
  if (original === undefined) {
    delete (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath;
  } else {
    (process as NodeJS.Process & { resourcesPath?: string }).resourcesPath = original;
  }
});

it("points bundled KiCad at its standard libraries while preserving overrides", () => {
  const root = NodeFS.mkdtempSync(NodePath.join(NodeOS.tmpdir(), "backplane-kicad-libraries-"));
  const executable = NodePath.join(root, "kicad", "bin", "kicad-cli");
  const share = NodePath.join(root, "kicad", "share", "kicad");
  NodeFS.mkdirSync(NodePath.dirname(executable), { recursive: true });
  NodeFS.writeFileSync(executable, "#!/bin/sh\n");
  for (const directory of ["symbols", "footprints", "3dmodels", "template"]) {
    NodeFS.mkdirSync(NodePath.join(share, directory), { recursive: true });
  }
  try {
    const resolved = resolveKiCadEnvironment({ BACKPLANE_KICAD_CLI: executable });
    expect(resolved.KICAD10_SYMBOL_DIR).toBe(NodePath.join(share, "symbols"));
    expect(resolved.KICAD10_FOOTPRINT_DIR).toBe(NodePath.join(share, "footprints"));
    expect(resolved.KICAD10_3DMODEL_DIR).toBe(NodePath.join(share, "3dmodels"));
    expect(resolved.KICAD10_TEMPLATE_DIR).toBe(NodePath.join(share, "template"));

    const override = "/custom/kicad-symbols";
    expect(
      resolveKiCadEnvironment({
        BACKPLANE_KICAD_CLI: executable,
        KICAD10_SYMBOL_DIR: override,
      }).KICAD10_SYMBOL_DIR,
    ).toBe(override);
  } finally {
    NodeFS.rmSync(root, { recursive: true, force: true });
  }
});

it("puts the selected executable directory first and removes duplicate PATH entries", () => {
  const executable = "/opt/kicad/bin/kicad-cli";
  const resolved = resolveKiCadEnvironment({
    PATH: `/usr/bin${NodePath.delimiter}/opt/kicad/bin${NodePath.delimiter}/usr/bin`,
    BACKPLANE_KICAD_CLI: executable,
  });
  expect(resolved.PATH).toBe(`/opt/kicad/bin${NodePath.delimiter}/usr/bin`);
});
