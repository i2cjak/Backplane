// @effect-diagnostics nodeBuiltinImport:off
import { describe, expect, it } from "vite-plus/test";
import * as NodeFS from "node:fs";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import { buildRuntimeInstructions } from "./RuntimeInstructions.ts";

describe("buildRuntimeInstructions", () => {
  it.each(["Codex", "Claude Code", "Cursor", "Grok", "OpenCode", "Antigravity"])(
    "identifies the %s harness and describes media embedding",
    (harness) => {
      const instructions = buildRuntimeInstructions({ harness });
      expect(instructions).toContain(`running in Backplane through the ${harness} harness.`);
      expect(instructions).toContain("embed images and videos");
      expect(instructions).toContain("Markdown with absolute file paths");
      expect(instructions).not.toContain("undefined");
      expect(instructions).toContain("<kistack_skills>");
      expect(instructions).toContain("kicad-schematic");
      expect(instructions).toContain("kicad-bom");
      expect(instructions).toContain("pcb-product-render");
    },
  );

  it("keeps known model and effort metadata on one line", () => {
    expect(
      buildRuntimeInstructions({
        harness: "Codex",
        model: "  custom\nmodel  ",
        reasoningEffort: " high\n",
      }),
    ).toContain("through the Codex harness, as custom model with high reasoning effort.");
  });

  it.each([undefined, "", "auto", "default"])("omits unresolved model %s", (model) => {
    const instructions = buildRuntimeInstructions({ harness: "Cursor", model });
    expect(instructions).toContain("through the Cursor harness.");
    expect(instructions).not.toContain("reasoning effort");
  });

  it("uses the supplied environment when describing a system KiCad CLI", () => {
    const instructions = buildRuntimeInstructions({
      harness: "Codex",
      environment: { KICAD_CLI: "/usr/bin/kicad-cli" },
    });
    expect(instructions).toContain('"/usr/bin/kicad-cli" --version');
    expect(instructions).toContain("No matching Backplane fork manifest");
  });

  it("uses the selected runtime manifest version and commit for fork links", () => {
    const root = NodeFS.mkdtempSync(
      NodePath.join(NodeOS.tmpdir(), "backplane-runtime-instructions-"),
    );
    const executable = NodePath.join(root, "bin", "kicad cli");
    NodeFS.mkdirSync(NodePath.dirname(executable), { recursive: true });
    NodeFS.writeFileSync(executable, "");
    const commit = "fedcba9876543210fedcba9876543210fedcba98";
    NodeFS.writeFileSync(
      NodePath.join(root, "manifest.json"),
      JSON.stringify({
        version: "10.0.7",
        sourceRepository: "https://github.com/i2cjak/Backplane_KiCad",
        sourceCommit: commit,
      }),
    );
    try {
      const instructions = buildRuntimeInstructions({
        harness: "Codex",
        environment: { BACKPLANE_KICAD_CLI: executable },
      });
      expect(instructions).toContain("Backplane KiCad 10.0.7");
      expect(instructions).toContain(`/tree/${commit}/BACKPLANE_IPC.md`);
      expect(instructions).toContain(`${JSON.stringify(executable)} api-server`);
      expect(instructions).toContain(".backplane.json");
      const changedCommit = "abcdef0123456789abcdef0123456789abcdef01";
      NodeFS.writeFileSync(
        NodePath.join(root, "manifest.json"),
        JSON.stringify({
          version: "10.0.8",
          sourceRepository: "https://github.com/i2cjak/Backplane_KiCad",
          sourceCommit: changedCommit,
        }),
      );
      const changed = buildRuntimeInstructions({
        harness: "Codex",
        environment: { BACKPLANE_KICAD_CLI: executable },
      });
      expect(changed).toContain(`/tree/${changedCommit}/BACKPLANE_IPC.md`);
      expect(changed).not.toContain(`/tree/${commit}/BACKPLANE_IPC.md`);
    } finally {
      NodeFS.rmSync(root, { recursive: true, force: true });
    }
  });
});
