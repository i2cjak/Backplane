// End to end: connecting Google with the shared client (docs/bots.md) on
// headless hubs, against a stand-in for Google's token, revoke, Gmail and
// Calendar endpoints. Connect asks for Gmail and Calendar, shows Google's
// account chooser and needs nothing pasted; the redirect finishes the
// sign-in; a bot's tools run; a second sign-in adds a second account, and
// a tool's "account" picks whose token it uses; one account signs out
// alone; a secrets file from before accounts still works; a client of the
// user's own wins; a build with no shared client says so. Prints "ok ..."
// / "FAIL ..." lines.
//
//   bun test/tools/google_e2e.ts [BINARY] [WIREDIR]
//
// BINARY defaults to build/backplane and must be built with
// BACKPLANE_GOOGLE_BAKE=0; WIREDIR to build/wire (bend
// test/wire/index.html -o build/wire).
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, chmodSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const [bin = "build/backplane", wire = "build/wire"] = process.argv.slice(2);
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;

let failed = false;
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)?.slice(0, 400)}`);
  if (!ok) failed = true;
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function until<T>(ms: number, f: () => T | undefined | null | false): Promise<T | undefined> {
  const end = Date.now() + ms;
  for (;;) {
    const v = f();
    if (v) return v;
    if (Date.now() > end) return undefined;
    await sleep(50);
  }
}
function freePort(): number {
  const s = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {} } });
  const p = s.port;
  s.stop(true);
  return p;
}

// Google, as far as the hub sees it
const b64u = (s: string) => Buffer.from(s).toString("base64url");
const grants: Record<string, string>[] = [];
const revoked: string[] = [];
const bearers: string[] = [];
// the code names the account: 4/0Ab* signs in cat, 4/0Ad* dog
const who = (code: string) => (code.startsWith("4/0Ad") ? "dog" : "cat");
const google = Bun.serve({
  hostname: "127.0.0.1",
  port: 0,
  async fetch(req) {
    const u = new URL(req.url);
    bearers.push(req.headers.get("authorization") ?? "");
    if (req.method === "POST" && u.pathname === "/token") {
      const f = Object.fromEntries(new URLSearchParams(await req.text()));
      grants.push(f);
      const w = who(f.code ?? "");
      const id_token = `${b64u("{}")}.${b64u(JSON.stringify({ email: `${w}@example.com` }))}.sig`;
      return Response.json({ access_token: `at-${w}-${grants.length}`, expires_in: 3600, refresh_token: `rt-${w}`, id_token, token_type: "Bearer" });
    }
    if (u.pathname === "/revoke") {
      revoked.push(new URLSearchParams(await req.text()).get("token") ?? "");
      return new Response("{}");
    }
    if (u.pathname === "/gmail/v1/users/me/messages") return Response.json({ resultSizeEstimate: 0 });
    if (u.pathname === "/calendar/v3/calendars/primary/events")
      return Response.json({ timeZone: "UTC", items: [{ id: "ev1", summary: "Board bring-up", start: { dateTime: "2026-09-28T09:00:00Z" }, end: { dateTime: "2026-09-28T10:00:00Z" } }] });
    return new Response("not here", { status: 404 });
  },
});
const G = `http://127.0.0.1:${google.port}`;

const root = mkdtempSync(join(tmpdir(), "bp-google-e2e-"));
const fake = join(root, "bin");
mkdirSync(fake);
for (const n of ["claude", "codex", "grok"]) {
  writeFileSync(join(fake, n), "#!/bin/sh\nexit 1\n");
  chmodSync(join(fake, n), 0o755);
}

