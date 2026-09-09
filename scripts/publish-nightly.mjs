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
for (const pattern of [/\.AppImage$/, /\.apk$/, /^nightly-linux\.yml$/]) {
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
const notes = `Automated Backplane nightly from ${sha}.

Download the Linux x64 AppImage or signed Android APK. The Linux desktop includes the Backplane server, modified KiCad, Python, and standard KiCad libraries. Android connects to a Backplane server.

Nightlies are prereleases; the Linux desktop updater stays on the Backplane nightly channel.

KiCad source and license information: https://github.com/i2cjak/Backplane_KiCad/releases. The bundled runtime manifest identifies its source revision. Verify downloads with SHA256SUMS.
`;
await writeFile(`${process.env.RUNNER_TEMP}/backplane-nightly-notes.md`, notes);
const gh = (args) => execFileSync("gh", args, { stdio: "inherit" });
// Resume an interrupted upload only while the release is still a draft.
let existing;
try {
  existing = JSON.parse(
    execFileSync(
      "gh",
      ["release", "view", tag, "--repo", repo, "--json", "isDraft,targetCommitish"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    ),
  );
} catch (error) {
  if (error.status !== 1) throw error;
}
if (existing && (!existing.isDraft || existing.targetCommitish !== sha)) {
  throw new Error("Refusing to overwrite a published nightly or a draft from another commit");
}
const assets = [...files.map((name) => `release-publish/${name}`), "release-publish/SHA256SUMS"];
if (existing) {
  gh(["release", "upload", tag, ...assets, "--repo", repo, "--clobber"]);
} else {
  gh([
    "release",
    "create",
    tag,
    ...assets,
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
}
gh(["release", "edit", tag, "--repo", repo, "--draft=false", "--prerelease", "--latest=false"]);
