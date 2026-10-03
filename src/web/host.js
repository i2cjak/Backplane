// Backplane browser host.
//
// This file only moves data: JSON <-> Bend values, a keyed DOM patch of the
// Node tree app.bend's view returns, event delegation back to app.bend's
// act, and the socket. No product decision is made here (AGENTS.md: the UI
// is dumb).

import App from "./app.bend";
import * as Solid from "./solid.js";
import * as Plot2d from "./plot2d.js";

// JSON <-> Bend Json
// ------------------

function toJson(v) {
  if (v === null || v === undefined) return { $: "Null" };
  if (typeof v === "boolean") return { $: "Flag", value: v };
  if (typeof v === "number") return { $: "Num", raw: String(v) };
  if (typeof v === "string") return { $: "Str", text: v };
  if (Array.isArray(v)) {
    let items = { $: "End" };
    for (let i = v.length - 1; i >= 0; i -= 1) items = { $: "Item", head: toJson(v[i]), tail: items };
    return { $: "Arr", items };
  }
  let fields = { $: "End" };
  const keys = Object.keys(v);
  for (let i = keys.length - 1; i >= 0; i -= 1) {
    fields = { $: "Field", key: keys[i], value: toJson(v[keys[i]]), tail: fields };
  }
  return { $: "Obj", fields };
}

// bytes <-> Bend List<U32>
function toList(u8) {
  let xs = { $: "Nil" };
  for (let i = u8.length - 1; i >= 0; i -= 1) xs = { $: "Con", head: u8[i], tail: xs };
  return xs;
}

function fromList(xs) {
  const out = [];
  for (const b of each(xs)) out.push(b);
  return new Uint8Array(out);
}

function* each(list) {
  for (let xs = list; xs && xs.$ === "Con"; xs = xs.tail) yield xs.head;
}

// DOM patch
// ---------

const EVENTS = ["click", "input", "contextmenu"];

// icons (src/web/icon.bend) are inline SVG, which needs its namespace
const SVG_NS = "http://www.w3.org/2000/svg";
const SVG_TAGS = new Set(["svg", "path"]);

function create(v) {
  if (v.$ === "Txt") return document.createTextNode(v.text);
  const el = SVG_TAGS.has(v.tag) ? document.createElementNS(SVG_NS, v.tag) : document.createElement(v.tag);
  el.__v = { $: "El", tag: v.tag, key: v.key, attrs: { $: "Nil" }, kids: { $: "Nil" } };
  el.__kids = [];
  patch(el, v);
  return el;
}

// bots' cats: an <img data-cat="<look>:<mood>:<px>"> shows app.bend's
// SVG for that name, made once per name and kept
const CATS = new Map();
function catUri(name) {
  let u = CATS.get(name);
  if (u === undefined) {
    u = App.cat(name);
    CATS.set(name, u);
  }
  return u;
}

function setAttrs(el, oldAttrs, attrs) {
  const seen = new Set();
  for (const a of each(attrs)) {
    if (a.$ === "At") {
      seen.add(a.name);
      if (a.name === "value") {
        if (el.value !== a.value) el.value = a.value;
      } else if (el.getAttribute(a.name) !== a.value) {
        el.setAttribute(a.name, a.value);
        if (a.name === "data-cat") el.src = catUri(a.value);
      }
    } else {
      const name = "data-on-" + a.event;
      seen.add(name);
      if (el.getAttribute(name) !== a.action) el.setAttribute(name, a.action);
    }
  }
  for (const a of each(oldAttrs)) {
    const name = a.$ === "At" ? a.name : "data-on-" + a.event;
    if (!seen.has(name)) {
      if (name === "value") el.value = "";
      else el.removeAttribute(name);
    }
  }
}

function same(a, b) {
  return a.$ === b.$ && (a.$ === "Txt" || (a.tag === b.tag && a.key === b.key));
}

// make el (whose last vnode is el.__v) match v
function patch(el, v) {
  const old = el.__v;
  setAttrs(el, old.attrs, v.attrs);
  const kids = [...each(v.kids)];
  const prev = el.__kids;
  const byKey = new Map();
  const free = [];
  for (const p of prev) {
    if (p.v.$ === "El" && p.v.key) byKey.set(p.v.tag + "\u0000" + p.v.key, p);
    else free.push(p);
  }
  const next = [];
  let f = 0;
  for (let i = 0; i < kids.length; i += 1) {
    const k = kids[i];
    let hit = null;
    if (k.$ === "El" && k.key) {
      hit = byKey.get(k.tag + "\u0000" + k.key) ?? null;
      if (hit) byKey.delete(k.tag + "\u0000" + k.key);
    } else {
      while (f < free.length && !same(free[f].v, k)) f += 1;
      if (f < free.length) hit = free[f++];
    }
    let node;
    if (hit) {
      node = hit.node;
      if (k.$ === "Txt") {
        if (node.nodeValue !== k.text) node.nodeValue = k.text;
      } else if (hit.v !== k) {
        patch(node, k);
      }
      hit.used = true;
    } else {
      node = create(k);
    }
    const at = el.childNodes[i];
    if (at !== node) el.insertBefore(node, at ?? null);
    next.push({ v: k, node });
  }
  for (const p of prev) if (!p.used && p.node.parentNode === el) el.removeChild(p.node);
  for (const p of next) p.used = false;
  el.__kids = next;
  el.__v = v;
}

