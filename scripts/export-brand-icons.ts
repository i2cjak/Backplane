#!/usr/bin/env node
// @effect-diagnostics nodeBuiltinImport:off - standalone asset exporter uses Sharp’s Node buffers and file APIs.
// @effect-diagnostics globalConsole:off - CLI progress and stale-file diagnostics are written directly to its terminal.
import * as NodeFSP from "node:fs/promises";
import * as NodePath from "node:path";
import sharp from "sharp";
import { BRAND_ASSET_PATHS as assets, resolveWebIconOverrides } from "./lib/brand-assets.ts";

const root = NodePath.resolve(import.meta.dirname, "..");
const check = process.argv.includes("--check");
const mark = await NodeFSP.readFile(NodePath.join(root, "assets/backplane.svg"), "utf8");
const shape = mark.slice(mark.indexOf("<path"), mark.lastIndexOf("</svg>"));
const outputs = new Map<string, Buffer>();

const variants = [
  { name: "production", background: "#111410", ink: "#e6e9de", prefix: "production" },
  { name: "development", background: "#263824", ink: "#d6edaf", prefix: "development" },
  { name: "nightly", background: "#24291f", ink: "#d6edaf", prefix: "nightly" },
] as const;

function iconSvg(background: string, ink: string, rounded: boolean) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 256 256"><rect width="256" height="256" rx="${rounded ? 52 : 0}" fill="${background}"/><g transform="translate(20 20) scale(.84)">${shape.replaceAll("#e6e9de", ink)}</g></svg>`;
}

async function png(svg: string, size: number) {
  return sharp(Buffer.from(svg)).resize(size, size).png().toBuffer();
}

// ICO permits PNG payloads; preserve multiple sizes for native Windows shells.
async function ico(svg: string) {
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const images = await Promise.all(sizes.map((size) => png(svg, size)));
  const header = Buffer.alloc(6 + 16 * sizes.length);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  images.forEach((image, index) => {
    const entry = 6 + index * 16;
    header[entry] = sizes[index] === 256 ? 0 : sizes[index]!;
    header[entry + 1] = header[entry]!;
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(image.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += image.length;
  });
  return Buffer.concat([header, ...images]);
}

for (const variant of variants) {
  const rounded = iconSvg(variant.background, variant.ink, true);
  const square = iconSvg(variant.background, variant.ink, false);
  for (const [key, target] of Object.entries(assets)) {
    if (!key.startsWith(variant.prefix) || target.endsWith(".icon")) continue;
    if (target.endsWith(".ico")) outputs.set(target, await ico(rounded));
    else if (target.endsWith(".png")) {
      const size = key.includes("16Png")
        ? 16
        : key.includes("32Png")
          ? 32
          : key.includes("180") || key.includes("AppleTouch")
            ? 180
            : 1024;
      outputs.set(target, await png(key.includes("Ios") ? square : rounded, size));
    }
  }
  const project = assets[`${variant.prefix}IconComposerProject`];
  outputs.set(`${project}/Assets/text.svg`, Buffer.from(mark));
  outputs.set(
    `${project}/icon.json`,
    Buffer.from(
      JSON.stringify(
        {
          fill: {
            solid:
              "display-p3:" +
              [1, 3, 5]
                .map((offset) =>
                  (parseInt(variant.background.slice(offset, offset + 2), 16) / 255).toFixed(5),
                )
                .join(",") +
              ",1.00000",
          },
          groups: [
            {
              layers: [
                {
                  "image-name": "text.svg",
                  name: "Backplane",
                  position: { scale: 3.3, "translation-in-points": [0, 0] },
                },
              ],
            },
          ],
          "supported-platforms": { squares: "shared" },
        },
        null,
        2,
      ) + "\n",
    ),
  );
}

outputs.set("assets/prod/logo.svg", Buffer.from(mark));
outputs.set("apps/mobile/assets/widget/BackplaneMark.svg", Buffer.from(mark));
const adaptive = `<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 256 256"><g transform="translate(52 52) scale(.594)">${shape}</g></svg>`;
outputs.set("apps/mobile/assets/android-icon-foreground.svg", Buffer.from(adaptive));
outputs.set("apps/mobile/assets/android-icon-foreground.png", await png(adaptive, 432));
outputs.set("apps/mobile/assets/android-icon-mark.png", await png(adaptive, 432));
outputs.set(
  "apps/mobile/assets/android-notification-icon.png",
  await png(mark.replaceAll("#e6e9de", "#ffffff"), 96),
);
for (const target of ["apps/web/public", "apps/marketing/public"]) {
  for (const asset of resolveWebIconOverrides("production", target)) {
    outputs.set(asset.targetRelativePath, outputs.get(asset.sourceRelativePath)!);
  }
}
outputs.set("apps/marketing/public/backplane.svg", Buffer.from(mark));
outputs.set("apps/web/public/backplane.svg", Buffer.from(mark));

let stale = false;
for (const [relative, data] of outputs) {
  const file = NodePath.join(root, relative);
  if (check) {
    const existing = await NodeFSP.readFile(file).catch(() => null);
    if (!existing?.equals(data)) {
      console.error(`Outdated brand asset: ${relative}`);
      stale = true;
    }
  } else {
    await NodeFSP.mkdir(NodePath.dirname(file), { recursive: true });
    await NodeFSP.writeFile(file, data);
  }
}
if (stale) process.exitCode = 1;
else console.log(`${check ? "Verified" : "Exported"} ${outputs.size} Backplane brand assets.`);
