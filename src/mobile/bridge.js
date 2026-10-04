// Backplane phone bridge.
//
// Loaded into JavaScriptCore (iOS) or a JavaScriptSandbox isolate
// (Android). It only moves data: the hub's CBOR frames in (as base64), the
// screen JSON and commands out, as strings. The native app owns the socket and the views;
// app.bend decides everything (AGENTS.md: the UI is dumb).
//
// Frames are decoded here rather than by Cbor.decode in Bend: neither
// engine has a JIT in an app, and a 900 KB snapshot took 8 s in Bend
// against 0.5 s here. The result is the same Json tree (cbor.bend is the
// wire format; its dictionaries come from there).

import App from "./app.bend";
import { cbor as decode } from "../web/wire.js";

function* each(list) {
  for (let xs = list; xs && xs.$ === "Con"; xs = xs.tail) yield xs.head;
}

const secs = (n) => BigInt(Math.floor(Number(n)));

const listed = (list) => Array.from(each(list));
const KEYS = listed(App.cbor_keys());
const WORDS = listed(App.cbor_words());

// base64 to bytes (neither engine has atob)
const B64 = new Int16Array(128).fill(-1);
for (let i = 0; i < 64; i += 1) B64["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charCodeAt(i)] = i;
function bytes(b64) {
  const out = new Uint8Array((b64.length * 3) >> 2);
  let n = 0, acc = 0, bits = 0;
  for (let i = 0; i < b64.length; i += 1) {
    const c = b64.charCodeAt(i);
    const v = c < 128 ? B64[c] : -1;
    if (v < 0) continue;
    acc = ((acc << 6) | v) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[n++] = (acc >> bits) & 255;
    }
  }
  return out.subarray(0, n);
}

// The client state as flat text and back, with no recursion: Bend lists
// are chains of cells ({head, tail}) tens of thousands deep, and
// JSON.parse with a reviver recursed once per cell, overflowed the
// engine's stack on a real log and lost the kept state at every launch.
// Every object is a node in one array, named by its index; in a node a
// value [i] is node i, ["<digits>"] a BigInt, anything else itself.
// Shared parts are written once.
function flat(root) {
  const ids = new Map();
  const nodes = [];
  const ref = (v) => {
    if (typeof v === "bigint") return [v.toString()];
    if (v === null || typeof v !== "object") return v;
    let i = ids.get(v);
    if (i === undefined) {
      i = nodes.length;
      ids.set(v, i);
      nodes.push(v);
    }
    return [i];
  };
  const top = ref(root);
  const out = [];
  for (let k = 0; k < nodes.length; k += 1) {
    const v = nodes[k];
    if (Array.isArray(v)) out.push(v.map(ref));
    else {
      const o = {};
      for (const key in v) {
        const x = v[key];
        if (x !== undefined && typeof x !== "function") o[key] = ref(x);
      }
      out.push(o);
    }
  }
  return JSON.stringify({ flat: 1, top, nodes: out });
}

function unflat(text) {
  const d = JSON.parse(text);
  if (!d || d.flat !== 1) throw new Error("state");
  const nodes = d.nodes;
  const val = (x) => (Array.isArray(x) ? (typeof x[0] === "number" ? nodes[x[0]] : BigInt(x[0])) : x);
  for (const n of nodes) {
    if (Array.isArray(n)) for (let i = 0; i < n.length; i += 1) n[i] = val(n[i]);
    else for (const key in n) n[key] = val(n[key]);
  }
  return val(d.top);
}

let hubs = null;
// the drafts kept on this phone, {"<hub>|<thread>": text}
let kept = {};

// kept drafts into the clients of the hubs they belong to
function restore() {
  for (const [k, text] of Object.entries(kept)) {
    const i = k.indexOf("|");
    if (i > 0 && typeof text === "string") hubs = App.restore(hubs, k.slice(0, i), k.slice(i + 1), text);
  }
}

// every call answers {"screen": <screen>, "cmds": [...]} as one string;
// a send names the hub it goes to; alerts ride along as
// {"type": "notify", ...} commands
// a Bend JSON value (core/json.bend: Arr/Obj hold Item/Field chains ending
// in End) as a plain JS value, for the engine's own JSON.stringify
function plain(j) {
  switch (j.$) {
    case "Null":
      return null;
    case "Flag":
      return j.value;
    case "Num": {
      const n = Number(j.raw);
      return Number.isFinite(n) ? n : j.raw;
    }
    case "Str":
      return j.text;
    case "Arr": {
      const a = [];
      for (let c = j.items; c.$ === "Item"; c = c.tail) a.push(plain(c.head));
      return a;
    }
    case "Obj": {
      const o = {};
      for (let c = j.fields; c.$ === "Field"; c = c.tail) o[c.key] = plain(c.value);
      return o;
    }
    default:
      return null;
  }
}

// a frame that could change the screen came while more waited behind it
// (so it built none): the next call builds one, whatever that frame is
let owed = false;