// Loop
// ----

const root = document.getElementById("root");
root.__v = { $: "El", tag: "div", key: "", attrs: { $: "Nil" }, kids: { $: "Nil" } };
root.__kids = [];

const now = () => BigInt(Math.floor(Date.now() / 1000));
// this browser's id: part of every message id, so a resend after a dropped
// link is recognised and stored once
const cid = (() => {
  let c = localStorage.getItem("backplane-cid");
  if (!c) {
    c = Array.from(crypto.getRandomValues(new Uint8Array(4)), (b) => b.toString(16).padStart(2, "0")).join("");
    localStorage.setItem("backplane-cid", c);
  }
  return c;
})();

let ui = App.page(App.init(now(), cid), location.origin);
// opened from another hub to show one of this machine's bots ("#bot=<name>")
if (location.hash) {
  try { ui = App.wanted(ui, decodeURIComponent(location.hash)); } catch {}
  history.replaceState(null, "", location.pathname + location.search);
}
// drafts this browser kept (Keep commands), one key per thread
const DRAFT = "backplane-draft:";
for (let i = 0; i < localStorage.length; i += 1) {
  const k = localStorage.key(i);
  if (k && k.startsWith(DRAFT)) ui = App.restore(ui, k.slice(DRAFT.length), localStorage.getItem(k) ?? "");
}
let socket = null;
let queued = false;
let scroll = false;
let focus = null;
let jump = null;
let earlierAsked = false;

// the entry at the top of the timeline's view, and how far into the view
// it sits: kept there across a render while the reader is not at the end
function anchorOf(tl) {
  const top = tl.getBoundingClientRect().top;
  for (const el of tl.querySelectorAll("[data-id]")) {
    const r = el.getBoundingClientRect();
    if (r.bottom > top + 1) return { id: el.getAttribute("data-id"), off: r.top - top };
  }
  return null;
}

function render() {
  queued = false;
  const tl = document.getElementById("timeline");
  const pinned = tl ? tl.scrollHeight - tl.scrollTop - tl.clientHeight < 40 : true;
  const anchor = tl && !pinned ? anchorOf(tl) : null;
  const fromEnd = tl ? tl.scrollHeight - tl.scrollTop : 0;
  patch(root, { $: "El", tag: "div", key: "", attrs: { $: "Nil" }, kids: { $: "Con", head: App.view(ui), tail: { $: "Nil" } } });
  const tl2 = document.getElementById("timeline");
  if (tl2 && (scroll || pinned)) tl2.scrollTop = tl2.scrollHeight;
  // read further up, the view stays on what is read: text streaming in
  // below and earlier entries added above move nothing on screen
  else if (tl2 && tl === tl2) {
    const el = anchor && tl2.querySelector(`[data-id="${CSS.escape(anchor.id)}"]`);
    if (el) tl2.scrollTop += el.getBoundingClientRect().top - tl2.getBoundingClientRect().top - anchor.off;
    else tl2.scrollTop = tl2.scrollHeight - fromEnd;
  }
  scroll = false;
  // an entry the history went back to (Jump): brought into view, flashed
  if (jump && tl2) {
    const el = tl2.querySelector(`[data-id="${CSS.escape(jump)}"]`);
    if (el) {
      el.scrollIntoView({ block: "center" });
      el.classList.remove("jumped");
      void el.offsetWidth;
      el.classList.add("jumped");
    }
    jump = null;
  }
  Solid.mount(document.getElementById("solid"));
  Plot2d.mount(document.getElementById("plot"));
  earlierAsked = false;
  if (focus) {
    document.getElementById(focus)?.focus();
    focus = null;
  }
  tourSync();
}

function later() {
  if (!queued) {
    queued = true;
    requestAnimationFrame(render);
  }
}

function copy(text) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text);
    return;
  }
  const t = document.createElement("textarea");
  t.value = text;
  document.body.appendChild(t);
  t.select();
  document.execCommand("copy");
  t.remove();
}

