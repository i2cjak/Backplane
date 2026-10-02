// Agent containment, end to end (core/contain.bend; server.bend's Ctn.*):
// every agent runs in its own memory-limited systemd scope, so a runaway
// ends only its own tree. A headless hub with the stand-in `claude`
// (test/tools/claude_standin.ts) and the test-only setting agent.memory.mb
// (200). One thread's agent allocates past it (600 MB at most, never
// gigabytes): the hub survives, its turn fails saying it ran out of memory,
// and another thread keeps working. Skipped cleanly (exit 0) where
// `systemd-run --user` is unavailable or does not enforce MemoryMax.
//
//   bun test/tools/contain_e2e.ts [BINARY] [WIREDIR]
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const skip = (why: string): never => {
  console.log(`skip: ${why}`);
  process.exit(0);
};

// can a user scope be made, and does it hold a limit?
{
  const q = Bun.spawnSync(["systemctl", "--user", "show-environment"], { stdout: "ignore", stderr: "ignore" });
  if (q.exitCode !== 0) skip("no user systemd");
  const t = Bun.spawnSync(["systemd-run", "--user", "--scope", "--quiet", "-p", "MemoryMax=64M", "-p", "MemorySwapMax=0", "--",
    process.execPath, "-e", "const k=[];for(let i=0;i<8;i++)k.push(Buffer.alloc(20*1024*1024,1));"], { stdout: "ignore", stderr: "ignore" });
  if (t.exitCode === 0) skip("MemoryMax is not enforced for user scopes here");
}

const [bin = "build/backplane", wire = "build/wire"] = process.argv.slice(2);
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;

const root = mkdtempSync(join(tmpdir(), "bp-contain-"));
const fake = join(root, "bin");
const log = join(root, "claude.log");
mkdirSync(fake);
writeFileSync(join(fake, "claude"), `#!/bin/sh\nexec ${process.execPath} ${resolve("test/tools/claude_standin.ts")} "$@"\n`);
chmodSync(join(fake, "claude"), 0o755);
// systemctl's `show` and `stop` hang while the flag file exists (a user manager that does not answer)
const slow = join(root, "slow");
writeFileSync(join(fake, "systemctl"), `#!/bin/sh\nif [ -e ${slow} ]; then case "$2" in show|stop|reset-failed) sleep 8;; esac; fi\nexec /usr/bin/systemctl "$@"\n`);
chmodSync(join(fake, "systemctl"), 0o755);
for (const n of ["codex", "grok"]) {
  writeFileSync(join(fake, n), "#!/bin/sh\nexit 1\n");
  chmodSync(join(fake, n), 0o755);
}
const home = join(root, "home");
const proj = join(root, "proj");
mkdirSync(proj);
mkdirSync(home);
writeFileSync(join(home, "events.jsonl"), "");

function freePort(): number {
  for (let p = 39300 + (process.pid % 90); p < 39400; p++) {
    try {
      Bun.listen({ hostname: "127.0.0.1", port: p, socket: { data() {} } }).stop(true);
      return p;
    } catch {}
  }
  throw new Error("no free port");
}
const until = async <T>(ms: number, f: () => T | undefined) => {
  const end = Date.now() + ms;
  for (;;) {
    const v = f();
    if (v) return v;
    if (Date.now() > end) return undefined;
    await sleep(50);
  }
};
const lines = () => (existsSync(log) ? readFileSync(log, "utf8").split("\n").filter(Boolean) : []);
let fail = 0;
const check = (ok: boolean, what: string) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) fail++;
};

