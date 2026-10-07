// wire.js (the web's and phones' own CBOR decoder) against Bend's
// Cbor.decode, on every frame a hub sends a joining client:
//   bun test/tools/wire_js_test.ts HOST:PORT TOKEN
// build/wire (scripts/build.sh) is Bend's decoder, compiled.
import { readFileSync, readdirSync } from "node:fs";
import { cbor, plain } from "../../src/web/wire.js";
const wire = new URL("../../build/wire/", import.meta.url).pathname;
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;
const src = readFileSync(new URL("../../src/core/cbor.bend", import.meta.url).pathname, "utf8");
const list = (name: string) => JSON.parse(src.split(`def Cbor.${name}() -> List<&2, String>:`)[1].split("\n\n")[0].replace(/\s+/g, " ").trim());
const KEYS = list("keys"), WORDS = list("words");
const [host, token] = process.argv.slice(2);
const ws = new WebSocket(`ws://${host}/ws?token=${token}&since=0&origin=&enc=cbor`);
ws.binaryType = "arraybuffer";
let frames = 0, bytes = 0, bad = 0, tBend = 0, tJs = 0, last = Date.now();
ws.onmessage = (e) => {
  const b = new Uint8Array(e.data);
  if (b[1] === 1 && Buffer.from(b.subarray(3, 7)).toString() === "plot") return;
  frames++; bytes += b.length; last = Date.now();
  let t = performance.now(); const want = JSON.parse(W.decode(b)); tBend += performance.now() - t;
  t = performance.now(); const got = plain(cbor(b, KEYS, WORDS)); tJs += performance.now() - t;
  if (JSON.stringify(got) !== JSON.stringify(want)) { bad++; if (bad < 3) console.log("MISMATCH", JSON.stringify(want).slice(0, 200), "\n        ", JSON.stringify(got).slice(0, 200)); }
};
while (Date.now() - last < 4000) await new Promise((r) => setTimeout(r, 200));
console.log(`${frames} frames, ${(bytes / 1e6).toFixed(1)} MB: ${bad} mismatches; Bend ${tBend.toFixed(0)} ms, wire.js ${tJs.toFixed(0)} ms`);
ws.close(); process.exit(bad ? 1 : 0);
