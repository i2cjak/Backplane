// End to end: a window on another machine's hub (core/rview.bend, docs/bots.md
// "A window on another hub"). One headless hub owns a project holding a
// KiCad board (the ecc83 demo), a git commit of it, and things that must
// never leave it (.env, .git, a symlink out). A stand-in window, a plain
// HTTP client of the hub, lists the thread's viewer files (GET /view/ver),
// holds on the digest until a file changes (the long poll) and is woken by
// the change, fetches a file's bytes (/view/get) and a file of a commit
// (/view/git), and is refused ../, absolute and hidden paths, a symlink
// out, a thread the hub does not have, a git directory that is no history,
// a commit that is an option, and a client the hub does not let in (no
// token). Prints "ok ..." / "FAIL ..." lines and timings.
//
//   bun test/tools/remote_view_e2e.ts [BINARY] [WIREDIR]
//
// BINARY defaults to build/backplane (build/backplane-serve works too);
// WIREDIR to build/wire. Needs KiCad's ecc83 demo.
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, chmodSync, mkdirSync, existsSync, copyFileSync, symlinkSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const [bin = "build/backplane", wire = "build/wire"] = args.filter((a) => !a.startsWith("--"));
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;

let failed = false;
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)?.slice(0, 600)}`);
  if (!ok) failed = true;
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
function freePort(): number {
  const s = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {} } });
  const p = s.port;
  s.stop(true);
  return p;
}

const demo = "/usr/share/kicad/demos/ecc83";
if (!existsSync(`${demo}/ecc83-pp.kicad_pcb`)) {
  console.log("skip: KiCad's ecc83 demo is not installed");
  process.exit(0);
}

const root = mkdtempSync(join(tmpdir(), "bp-remote-view-e2e-"));
const fake = join(root, "bin");
mkdirSync(fake);
for (const n of ["claude", "codex", "grok"]) {
  writeFileSync(join(fake, n), "#!/bin/sh\nexit 1\n");
  chmodSync(join(fake, n), 0o755);
}

const port = freePort();
const home = join(root, "hub");
const project = join(root, "board");
mkdirSync(join(project, "hw"), { recursive: true });
for (const f of ["ecc83-pp.kicad_pro", "ecc83-pp.kicad_pcb", "ecc83-pp.kicad_sch"]) copyFileSync(`${demo}/${f}`, join(project, f));
copyFileSync(`${demo}/ecc83-pp.kicad_pcb`, join(project, "hw", "second.kicad_pcb"));
writeFileSync(join(project, ".env"), "SECRET=1\n");
writeFileSync(join(project, "mech.step"), "ISO-10303-21;\nEND-ISO-10303-21;\n");
symlinkSync("/etc", join(project, "hw", "etclink"));
symlinkSync("/etc/passwd", join(project, "leak.kicad_pcb"));
const git = (...a: string[]) => spawnSync("git", ["-C", project, "-c", "user.email=a@b", "-c", "user.name=x", ...a], { encoding: "utf8" });
git("init", "-q");
git("add", "ecc83-pp.kicad_pcb", "ecc83-pp.kicad_pro");
git("commit", "-qm", "first");
const sha = git("rev-parse", "HEAD").stdout.trim();
const committed = readFileSync(join(project, "ecc83-pp.kicad_pcb"));

const base = `http://127.0.0.1:${port}`;
let proc: ReturnType<typeof Bun.spawn> | null = null;
try {
  proc = Bun.spawn([resolve(bin), "--home", home, "--port", String(port), "--no-tailscale"], {
    env: { ...process.env, DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NO_UPDATE: "1", PATH: `${fake}:/usr/bin:/bin` },
    stdout: "ignore",
    stderr: "ignore",
  });
  for (let i = 0; ; i++) {
    try {
      if ((await fetch(`${base}/hello`)).status === 200) break;
    } catch {}
    if (i > 200) throw new Error("hub did not start");
    await sleep(100);
  }

  // a project and a thread, made as a client does
  const replies = new Map<number, any>();
  const seen: any[] = [];
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => {
    const o = JSON.parse(W.decode(new Uint8Array(e.data as ArrayBuffer)));
    for (const x of o.items ?? []) seen.push(x);
    if (o.t === "reply") replies.set(Number(o.id), o);
  };
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let n = 0;
  const until = async <T>(ms: number, f: () => T | undefined | null | false) => {
    for (const end = Date.now() + ms; ; await sleep(50)) {
      const v = f();
      if (v) return v;
      if (Date.now() > end) return undefined;
    }
  };
  const rpc = async (m: string, p: object) => {
    const id = ++n;
    ws.send(W.encode(JSON.stringify({ id, m, p })));
    return await until(20000, () => replies.get(id));
  };
  const added = await rpc("project.add", { path: project });
  const pc: any = await until(5000, () => seen.find((c) => c.$ === "ProjectCreated" && c.root === project));
  await rpc("thread.create", { project: pc?.id ?? added?.id, title: "REMOTE" });
  const th: string = ((await until(5000, () => seen.find((c) => c.$ === "ThreadCreated" && c.project === pc?.id))) as any)?.id;
  check("project and thread made", !!pc && !!th, [added]);

  const q = (o: Record<string, string>) => "?" + Object.entries(o).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&");
  const get = (path: string, o: Record<string, string>, init: RequestInit = {}) => fetch(`${base}${path}${q(o)}`, init);
  const ver = async (want = "", have = "") => {
    const r = await get("/view/ver", { thread: th, want, have });
    return { status: r.status, body: r.status === 200 ? await r.json() : await r.text() };
  };

  // the list
  const t0 = Date.now();
  const v1 = await ver();
  const res = v1.body?.result;
  const files = String(res?.files ?? "").split("\n").filter(Boolean).map((l: string) => l.split("\t")[0]);
  console.log(`  /view/ver first answer ${Date.now() - t0} ms (${files.length} files)`);
  check("the list answers with the folder, a digest and the files", v1.status === 200 && v1.body?.ok === true && res?.root === project && String(res?.ver).length > 0, v1);
  check("it holds the board, schematic, project and a model", ["ecc83-pp.kicad_pcb", "ecc83-pp.kicad_sch", "ecc83-pp.kicad_pro", "hw/second.kicad_pcb", "mech.step"].every((f) => files.includes(f)), files);
  check("nothing hidden or linked is listed", !files.some((f: string) => f.startsWith(".") || f.includes("/.") || f.includes("etclink") || f === "leak.kicad_pcb"), files);

  // a file's bytes
  const t1 = Date.now();
  const g1 = await get("/view/get", { thread: th, path: "ecc83-pp.kicad_pcb" });
  const bytes = Buffer.from(await g1.arrayBuffer());
  console.log(`  /view/get ${bytes.length} bytes ${Date.now() - t1} ms`);
  check("a file comes byte for byte", g1.status === 200 && bytes.equals(readFileSync(join(project, "ecc83-pp.kicad_pcb"))), g1.status);
  const g2 = await get("/view/get", { thread: th, path: "hw/second.kicad_pcb" });
  check("a file in a folder", g2.status === 200 && Buffer.from(await g2.arrayBuffer()).length === bytes.length);

  // the long poll
  const t2 = Date.now();
  const hold = new AbortController();
  const waiting = get("/view/ver", { thread: th, want: "", have: String(res.ver) }, { signal: hold.signal }).then((r) => r.status, () => "aborted");
  const early = await Promise.race([waiting, sleep(1500).then(() => "held")]);
  check("with the digest it holds while nothing changes", early === "held", early);
  appendFileSync(join(project, "ecc83-pp.kicad_pcb"), "\n");
  const woke = (await Promise.race([waiting, sleep(8000).then(() => "late")])) as any;
  const wokeMs = Date.now() - t2;
  console.log(`  long poll woken ${wokeMs} ms after it began (change at 1500 ms)`);
  check("a changed file wakes it", woke === 200 && wokeMs < 7000, woke);
  const v2 = await ver();
  check("the digest moved and the board's size with it", v2.body?.result?.ver !== res.ver && String(v2.body?.result?.files).includes(`ecc83-pp.kicad_pcb\t${bytes.length + 1}\t`), v2.body?.result);
  const idle = await Promise.race([ver("", String(v2.body.result.ver)).then((r) => r.status), sleep(2500).then(() => "held")]);
  check("an unchanged list is held, no polling answer", idle === "held", idle);

  // a file asked for by name
  const v3 = await ver("hw/second.kicad_pcb", "");
  check("a named file is listed", String(v3.body?.result?.files).includes("hw/second.kicad_pcb"), v3.body?.result);

  // a file of a commit
  const top = project;
  const hp = (g: string, c: string, rel: string) => `git\t${g}\t${c}\t${top.length}\t${top}/${rel}`;
  const gc = await get("/view/git", { thread: th, path: hp(`${project}/.git`, sha, "ecc83-pp.kicad_pcb") });
  check("a file of a commit is its committed bytes", gc.status === 200 && Buffer.from(await gc.arrayBuffer()).equals(committed), gc.status);
  const gm = await get("/view/git", { thread: th, path: hp(`${project}/.git`, sha, "nothere.kicad_pcb") });
  check("a file the commit lacks is 404", gm.status === 404, gm.status);

  // refusals
  const status = async (path: string, o: Record<string, string>, init: RequestInit = {}) => (await get(path, o, init)).status;
  check("../ is refused", (await status("/view/get", { thread: th, path: "../x" })) === 403 && (await status("/view/get", { thread: th, path: "hw/../../x" })) === 403);
  check("an absolute path is refused", (await status("/view/get", { thread: th, path: "/etc/passwd" })) === 403);
  check("a hidden file is refused", (await status("/view/get", { thread: th, path: ".env" })) === 403 && (await status("/view/get", { thread: th, path: ".git/config" })) === 403);
  check("a symlink out is not sent", (await status("/view/get", { thread: th, path: "leak.kicad_pcb" })) === 404 && (await status("/view/get", { thread: th, path: "hw/etclink/passwd" })) === 404);
  check("a list naming a hidden file or ../ is refused", (await status("/view/ver", { thread: th, want: "a\n.env" })) === 403 && (await status("/view/ver", { thread: th, want: "../x" })) === 403);
  check("a thread the hub does not have is refused", (await status("/view/get", { thread: "nope", path: "ecc83-pp.kicad_pcb" })) === 403 && (await status("/view/ver", { thread: "", want: "" })) === 403);
  check("a thread of another machine this hub does not mirror is refused", (await status("/view/get", { thread: "x~y", path: "a.kicad_pcb" })) === 403);
  check("a commit that is an option is refused", (await status("/view/git", { thread: th, path: hp(`${project}/.git`, "--output=/tmp/bp-x", "ecc83-pp.kicad_pcb") })) === 403);
  check("a git directory that is no history is refused", (await status("/view/git", { thread: th, path: hp("/etc", sha, "ecc83-pp.kicad_pcb") })) === 403);
  check("a path that climbs in a commit is refused", (await status("/view/git", { thread: th, path: hp(`${project}/.git`, sha, "../../etc/passwd") })) === 403);
  check("a live file is not a version", (await status("/view/git", { thread: th, path: "ecc83-pp.kicad_pcb" })) === 403);
  check("an unknown request is nothing", (await status("/view/other", { thread: th })) !== 200);

  // a client the hub does not let in: a request that came through Tailscale
  // (its identity header) carries the pairing token or is refused
  const token = readFileSync(join(home, "token"), "utf8").trim();
  const via = { headers: { "Tailscale-User-Login": "someone@example.com" } };
  check("no token through the tailnet: 401 on every request", (await status("/view/ver", { thread: th, want: "" }, via)) === 401 && (await status("/view/get", { thread: th, path: "ecc83-pp.kicad_pcb" }, via)) === 401 && (await status("/view/git", { thread: th, path: hp(`${project}/.git`, sha, "ecc83-pp.kicad_pcb") }, via)) === 401);
  check("a wrong token: 401", (await status("/view/get", { thread: th, path: "ecc83-pp.kicad_pcb", token: "0".repeat(token.length) }, via)) === 401);
  check("the token lets it in", (await status("/view/get", { thread: th, path: "ecc83-pp.kicad_pcb", token }, via)) === 200);
  ws.close();
} catch (e) {
  console.log(`FAIL error: ${e}`);
  failed = true;
} finally {
  if (proc) proc.kill();
  rmSync(root, { recursive: true, force: true });
}
console.log(failed ? "FAILED" : "all ok");
process.exit(failed ? 1 : 0);
