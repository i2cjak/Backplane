// @effect-diagnostics nodeBuiltinImport:off globalDate:off
import { afterEach, describe, expect, it } from "vite-plus/test";
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import { createKiCadPanelizationCache, emphasizeEdgeCuts } from "./KiCadPanelization.ts";

const roots: string[] = [];
afterEach(async () => {
  await Promise.all(
    roots.splice(0).map((root) => NodeFSP.rm(root, { recursive: true, force: true })),
  );
});
async function fixture() {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "kikit-preview-test-"));
  roots.push(root);
  await NodeFSP.writeFile(NodePath.join(root, "board.kicad_pcb"), "(kicad_pcb (version 20240108))");
  await NodeFSP.writeFile(
    NodePath.join(root, "panel.json"),
    JSON.stringify({ layout: { type: "grid", rows: 1, cols: 2 } }),
  );
  return root;
}

describe("KiKit panelization preview", () => {
  it("brings the Edge.Cuts profile to the front with a readable stroke", () => {
    const svg = `<svg viewBox="0 0 1 1"><g style="fill:none; \nstroke:#C9A57C; stroke-width:0.1000;"><path d="M0 0 L1 1" /></g><g style="stroke:#DCB4AA"><path d="M0 0" /></g></svg>`;
    const emphasized = emphasizeEdgeCuts(
      svg,
      `<svg viewBox="0 0 1 1"><g style="stroke:#000000; stroke-width:0.1000"><path d="M0 0 L1 1" /></g></svg>`,
    );
    expect(emphasized.indexOf("stroke:#DCB4AA")).toBeLessThan(
      emphasized.indexOf('<g class="backplane-panel-outline">'),
    );
    expect(emphasized).toContain("stroke-width: 1.25px");
    expect(emphasized.match(/<\/svg>/g)).toHaveLength(1);
    expect(emphasized).toContain("vector-effect: non-scaling-stroke");
  });

  it("runs KiKit and SVG export, and coalesces identical requests", async () => {
    const root = await fixture();
    let calls = 0;
    const cache = createKiCadPanelizationCache({
      run: async (_command, args) => {
        calls++;
        const output = args[args.indexOf("--output") + 1];
        if (output?.endsWith(".svg"))
          await NodeFSP.writeFile(output, "<svg><!-- holes and V-CUT --></svg>");
      },
    });
    const [a, b] = await Promise.all([
      cache.get(root, "board.kicad_pcb", "panel.json"),
      cache.get(root, "board.kicad_pcb", "panel.json"),
    ]);
    expect(a.svg).toContain("<svg>");
    expect(a.revision).toBe(b.revision);
    expect(calls).toBe(3);
    await cache.get(root, "board.kicad_pcb", "panel.json");
    expect(calls).toBe(3);
  });

  it("invalidates only when board or preset content changes", async () => {
    const root = await fixture();
    let calls = 0;
    const cache = createKiCadPanelizationCache({
      run: async (_command, args) => {
        calls++;
        const output = args[args.indexOf("--output") + 1];
        if (output?.endsWith(".svg")) await NodeFSP.writeFile(output, "<svg/>");
      },
    });
    const first = await cache.get(root, "board.kicad_pcb", "panel.json");
    await NodeFSP.writeFile(NodePath.join(root, "unrelated.txt"), "change");
    expect((await cache.get(root, "board.kicad_pcb", "panel.json")).revision).toBe(first.revision);
    await NodeFSP.appendFile(NodePath.join(root, "panel.json"), "\n");
    expect((await cache.get(root, "board.kicad_pcb", "panel.json")).revision).not.toBe(
      first.revision,
    );
    expect(calls).toBe(6);
  });

  it("rejects unsafe presets and paths before invoking tools", async () => {
    const root = await fixture();
    let calls = 0;
    const cache = createKiCadPanelizationCache({
      run: async () => {
        calls++;
      },
    });
    await NodeFSP.writeFile(
      NodePath.join(root, "unsafe.json"),
      JSON.stringify({ post: { script: "evil.py" } }),
    );
    await expect(cache.get(root, "board.kicad_pcb", "unsafe.json")).rejects.toThrow(
      /not allowed|cannot load/,
    );
    await expect(cache.get(root, "../outside.kicad_pcb", "panel.json")).rejects.toThrow(/inside/);
    expect(calls).toBe(0);
  });

  it("reports missing KiKit clearly", async () => {
    const root = await fixture();
    const cache = createKiCadPanelizationCache({
      run: async () => {
        throw new Error("kikit is not installed or is not on PATH.");
      },
    });
    await expect(cache.get(root, "board.kicad_pcb", "panel.json")).rejects.toThrow(/not installed/);
  });

  it("keeps the waiting queue bounded", async () => {
    const root = await fixture();
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const cache = createKiCadPanelizationCache({
      maxConcurrent: 1,
      run: async (_command, args) => {
        if (args[0] === "panelize") await gate;
        const output = args[args.indexOf("--output") + 1];
        if (output?.endsWith(".svg")) await NodeFSP.writeFile(output, "<svg/>");
      },
    });
    const overflow = Promise.withResolvers<void>();
    const pending = Array.from({ length: 10 }, (_, i) => {
      const preset = `p${i}.json`;
      return NodeFSP.writeFile(
        NodePath.join(root, preset),
        JSON.stringify({ layout: { type: "grid", rows: 1, cols: i + 1 } }),
      )
        .then(() => cache.get(root, "board.kicad_pcb", preset))
        .catch((cause) => {
          overflow.resolve();
          throw cause;
        });
    });
    const settled = Promise.allSettled(pending);
    await overflow.promise;
    release();
    const requests = await settled;
    expect(
      requests.some(
        (result) => result.status === "rejected" && /Too many/.test(String(result.reason)),
      ),
    ).toBe(true);
  });
});