function run(cmds) {
  for (const c of each(cmds)) {
    if (c.$ === "Send") {
      if (socket && socket.readyState === 1) socket.send(fromList(App.wire_out(c.text)));
    } else if (c.$ === "Copy") {
      copy(c.text);
    } else if (c.$ === "Focus") {
      focus = c.id; // after the next render, which may create it
      later();
    } else if (c.$ === "Connect") {
      // another machine's hub serves its own page; "" is this one
      if (c.url) location.href = App.visit(ui, c.url);
    } else if (c.$ === "Scroll") {
      scroll = true;
    } else if (c.$ === "Notify") {
      notify(c);
    } else if (c.$ === "Later") {
      // a client action come due (the history playing)
      setTimeout(() => dispatch(c.action, c.value), Number(c.ms));
    } else if (c.$ === "Jump") {
      jump = c.id; // after the next render, which opens its folds
      later();
    } else if (c.$ === "Keep") {
      // written at once: a crash or a closed tab loses nothing typed
      try {
        if (c.text) localStorage.setItem(DRAFT + c.thread, c.text);
        else localStorage.removeItem(DRAFT + c.thread);
      } catch {}
    }
  }
}

// Desk
// ----
// This page is a desk (core/desk.bend): app.bend's desk decides when to
// tell the hub which thread it shows and whether the person has it in
// front of them; the hub then holds the phones' alerts for that thread and
// sends this page a desktop notification for others when it was the desk
// used last.

function deskCheck() {
  const focused = document.visibilityState === "visible" && document.hasFocus();
  const r = App.desk(ui, focused, now());
  ui = r.ui;
  run(r.cmds);
}

for (const ev of ["focus", "blur"]) window.addEventListener(ev, deskCheck);
document.addEventListener("visibilitychange", deskCheck);
for (const ev of ["pointerdown", "keydown", "wheel"]) document.addEventListener(ev, deskCheck, { capture: true, passive: true });

// the browser asks the person once, on a first click or key (the only time
// browsers let a page ask)
function askNotify() {
  if ("Notification" in window && Notification.permission === "default") Notification.requestPermission().catch(() => {});
}
for (const ev of ["pointerdown", "keydown"]) document.addEventListener(ev, askNotify, { once: true, capture: true });

function notify(c) {
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  try {
    const n = new Notification(c.title, { body: c.body, tag: c.key || c.thread, icon: "./apple-touch-icon.png" });
    n.onclick = () => {
      window.focus();
      if (c.thread) dispatch("select", c.thread);
      n.close();
    };
  } catch {}
}

// run an action; answers whether it did anything (a key it did nothing
// with stays the browser's)
function dispatch(action, value) {
  const r = App.act(ui, action, value);
  ui = r.ui;
  const did = r.cmds && r.cmds.$ === "Con";
  run(r.cmds);
  deskCheck();
  later();
  return did;
}

// how many terminal cells fit: the thread pane's width, 40% of the height
function termSize() {
  let probe = document.getElementById("term-probe");
  if (!probe) {
    probe = document.createElement("span");
    probe.id = "term-probe";
    probe.className = "term-probe";
    probe.textContent = "0".repeat(20);
    document.body.appendChild(probe);
  }
  const cw = probe.getBoundingClientRect().width / 20 || 7.2;
  const pane = document.getElementById("thread");
  const w = (pane ? pane.clientWidth : window.innerWidth) - 24;
  const h = window.innerHeight * 0.4 - 40;
  return `${Math.max(20, Math.floor(w / cw))}x${Math.max(5, Math.floor(h / 17))}`;
}

function valueOf(el) {
  const sp = el.getAttribute("data-space");
  if (sp !== null) {
    const f = document.getElementById(el.getAttribute("data-field") || "") || el;
    const t = f.value ?? "";
    f.value = "";
    return sp + "\u001f" + t;
  }
  const v = el.getAttribute("data-value");
  if (v === null) return el.value ?? "";
  if (v === "@term-size") return termSize();
  if (v.startsWith("#")) return document.getElementById(v.slice(1))?.value ?? "";
  return v;
}

// what a field sends as it is typed in; a form field (data-bfield) sends
// "<field>\u001f<text>"
function inputValue(el) {
  const f = el.getAttribute("data-bfield");
  return f === null ? el.value : f + "\u001f" + el.value;
}

// Files: each goes whole as the body of one POST /attach to the hub (the
// pairing cookie carries the token); "attach-up" and "attach-end" tell
// app.bend it started and what the hub answered, and it decides the rest
async function upload(action, file) {
  const key = Array.from(crypto.getRandomValues(new Uint8Array(4)), (b) => b.toString(16).padStart(2, "0")).join("");
  const name = file.name || "pasted." + ((file.type || "").split("/")[1] || "bin");
  if (file.size === 0) return;
  const thread = App.sel(ui);
  dispatch("attach-up", JSON.stringify({ name, size: file.size }));
  if (App.uploading(ui, thread) !== name) return;
  const q = new URLSearchParams({ thread, key, name });
  let answer = "";
  try {
    const r = await fetch(`/attach?${q}`, { method: "POST", body: file, credentials: "same-origin" });
    answer = await r.text();
    JSON.parse(answer);
  } catch {
    answer = JSON.stringify({ text: "the upload did not reach the hub", thread, upload: true });
  }
  dispatch("attach-end", answer);
}