const port = freePort();
const proc = Bun.spawn([resolve(bin), "--home", home, "--port", String(port), "--no-tailscale", "--foreground"], {
  env: { ...process.env, DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NO_UPDATE: "1", BACKPLANE_PEERS: "", BACKPLANE_GOOGLE_BAKE: "0", FAKE_LOG: log,
    BP_WORK_MS: "300", PATH: `${fake}:${process.env.PATH}` },
  stdout: "ignore",
  stderr: "ignore",
});
try {
  for (let i = 0; i < 200; i++) {
    try { if ((await fetch(`http://127.0.0.1:${port}/hello`)).status === 200) break; } catch {}
    await sleep(100);
  }
  const seen: any[] = [];
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => {
    let o: any = null;
    try { o = JSON.parse(typeof e.data === "string" ? (e.data as string) : W.decode(new Uint8Array(e.data as ArrayBuffer))); } catch {}
    for (const c of o?.items ?? []) seen.push(c);
  };
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0;
  const send = (m: string, p: object) => ws.send(W.encode(JSON.stringify({ id: ++id, m, p })));
  const turns = (th: string) => seen.filter((x) => x.$ === "TurnChanged" && x.thread === th).map((x) => String(x.state));
  const exits = (th: string) => seen.filter((x) => x.$ === "ActivityLogged" && x.thread === th && x.kind === "exit");
  send("setting.set", { key: "agent.memory.mb", value: "200" });
  await until(5000, () => seen.find((c) => c.$ === "SettingSet" && c.key === "agent.memory.mb"));
  send("project.add", { path: proj });
  const pc = await until(10000, () => seen.find((x) => x.$ === "ProjectCreated"));
  const made = async (title: string) => {
    const n = seen.filter((x) => x.$ === "ThreadCreated").length;
    send("thread.create", { project: pc.id, title, env: "local", provider: "claude" });
    return (await until(10000, () => seen.filter((x) => x.$ === "ThreadCreated")[n]))?.id as string;
  };

  // a healthy thread first, so something is streaming when the other dies
  const ok1 = await made("healthy");
  send("turn.start", { thread: ok1, text: "mode:plain hello", msg: "c-1" });
  await until(15000, () => turns(ok1).at(-1) === "completed" ? true : undefined);
  check(turns(ok1).at(-1) === "completed", `a contained agent works (${turns(ok1).join(",")})`);
  const scoped = lines().some((l) => l.startsWith("START"));
  check(scoped, "the agent started");

  // dollar text in an argument reaches the agent as it is (systemd-run
  // would expand ${VAR} without --expand-environment=no)
  const lit = "m-${BP_EXAMPLE}-$HOME-$$";
  send("thread.modes", { thread: ok1, model: lit });
  send("turn.start", { thread: ok1, text: "dollars", msg: "c-d" });
  await until(15000, () => lines().some((l) => l.startsWith("ARGV") && l.includes(JSON.stringify(lit).slice(1, -1))) ? true : undefined);
  check(lines().some((l) => l.startsWith("ARGV") && l.includes(JSON.stringify(lit).slice(1, -1))), "dollar text in an argument reaches the agent literally");
  await until(15000, () => turns(ok1).filter((s) => s === "completed").length >= 2 ? true : undefined);

  const bad = await made("runaway");
  send("turn.start", { thread: bad, text: "mode:oom go", msg: "c-2" });
  await until(15000, () => turns(bad).at(-1) === "failed" ? true : undefined);
  await sleep(500);
  const ex = exits(bad);
  check(turns(bad).at(-1) === "failed", `the runaway's turn fails (${turns(bad).join(",")})`);
  check(ex.length === 1 && /out of memory \(limit 200 MB\)/.test(String(ex[0]?.text ?? ex[0]?.detail ?? ex[0]?.summary ?? JSON.stringify(ex[0]))),
    `it says it ran out of memory (${JSON.stringify(ex[0])})`);
  check(!lines().some((l) => l.startsWith("SURVIVED")), "the allocation never completed");

  // the hub lives and another thread still works
  const hello = await fetch(`http://127.0.0.1:${port}/hello`).then((r) => r.status).catch(() => 0);
  check(hello === 200, `the hub answers (${hello})`);
  send("turn.start", { thread: ok1, text: "again", msg: "c-3" });
  await until(15000, () => turns(ok1).filter((s) => s === "completed").length >= 3 ? true : undefined);
  check(turns(ok1).filter((s) => s === "completed").length >= 3, `another thread keeps working (${turns(ok1).join(",")})`);

  // the scope's account is asked off the hub's inbox: while a runaway's
  // exit waits on a user manager that does not answer, the hub still serves
  writeFileSync(slow, "");
  const alloc0 = lines().filter((l) => l.startsWith("ALLOC")).length;
  const bad2 = await made("runaway 2");
  send("turn.start", { thread: bad2, text: "mode:oom go", msg: "c-4" });
  await until(15000, () => lines().filter((l) => l.startsWith("ALLOC")).length > alloc0 ? true : undefined);
  await sleep(1500);
  const t0 = Date.now();
  send("setting.set", { key: "probe.key", value: "x" });
  const probe = await until(10000, () => seen.find((c) => c.$ === "SettingSet" && c.key === "probe.key"));
  const took = Date.now() - t0;
  check(!!probe && took < 1500, `the hub answers while an exit waits on systemctl (${took} ms)`);
  check(turns(bad2).at(-1) !== "failed", "the runaway's account is still pending");
  await until(20000, () => turns(bad2).at(-1) === "failed" ? true : undefined);
  check(turns(bad2).at(-1) === "failed", `its turn fails in the end (${turns(bad2).join(",")})`);
} finally {
  proc.kill(9);
  await proc.exited;
  if (process.env.KEEP) console.log(root); else rmSync(root, { recursive: true, force: true });
}
console.log(fail ? `${fail} failed` : "all ok");
process.exit(fail ? 1 : 0);
