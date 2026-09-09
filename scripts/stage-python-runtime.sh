#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $0 --platform linux|mac|win --arch x64|arm64 --destination DIR [--check]" >&2; }
platform=""; arch=""; destination=""; check_only=0
while (($#)); do
  case "$1" in
    --platform) platform="${2:?missing value for --platform}"; shift 2 ;;
    --arch) arch="${2:?missing value for --arch}"; shift 2 ;;
    --destination) destination="${2:?missing value for --destination}"; shift 2 ;;
    --check) check_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
case "$platform:$arch" in linux:x64|mac:arm64|mac:x64|win:x64) ;; *) echo "Unsupported target: ${platform:-?}/${arch:-?}" >&2; exit 2 ;; esac
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
metadata="$repo_root/assets/runtime/python-$platform-$arch.json"
[[ -f "$metadata" ]] || { echo "Missing metadata: $metadata" >&2; exit 1; }
command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar is required" >&2; exit 1; }

if ((check_only)); then
  node - "$metadata" <<'NODE'
const fs = require("node:fs");
const metadata = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const key of ["runtime", "version", "release", "platform", "arch", "installOnly", "fullBuild"]) if (!metadata[key]) throw new Error(`metadata is missing ${key}`);
for (const key of ["installOnly", "fullBuild"]) {
  if (!/^https:\/\/github\.com\/astral-sh\/python-build-standalone\/releases\/download\//.test(metadata[key].url)) throw new Error(`unexpected ${key} URL`);
  if (!/^[0-9a-f]{64}$/.test(metadata[key].sha256)) throw new Error(`invalid ${key} SHA-256`);
}
console.log(`${metadata.platform}/${metadata.arch}: CPython ${metadata.version} (${metadata.release})`);
NODE
  exit 0
fi
if [[ -z "$destination" ]]; then destination="$repo_root/apps/desktop/prod-resources/python-runtime"; fi
mkdir -p "$destination"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/backplane-python.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
read -r install_url install_sha full_url full_sha version < <(node - "$metadata" <<'NODE'
const fs = require("node:fs"); const m = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
console.log(m.installOnly.url, m.installOnly.sha256, m.fullBuild.url, m.fullBuild.sha256, m.version);
NODE
)
download_and_verify() {
  local url="$1" expected="$2" output="$3"; curl --fail --location --retry 3 --retry-all-errors "$url" --output "$output"
  if command -v sha256sum >/dev/null; then echo "$expected  $output" | sha256sum --check --status; else echo "$expected  $output" | shasum -a 256 --check --status; fi
}
archive="$tmp_dir/install.tar.gz"; download_and_verify "$install_url" "$install_sha" "$archive"; tar -xzf "$archive" -C "$tmp_dir"
[[ -f "$tmp_dir/python/bin/python3" || -f "$tmp_dir/python/python.exe" ]] || { echo "install archive has an unexpected layout" >&2; exit 1; }
staged="$tmp_dir/staged"; mkdir -p "$staged"
if [[ "$platform" == win ]]; then mkdir -p "$staged/bin"; mv "$tmp_dir/python"/* "$staged/bin/"; executable="$staged/bin/python.exe"; else mv "$tmp_dir/python"/* "$staged/"; executable="$staged/bin/python3"; fi
full_archive="$tmp_dir/full.tar.zst"; full_tar="$tmp_dir/full.tar"; download_and_verify "$full_url" "$full_sha" "$full_archive"; mkdir -p "$staged/LICENSES"
# Node 24 has a zstd stream decoder on every runner. This avoids relying on
# GNU tar's optional external `zstd` binary (which is absent on macOS/Windows).
node - "$full_archive" "$full_tar" <<'NODE'
const fs = require("node:fs");
const { pipeline } = require("node:stream/promises");
const { createZstdDecompress } = require("node:zlib");
pipeline(fs.createReadStream(process.argv[2]), createZstdDecompress(), fs.createWriteStream(process.argv[3])).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
NODE
tar -xOf "$full_tar" python/PYTHON.json > "$staged/PYTHON.json"
while IFS= read -r license_path; do [[ -n "$license_path" ]] || continue; tar -xOf "$full_tar" "$license_path" > "$staged/LICENSES/${license_path##*/}"; done < <(tar -tf "$full_tar" | awk '/^python\/licenses\/LICENSE\..+\.txt$/')
license_count="$(find "$staged/LICENSES" -type f -name 'LICENSE.*.txt' | wc -l)"
((license_count > 0)) || { echo "full archive did not contain license files" >&2; exit 1; }
cat > "$staged/LICENSES/SOURCE.txt" <<EOF
python-build-standalone CPython $version
Install-only source: $install_url
Install-only SHA-256: $install_sha
Full-build metadata source: $full_url
Full-build SHA-256: $full_sha
EOF
[[ -f "$executable" ]] || { echo "staged executable is missing: $executable" >&2; exit 1; }; [[ "$platform" == win ]] || chmod +x "$executable"
rm -rf "$destination"; mv "$staged" "$destination"; echo "Staged CPython $version at $destination"
