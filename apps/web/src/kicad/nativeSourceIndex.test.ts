import { expect, it } from "vite-plus/test";
const url = new URL("../../public/kicad-viewer/native-source-index.js", import.meta.url).href;
const { indexNativeSources } = await import(/* @vite-ignore */ url);

const sources = (position: number, text = "a (quoted) label") => [
  {
    filename: "board.kicad_pcb",
    content: `(kicad_pcb (version 20250101) (layers (0 "F.Cu" signal))
    (footprint "Part" (at ${position} 2) (uuid "fp") (property "Value" "${text}")
      (pad "1" smd rect (at 0 0) (uuid "pad")))
    (segment (start 0 0) (end 2 2) (uuid "track")))`,
  },
];

it("tracks complete footprint edits without confusing nested pad UUIDs or quoted parentheses", () => {
  const before = indexNativeSources(sources(1));
  const next = indexNativeSources(sources(2), before);
  expect([...next.changed]).toEqual(["fp"]);
  expect(next.signatures.get("track")).toBe(before.signatures.get("track"));
  expect(next.globalChanged).toBe(false);
  expect(next.items.has("pad")).toBe(false);
});

it("ignores whitespace between items but invalidates layer and symbol-library changes", () => {
  const before = indexNativeSources(sources(1));
  const same = sources(1);
  same[0]!.content += "\n\n";
  const next = indexNativeSources(same, before);
  expect(next.changed.size).toBe(0);
  expect(next.globalChanged).toBe(false);
  same[0]!.content = same[0]!.content.replace('"F.Cu"', '"B.Cu"');
  expect(indexNativeSources(same, before).globalChanged).toBe(true);
});

it("rejects partial saved files so an incomplete write cannot replace the visible drawing", () => {
  const partial = sources(1);
  partial[0]!.content = partial[0]!.content.slice(0, -1);
  expect(() => indexNativeSources(partial)).toThrow("incomplete");
});
