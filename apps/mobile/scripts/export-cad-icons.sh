#!/usr/bin/env bash
set -euo pipefail

# Render the CAD vectors, rather than modifying the legacy Icon Composer exports.
mobile_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for variant in production development preview foreground monochrome notification; do
  magick -background none "$mobile_root/assets/cad/$variant.svg" \
    -strip "PNG32:$mobile_root/assets/cad/$variant.png"
done
