#!/usr/bin/env bash
set -euo pipefail

: "${BACKPLANE_RELEASE_VERSION:?BACKPLANE_RELEASE_VERSION is required}"
: "${BACKPLANE_RELEASE_VERSION_CODE:?BACKPLANE_RELEASE_VERSION_CODE is required}"
: "${BACKPLANE_ANDROID_KEYSTORE_PATH:?BACKPLANE_ANDROID_KEYSTORE_PATH is required}"
: "${BACKPLANE_ANDROID_KEYSTORE_PASSWORD:?BACKPLANE_ANDROID_KEYSTORE_PASSWORD is required}"
: "${BACKPLANE_ANDROID_KEY_ALIAS:?BACKPLANE_ANDROID_KEY_ALIAS is required}"
: "${BACKPLANE_ANDROID_KEY_PASSWORD:?BACKPLANE_ANDROID_KEY_PASSWORD is required}"

if ! [[ "$BACKPLANE_RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "BACKPLANE_RELEASE_VERSION must be a semantic version, received '$BACKPLANE_RELEASE_VERSION'." >&2
  exit 1
fi
if ! [[ "$BACKPLANE_RELEASE_VERSION_CODE" =~ ^[1-9][0-9]*$ ]]; then
  echo "BACKPLANE_RELEASE_VERSION_CODE must be a positive integer, received '$BACKPLANE_RELEASE_VERSION_CODE'." >&2
  exit 1
fi

export APP_VARIANT="${APP_VARIANT:-production}"
export EXPO_NO_GIT_STATUS=1
export NODE_ENV=production

pnpm exec expo prebuild --clean --platform android
(
  cd android
  ./gradlew :app:assembleRelease \
    -PreactNativeArchitectures="${ANDROID_ARCHITECTURES:-arm64-v8a,x86_64}"
)

apk="android/app/build/outputs/apk/release/app-release.apk"
test -f "$apk"

build_tools_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/build-tools"
apksigner="$(find "$build_tools_dir" -maxdepth 2 -type f -name apksigner -print 2>/dev/null | sort -V | tail -n 1)"
aapt="$(find "$build_tools_dir" -maxdepth 2 -type f -name aapt -print 2>/dev/null | sort -V | tail -n 1)"
test -x "$apksigner"
test -x "$aapt"
"$apksigner" verify --verbose --print-certs "$apk" | grep -q "Verified using v2 scheme (APK Signature Scheme v2)"
badging="$("$aapt" dump badging "$apk")"
grep -q "package: name='${BACKPLANE_ANDROID_PACKAGE:-works.backplane.app}'" <<< "$badging"
grep -q "versionCode='${BACKPLANE_RELEASE_VERSION_CODE}'" <<< "$badging"
grep -q "versionName='${BACKPLANE_RELEASE_VERSION}'" <<< "$badging"

release_apk="android/app/build/outputs/apk/release/Backplane-${BACKPLANE_RELEASE_VERSION}-android.apk"
mv "$apk" "$release_apk"
echo "Built and verified $release_apk"
