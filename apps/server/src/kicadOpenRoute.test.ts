// @effect-diagnostics nodeBuiltinImport:off globalDate:off
import { afterEach, expect, it, vi } from "vite-plus/test";
import * as HttpRouter from "effect/unstable/http/HttpRouter";
import * as Context from "effect/Context";
import { ChildProcess } from "node:child_process";
import * as NodeFS from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import { kicadOpenRouteLayer, kicadViewerSessions } from "./http.ts";
import { launchKiCadEditor } from "./kicad/KiCadExecutable.ts";

vi.mock("./kicad/KiCadExecutable.ts", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./kicad/KiCadExecutable.ts")>()),
  resolveKiCadEditor: () => "eeschema",
  launchKiCadEditor: vi.fn(),
}));
afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetAllMocks();
});

it("rejects missing or expired viewer credentials before launching an editor", async () => {
  const { handler, dispose } = HttpRouter.toWebHandler(kicadOpenRouteLayer, {
    disableLogger: true,
  });
  try {
    for (const suffix of ["", "?token=expired-viewer-session"]) {
      const response = await handler(
        new Request(`http://localhost/api/kicad/open${suffix}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ path: "main.kicad_sch" }),
        }),
        Context.empty(),
      );
      expect(response.status).toBe(401);
      expect(await response.text()).toBe("Viewer session expired");
    }
    expect(
      (await handler(new Request("http://localhost/api/kicad/open"), Context.empty())).status,
    ).toBe(404);
    expect(launchKiCadEditor).not.toHaveBeenCalled();
  } finally {
    await dispose();
  }
});

it("launches only a workspace KiCad file and reports process failures", async () => {
  vi.stubEnv("DISPLAY", ":fixture");
  const cwd = await NodeFS.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-kicad-open-"));
  await NodeFS.writeFile(NodePath.join(cwd, "main.kicad_sch"), "(kicad_sch (version 20231120))");
  await NodeFS.writeFile(NodePath.join(cwd, "notes.txt"), "notes");
  await NodeFS.symlink(NodeOS.tmpdir(), NodePath.join(cwd, "outside"));
  kicadViewerSessions.set("test-valid", { cwd, expiresAt: Date.now() + 60_000 });
  const { handler, dispose } = HttpRouter.toWebHandler(kicadOpenRouteLayer, {
    disableLogger: true,
  });
  const post = (path: string) =>
    handler(
      new Request("http://localhost/api/kicad/open?token=test-valid", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path }),
      }),
      Context.empty(),
    );
  try {
    const child = new ChildProcess();
    const unref = vi.spyOn(child, "unref").mockImplementation(() => {});
    vi.mocked(launchKiCadEditor).mockResolvedValue(child);
    const response = await post("main.kicad_sch");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, editor: "eeschema" });
    expect(launchKiCadEditor).toHaveBeenCalledExactlyOnceWith(
      "schematic",
      NodePath.join(cwd, "main.kicad_sch"),
      cwd,
    );
    expect(unref).toHaveBeenCalledOnce();
    vi.mocked(launchKiCadEditor).mockClear();
    for (const path of [
      "../outside.kicad_sch",
      "outside/outside.kicad_sch",
      "notes.txt",
      "missing.kicad_pcb",
    ]) {
      expect((await post(path)).status).toBe(404);
    }
    expect(launchKiCadEditor).not.toHaveBeenCalled();
    vi.mocked(launchKiCadEditor).mockRejectedValue(new Error("spawn failed"));
    expect((await post("main.kicad_sch")).status).toBe(503);
  } finally {
    kicadViewerSessions.delete("test-valid");
    await dispose();
    await NodeFS.rm(cwd, { recursive: true, force: true });
  }
});