document.addEventListener("change", (e) => {
  const el = e.target.closest?.("[data-attach]");
  if (!el || !el.files) return;
  const files = [...el.files];
  el.value = "";
  (async () => {
    for (const f of files) await upload(el.getAttribute("data-attach"), f);
  })();
});

// Drops: files dragged onto a [data-drop] area go to its action, the way
// the attach button's do; its data-drop-hover action hears "1" while they
// hover and "" once they leave or land (app.bend decides what that shows)
let dropOver = null;
function dragsFiles(e) {
  return [...(e.dataTransfer?.types || [])].includes("Files");
}
function dropHover(el) {
  if (el === dropOver) return;
  if (dropOver) dispatch(dropOver.getAttribute("data-drop-hover"), "");
  dropOver = el;
  if (el) dispatch(el.getAttribute("data-drop-hover"), "1");
}

document.addEventListener("dragover", (e) => {
  if (!dragsFiles(e)) return;
  e.preventDefault();
  const el = e.target.closest?.("[data-drop]") || null;
  e.dataTransfer.dropEffect = el ? "copy" : "none";
  dropHover(el);
});

document.addEventListener("dragleave", (e) => {
  if (dropOver && !(e.relatedTarget && dropOver.isConnected && dropOver.contains(e.relatedTarget))) dropHover(null);
});

document.addEventListener("drop", (e) => {
  if (!dragsFiles(e)) return;
  e.preventDefault();
  const el = e.target.closest?.("[data-drop]");
  dropHover(null);
  const files = [...(e.dataTransfer.files || [])];
  if (!el || files.length === 0) return;
  (async () => {
    for (const f of files) await upload(el.getAttribute("data-drop"), f);
  })();
});

// Row drags: a [data-drag] element dropped on a [data-drag-to] one with the
// same data-drag-act sends that action "dragged|target" (app.bend decides
// what moves where)
const ROW = "application/x-backplane-row";
document.addEventListener("dragstart", (e) => {
  const el = e.target.closest?.("[data-drag]");
  if (!el) return;
  e.dataTransfer.setData(ROW, el.getAttribute("data-drag-act") + "\n" + el.getAttribute("data-drag"));
  e.dataTransfer.effectAllowed = "move";
});

function rowTarget(e) {
  if (![...(e.dataTransfer?.types || [])].includes(ROW)) return null;
  return e.target.closest?.("[data-drag-to]") || null;
}

document.addEventListener("dragover", (e) => {
  if (!rowTarget(e)) return;
  e.preventDefault();
  e.dataTransfer.dropEffect = "move";
});

document.addEventListener("drop", (e) => {
  const el = rowTarget(e);
  if (!el) return;
  e.preventDefault();
  const [act, v] = e.dataTransfer.getData(ROW).split("\n");
  if (act === el.getAttribute("data-drag-act")) dispatch(act, v + "|" + el.getAttribute("data-drag-to"));
});

// a key field that names its terminal (a terminal in the chat) puts the
// name first: "<key>\t..."
const forKey = (el) => (el.getAttribute("data-for") ? el.getAttribute("data-for") + "\t" : "");

document.addEventListener("paste", (e) => {
  const cd = e.clipboardData;
  if (!cd) return;
  const keys = e.target.closest?.("[data-keys]");
  if (keys) {
    e.preventDefault();
    dispatch(keys.getAttribute("data-text"), forKey(keys) + cd.getData("text/plain"));
    return;
  }
  const el = e.target.closest?.("[data-paste]");
  const files = [...(cd.files || [])];
  if (!el || files.length === 0) return;
  e.preventDefault();
  (async () => {
    for (const f of files) await upload(el.getAttribute("data-paste"), f);
  })();
});

// text typed into a key field without a key event (a phone keyboard)
document.addEventListener("input", (e) => {
  const el = e.target.closest?.("[data-text]");
  if (!el || !el.value) return;
  const v = el.value;
  el.value = "";
  dispatch(el.getAttribute("data-text"), forKey(el) + v);
});

for (const ev of EVENTS) {
  document.addEventListener(ev, (e) => {
    const el = e.target.closest?.(`[data-on-${ev}]`);
    if (!el) return;
    const action = el.getAttribute(`data-on-${ev}`);
    // a row's menu opens where the pointer was (view.bend's View.rmenu
    // reads these)
    // a file link (dom.bend's Dom.file) goes to the hub, not to its href
    if (ev === "click" && el.tagName === "A") e.preventDefault();
    if (ev === "contextmenu") {
      e.preventDefault();
      document.documentElement.style.setProperty("--mx", Math.min(e.clientX, innerWidth - 216) + "px");
      document.documentElement.style.setProperty("--my", e.clientY + "px");
    }
    dispatch(action, ev === "input" ? inputValue(el) : valueOf(el));
  });
}

