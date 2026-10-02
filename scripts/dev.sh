#!/bin/sh
# Try this checkout without CI or a release.
#
#   scripts/dev.sh                 build the app + web client into build/dev
#                                  and run it beside your installed Backplane
#   scripts/dev.sh run --no-build  run the last dev build again
#   scripts/dev.sh web             rebuild only the web client (reload the page;
#                                  the hub reads it from disk per request)
#   scripts/dev.sh install         app + server + web client + voice helper,
#                                  installed over ~/.local/share/backplane,
#                                  service restarted
#   scripts/dev.sh install h@host  the same onto another machine over ssh
#                                  (same os/arch; restarts backplane-bend there)
#   scripts/dev.sh install --force [h@host]
#                                  install even while threads work: without it
#                                  install refuses while the running hub's
#                                  /hello says "busy" (threads running a turn
#                                  or waiting on background work, which the
#                                  restart would cut off)
#
# The dev run keeps to itself: its own home (BACKPLANE_DEV_HOME, default
# ~/.backplane-dev, never ~/.backplane-bend), port 3788 (BACKPLANE_DEV_PORT),
# no tailnet, no self-update. Its window opens next to your normal one.
# The voice helper is built from this checkout (it takes a second); the
# browser and step2glb helpers are borrowed from the installed copy.
#
# An installed build is stamped <next patch>-dev.<date>.<time>, e.g.
# 0.10.1-dev.20260925.2130: newer than the release it came after, older than
# the next one, so the updater replaces it with the next real release (or a
# later nightly) and never with an older one.
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.bend/bin:$HOME/.bun/bin:$PATH"
# 4 clang jobs at -O3 passed 28 GB here; 2 stay near 12 GB
export BACKPLANE_JOBS=${BACKPLANE_JOBS:-2}
prefix=${BACKPLANE_PREFIX:-$HOME/.local/share/backplane}
dev=build/dev
port=${BACKPLANE_DEV_PORT:-3788}
home=${BACKPLANE_DEV_HOME:-$HOME/.backplane-dev}

say() { printf '\033[1mdev:\033[0m %s\n' "$*"; }

check() {
  out=$(bend "$1" --check-only 2>&1) || { echo "$out"; exit 1; }
  case $out in *"All terms check"*) ;; *) echo "$out"; exit 1 ;; esac
}

