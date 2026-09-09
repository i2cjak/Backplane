import { createReadStream } from "node:fs";
import { readdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";

const {
  RELEASE_TAG: tag,
  RELEASE_VERSION: version,
  GITHUB_SHA: sha,
  GITHUB_REPOSITORY: repo,
} = process.env;
if (
  repo !== "i2cjak/Backplane" ||
  !/^v\d+\.\d+\.\d+-nightly\.\d{8}\.\d+$/.test(tag ?? "") ||
  tag !== `v${version}` ||
  !/^[a-f0-9]{40}$/.test(sha ?? "")
)
  throw new Error("Invalid Backplane release identity");
const files = (await readdir("release-publish")).sort();
for (const pattern of [
  /\.AppImage$/,
  /-arm64\.dmg$/,
  /-x64\.dmg$/,
  /-arm64\.zip$/,
  /-x64\.zip$/,
  /\.exe$/,
  /\.apk$/,
  /^nightly-linux\.yml$/,
  /^nightly-mac\.yml$/,
  /^nightly\.yml$/,
]) {
  if (!files.some((name) => pattern.test(name)))
    throw new Error(`Incomplete nightly: missing ${pattern}`);
}
const sums = [];
for (const name of files) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(`release-publish/${name}`)) hash.update(chunk);
  sums.push(`${hash.digest("hex")}  ${name}`);
}
await writeFile("release-publish/SHA256SUMS", `${sums.join("\n")}\n`);
const notes = `Automated Backplane nightly from ${sha}.\n\nDownload the AppImage for Linux, DMG for your Mac, EXE for Windows, or APK for Android. Desktop installers include the Backplane server, modified KiCad, Python, and standard KiCad libraries. Android connects to a Backplane server.\n\nWindows and macOS installers are unsigned. Android uses the permanent Backplane release key. Nightlies are prereleases; the desktop updater stays on the Backplane nightly channel.\n\nKiCad source and license information: https://github.com/i2cjak/Backplane_KiCad/releases. Each runtime manifest identifies its source revision. Verify downloads with SHA256SUMS.\n`;
await writeFile(`${process.env.RUNNER_TEMP}/backplane-nightly-notes.md`, notes);
const gh = (args) => execFileSync("gh", args, { stdio: "inherit" });
// Upload into a draft so an interrupted upload cannot expose a partial nightly.
gh([
  "release",
  "create",
  tag,
  ...files.map((name) => `release-publish/${name}`),
  "release-publish/SHA256SUMS",
  "--repo",
  repo,
  "--target",
  sha,
  "--title",
  `Backplane Nightly ${version}`,
  "--notes-file",
  `${process.env.RUNNER_TEMP}/backplane-nightly-notes.md`,
  "--generate-notes",
  "--draft",
  "--prerelease",
]);
gh(["release", "edit", tag, "--repo", repo, "--draft=false", "--prerelease", "--latest=false"]);
