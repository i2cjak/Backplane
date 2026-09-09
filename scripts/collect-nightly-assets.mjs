import { cp, mkdir, readdir, stat } from "node:fs/promises";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: { platform: { type: "string" }, arch: { type: "string" } },
});
const required = { linux: [".AppImage"], mac: [".dmg", ".zip"], win: [".exe"] }[values.platform];
if (!required) throw new Error("Unknown platform");
const files = (await readdir("release")).filter(
  (name) => /\.(AppImage|dmg|zip|exe|blockmap)$/.test(name) || /^nightly.*\.yml$/.test(name),
);
for (const extension of required) {
  if (!files.some((name) => name.endsWith(extension)))
    throw new Error(`Missing ${extension} installer`);
}
await mkdir("release-publish", { recursive: true });
for (const name of files) {
  if ((await stat(`release/${name}`)).size >= 2 ** 31)
    throw new Error(`Release asset exceeds GitHub's limit: ${name}`);
  const target =
    values.platform === "mac" && values.arch === "x64" && name === "nightly-mac.yml"
      ? "nightly-mac-x64.yml"
      : name;
  await cp(`release/${name}`, `release-publish/${target}`);
}
console.log(`Collected ${files.length} release assets.`);