build_web() {
  check src/web/app.bend
  rm -rf "$dev/web.new"
  bend src/web/index.html -o "$dev/web.new" >/dev/null
  cp src/web/sw.js "$dev/web.new/sw.js"
  for f in "$dev"/web.new/*.js "$dev"/web.new/*.css "$dev"/web.new/*.html; do gzip -9 -k -n -f "$f"; done
  rm -rf "$dev/web" && mv "$dev/web.new" "$dev/web"
}

# the voice helper (Bun, one executable) into $1
build_voice() {
  out=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  (cd tools/voice && bun build.ts "$out.new" >/dev/null)
  mv -f "$out.new" "$out"
}

build_app() {
  check src/app/main.bend
  scripts/build-app.sh src/app/main.bend "$dev/backplane.new"
  mv -f "$dev/backplane.new" "$dev/backplane"
  rm -f "$dev/backplane-voice"
  build_voice "$dev/backplane-voice"
  for h in backplane-browser backplane-step2glb; do
    [ -e "$prefix/$h" ] && ln -sf "$prefix/$h" "$dev/$h"
  done
  return 0
}

run() {
  [ -x "$dev/backplane" ] || { say "no dev build yet: run scripts/dev.sh"; exit 1; }
  mkdir -p "$home"
  say "http://127.0.0.1:$port  home $home  (ctrl-c stops it)"
  BACKPLANE_NO_UPDATE=1 exec "$dev/backplane" --home "$home" --port "$port" --no-tailscale
}

stamp() {
  # the highest full release, whether or not this branch contains it
  git fetch -q --tags 2>/dev/null || true
  last=$(git tag --list 'v[0-9]*' --sort=-v:refname | grep -v -- - | head -n 1)
  last=${last:-v0.0.0}
  core=${last#v}; core=${core%%-*}
  echo "${core%.*}.$(( ${core##*.} + 1 ))-dev.$(date +%Y%m%d.%H%M)"
}

# the app, the server, the web client and the voice helper into dist/,
# stamped; src/core/version.bend is put back after. The browser and step2glb
# helpers are not rebuilt: the installed ones stay (scripts/build.sh builds
# them for releases)
build_dist() {
  ver=$(stamp)
  keep=$(mktemp)
  cp src/core/version.bend "$keep"
  trap 'cp "$keep" src/core/version.bend; rm -f "$keep"' EXIT
  printf 'import Base\n\n# The running build'"'"'s version (stamped by scripts/build.sh).\n\ndef Version.current() -> String:\n  "%s"\n' "$ver" > src/core/version.bend
  for f in src/web/app.bend src/server/main.bend src/app/main.bend; do check "$f"; done
  rm -rf dist && mkdir -p dist
  bend src/web/index.html -o dist/web >/dev/null
  cp src/web/sw.js dist/web/sw.js
  for f in dist/web/*.js dist/web/*.css dist/web/*.html; do gzip -9 -k -n -f "$f"; done
  scripts/build-app.sh src/server/main.bend dist/backplane-serve
  scripts/build-app.sh src/app/main.bend dist/backplane
  build_voice dist/backplane-voice
  cp "$keep" src/core/version.bend
  say "built $ver"
}

# swap dist/ into a prefix the way deploy/install.sh.in does (renames, so a
# running binary is replaced safely); run here or over ssh
install_into() {
  cat <<'EOF'
set -eu
src=$1 prefix=$2
mkdir -p "$prefix" "$HOME/.local/bin"
rm -rf "$prefix/web.old"
[ -d "$prefix/web" ] && mv "$prefix/web" "$prefix/web.old"
mv "$src/web" "$prefix/web"
for f in backplane backplane-serve backplane-browser backplane-step2glb backplane-voice LICENSE; do
  [ -e "$src/$f" ] && mv -f "$src/$f" "$prefix/$f"
done
ln -sf "$prefix/backplane" "$HOME/.local/bin/backplane"
ln -sf "$prefix/backplane-serve" "$HOME/.local/bin/backplane-serve"
EOF
}

stage() {
  rm -rf build/dev-pkg && mkdir -p build/dev-pkg
  cp -R dist/web build/dev-pkg/web
  for f in backplane backplane-serve backplane-browser backplane-step2glb backplane-voice; do
    [ -e "dist/$f" ] && cp "dist/$f" build/dev-pkg/
  done
  [ -e LICENSE ] && cp LICENSE build/dev-pkg/
  return 0
}

# how many threads the hub answering /hello says run or wait on work
# (CBOR: the "busy" key's unsigned integer; 0 when it does not say)
busy_js() {
  printf %s 'const b=new Uint8Array(await Bun.stdin.arrayBuffer());const k=[0x64,0x62,0x75,0x73,0x79];let n=0;for(let i=0;i+5<b.length;i++){if(k.every((x,j)=>b[i+j]===x)){const h=b[i+5];n=h<24?h:h===24?b[i+6]:h===25?(b[i+6]<<8)|b[i+7]:0;break}}console.log(n)'
}

busy_of() {
  bun -e "$(busy_js)"
}

# refuse to restart a hub whose threads are at work, unless --force
check_busy() {
  [ "$force" = 1 ] && return 0
  n=$(eval "$1" 2>/dev/null | busy_of 2>/dev/null || echo 0)
  if [ "${n:-0}" -gt 0 ]; then
    say "the hub has $n thread(s) at work; an install restarts it and cuts them off. Try again later, or pass --force."
    exit 1
  fi
}

install_local() {
  hello="curl -s --max-time 5 http://127.0.0.1:${BACKPLANE_INSTALL_PORT:-3787}/hello"
  check_busy "$hello"
  build_dist
  stage
  # the build takes minutes: look again right before the files are replaced
  check_busy "$hello"
  install_into | sh -s "$PWD/build/dev-pkg" "$prefix"
  say "installed into $prefix"
  if systemctl --user is-active --quiet backplane.service 2>/dev/null; then
    # the restart ends every session inside the app (this one too, if it
    # runs there), so it waits a few seconds for this script to finish
    # (and looks once more then: a turn may have started meanwhile)
    if [ "$force" = 1 ]; then
      systemd-run --user --quiet --on-active=5 systemctl --user restart backplane.service
    else
      bun_bin=$(command -v bun)
      systemd-run --user --quiet --on-active=5 sh -c "n=\$(curl -s --max-time 5 http://127.0.0.1:${BACKPLANE_INSTALL_PORT:-3787}/hello | '$bun_bin' -e '$(busy_js)' 2>/dev/null || echo 0); if [ \"\${n:-0}\" -gt 0 ]; then echo \"backplane.service not restarted: \$n thread(s) at work\" | systemd-cat -t backplane-install; else systemctl --user restart backplane.service; fi"
    fi
    say "backplane.service restarts in 5 s (unless threads are at work then)"
  else
    say "run: backplane"
  fi
}

install_remote() {
  host=$1
  check_busy "ssh $host curl -s --max-time 5 http://127.0.0.1:${BACKPLANE_INSTALL_PORT:-3787}/hello"
  build_dist
  stage
  rdir=$(ssh "$host" mktemp -d)
  tar -C build/dev-pkg -czf - . | ssh "$host" tar -C "$rdir" -xzf -
  # the build and copy take minutes: look again before the files are replaced
  check_busy "ssh $host curl -s --max-time 5 http://127.0.0.1:${BACKPLANE_INSTALL_PORT:-3787}/hello"
  install_into | ssh "$host" sh -s "$rdir" '$HOME/.local/share/backplane'
  check_busy "ssh $host curl -s --max-time 5 http://127.0.0.1:${BACKPLANE_INSTALL_PORT:-3787}/hello"
  ssh "$host" "rm -rf $rdir; systemctl --user restart backplane-bend.service 2>/dev/null || systemctl --user restart backplane.service 2>/dev/null || true"
  say "installed on $host"
}

mkdir -p "$dev"
case ${1:-run} in
  run)
    [ "${2:-}" = --no-build ] || { build_web; build_app; }
    run ;;
  web)
    build_web
    say "web client rebuilt: reload the page" ;;
  install)
    force=0
    shift
    if [ "${1:-}" = --force ]; then force=1; shift; fi
    if [ -n "${1:-}" ]; then install_remote "$1"; else install_local; fi ;;
  *)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
