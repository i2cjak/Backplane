import Base
import ./host.bend as H
import ./proc.bend as P
import ../core/json.bend as J
import ../core/utf8.bend as U
import ../core/kicadcli.bend as KC

# KiCad on this machine: which kicad-cli to use (the Backplane KiCad fork,
# with IPC, when present), a project's canonical files, and the KiStack
# skills. The agents' instructions are built from these, so every session
# is told the same exact paths.

# the CLI, whether it is the Backplane fork, its version and source commit
type Rt is Data:
  Rt{cli: String, fork: Bool, version: String, commit: String}

# a project's canonical design files ("" when it has none)
type Files is Data:
  Files{pro: String, pcb: String, sch: String, all: String}

# why a KiCad export cannot run: no kicad-cli anywhere (Rt.first)
def KiCad.missing() -> String:
  "KiCad is not installed on this machine (no kicad-cli): get it from kicad.org/download or its package manager"

# a KiCad command's result, or KiCad.missing() without a kicad-cli
def KiCad.run(+cli: String, args: List<&2, String>) -> IO(P.Ran):
  Bool.pick(IO(P.Ran), String.is_empty(cli), IO.pure(P.Ran, P.Ran{127, KiCad.missing()}), P.Proc.run(cli, args, "/"))

def KiCad.version() -> String:
  "10.0.6"

def KiCad.release() -> String:
  "backplane-kicad-v10.0.6-2"

# the KiStack commit to fall back on: the latest one found (KiStack.refresh)
# is used once it is here
def KiStack.revision() -> String:
  "ecf16c119c7ed610f5f251c479b03884b8d98b09"

def Io.bytes.done(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  do IO<List<&2, U32>>:
    File.close(f)
    return Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{})

def Io.bytes.sized(r: File & Result<&1, &1, U32 & String, U32>) -> IO(List<&2, U32>):
  (f, res) = r
  IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, List<&2, U32>,
    File.read_bytes(f, U32.max(Result.default(&1, &1, U32 & String, U32, res, 0), 1)), Io.bytes.done)

def Io.bytes.opened(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, U32>):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, List<&2, U32>, File.size(f), Io.bytes.sized)
    case Fail{_}:
      IO.pure(List<&2, U32>, Nil{})

# Files
# -----

# a whole file's bytes ([] when it cannot be read)
def Io.bytes(path: String) -> IO(List<&2, U32>):
  IO.bind(Result<&1, &1, U32 & String, File>, List<&2, U32>, File.open(path, "r"), Io.bytes.opened)

def Io.text(path: String) -> IO(String):
  IO.bind(List<&2, U32>, String, Io.bytes(path), bs => IO.pure(String, U.Utf8.decode(bs)))

def Io.is_file.kind(v: U32 & U32 & U32) -> Bool:
  (k, _) = v
  U32.is_eq(k, 0)