// keys: the page's own shortcuts (app.bend lists them), then a key field
// (the terminal) gets every key as "<key>\t<mods>"
const KEYS_PAGE = App.keys_page().split(",");
const KEYS_TERM = App.keys_term().split(",");

document.addEventListener("keydown", (e) => {
  if (e.isComposing) return;
  const field = e.target.closest?.("[data-keys]");
  const combo = (e.ctrlKey ? "ctrl+" : "") + (e.altKey ? "alt+" : "") + (e.shiftKey ? "shift+" : "") + e.key.toLowerCase();
  if ((field ? KEYS_TERM : KEYS_PAGE).includes(combo)) {
    e.preventDefault();
    dispatch("key", combo + "\t" + termSize());
    return;
  }
  if (field) {
    const mods = (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 4 : 0) | (e.altKey ? 8 : 0);
    if (dispatch(field.getAttribute("data-keys"), forKey(field) + e.key + "\t" + mods)) e.preventDefault();
  }
});

document.addEventListener("keydown", (e) => {
  // up and down move the highlight in a menu the field offers (the
  // composer's completions)
  if ((e.key === "ArrowUp" || e.key === "ArrowDown") && !e.shiftKey && !e.ctrlKey && !e.metaKey && !e.altKey) {
    const arrows = e.target.getAttribute?.("data-arrows");
    if (arrows) {
      e.preventDefault();
      dispatch(arrows, e.key === "ArrowDown" ? "down" : "up");
    }
    return;
  }
  if (e.key === "Tab" && !e.shiftKey) {
    const tab = e.target.getAttribute?.("data-tab");
    if (tab) {
      e.preventDefault();
      dispatch(tab, valueOf(e.target));
    }
    return;
  }
  const el = e.target.closest?.("[data-enter]");
  if (!el || e.key !== "Enter" || e.shiftKey || e.isComposing) return;
  e.preventDefault();
  // ctrl/cmd+Enter: the element's other action (send with the other follow-up mode)
  const alt = (e.ctrlKey || e.metaKey) && el.getAttribute("data-enter-alt");
  dispatch(alt || el.getAttribute("data-enter"), valueOf(el));
});

// The first-run tour (view.bend's View.tour) is modal while its dialog is on
// the page: the page behind is inert, focus stays in the dialog (Tab goes
// round its buttons), the keys that mean something go through app.bend's
// tour_key (a repeat does nothing), every other key, ctrl/meta combination,
// paste and drop is stopped, and a focused button does its own action. Every
// key pressed while it is up (by KeyboardEvent.code, modified ones too) has
// its repeats dropped after it closes, until the key is let go or pressed
// afresh, so holding Enter through Done never reaches the composer behind.
let tourFocus = null; // where the keyboard was when the dialog came up
let tourOn = false;
const tourEaten = new Set();
let tourDrop = "";
function tourSync() {
  const tour = document.querySelector(".tour");
  const app = document.querySelector(".app");
  if (tour && !tourOn) {
    tourOn = true;
    tourFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  }
  if (app) {
    for (const el of app.children) {
      if (tour && !el.classList.contains("tour") && !el.classList.contains("tour-back")) el.setAttribute("inert", "");
      else el.removeAttribute("inert");
    }
  }
  if (tour) {
    if (!tour.contains(document.activeElement)) (tour.querySelector("button.primary") || tour.querySelector("button"))?.focus();
  } else if (tourOn) {
    tourOn = false;
    // back where it was, unless that went away (Settings shut): the composer
    const back = tourFocus && tourFocus !== document.body && tourFocus.isConnected ? tourFocus : document.getElementById("composer");
    back?.focus?.();
    tourFocus = null;
  }
}
document.addEventListener("keydown", (e) => {
  const tour = document.querySelector(".tour");
  if (!tour) {
    // a key pressed while it was up, still held: its repeats are dropped
    // (its keypress and input with them) until it is let go or pressed afresh
    if (tourEaten.has(e.code)) {
      if (e.repeat) { tourDrop = e.code; e.preventDefault(); e.stopImmediatePropagation(); return; }
      tourEaten.delete(e.code);
    }
    tourDrop = "";
    return;
  }
  if (e.isComposing) return;
  tourEaten.add(e.code);
  e.stopImmediatePropagation();
  if (e.ctrlKey || e.metaKey || e.altKey) { e.preventDefault(); return; }
  if (e.key === "Tab") {
    e.preventDefault();
    const bs = [...tour.querySelectorAll("button")];
    const at = bs.indexOf(document.activeElement);
    bs[(at + (e.shiftKey ? bs.length - 1 : 1)) % bs.length]?.focus();
    return;
  }
  const act = App.tour_key(e.key);
  const onButton = document.activeElement instanceof HTMLButtonElement && tour.contains(document.activeElement);
  // Enter or Space on a focused button is that button's (the click does it)
  if (onButton && (e.key === "Enter" || e.key === " ")) {
    if (e.repeat) e.preventDefault();
    return;
  }
  e.preventDefault();
  if (!act || e.repeat) return;
  dispatch(act, "");
}, true);
document.addEventListener("keyup", (e) => {
  tourEaten.delete(e.code);
  if (tourDrop === e.code) tourDrop = "";
}, true);
for (const ev of ["paste", "drop", "dragover", "beforeinput", "cut", "keypress"]) {
  document.addEventListener(ev, (e) => {
    if (document.querySelector(".tour") || (tourDrop && (ev === "beforeinput" || ev === "keypress"))) { e.preventDefault(); e.stopImmediatePropagation(); }
  }, true);
}