function out(cmds, quiet, alerts) {
  if (!quiet) owed = false;
  const cs = [];
  for (const h of each(cmds)) {
    const c = h.cmd;
    if (c.$ === "Send") cs.push({ type: "send", hub: h.hub, data: App.wire(c.text) });
    else if (c.$ === "Copy") cs.push({ type: "copy", text: c.text });
    else if (c.$ === "Focus") cs.push({ type: "focus", id: c.id });
    else if (c.$ === "Scroll") cs.push({ type: "scroll" });
    // a client action come due (the design history playing), back to the hub that asked
    else if (c.$ === "Later") cs.push({ type: "later", ms: Number(c.ms), action: c.action, value: h.hub + "|" + c.value });
    // show an entry of the thread (the history's way back to it)
    else if (c.$ === "Jump") cs.push({ type: "jump", id: c.id });
    // the native side writes it down at once; "" forgets it
    else if (c.$ === "Keep") {
      const key = h.hub + "|" + c.thread;
      if (c.text) kept[key] = c.text;
      else delete kept[key];
      cs.push({ type: "keep", thread: key, text: c.text });
    }
  }
  for (const a of alerts ?? []) cs.push({ type: "notify", ...a });
  return '{"screen":' + (quiet ? "null" : JSON.stringify(plain(App.screenj(hubs)))) + ',"cmds":' + JSON.stringify(cs) + "}";
}

// a step's answer: the hubs after it, its commands and alerts
function step(r, quiet) {
  hubs = r.hubs;
  return out(r.cmds, quiet, JSON.parse(App.alerts(r)));
}

globalThis.Backplane = {
  // cid: this phone's id, part of every message id (a resend is stored once);
  // drafts: the drafts it kept, as JSON {"<hub>|<thread>": text}
  start(cid, drafts) {
    hubs = App.init(secs(Date.now() / 1000), cid);
    try {
      kept = JSON.parse(drafts ?? "{}") ?? {};
    } catch {
      kept = {};
    }
    return out(null);
  },
  // the hubs paired, as their keys (host:port) in order
  hubs(keys) {
    hubs = App.hubs(hubs, JSON.stringify(keys));
    restore();
    return out(null);
  },
  // hub k's socket query: resume from what this app already holds
  resume(k) {
    return JSON.stringify({ since: App.seq(hubs, k), origin: App.origin(hubs, k) });
  },
  screen() {
    return out(null);
  },
  // a cat's rig (JSON text) for the key a screen names it by, "look:mood"
  cat(key) {
    const i = String(key).indexOf(":");
    return App.cat(BigInt(Number(String(key).slice(0, i)) || 0), String(key).slice(i + 1));
  },
  // a binary frame from hub k, as base64
  // quiet: more frames wait behind this one, so no screen is built for it
  // (only the last of a burst is drawn: terminal echoes, streamed text)
  // (nor for streamed text the screen does not show: App.shows, that is
  // Hubs.redraw, laws hubs_redraw_*; every token of every agent at work is
  // a frame; anything else from any paired hub redraws the merged screen)
  // owe: the app dropped a screen since (a newer call was waiting), so
  // this one builds one
  recv(k, data, quiet, owe) {
    const o = decode(bytes(data), KEYS, WORDS);
    const r = App.recv(hubs, k, o);
    const shows = App.shows(r.hubs, k, o);
    if (owe === true || (quiet === true && shows)) owed = true;
    return step(r, quiet === true || !(shows || owed));
  },
  // The whole client state as text, kept by the app when it leaves the
  // foreground: the next launch load()s it instead of folding every event
  // again (on QuickJS a few thousand took seconds), and resume() then asks
  // each hub only for what came since. The state is plain data (objects,
  // strings, booleans, BigInt naturals), written flat (flat()).
  save() {
    return flat(hubs);
  },
  load(text) {
    try {
      hubs = App.stale(unflat(text));
    } catch {
      return "";
    }
    return out(null);
  },
  register(platform, token, kind, thread, env, bundle) {
    return step(App.register(hubs, platform, token, kind, thread, env, bundle), true);
  },
  act(action, value) {
    return step(App.act(hubs, action, value));
  },
  // an action whose screen the native side already shows (typing a draft),
  // unless it changed what the composer offers (app.bend's offer)
  quiet(action, value) {
    const was = App.offer(hubs);
    const r = App.act(hubs, action, value);
    return step(r, App.offer(r.hubs) === was);
  },
  // hub k's socket opened or closed; a new connection re-asks for the
  // viewer's plot
  // quiet: no screen (the hubs marked offline after load(), before the
  // screen that follows)
  // (no screen either when the hub already was so: app.bend's online_same)
  online(k, b, quiet) {
    const same = App.online_same(hubs, k, !!b);
    return step(App.online(hubs, k, !!b), quiet === true || same);
  },
  tick(now) {
    return step(App.tick(hubs, secs(now)));
  },
};