def Io.is_file.k(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> Bool:
  match r:
    case Done{v}:
      Io.is_file.kind(v)
    case Fail{_}:
      False{}

def Io.is_file(path: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(path)
    return Io.is_file.k(r)

def Io.names.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Io.names.copy(t)

def Io.names.k(r: Result<&1, &1, U32 & String, List<String>>) -> List<&2, String>:
  match r:
    case Done{xs}:
      Io.names.copy(xs)
    case Fail{_}:
      Nil{}

def Io.names(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    r : Result<&1, &1, U32 & String, List<String>> <- H.FS.list(path)
    return List.sort(~String, ~String.is_le, Io.names.k(r))

def Rt.manifest.k(m: Maybe<&2, J.Json>, +cli: String) -> Rt:
  match m:
    case Some{+o}:
      Rt{cli, String.contains(J.Json.get_str(o, "sourceRepository", ""), "Backplane_KiCad"), J.Json.get_str(o, "version", ""), J.Json.get_str(o, "sourceCommit", "")}
    case None{}:
      Rt{cli, False{}, "", ""}

# Runtime
# -------

def Rt.manifest(+cli: String, +text: String) -> Rt:
  Rt.manifest.k(J.Json.parse(text), cli)

# <root>/bin/kicad-cli -> <root>
def Rt.root(+cli: String) -> String:
  String.take(cli, Nat.sub(String.length(cli), String.length("/bin/kicad-cli")))

# which of the paths exist, in order
def Io.flags(cs: List<&2, String>) -> IO(List<&2, Bool>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, Bool>, Nil{})
    case c <> t:
      IO.bind(Bool, List<&2, Bool>, Io.is_file(c), ok => IO.bind(List<&2, Bool>, List<&2, Bool>, Io.flags(t), fs => IO.pure(List<&2, Bool>, ok <> fs)))

def Rt.found(cs: List<&2, String>, fs: List<&2, Bool>) -> String:
  match cs fs:
    case c <> _ True{} <> _:
      c
    case _ <> t False{} <> g:
      Rt.found(t, g)
    case _ _:
      ""

def Rt.read(+cli: String) -> IO(Rt):
  IO.bind(String, Rt, Io.text(Rt.root(cli) ++ "/manifest.json"), text => IO.pure(Rt, Rt.manifest(cli, text)))

# a kicad-cli on the PATH, when none is in the usual places ("" when there
# is none: KiCad is not installed, and Settings, the agents and the
# phones' 3D view say so)
def Rt.path.k(r: P.Ran) -> IO(Rt):
  match r:
    case P.Ran{0, +out}:
      Bool.pick(IO(Rt), String.is_empty(String.trim(out)), IO.pure(Rt, Rt{"", False{}, "", ""}), Rt.read(String.trim(out)))
    case _:
      IO.pure(Rt, Rt{"", False{}, "", ""})

def Rt.first.k(+cli: String) -> IO(Rt):
  Bool.pick(IO(Rt), String.is_empty(cli), IO.bind(P.Ran, Rt, P.Proc.run("sh", ["-c", "command -v kicad-cli"], "/"), Rt.path.k), Rt.read(cli))

# the first candidate that exists, with its runtime's manifest read
def Rt.first(+cs: List<&2, String>) -> IO(Rt):
  IO.bind(List<&2, Bool>, Rt, Io.flags(cs), fs => Rt.first.k(Rt.found(cs, fs)))

def KiCad.plat.k(r: P.Ran) -> String:
  match r:
    case P.Ran{_, out}:
      String.trim(out)

# this machine (`uname -sm`)
def KiCad.plat() -> IO(String):
  IO.bind(P.Ran, String, P.Proc.run("uname", ["-sm"], "/"), r => IO.pure(String, KiCad.plat.k(r)))

def Rt.resolve.k(none: Bool, +explicit: String, +exe: String, +data: String) -> IO(Rt):
  match none:
    case True{}:
      do IO<Rt>:
        plat : String <- KiCad.plat()
        h : Result<&1, &1, U32 & String, String> <- IO.get_env("HOME")
        +user : String = Result.default(&1, &1, U32 & String, String, h, "")
        Rt.first(KC.Cli.candidates(plat, exe, data, KiCad.version(), user))
    case False{}:
      Rt.read(explicit)

# an explicit BACKPLANE_KICAD_CLI, then where this machine keeps KiCad
# (KC.Cli.candidates: the fork beside this install or in our data directory
# on Linux x86-64, KiCad.app on a Mac, the system's), then PATH's
def Rt.resolve(+explicit: String, +exe: String, +data: String) -> IO(Rt):
  Rt.resolve.k(String.is_empty(explicit), explicit, exe, data)

# Project files
# -------------

def Files.pick.hit(ns: List<&2, String>, +ext: String) -> Bool:
  match ns:
    case n <> _:
      String.ends_with(n, ext)
    case Nil{}:
      False{}

def Files.pick.go(ns: List<&2, String>, hit: Bool, +ext: String) -> String:
  match ns hit:
    case n <> _ True{}:
      n
    case _ <> +t False{}:
      Files.pick.go(t, Files.pick.hit(t, ext), ext)
    case Nil{} _:
      ""

# the first name with the extension ("" when none)
def Files.pick(+ns: List<&2, String>, +ext: String) -> String:
  Files.pick.go(ns, Files.pick.hit(ns, ext), ext)

def Files.stem(+name: String, +ext: String) -> String:
  String.take(name, Nat.sub(String.length(name), String.length(ext)))

def Files.abs(+root: String, +rel: String) -> String:
  Bool.pick(String, String.is_empty(rel), "", Bool.pick(String, String.starts_with(rel, "/"), rel, root ++ "/" ++ rel))

def Files.named.k(found: Bool, +exact: String, +first: String) -> String:
  Bool.pick(String, found, exact, first)

def Files.in(ns: List<&2, String>, +want: String) -> Bool:
  match ns:
    case Nil{}:
      False{}
    case n <> t:
      Bool.or(String.eq(n, want), Files.in(t, want))

# prefer the file named like the project, else the first of its kind
def Files.named(+ns: List<&2, String>, +stem: String, +ext: String) -> String:
  Files.named.k(Files.in(ns, stem ++ ext), stem ++ ext, Files.pick(ns, ext))

# a path's folder ("" for a name at the root) and its last part
def Files.last(+p: String) -> String:
  Maybe.default(&2, String, List.last(&2, String, String.split(p, '/')), p)

def Files.dir(+p: String) -> String:
  String.take(p, Nat.sub(Nat.sub(String.length(p), String.length(Files.last(p))), Bool.pick(Nat, String.contains(p, "/"), 1n, 0n)))

def Files.in.dir(+dir: String, +name: String) -> String:
  Bool.pick(String, Bool.or(String.is_empty(dir), String.is_empty(name)), name, dir ++ "/" ++ name)

# which .kicad_pro is the project's (a path from the root): the one
# .backplane.json names ("project"), else one in the root, else the first
# found below it (Files.found: shallowest first)
def Files.pro(+named: String, +top: String, +found: String) -> String:
  Bool.pick(String, String.is_empty(named), Bool.pick(String, String.is_empty(top), Maybe.default(&2, String, List.head(&2, String, String.lines(found)), ""), top), named)

# .backplane.json may name "project" (a .kicad_pro), "pcb" and "schematic"
# (all project-relative); the board and schematic are otherwise found
# beside the .kicad_pro (ns: the names in its folder)
def Files.of(+root: String, +pro: String, +ns: List<&2, String>, +cfg: J.Json, +all: String) -> Files:
  +stem = Files.stem(Files.last(pro), ".kicad_pro")
  Files{Files.abs(root, pro),
    Files.abs(root, Bool.pick(String, String.is_empty(J.Json.get_str(cfg, "pcb", "")), Files.in.dir(Files.dir(pro), Files.named(ns, stem, ".kicad_pcb")), J.Json.get_str(cfg, "pcb", ""))),
    Files.abs(root, Bool.pick(String, String.is_empty(J.Json.get_str(cfg, "schematic", "")), Files.in.dir(Files.dir(pro), Files.named(ns, stem, ".kicad_sch")), J.Json.get_str(cfg, "schematic", ""))),
    all}

# every .kicad_pro under the root, four folders deep, as paths from it,
# shallowest first (hidden folders, KiCad's backups and node_modules left
# out; a worktree under .backplane is not the project's)
# (the answer is kept for 30 s per folder in the user's cache: a start asks
# every time, and the walk is the slow part)
def Files.found.sh() -> String:
  "b=\"${XDG_CACHE_HOME:-$HOME/.cache}/backplane-bend/found\"; c=\"$b/$(printf %s \"$1\" | cksum | cut -d' ' -f1)\"; now=$(date +%s); if [ -f \"$c\" ]; then t=$(head -n 1 \"$c\"); case $t in ''|*[!0-9]*) ;; *) if [ $((now - t)) -lt 30 ]; then tail -n +2 \"$c\"; exit 0; fi;; esac; fi; cd \"$1\" 2>/dev/null || exit 0; out=$(find . -mindepth 1 -maxdepth 4 \\( -type d \\( -name '.*' -o -name node_modules -o -name '*-backups' \\) -prune \\) -o -name '*.kicad_pro' -print 2>/dev/null | sed 's|^\\./||' | awk -F/ '{print NF \"\\t\" $0}' | LC_ALL=C sort -t \"$(printf '\\t')\" -k1,1n -k2 | cut -f2- | head -n 50); mkdir -p \"$b\" 2>/dev/null && { printf '%s\\n%s\\n' \"$now\" \"$out\" > \"$c.tmp\" 2>/dev/null && mv \"$c.tmp\" \"$c\"; }; [ -z \"$out\" ] || printf '%s\\n' \"$out\""

def Files.found.out(r: P.Ran) -> String:
  match r:
    case P.Ran{0, +out}:
      String.trim(out)
    case _:
      ""

def Files.found(+root: String) -> IO(String):
  IO.bind(P.Ran, String, P.Proc.run("sh", ["-c", Files.found.sh(), "sh", root], "/"), r => IO.pure(String, Files.found.out(r)))

def Files.read.at(+root: String, +pro: String, +cfg: J.Json, +all: String) -> IO(Files):
  IO.bind(List<&2, String>, Files, Io.names(Bool.pick(String, String.is_empty(Files.dir(pro)), root, Files.abs(root, Files.dir(pro)))), ns => IO.pure(Files, Files.of(root, pro, ns, cfg, all)))

def Files.read.cfg(+root: String, +cfg: J.Json) -> IO(Files):
  do IO<Files>:
    +ns : List<&2, String> <- Io.names(root)
    +all : String <- Files.found(root)
    Files.read.at(root, Files.pro(J.Json.get_str(cfg, "project", ""), Files.pick(ns, ".kicad_pro"), all), cfg, all)

def Files.read(+root: String) -> IO(Files):
  IO.bind(String, Files, Io.text(root ++ "/.backplane.json"), text => Files.read.cfg(root, Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})))

def KiStack.ensure.k(have: Bool, +dir: String) -> IO(Unit):
  match have:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(dir)
        r : P.Ran <- P.Proc.run("sh", ["-c", "curl -fsSL --max-time 120 \"$1\" | tar -xz -C \"$2\" --strip-components=1", "sh",
          "https://codeload.github.com/American-Embedded/KiStack/tar.gz/" ++ KiStack.revision(), dir], "/")
        return Unit{}

# KiStack
# -------

# KiStack's latest commit, fetched off the hub's start: downloaded once,
# checked, and named in <base>/current, which the next start uses (a start
# never waits on the network; offline, the one there or the pinned one)
def KiStack.base(+home: String) -> String:
  home ++ "/.cache/backplane/kistack"

def KiStack.refresh.sh() -> String:
  "base=$1; sha=$(curl -fsSL --max-time 20 -H 'Accept: application/vnd.github.sha' https://api.github.com/repos/American-Embedded/KiStack/commits/HEAD) || exit 0; case $sha in ''|*[!0-9a-f]*) exit 0;; esac; if [ ! -f \"$base/$sha/skills/pcb/SKILL.md\" ]; then rm -rf \"$base/$sha.new\"; mkdir -p \"$base/$sha.new\"; curl -fsSL --max-time 120 \"https://codeload.github.com/American-Embedded/KiStack/tar.gz/$sha\" | tar -xz -C \"$base/$sha.new\" --strip-components=1 || exit 0; [ -f \"$base/$sha.new/skills/pcb/SKILL.md\" ] || exit 0; rm -rf \"$base/$sha\"; mv \"$base/$sha.new\" \"$base/$sha\"; fi; printf '%s\\n' \"$sha\" > \"$base/current.new\" && mv \"$base/current.new\" \"$base/current\""

def KiStack.refresh(+home: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", KiStack.refresh.sh(), "sh", KiStack.base(home)], "/"), r => IO.pure(Unit, Unit{}))

def KiStack.current.k(ok: Bool, +sha: String) -> String:
  Bool.pick(String, Bool.and(ok, Bool.not(String.is_empty(sha))), sha, KiStack.revision())

# the revision a start uses: the latest one fetched, else the pinned one
def KiStack.current(+home: String) -> IO(String):
  do IO<String>:
    +sha : String <- IO.bind(String, String, Io.text(KiStack.base(home) ++ "/current"), t => IO.pure(String, String.trim(t)))
    ok : Bool <- Io.is_file(KiStack.base(home) ++ "/" ++ sha ++ "/skills/pcb/SKILL.md")
    return KiStack.current.k(ok, sha)

# a revision directory made a Claude Code plugin named kistack (its skills
# are already where a plugin keeps them), so every Claude thread gets them
# as its own skills through --plugin-dir
def KiStack.plugin.sh() -> String:
  "[ -d \"$1/skills\" ] || exit 0; [ -f \"$1/.claude-plugin/plugin.json\" ] && exit 0; mkdir -p \"$1/.claude-plugin\" && printf '%s\\n' '{\"name\":\"kistack\",\"description\":\"KiStack KiCad skills by American Embedded\"}' > \"$1/.claude-plugin/plugin.json\""

def KiStack.plugin(+dir: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", KiStack.plugin.sh(), "sh", dir], "/"), r => IO.pure(Unit, Unit{}))

# the skills live in <cache>/backplane/kistack/<revision>/skills (shared with
# the TypeScript Backplane); with no latest revision fetched yet, fetch the
# pinned one when it is missing
def KiStack.ensure(+home: String) -> IO(Unit):
  do IO<Unit>:
    rev : String <- KiStack.current(home)
    +dir : String = KiStack.base(home) ++ "/" ++ rev
    have : Bool <- Io.is_file(dir ++ "/skills/pcb/SKILL.md")
    KiStack.ensure.k(have, dir)
    KiStack.plugin(dir)

def KiCad.install.k(r: P.Ran) -> String:
  match r:
    case P.Ran{0, _}:
      ""
    case P.Ran{_, out}:
      "KiCad install failed: " ++ String.trim(out)

# The fork, installed on request
# ------------------------------

# download this machine's build of Backplane KiCad, check it against the
# release's SHA256SUMS, unpack into its folder (KC.Cli.dir, emptied first);
# answers "" or an error
def KiCad.install.go(+data: String, +asset: String) -> IO(String):
  do IO<String>:
    +dir : String = KC.Cli.dir(data, KiCad.version(), asset)
    +name : String = KC.Cli.package(asset, KiCad.version())
    +base : String = "https://github.com/i2cjak/Backplane_KiCad/releases/download/" ++ KiCad.release() ++ "/"
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(dir)
    r : P.Ran <- P.Proc.run("sh", ["-c",
      "set -e; rm -rf \"$1\"; mkdir -p \"$1\"; cd \"$1\"; curl -fsSL -o pkg.tgz \"$2$3\"; curl -fsSL -o SUMS \"$2SHA256SUMS\"; want=$(awk -v n=\"$3\" '$2 == n || $2 == \"./\" n { print $1 }' SUMS); got=$({ command -v sha256sum >/dev/null && sha256sum pkg.tgz || shasum -a 256 pkg.tgz; } | cut -d' ' -f1); [ \"$want\" = \"$got\" ] || { echo checksum mismatch; exit 1; }; tar -xzf pkg.tgz --strip-components=1; rm pkg.tgz SUMS",
      "sh", dir, base, name], "/")
    return KiCad.install.k(r)

def KiCad.install.on(runs: Bool, +data: String, +asset: String) -> IO(String):
  match runs:
    case True{}:
      KiCad.install.go(data, asset)
    case False{}:
      IO.pure(String, KC.Cli.no_fork())

def KiCad.install.at(+plat: String, +data: String) -> IO(String):
  KiCad.install.on(KC.Cli.fork_runs(plat), data, KC.Cli.asset(plat))

# this machine's build of the fork (KC.Cli.asset); where there is none, why not
def KiCad.install(+data: String) -> IO(String):
  IO.bind(String, String, KiCad.plat(), plat => KiCad.install.at(plat, data))

# Opening a project
# -----------------

def KiCad.open.said(r: P.Ran) -> String:
  match r:
    case P.Ran{0, _}:
      ""
    case P.Ran{_, out}:
      String.trim(out)

def KiCad.open.k(fork: Bool, +cli: String, +fs: Files) -> IO(String):
  match fork fs:
    case True{} Files{+pro, +pcb, +sch, _}:
      do IO<String>:
        r : P.Ran <- P.Proc.run("sh", ["-c",
          "r=\"$1\"; if [ -n \"$2\" ]; then set -- kicad \"$2\"; elif [ -n \"$3\" ]; then set -- pcbnew \"$3\"; elif [ -n \"$4\" ]; then set -- eeschema \"$4\"; else echo \"no KiCad project here\"; exit 1; fi; [ -x \"$r/bin/$1\" ] || { echo \"Backplane KiCad has no $1\"; exit 1; }; if command -v setsid >/dev/null 2>&1; then setsid -f \"$r/bin/$1\" \"$2\" </dev/null >/dev/null 2>&1; else nohup \"$r/bin/$1\" \"$2\" </dev/null >/dev/null 2>&1 & fi",
          "sh", Rt.root(cli), pro, pcb, sch], "/")
        return KiCad.open.said(r)
    case False{} _:
      IO.pure(String, "Install Backplane KiCad (Settings) to open projects in it")

# open a project's .kicad_pro in the bundled KiCad (its board or schematic
# editor when there is no .kicad_pro), detached; answers "" or an error.
# Only the Backplane fork: its launcher brings the official libraries
def KiCad.open(rt: Rt, +fs: Files) -> IO(String):
  match rt:
    case Rt{+cli, fork, _, _}:
      KiCad.open.k(fork, cli, fs)
