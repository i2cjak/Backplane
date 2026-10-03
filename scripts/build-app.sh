#!/bin/sh
# Build a Bend program to a native binary in parallel, gently.
#
#   scripts/build-app.sh src/app/main.bend build/backplane
#
# `bend X -o bin` compiles one ~30 MB C file on one core (minutes, ~20 GB).
# Here bend emits the C, scripts/cc-split.py deals it into units, and clang
# compiles them side by side at low priority, so the machine stays usable.
# Builds on this machine share one lock (/tmp/bp-wt-build.lock, as the
# agents' builds do), so only one runs at a time, and stay on 4 cores.
#   BACKPLANE_JOBS  parallel compiles (default 4)
#   BACKPLANE_CPUS  the cores builds may use (default 0-3; "" for any)
#   BACKPLANE_CFLAGS  (default: -O3, as bend -o)
# The Google OAuth client "Connect Google" signs in with is baked in from
# BACKPLANE_GOOGLE_CLIENT_ID and _SECRET: the environment's (CI secrets), else
# a git-ignored .env here or in the main checkout (src/server/effects/google.c).
# BACKPLANE_GOOGLE_BAKE=0 bakes none (test/tools/google_e2e.ts).
set -eu
# (a caller already inside `flock /tmp/bp-wt-build.lock ...` holds it)
held() {
  p=$$
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    case $(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) in
      *flock*bp-wt-build.lock*) return 0 ;;
    esac
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
  done
  return 1
}
if [ -z "${BP_BUILD_LOCKED:-}" ] && command -v flock >/dev/null 2>&1 && ! held; then
  BP_BUILD_LOCKED=1 exec flock /tmp/bp-wt-build.lock "$0" "$@"
fi
src=$1
out=$2
cd "$(dirname "$0")/.."
jobs=${BACKPLANE_JOBS:-4}
# bend is a Bun program: JavaScriptCore sizes its heap to the machine's RAM
# and let the app's emit grow past 28 GB (systemd-oomd then killed whole
# desktop sessions). Told the machine has 12 GB, it peaks near 12 GB and
# takes a few seconds longer.
export BUN_JSC_forceRAMSize=${BUN_JSC_forceRAMSize:-12884901888}
cpus=${BACKPLANE_CPUS-0-3}
pin=""
if [ -n "$cpus" ] && command -v taskset >/dev/null 2>&1; then
  pin="taskset -c $cpus"
fi
cflags=${BACKPLANE_CFLAGS:--O3}
CC=${CC:-clang}
export CC
work="build/cc/$(basename "$out")"
mkdir -p "$work"
# bend's own emit runs on every core; keep it polite too. Its C is the
# same on every platform (effects choose with #ifdef), so it may be made
# on another machine: BACKPLANE_EMIT_ONLY=1 stops after writing it, and
# BACKPLANE_PREBUILT=1 compiles the one already there
if [ "${BACKPLANE_PREBUILT:-}" = 1 ] && [ -f "$work/all.c" ]; then
  echo "prebuilt $work/all.c"
else
  nice -n 19 $pin bend "$src" -o "$work/all.c" >/dev/null
fi
[ "${BACKPLANE_EMIT_ONLY:-}" = 1 ] && { echo "$work/all.c"; exit 0; }
n=$(nice -n 19 python3 scripts/cc-split.py "$work/all.c" "$work" "$(( jobs * 2 ))")
rm -f "$work"/u*.o
# the baked Google client, read from .env without running it
envval() {
  for f in .env "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/../.env"; do
    [ -f "$f" ] || continue
    v=$(sed -n "s/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}$1=//p" "$f" | tail -n1 | tr -d "\"'\r")
    [ -n "$v" ] && { printf %s "$v"; return; }
  done
}
gid=${BACKPLANE_GOOGLE_CLIENT_ID:-$(envval BACKPLANE_GOOGLE_CLIENT_ID)}
gsec=${BACKPLANE_GOOGLE_CLIENT_SECRET:-$(envval BACKPLANE_GOOGLE_CLIENT_SECRET)}
rm -f "$work/bp_google.h"
if [ "${BACKPLANE_GOOGLE_BAKE:-1}" != 0 ] && [ -n "$gid" ] && [ -n "$gsec" ]; then
  case "$gid$gsec" in
    *[!A-Za-z0-9._-]*) echo "BACKPLANE_GOOGLE_CLIENT_ID/_SECRET: unexpected characters" >&2; exit 1 ;;
  esac
  printf '#define BP_GOOGLE_CLIENT_ID "%s"\n#define BP_GOOGLE_CLIENT_SECRET "%s"\n' "$gid" "$gsec" > "$work/bp_google.h"
  echo "baked Google client ${gid%%-*}-..."
fi
ls "$work"/u*.c | nice -n 19 $pin xargs -P "$jobs" -I{} sh -c \
  '"$CC" -std=c11 '"$cflags"' -w -c "$1" -o "${1%.c}.o" || { echo "cc failed: $1" >&2; exit 255; }' _ {}
# the libraries bend -o links: X11 and ALSA when an effect includes them
libs=""
grep -q '#include <X11/' "$work/all.c" && libs="$libs -lX11"
grep -q '#include <alsa/' "$work/all.c" && libs="$libs -lasound"
nice -n 19 $pin "$CC" $cflags "$work"/u*.o -o "$out" -lpthread -lm $libs
echo "$out ($n units, $jobs jobs)"