// Lightbox
// --------
// A click on an image in a thread ([data-lightbox]) shows it over the page.
// app.bend's lb_* hold every decision (zoom, pan, easing, what closes it);
// this feeds them the pointer and sets the style they answer, drawing
// frames only while lb_busy says an ease is running.

let lb = null; // { el, img, v: the Bend Lb, drawing, pointers }
const lbNow = () => BigInt(Math.floor(performance.now())) + 1n;
const lbN = (x) => BigInt(Math.max(0, Math.round(x)));
const lbBox = () => App.lb_box(lbN(lb.img.naturalWidth), lbN(lb.img.naturalHeight), lbN(window.innerWidth), lbN(window.innerHeight));

function lbDraw() {
  if (!lb) return;
  lb.drawing = false;
  if (!lb.img.naturalWidth) return;
  const now = lbNow();
  lb.v = App.lb_stamp(lb.v, now);
  lb.img.style.cssText = App.lb_css(lb.v, lbBox(), now);
  if (App.lb_busy(lb.v, now)) lbLater();
}

function lbLater() {
  if (lb && !lb.drawing) {
    lb.drawing = true;
    requestAnimationFrame(lbDraw);
  }
}

function lbClose() {
  if (!lb) return;
  lb.el.remove();
  lb = null;
}