it("retries failed exports and preserves source files even when named panel.kicad_pcb", async () => {
  const root = await fixture();
  const board = NodePath.join(root, "panel.kicad_pcb");
  await NodeFSP.rename(NodePath.join(root, "board.kicad_pcb"), board);
  const original = await NodeFSP.readFile(board, "utf8");
  let fail = true;
  const cache = createKiCadPanelizationCache({
    run: async (command, args, cwd) => {
      if (command === "kikit") {
        expect(await NodeFSP.readFile(args.at(-2)!, "utf8")).toBe(original);
        expect(args.at(-2)).not.toBe(args.at(-1));
        expect(cwd).not.toBe(root);
        if (fail) throw new Error("transient failure");
      } else {
        await NodeFSP.writeFile(args[args.indexOf("--output") + 1]!, "<svg/>");
      }
    },
  });
  await expect(cache.get(root, "panel.kicad_pcb", "panel.json")).rejects.toThrow(
    "transient failure",
  );
  fail = false;
  expect((await cache.get(root, "panel.kicad_pcb", "panel.json")).svg).toBe("<svg/>");
  expect(await NodeFSP.readFile(board, "utf8")).toBe(original);
});

it("rejects malformed JSON and symlinked presets", async () => {
  const root = await fixture();
  const cache = createKiCadPanelizationCache({
    run: async () => {
      throw new Error("must not execute");
    },
  });
  await NodeFSP.writeFile(NodePath.join(root, "broken.json"), "{");
  await expect(cache.get(root, "board.kicad_pcb", "broken.json")).rejects.toThrow("not valid JSON");
  await NodeFSP.symlink(NodePath.join(root, "panel.json"), NodePath.join(root, "link.json"));
  await expect(cache.get(root, "board.kicad_pcb", "link.json")).rejects.toThrow("symbolic link");
  await expect(cache.get(root, "board.kicad_pcb", "missing.json")).rejects.toThrow(
    "Preset was not found",
  );
});
