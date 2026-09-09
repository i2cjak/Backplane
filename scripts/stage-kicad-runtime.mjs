import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { mkdir, readFile, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { resolve, join } from "node:path";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: { platform: { type: "string" }, arch: { type: "string" } },
});
const config = JSON.parse(await readFile("assets/runtime/kicad.json", "utf8"));
const assetName = config.assets[`${values.platform}-${values.arch}`];
if (!assetName) throw new Error("Unsupported KiCad target");
const destination = resolve("apps/desktop/prod-resources/kicad-runtime");
let download, digest;
if (values.platform === "linux") {
  const release = JSON.parse(
    execFileSync("gh", ["api", `repos/${config.repository}/releases/tags/${config.tag}`], {
      encoding: "utf8",
    }),
  );
  const asset = release.assets.find((item) => item.name === assetName);
  if (!asset || !/^sha256:[a-f0-9]{64}$/.test(asset.digest ?? ""))
    throw new Error(`Verified KiCad asset is unavailable: ${assetName}`);
  digest = asset.digest;
  download = join(process.env.RUNNER_TEMP ?? process.cwd(), assetName);
  execFileSync(
    "curl",
    ["--fail", "--location", "--retry", "3", asset.browser_download_url, "--output", download],
    { stdio: "inherit" },
  );
} else {
  download = resolve("native-runtime", assetName);
  const checksum = (await readFile(download.replace(/\.tar\.gz$/, ".sha256"), "utf8"))
    .trim()
    .split(/\s+/)[0];
  if (!/^[a-f0-9]{64}$/.test(checksum)) throw new Error("Missing native runtime checksum");
  digest = `sha256:${checksum}`;
}
const hash = createHash("sha256");
for await (const chunk of createReadStream(download)) hash.update(chunk);
if (`sha256:${hash.digest("hex")}` !== digest) throw new Error("KiCad archive checksum mismatch");
await mkdir(destination, { recursive: true });
execFileSync("tar", ["-xzf", download, "-C", destination, "--strip-components=1"], {
  stdio: "inherit",
});
await rm(download);
const manifest = JSON.parse(await readFile(join(destination, "manifest.json"), "utf8"));
if (
  manifest.sourceRepository !== `https://github.com/${config.repository}` ||
  manifest.sourceCommit !== config.sourceCommit ||
  manifest.version !== config.version
)
  throw new Error("Unexpected KiCad source revision");
const executable = join(
  destination,
  "bin",
  values.platform === "win" ? "kicad-cli.exe" : "kicad-cli",
);
execFileSync(executable, ["--version"], { stdio: "inherit" });
execFileSync(executable, ["api-server", "--help"], { stdio: "inherit" });
console.log(`Verified ${assetName} from ${manifest.sourceCommit}`);
