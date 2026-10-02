// A client that stops reading cannot hold the hub. Starts a headless hub
// with a stand-in `claude` that answers a message with a flood of
// assistant messages and then a result. Client A connects (a raw socket,
// small receive buffer) and never reads; client B starts the turn. Its
// frames fill A's queue (1024) and socket, so the hub's next send to A
// would wait; the writer's deadline (server.bend's Conn.deadline, 10 s)
// fails, closes A's channel and shuts its socket. Checks B still gets the
// turn's end and an answer to a request in time, A is dropped (its socket
// ends), and a client reconnecting from the start gets exactly what B
// holds. Twice.
//
//   bun test/tools/stall_e2e.ts [BINARY] [WIREDIR]
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const [bin = "build/backplane", wire = "build/wire"] = process.argv.slice(2);
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const root = mkdtempSync(join(tmpdir(), "bp-stall-"));
const fake = join(root, "bin");
mkdirSync(fake);
const pad = "x".repeat(3000);
writeFileSync(join(fake, "claude"), `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'"type":"user"'*)
      printf '%s\\n' '{"type":"system","subtype":"init","session_id":"sess-1","cwd":"/tmp","tools":["Bash"],"model":"fake","permissionMode":"default"}'
      i=0
      while [ $i -lt 4000 ]; do
        printf '{"type":"assistant","message":{"id":"m%s-%s","role":"assistant","content":[{"type":"text","text":"%s ${pad}"}],"usage":{"input_tokens":1}},"session_id":"sess-1"}\\n' "$$" "$i" "$i"
        i=$((i+1))
      done
      printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"sess-1"}' ;;
  esac
done
`);
chmodSync(join(fake, "claude"), 0o755);
for (const n of ["codex", "grok"]) {
  writeFileSync(join(fake, n), "#!/bin/sh\nexit 1\n");
  chmodSync(join(fake, n), 0o755);
}
const stalled = join(root, "stalled.py");
writeFileSync(stalled, `import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
s.connect(("127.0.0.1", int(sys.argv[1])))
s.sendall(b"GET /ws HTTP/1.1\\r\\nHost: x\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\\r\\nSec-WebSocket-Version: 13\\r\\n\\r\\n")
print("connected", flush=True)
time.sleep(float(sys.argv[2]))
s.settimeout(10)
total = 0
try:
    while True:
        d = s.recv(65536)
        if not d:
            print("EOF", total, flush=True)
            break
        total += len(d)
except Exception as e:
    print("ERR", e, total, flush=True)
`);
const home = join(root, "home");
const proj = join(root, "proj");
mkdirSync(proj);

function freePort(): number {
  const s = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {} } });
  const p = s.port;
  s.stop(true);
  return p;
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

let fail = 0;
const check = (ok: boolean, what: string) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) fail++;
};

const port = freePort();
const proc = Bun.spawn([resolve(bin), "--home", home, "--port", String(port), "--no-tailscale"], {
  env: { ...process.env, DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NO_UPDATE: "1", BACKPLANE_PEERS: "", BACKPLANE_GOOGLE_BAKE: "0", PATH: `${fake}:${process.env.PATH}` },
  stdout: "ignore",
  stderr: "ignore",
});

type Client = { seen: any[]; replies: Set<number>; send: (m: string, p: object) => number; close: () => void; origin: string };
async function connect(query = ""): Promise<Client> {
  const seen: any[] = [];
  const replies = new Set<number>();
  let origin = "";
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws${query}`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => {
    const text = typeof e.data === "string";
    let o: any = null;
    try { o = JSON.parse(text ? (e.data as string) : W.decode(new Uint8Array(e.data as ArrayBuffer))); } catch {}
    if (o?.origin) origin = o.origin;
    if (o?.id !== undefined && (o?.ok !== undefined || o?.error !== undefined || o?.result !== undefined)) replies.add(Number(o.id));
    for (const c of o?.items ?? []) seen.push(c);
  };
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0;
  return {
    seen, replies,
    get origin() { return origin; },
    send: (m, p) => { ws.send(W.encode(JSON.stringify({ id: ++id, m, p }))); return id; },
    close: () => ws.close(),
  } as Client;
}

try {
  for (let i = 0; i < 200; i++) {
    try {
      if ((await fetch(`http://127.0.0.1:${port}/hello`)).status === 200) break;
    } catch {}
    await sleep(100);
  }
  const b = await connect();
  b.send("project.add", { path: proj });
  const pc = await until(10000, () => b.seen.find((c) => c.$ === "ProjectCreated"));
  if (!pc) throw new Error("no project");
  b.send("setting.set", { key: "restart.continue", value: "off" });

  for (const round of [1, 2]) {
    const n = b.seen.filter((c) => c.$ === "ThreadCreated").length;
    b.send("thread.create", { project: pc.id, title: `flood ${round}`, env: "local", provider: "claude" });
    const th = await until(10000, () => b.seen.filter((c) => c.$ === "ThreadCreated")[n]);
    if (!th) throw new Error("no thread");
    const a = Bun.spawn(["python3", stalled, String(port), "45"], { stdout: "pipe", stderr: "inherit" });
    const out = new Response(a.stdout).text();
    await sleep(1000);
    const t0 = Date.now();
    b.send("turn.start", { thread: th.id, text: "flood", msg: `c-stall-${round}` });
    const done = await until(60000, () => b.seen.find((c) => c.$ === "TurnChanged" && c.thread === th.id && JSON.stringify(c).includes("Completed")));
    check(!!done, `round ${round}: B saw the turn complete (${((Date.now() - t0) / 1000).toFixed(1)} s)`);
    const rid = b.send("thread.pin", { thread: th.id });
    const t1 = Date.now();
    const pinned = await until(15000, () => b.seen.find((c) => c.$ === "ThreadPinned" && c.thread === th.id));
    check(!!pinned, `round ${round}: a request after it is answered (${((Date.now() - t1) / 1000).toFixed(1)} s)`);
    const said = (await out).trim();
    check(said.includes("EOF"), `round ${round}: the stalled client was dropped (${said.replace(/\n/g, " | ")})`);
    await a.exited;
    const c = await connect(`?since=0`);
    await sleep(3000);
    check(c.seen.length === b.seen.length, `round ${round}: a client from the start holds what B holds (${c.seen.length} / ${b.seen.length})`);
    c.close();
  }
} finally {
  proc.kill(9);
  await proc.exited;
  if (process.env.KEEP) console.log(root); else rmSync(root, { recursive: true, force: true });
}
console.log(fail ? `${fail} failed` : "all ok");
process.exit(fail ? 1 : 0);
