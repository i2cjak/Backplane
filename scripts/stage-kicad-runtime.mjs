import * as NodeCrypto from "node:crypto";
import * as NodeFS from "node:fs";
import * as NodeFSP from "node:fs/promises";
import * as NodeChildProcess from "node:child_process";
import * as NodePath from "node:path";
import * as NodeUtil from "node:util";
import { supplementKiCadGlibc } from "./supplement-kicad-glibc.mjs";

const { values } = NodeUtil.parseArgs({
  options: { platform: { type: "string" }, arch: { type: "string" } },
});
const config = JSON.parse(await NodeFSP.readFile("assets/runtime/kicad.json", "utf8"));
const assetName = config.assets[`${values.platform}-${values.arch}`];
if (!assetName) throw new Error("Unsupported KiCad target");
const destination = NodePath.resolve("apps/desktop/prod-resources/kicad-runtime");
let download, digest;
if (values.platform === "linux") {
  const release = JSON.parse(
    NodeChildProcess.execFileSync(
      "gh",
      ["api", `repos/${config.repository}/releases/tags/${config.tag}`],
      {
        encoding: "utf8",
      },
    ),
  );
  const asset = release.assets.find((item) => item.name === assetName);
  if (!asset || !/^sha256:[a-f0-9]{64}$/.test(asset.digest ?? ""))
    throw new Error(`Verified KiCad asset is unavailable: ${assetName}`);
  digest = asset.digest;
  download = NodePath.join(process.env.RUNNER_TEMP ?? process.cwd(), assetName);
  NodeChildProcess.execFileSync(
    "curl",
    ["--fail", "--location", "--retry", "3", asset.browser_download_url, "--output", download],
    { stdio: "inherit" },
  );
} else {
  download = NodePath.resolve("native-runtime", assetName);
  const checksum = (await NodeFSP.readFile(download.replace(/\.tar\.gz$/, ".sha256"), "utf8"))
    .trim()
    .split(/\s+/)[0];
  if (!/^[a-f0-9]{64}$/.test(checksum)) throw new Error("Missing native runtime checksum");
  digest = `sha256:${checksum}`;
}
const hash = NodeCrypto.createHash("sha256");
for await (const chunk of NodeFS.createReadStream(download)) hash.update(chunk);
if (`sha256:${hash.digest("hex")}` !== digest) throw new Error("KiCad archive checksum mismatch");
await NodeFSP.mkdir(destination, { recursive: true });
NodeChildProcess.execFileSync(
  "tar",
  ["-xzf", download, "-C", destination, "--strip-components=1"],
  {
    stdio: "inherit",
  },
);
await NodeFSP.rm(download);
const manifest = JSON.parse(
  await NodeFSP.readFile(NodePath.join(destination, "manifest.json"), "utf8"),
);
if (
  manifest.sourceRepository !== `https://github.com/${config.repository}` ||
  manifest.sourceCommit !== config.sourceCommit ||
  manifest.version !== config.version
)
  throw new Error("Unexpected KiCad source revision");
if (values.platform === "linux") {
  const pin = JSON.parse(await NodeFSP.readFile("assets/runtime/kicad-linux-glibc.json", "utf8"));
  const deb = NodePath.join(process.env.RUNNER_TEMP ?? process.cwd(), "backplane-kicad-libc6.deb");
  try {
    NodeChildProcess.execFileSync(
      "curl",
      ["--fail", "--location", "--retry", "3", pin.url, "--output", deb],
      {
        stdio: "inherit",
      },
    );
    const added = await supplementKiCadGlibc(destination, deb, pin);
    console.log(`Completed KiCad glibc ${pin.version}: ${added.join(", ") || "already complete"}`);
  } finally {
    await NodeFSP.rm(deb, { force: true });
  }
}
const executable = NodePath.join(
  destination,
  "bin",
  values.platform === "win" ? "kicad-cli.exe" : "kicad-cli",
);
NodeChildProcess.execFileSync(executable, ["--version"], { stdio: "inherit" });
NodeChildProcess.execFileSync(executable, ["api-server", "--help"], { stdio: "inherit" });
console.log(`Verified ${assetName} from ${manifest.sourceCommit}`);