type Hub = { port: number; proc: ReturnType<typeof Bun.spawn>; ws: WebSocket; seen: any[]; replies: Map<number, any>; n: number };
async function start(name: string, env: Record<string, string>): Promise<Hub> {
  const port = freePort();
  const proc = Bun.spawn([resolve(bin), "--home", join(root, name), "--port", String(port), "--no-tailscale"], {
    env: { ...process.env, HOME: join(root, "user"), DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NO_UPDATE: "1", BACKPLANE_PEERS: "",
      BACKPLANE_GOOGLE_OAUTH: G, BACKPLANE_GOOGLE_API: G, PATH: `${fake}:${process.env.PATH}`, ...env },
    stdout: "ignore",
    stderr: process.env.E2E_LOG ? "inherit" : "ignore",
  });
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(`http://127.0.0.1:${port}/hello`)).status === 200) break;
    } catch {}
    await sleep(100);
  }
  const h: Hub = { port, proc, ws: null as any, seen: [], replies: new Map(), n: 0 };
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => {
    const o = JSON.parse(W.decode(new Uint8Array(e.data as ArrayBuffer)));
    for (const c of o.items ?? []) h.seen.push(c);
    if (o.t === "reply") h.replies.set(Number(o.id), o);
  };
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  h.ws = ws;
  return h;
}
async function rpc(h: Hub, m: string, p: object): Promise<any> {
  const id = ++h.n;
  h.ws.send(W.encode(JSON.stringify({ id, m, p })));
  return await until(10000, () => h.replies.get(id));
}
const op = (h: Hub, o: string, extra: object = {}) => rpc(h, "bots.google", { op: o, clientId: "", clientSecret: "", pasted: "", ...extra });
const tool = (h: Hub, th: string, name: string, args: object = {}) =>
  fetch(`http://127.0.0.1:${h.port}/mcp/${th}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 9, method: "tools/call", params: { name, arguments: args } }),
  }).then((r) => r.json()).then((r: any) => String(r?.result?.content?.[0]?.text ?? JSON.stringify(r)));

const hubs: Hub[] = [];
try {
  mkdirSync(join(root, "user"));
  const a = await start("shared", { BACKPLANE_GOOGLE_CLIENT_ID: "shared-id.apps.googleusercontent.com", BACKPLANE_GOOGLE_CLIENT_SECRET: "shared-secret" });
  hubs.push(a);

  const s0 = await op(a, "status");
  check("status before: not connected", s0?.ok && s0.google === "Not connected.", s0);

  const c = await op(a, "connect");
  const url = new URL(c?.googleUrl ?? "http://x/");
  const scope = url.searchParams.get("scope") ?? "";
  check("connect needs nothing pasted", c?.ok && url.host === "accounts.google.com", c);
  check("connect uses the shared client", url.searchParams.get("client_id") === "shared-id.apps.googleusercontent.com", url.search);
  check("the shared client asks for Gmail and Calendar", scope.includes("calendar.events") && scope.includes("gmail.modify"), scope);
  check("with Google's account chooser", url.searchParams.get("prompt") === "select_account consent", url.search);
  check("with PKCE", url.searchParams.get("code_challenge_method") === "S256" && (url.searchParams.get("code_challenge") ?? "").length === 43);

  const pend = await op(a, "status");
  check("status while waiting", String(pend?.google).startsWith("Waiting for Google"), pend);

  // a sign-in started on another of the owner's hubs lands here (Google
  // always sends the browser to 127.0.0.1): sent on to that hub, once
  const other = `zz.${b64u("http://box.tail1.ts.net:3787")}`;
  const hop = await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${other}&code=4%2F0Ab`, { redirect: "manual" });
  check("another hub's sign-in is sent on to it", hop.status === 302 && hop.headers.get("location") === `http://box.tail1.ts.net:3787/oauth/google?state=${other}&code=4%2F0Ab&hop=1`, [hop.status, hop.headers.get("location")]);
  const again = await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${other}&code=4%2F0Ab&hop=1`, { redirect: "manual" });
  check("but only once", again.status === 200 && (await again.text()).includes("paste this page"), again.status);
  const evil = await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=zz.${b64u("https://evil.example.com")}&code=c`, { redirect: "manual" });
  check("and only to a tailnet machine", evil.status === 200, evil.status);
  check("none of that traded a code", grants.length === 0, grants);

  const back = await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${url.searchParams.get("state")}&code=4%2F0Ab&scope=${encodeURIComponent(scope)}`);
  const page = await back.text();
  check("the redirect finishes the sign-in", back.status === 200 && page.includes("Google is connected"), page.slice(0, 300));
  const g = grants.at(-1) ?? {};
  check("the code is traded with the shared client and the verifier",
    g.grant_type === "authorization_code" && g.client_id === "shared-id.apps.googleusercontent.com" && g.client_secret === "shared-secret" && (g.code_verifier ?? "").length > 40, g);

  const s1 = await op(a, "status");
  check("status after: connected, Gmail and Calendar", s1?.google === "Connected as cat@example.com (Gmail and Calendar).", s1);
  check("status lists the account", s1?.googleAccounts === "cat@example.com", s1);

  const bot = await rpc(a, "bots.create", { name: "miso" });
  const set = await until(8000, () => a.seen.find((x) => x.$ === "BotSet" && x.id === bot?.bot));
  const th: string = set?.thread ?? "";
  check("a bot to call from", !!th, bot);
  const ev = await tool(a, th, "calendar_events");
  check("calendar_events works on the shared link", ev.includes("Board bring-up"), ev);
  const gm = await tool(a, th, "gmail_search");
  check("gmail tools run on the shared link", gm.includes("No messages"), gm);

  // a phone signs in through its own loopback listener: the sign-in
  // begins with the phone's redirect and finishes with what it caught
  const phone = "http://127.0.0.1:49152/oauth/google";
  const cp = await op(a, "connect", { redirect: phone });
  const up = new URL(cp?.googleUrl ?? "http://x/");
  check("a phone's loopback redirect begins its sign-in", up.searchParams.get("redirect_uri") === phone, up.search);
  const ce = await op(a, "connect", { redirect: "http://evil.example.com/oauth/google" });
  const ue = new URL(ce?.googleUrl ?? "http://x/");
  check("any other redirect is the hub's own", ue.searchParams.get("redirect_uri") === `http://127.0.0.1:${a.port}/oauth/google`, ue.search);
  const cp2 = await op(a, "connect", { redirect: phone });
  const up2 = new URL(cp2?.googleUrl ?? "http://x/");
  const fin = await op(a, "finish", { pasted: `${phone}?state=${up2.searchParams.get("state")}&code=4%2F0Ab9&scope=x` });
  check("the phone's caught address finishes it", fin?.ok && String(fin?.google).startsWith("Connected as cat@example.com"), fin);
  check("the code is traded with the phone's redirect", grants.at(-1)?.redirect_uri === phone, grants.at(-1));

  // a second account
  const c2 = await op(a, "connect");
  const u2 = new URL(c2?.googleUrl ?? "http://x/");
  await (await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${u2.searchParams.get("state")}&code=4%2F0Ad`)).text();
  const s2 = await op(a, "status");
  check("a second sign-in adds an account", s2?.googleAccounts === "cat@example.com\ndog@example.com", s2);
  check("both in the status line", s2?.google === "Connected as cat@example.com, dog@example.com (Gmail and Calendar).", s2);
  const la = await tool(a, th, "google_accounts");
  check("google_accounts lists them, the default first", la.includes("cat@example.com\ndog@example.com"), la);
  bearers.length = 0;
  await tool(a, th, "calendar_events", { account: "dog@example.com" });
  check("account picks whose token a tool uses", bearers.some((b) => b.startsWith("Bearer at-dog-")) && !bearers.some((b) => b.includes("at-cat")), bearers);
  bearers.length = 0;
  await tool(a, th, "calendar_events");
  check("no account: the first", bearers.some((b) => b.startsWith("Bearer at-cat-")), bearers);
  const none = await tool(a, th, "calendar_events", { account: "fox@example.com" });
  check("an account not signed in is named", none.includes("no connected Google account fox@example.com") && none.includes("dog@example.com"), none);

  // signing in to an address already there replaces it
  const c3 = await op(a, "connect");
  const u3 = new URL(c3?.googleUrl ?? "http://x/");
  await (await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${u3.searchParams.get("state")}&code=4%2F0Ab2`)).text();
  const s3a = await op(a, "status");
  check("the same account again replaces it", s3a?.googleAccounts === "cat@example.com\ndog@example.com", s3a);

  const out = await op(a, "disconnect", { account: "dog@example.com" });
  check("one account signs out alone", out?.googleAccounts === "cat@example.com", out);
  check("its token is revoked, the other's kept", revoked.includes("rt-dog") && !revoked.includes("rt-cat"), revoked);

  const d = await op(a, "disconnect");
  check("disconnect with no account signs out all", d?.google === "Not connected." && d?.googleAccounts === "", d);

  const own = await op(a, "connect", { clientId: "own-id", clientSecret: "own-secret" });
  const ou = new URL(own?.googleUrl ?? "http://x/");
  check("a client of your own wins", ou.searchParams.get("client_id") === "own-id", own);
  check("and asks for Gmail too", (ou.searchParams.get("scope") ?? "").includes("gmail.modify"), ou.search);
  const back2 = await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${ou.searchParams.get("state")}&code=4%2F0Ac`);
  await back2.text();
  const s4 = await op(a, "status");
  check("own client: Gmail and Calendar", s4?.google === "Connected as cat@example.com (Gmail and Calendar).", s4);

  // a secrets file from before accounts
  mkdirSync(join(root, "legacy", "secrets"), { recursive: true });
  writeFileSync(join(root, "legacy", "secrets", "google.json"), JSON.stringify({ client_id: "own-id", client_secret: "own-secret",
    refresh_token: "rt-old", access_token: "at-old", expiry: 4102444800, email: "old@example.com", pending_verifier: "", pending_state: "", redirect: "" }));
  const l = await start("legacy", {});
  hubs.push(l);
  const sl = await op(l, "status");
  check("an old secrets file reads as one account", sl?.googleAccounts === "old@example.com", sl);
  const lbot = await rpc(l, "bots.create", { name: "tofu" });
  const lset = await until(8000, () => l.seen.find((x) => x.$ === "BotSet" && x.id === lbot?.bot));
  bearers.length = 0;
  await tool(l, lset?.thread ?? "", "calendar_events");
  check("and its token still works", bearers.includes("Bearer at-old"), bearers);

  const b = await start("bare", {});
  hubs.push(b);
  const s5 = await op(b, "status");
  check("no shared client: status says so", String(s5?.google).includes("no shared Google client"), s5);
  const c5 = await op(b, "connect");
  check("no shared client: connect asks for one", c5?.ok === false || String(c5?.error ?? "").includes("no shared Google client"), c5);
} finally {
  for (const h of hubs) {
    h.ws?.close();
    h.proc.kill();
    await h.proc.exited;
  }
  google.stop(true);
  rmSync(root, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