function lbPinch() {
  const [a, b] = [...lb.pointers.values()];
  return { d: Math.hypot(a.x - b.x, a.y - b.y), x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function lbOpen(url) {
  lbClose();
  const el = create(App.lb_node(url));
  const img = el.querySelector("img");
  lb = { el, img, v: App.lb_open(), drawing: false, pointers: new Map(), pinch: null };
  img.style.visibility = "hidden"; // until loaded; lb_css then sets the whole style
  img.addEventListener("load", lbDraw);
  el.addEventListener("wheel", (e) => {
    e.preventDefault();
    const k = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? 400 : 1;
    const mag = Math.max(1, Math.round(Math.abs(e.deltaY) * k));
    if (e.deltaY === 0) return;
    lb.v = App.lb_wheel(lb.v, e.deltaY > 0, BigInt(mag), e.ctrlKey, lbN(e.clientX), lbN(e.clientY), lbBox(), lbNow());
    lbDraw();
  }, { passive: false });
  el.addEventListener("pointerdown", (e) => {
    if (e.target.closest("[data-lb-close]")) return;
    e.preventDefault();
    el.setPointerCapture(e.pointerId);
    lb.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (lb.pointers.size === 2) {
      lb.v = App.lb_release(lb.v, lbN(e.clientX), lbN(e.clientY), lbBox(), lbNow());
      lb.pinch = lbPinch();
    } else if (lb.pointers.size === 1) {
      lb.v = App.lb_press(lb.v, lbN(e.clientX), lbN(e.clientY), lbBox(), lbNow());
    }
  });
  el.addEventListener("pointermove", (e) => {
    if (!lb.pointers.has(e.pointerId)) return;
    lb.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (lb.pinch && lb.pointers.size === 2) {
      const p = lbPinch();
      lb.v = App.lb_pinch(lb.v, lbN(lb.pinch.d), lbN(p.d), lbN(p.x), lbN(p.y), lbBox(), lbNow());
      lb.pinch = p;
    } else if (lb.pointers.size === 1) {
      lb.v = App.lb_move(lb.v, lbN(e.clientX), lbN(e.clientY), lbBox(), lbNow());
    }
    lbDraw();
  });
  const up = (e) => {
    if (!lb || !lb.pointers.has(e.pointerId)) return;
    lb.pointers.delete(e.pointerId);
    if (lb.pinch) {
      if (lb.pointers.size === 0) lb.pinch = null;
      return;
    }
    const closes = e.type === "pointerup" && App.lb_closes(lb.v, lbN(e.clientX), lbN(e.clientY));
    lb.v = App.lb_release(lb.v, lbN(e.clientX), lbN(e.clientY), lbBox(), lbNow());
    if (closes) lbClose();
    else lbDraw();
  };
  el.addEventListener("pointerup", up);
  el.addEventListener("pointercancel", up);
  el.addEventListener("click", (e) => {
    if (e.target.closest("[data-lb-close]")) lbClose();
  });
  document.body.appendChild(el);
  document.activeElement?.blur?.();
  if (img.complete) lbDraw();
}

// a viewer's Fit button
document.addEventListener("click", (e) => {
  if (!e.target.closest?.('[data-view="fit"]')) return;
  Plot2d.fit();
  Solid.fit();
});
// the timeline scrolled within two screens of its top while earlier
// entries are left out (view.bend's mark): ask for them, once a render
document.addEventListener("scroll", (e) => {
  const tl = e.target;
  if (earlierAsked || !(tl instanceof Element) || tl.id !== "timeline") return;
  const mark = tl.querySelector("[data-earlier]");
  if (!mark || tl.scrollTop > tl.clientHeight * 2) return;
  earlierAsked = true;
  dispatch("earlier", mark.getAttribute("data-earlier") ?? "");
}, true);

document.addEventListener("click", (e) => {
  if (e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey) return;
  const a = e.target.closest?.("[data-lightbox]");
  if (!a) return;
  e.preventDefault();
  lbOpen(a.getAttribute("data-lightbox"));
});

// while the lightbox is up, its keys are its own
document.addEventListener("keydown", (e) => {
  if (!lb) return;
  e.stopImmediatePropagation();
  if (App.lb_key(e.key)) {
    e.preventDefault();
    lbClose();
  }
}, true);

window.addEventListener("resize", () => lbDraw());

// The viewer's width: its left edge (view.bend's View.split) drags it, the
// width is kept in this browser, and a double-click on the edge gives the
// pane its usual share back. The thread keeps at least 360 px.
const VIEWER_W = "backplane-viewer-w";
function viewerWidth(w) {
  const root = document.documentElement;
  if (w == null) { root.style.removeProperty("--viewer-w"); return; }
  root.style.setProperty("--viewer-w", `${Math.round(w)}px`);
}
function viewerClamp(w) {
  const app = document.querySelector(".app");
  const side = app?.querySelector(".sidebar")?.getBoundingClientRect().width ?? 264;
  const max = (app?.getBoundingClientRect().width ?? window.innerWidth) - side - 360;
  return Math.max(320, Math.min(w, max));
}
try { const w = Number(localStorage.getItem(VIEWER_W)); if (w > 0) viewerWidth(viewerClamp(w)); } catch {}
document.addEventListener("pointerdown", (e) => {
  const edge = e.target instanceof Element ? e.target.closest(".viewer-split") : null;
  if (!edge || e.button !== 0) return;
  e.preventDefault();
  const pane = edge.parentElement;
  const right = pane.getBoundingClientRect().right;
  try { edge.setPointerCapture(e.pointerId); } catch {}
  edge.classList.add("on");
  document.body.classList.add("resizing");
  let w = pane.getBoundingClientRect().width;
  const move = (m) => { w = viewerClamp(right - m.clientX); viewerWidth(w); };
  const done = () => {
    edge.removeEventListener("pointermove", move);
    edge.removeEventListener("pointerup", done);
    edge.removeEventListener("pointercancel", done);
    edge.classList.remove("on");
    document.body.classList.remove("resizing");
    try { localStorage.setItem(VIEWER_W, String(Math.round(w))); } catch {}
  };
  edge.addEventListener("pointermove", move);
  edge.addEventListener("pointerup", done);
  edge.addEventListener("pointercancel", done);
});
document.addEventListener("dblclick", (e) => {
  if (!(e.target instanceof Element) || !e.target.closest(".viewer-split")) return;
  viewerWidth(null);
  try { localStorage.removeItem(VIEWER_W); } catch {}
});
window.addEventListener("resize", () => {
  const w = parseFloat(document.documentElement.style.getPropertyValue("--viewer-w"));
  if (w > 0) viewerWidth(viewerClamp(w));
});

// Socket
// ------

let backoff = 250;

// A tailnet link carries the pairing token in its fragment; keep it for
// later visits and never send it anywhere but this server's socket.
const token = (() => {
  const m = location.hash.match(/token=([0-9a-f]+)/);
  if (m) {
    localStorage.setItem("backplane-token", m[1]);
    history.replaceState(null, "", location.pathname);
  }
  return localStorage.getItem("backplane-token") ?? "";
})();

// images in threads load by URL (<img src="/img?...">) and cannot carry the
// token in a query the way the socket does: a same-site cookie carries it
if (token) document.cookie = `bp_token=${token}; path=/; SameSite=Strict`;

// The event log this page holds, kept across reloads: a reload shows it at
// once and the socket then brings only what is new (since=, origin=). Raw
// server items only; the page state is rebuilt from them by app.bend.
const CACHE = "backplane-log";
let cache = (() => {
  try {
    return JSON.parse(localStorage.getItem(CACHE) ?? "null");
  } catch {
    return null;
  }
})();

// The log grows in place and is written out at most every 2 s (and when
// the page is hidden or left), not stringified whole for every message;
// a reload before a write catches up from the server (since). Over quota,
// the page keeps its copy in memory and drops only the stored one.
let dirty = false;
let flushing = null;

function flush() {
  if (flushing !== null) {
    clearTimeout(flushing);
    flushing = null;
  }
  if (!dirty || !cache) return;
  dirty = false;
  try {
    localStorage.setItem(CACHE, JSON.stringify(cache));
  } catch {
    try { localStorage.removeItem(CACHE); } catch {} // over quota: start from the server next time
  }
}

function keep(msg) {
  if (msg.t === "log") {
    if (msg.since > 0 && cache) {
      for (const x of msg.items) cache.items.push(x);
    } else {
      cache = { origin: msg.origin ?? "", items: msg.items };
    }
  } else if (msg.t === "changes" && cache) {
    for (const x of msg.items) cache.items.push(x);
  } else {
    return;
  }
  dirty = true;
  if (flushing === null) flushing = setTimeout(flush, 2000);
}

addEventListener("pagehide", flush);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") flush();
});

