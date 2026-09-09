# Backplane releases

The [nightly workflow](../../.github/workflows/backplane-nightly.yml) runs daily
at 02:23 UTC on the default branch and can also be dispatched manually. Scheduled
runs skip commits already released. It publishes a dated GitHub prerelease only
after the Linux x64 AppImage and signed Android APK finish successfully. The
release contains those two installers, the Linux updater metadata, and SHA-256
checksums; failed runs leave the previous published nightly available.

Nightlies use the KiCad revision and asset mapping in
`assets/runtime/kicad.json`. Linux uses the existing published archive. The
downloader verifies archive checksums and the bundled source manifest. Python
archives and checksums are pinned per target under `assets/runtime/`. Update
those pins only after the matching runtime builds have passed. Missing runtimes
fail packaging; nightlies never substitute system KiCad. Manual native
workflows remain available for macOS and Windows builds but are not part of the
nightly release.

Android uses a permanent PKCS12 release key stored in repository secrets:
`BACKPLANE_ANDROID_KEYSTORE_BASE64`, `BACKPLANE_ANDROID_KEYSTORE_PASSWORD`,
`BACKPLANE_ANDROID_KEY_ALIAS`, and `BACKPLANE_ANDROID_KEY_PASSWORD`. Keep a secure
backup: changing the key prevents updates over existing signed installations.
An earlier debug-signed local APK must be uninstalled once before installing the
release-signed APK. The APK runs independently of Metro and connects to a
Backplane server; it does not run desktop KiCad on the phone.

The [stable workflow](../../.github/workflows/backplane-release.yml) remains a
manual/tag-driven Linux release that creates a draft for maintainer review.

Configure the KiCad repository variables from a release of `i2cjak/Backplane_KiCad`:

- `BACKPLANE_KICAD_RUNTIME_URL_LINUX_X64`
- `BACKPLANE_KICAD_RUNTIME_SHA256_LINUX_X64`

The Linux x64 Python pin is checked into
[`assets/runtime/python-linux-x64.json`](../../assets/runtime/python-linux-x64.json).
The workflow verifies the install-only archive checksum, then downloads the
matching full-build archive from that file solely to extract `PYTHON.json` and
all 19 files under `python/licenses/` into the packaged runtime's
`LICENSES/` directory. Keep both checksums and both URLs synchronized when
updating the pin.

The runtime archive must contain `bin/kicad-cli` and `manifest.json`. The
manifest must have non-empty `sourceRepository`, `sourceCommit`, `version`,
and `license` fields. The release build sets
`BACKPLANE_REQUIRE_BUNDLED_KICAD=1`, so a missing or unverified runtime fails the
build instead of falling back to a developer's system KiCad.

The packaged server receives the runtime directory through
`BACKPLANE_KICAD_ROOT`. A pinned Python-build-standalone archive is staged at
`resources/python` and passed as `BACKPLANE_PYTHON`, so Gerber rendering does
not depend on a user's Python installation. Developers can use
`BACKPLANE_KICAD_CLI`, `KICAD_CLI`, or `BACKPLANE_PYTHON` for local tools.

For a local Linux build, install the normal desktop prerequisites, then run:

```bash
BACKPLANE_KICAD_RUNTIME=/path/to/stable-kicad-runtime \
BACKPLANE_REQUIRE_BUNDLED_KICAD=1 \
BACKPLANE_PYTHON_RUNTIME=/path/to/python-runtime \
BACKPLANE_REQUIRE_BUNDLED_PYTHON=1 \
BACKPLANE_DESKTOP_UPDATE_REPOSITORY=i2cjak/Backplane \
./node_modules/.bin/vp run dist:desktop:artifact \
  --platform linux --target AppImage --arch x64 --build-version X.Y.Z
```

The runtime path above must contain `bin/kicad-cli` and the provenance
`manifest.json`. The resulting installer is written to `release/`.

The [KiCad runtime workflow](https://github.com/i2cjak/Backplane_KiCad/blob/main/.github/workflows/backplane-linux-release.yml)
pins the official symbol, footprint, 3D model, and project template libraries
to matching stable release commits. The runtime carries their source metadata
and licenses under `licenses/kicad-libraries`; matching source archives accompany
the runtime release.

Library files live under `share/kicad/{symbols,footprints,3dmodels,template}`.
The runtime launcher sets the corresponding `KICAD10_*_DIR` defaults and creates
missing user library tables that reference the bundled stock tables. Existing
user configuration and explicit library path overrides are preserved.
