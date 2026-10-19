#!/bin/sh
# Package what scripts/build.sh left in dist/ as a Mac app:
#   dist/Backplane.app                              the hub and helpers in
#                                                   Contents/Resources/backplane,
#                                                   the window (mac/Backplane)
#   dist/backplane-<version>-darwin-arm64.app.zip   for the release
#   scripts/package-mac.sh v0.11.0
# The app is ad-hoc signed (no Developer ID): a downloaded copy opens after
# System Settings > Privacy & Security > Open Anyway. It updates as a whole,
# never file by file inside it (the hub runs with BACKPLANE_NO_UPDATE).
set -eu
cd "$(dirname "$0")/.."
ver=$1
[ "$(uname -s)" = Darwin ] || { echo "package-mac.sh runs on macOS"; exit 1; }
[ -x dist/backplane ] && [ -d dist/web ] || { echo "run scripts/build.sh first"; exit 1; }
v=${ver#v}
short=${v%%-*}
app=dist/Backplane.app
rm -rf "$app" build/mac && mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/backplane" build/mac

# the window
swiftc -O -swift-version 5 -target arm64-apple-macos13 \
  -framework Cocoa -framework WebKit \
  mac/Backplane/main.swift -o "$app/Contents/MacOS/Backplane"
sed -e "s/@SHORT@/$short/" -e "s/@VERSION@/$v/" mac/Backplane/Info.plist.in > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

# the icon, from the largest PNG (the iconset's 1024 is left out)
set_=build/mac/AppIcon.iconset
mkdir -p "$set_"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/icon/backplane-512.png --out "$set_/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); [ $d -le 512 ] && sips -z $d $d assets/icon/backplane-512.png --out "$set_/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_" -o "$app/Contents/Resources/AppIcon.icns"

# the hub: the same files as the tarball (scripts/package.sh)
res="$app/Contents/Resources/backplane"
cp dist/backplane dist/backplane-serve LICENSE "$res/"
cp -R dist/web "$res/web"
for h in backplane-browser backplane-step2glb backplane-voice; do
  [ -f "dist/$h" ] && cp "dist/$h" "$res/"
done
[ -d dist/licenses ] && cp -R dist/licenses "$res/licenses"

# sign the window and seal the bundle; the hub and helpers inside are
# resources to the seal and keep their own signatures (bun's executables
# break when signed again)
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"

rm -f "dist/backplane-$ver-darwin-arm64.app.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/backplane-$ver-darwin-arm64.app.zip"
ls -la "dist/backplane-$ver-darwin-arm64.app.zip"