if (cache && Array.isArray(cache.items)) {
  ui = App.recv(ui, toJson({ t: "log", since: 0, origin: cache.origin, items: cache.items })).ui;
  // a saved log is not this connection's: the hub's own log says when
  ui = App.unsync(ui);
}

function connect() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const q = new URLSearchParams();
  if (token) q.set("token", token);
  q.set("since", App.seq(ui));
  q.set("origin", App.origin(ui));
  q.set("enc", "cbor"); // a hub before CBOR-only still needs asking
  const s = new WebSocket(`${proto}//${location.host}/ws?${q}`);
  s.binaryType = "arraybuffer";
  s.onopen = () => {
    socket = s;
    heard = BigInt(Date.now());
    backoff = 250;
    ui = App.online(ui, true);
    deskCheck();
    later();
  };
  s.onmessage = (e) => {
    heard = BigInt(Date.now());
    // the hub sends only binary CBOR frames
    if (typeof e.data === "string") return;
    // plots go straight to the viewers, not through Bend: a 3D model
    // ("2|", "3|" or "4|...") to solid.js, a board or schematic to plot2d.js
    const bytes = new Uint8Array(e.data);
    if (Solid.isPlot(bytes)) {
      const at = { bytes: bytes.length, t: performance.now() };
      const o = Solid.cbor(bytes);
      const key = typeof o?.key === "string" ? o.key : "";
      if (key.startsWith("2|") || key.startsWith("3|") || key.startsWith("4|")) Solid.got(o, at);
      else if (o) Plot2d.got(o, at);
      return;
    }
    const j = App.wire_in(toList(bytes));
    // another thread's streamed text draws nothing and is not kept: only
    // the log and its changes are, and the page renders when the message
    // shows or gives commands
    const t = App.kind(j);
    const vis = App.shows(ui, j);
    if (t === "log" || t === "changes") keep(JSON.parse(App.show(j)));
    const r = App.recv(ui, j);
    ui = r.ui;
    let acts = false;
    for (const _ of each(r.cmds)) {
      acts = true;
      break;
    }
    run(r.cmds);
    if (vis || acts) later();
  };
  let lost = false;
  const gone = () => {
    if (lost) return;
    lost = true;
    if (socket === s) socket = null;
    // a new connection holds no plots
    Plot2d.reset();
    Solid.reset();
    ui = App.online(ui, false);
    later();
    setTimeout(connect, backoff);
    backoff = Math.min(backoff * 2, 5000);
  };
  s.onclose = gone;
  // a half-open link shows no close: the hub's heartbeat (every 15 s) not
  // arriving for 40 s ends it here (Alive.due)
  s.dead = () => {
    s.onmessage = null;
    try { s.close(); } catch {}
    gone();
  };
}

// when a frame (a heartbeat included) last arrived, in ms
let heard = BigInt(Date.now());
setInterval(() => {
  if (socket && App.alive_due(heard, BigInt(Date.now()))) socket.dead();
}, 5000);

setInterval(() => {
  ui = App.tick(ui, now());
  later();
}, 30000);

connect();
render();

// the app shell works offline where the browser allows it (HTTPS or localhost)
if ("serviceWorker" in navigator && window.isSecureContext) {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}
