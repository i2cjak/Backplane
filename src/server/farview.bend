import Base
import ./host.bend as H
import ./proc.bend as P
import ./botnet.bend as BN
import ../core/json.bend as J
import ../core/utf8.bend as U
import ../core/http.bend as W
import ../core/far.bend as FR
import ../core/fview.bend as FV
import ../core/mech.bend as MC

# Viewers for threads elsewhere (IO; core/fview.bend, docs/bots.md
# "Viewers elsewhere").
#
# On the owning hub: view.ver lists the files the viewers want of a thread's
# folder (the project's KiCad files, its small models, and the files a
# client names) with a digest of the list, and when the client holds that
# digest already it waits for the list to change (at most a while); view.get
# is one file's bytes. Both only read, and only inside the folder.
#
# On the hub the client is on: Fvs.sync brings the files that changed into
# its cache (<home>/farfs/<link>/<the owner's folder>), a few at a time,
# and Fvs.mech does the same for a part listing's renders.

def Fvs.now() -> IO(Nat):
  do IO<Nat>:
    t : U32 <- H.Clock.epoch()
    return U32.to_nat(t)

# the longest the owner holds a view.ver that has nothing new, in seconds
def Fvs.wait() -> Nat:
  24n

# Replies
# -------

def Fvs.err(+why: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{"0"}}, J.KV{"ok", J.Flag{False{}}}, J.KV{"error", J.Str{why}}]))

def Fvs.ok(r: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{"0"}}, J.KV{"ok", J.Flag{True{}}}, J.KV{"result", J.Json.obj(r)}]))

def Fvs.json(+text: String) -> List<&2, U32>:
  W.Http.response("200 OK", "application/json", U.Utf8.encode(text), "")

# The owning hub
# --------------

# what the scripts share: the folder (argument 1), whether a path is a
# plain file inside it (a symlink, or a folder that leads out, is not),
# and stat in the machine's own dialect
def Fvs.lib() -> String:
  "cd \"$1\" 2>/dev/null || { echo 'no such folder'; exit 2; }\nrr=$(pwd -P)\nok() { [ -f \"./$1\" ] && [ ! -L \"./$1\" ] && d=$(cd \"$(dirname \"./$1\")\" 2>/dev/null && pwd -P) && case \"$d/\" in \"$rr\"/*) return 0;; esac; return 1; }\nif stat -c %s . >/dev/null 2>&1; then SC=-c; SFMT='%n|%s|%Y'; else SC=-f; SFMT='%N|%z|%m'; fi\n"

# the list: the files asked for, the project's own choice, KiCad's files
# (four folders down), the small models (five), none hidden, none in a
# backup, at most 400, each "path<TAB>size<TAB>mtime" and none over the cap
def Fvs.list.sh() -> String:
  "mk() {\n  { printf '%s\\n' \"$W\" | while IFS= read -r f; do case \"$f\" in .backplane.json) ;; .*|*/.*|\"\") continue;; esac; ok \"$f\" && stat $SC \"$SFMT\" \"./$f\"; done\n"
  ++ "    [ -f ./.backplane.json ] && stat $SC \"$SFMT\" ./.backplane.json\n"
  ++ "    find . -maxdepth 4 \\( -path '*/.*' -o -name node_modules -o -name '*-backups' \\) -prune -o -type f \\( -iname '*.kicad_pcb' -o -iname '*.kicad_sch' -o -iname '*.kicad_pro' -o -name sym-lib-table -o -name fp-lib-table \\) ! -name '_autosave-*' -exec stat $SC \"$SFMT\" {} + 2>/dev/null | sort\n"
  ++ "    find . -maxdepth 5 \\( -path '*/.*' -o -name node_modules -o -name '*-backups' -o -path './mech' \\) -prune -o -type f \\( -iname '*.step' -o -iname '*.stp' -o -iname '*.wrl' -o -iname '*.glb' \\) -size -4096k -exec stat $SC \"$SFMT\" {} + 2>/dev/null | sort\n"
  ++ "  } | awk -F'|' '{n=split($0,a,\"|\"); nm=a[1]; for(i=2;i<n-1;i++) nm=nm \"|\" a[i]; sub(/^\\.\\//,\"\",nm); printf \"%s\\t%s\\t%s\\n\", nm, a[n-1], a[n]}' | awk -F'\\t' -v c=" ++ Nat.show(FV.Fv.cap()) ++ " '!seen[$1]++ && $2+0<=c' | head -n 400\n}\n"

def Fvs.ver.sh() -> String:
  Fvs.lib() ++ Fvs.list.sh() ++ "W=$4; V=$2; n=0\nwhile :; do\n  out=$(mk); v=$(printf '%s' \"$out\" | cksum | cut -d' ' -f1)\n  if [ \"$v\" != \"$V\" ] || [ \"$n\" -ge \"$3\" ]; then break; fi\n  sleep 2; n=$((n+2))\ndone\nprintf '%s\\n%s\\n' \"$v\" \"$out\"\n"

# one file: its size and where it really is
def Fvs.get.sh() -> String:
  Fvs.lib() ++ "case \"$2\" in .backplane.json) ;; .*|*/.*|\"\") echo 'no such file'; exit 1;; esac\nok \"$2\" || { echo 'no such file'; exit 1; }\ns=$(wc -c < \"./$2\" | tr -d ' ')\nd=$(cd \"$(dirname \"./$2\")\" && pwd -P)\nprintf '%s\\t%s' \"$s\" \"$d/$(basename \"$2\")\"\n"

def Fvs.ver.done(r: P.Ran, +root: String, +thread: String) -> List<&2, U32>:
  match r:
    case P.Ran{0, +out}:
      Fvs.json(Fvs.ok([J.KV{"root", J.Str{root}}, J.KV{"thread", J.Str{thread}}, J.KV{"ver", J.Str{String.trim(Maybe.default(&2, String, List.head(&2, String, String.lines(out)), ""))}},
        J.KV{"files", J.Str{String.join(List.drop(&2, String, String.lines(out), 1n), "\n")}}]))
    case P.Ran{_, _}:
      W.Http.text("404 Not Found", "no such folder")

# view.ver: the list of what the viewers want of the thread's folder; it
# answers at once when its digest is not `have`, else after the list
# changes or Fvs.wait() seconds
def Fvs.ver(+root: String, +thread: String, +want: String, +have: String) -> IO(List<&2, U32>):
  IO.bind(P.Ran, List<&2, U32>, P.Proc.run("sh", ["-c", Fvs.ver.sh(), "sh", root, have, Nat.show(Fvs.wait()), want], "/"), r => IO.pure(List<&2, U32>, Fvs.ver.done(r, root, thread)))

def Fvs.field(ps: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ps, i), "")

def Fvs.nat(+s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(String.trim(s)), 0n)

def Fvs.sent(+path: String, +size: Nat, bs: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}:
      Bool.pick(List<&2, U32>, Nat.is_eq(size, 0n), W.Http.response.c("200 OK", "application/octet-stream", Nil{}, "no-store", ""), W.Http.text("500 Internal Server Error", "could not read it"))
    case b <> t:
      W.Http.response.c("200 OK", "application/octet-stream", b <> t, "no-store", "")

def Fvs.get.read(+size: Nat, +path: String) -> IO(List<&2, U32>):
  Bool.pick(IO(List<&2, U32>), Nat.is_gt(size, FV.Fv.cap()), IO.pure(List<&2, U32>, W.Http.text("413 Payload Too Large", "too large to send")),
    IO.bind(List<&2, U32>, List<&2, U32>, BN.Bf.read(path), bs => IO.pure(List<&2, U32>, Fvs.sent(path, size, bs))))

def Fvs.get.done(r: P.Ran) -> IO(List<&2, U32>):
  match r:
    case P.Ran{0, +out}:
      Fvs.get.read(Fvs.nat(Fvs.field(String.split(out, '\t'), 0n)), String.trim(Fvs.field(String.split(out, '\t'), 1n)))
    case P.Ran{_, _}:
      IO.pure(List<&2, U32>, W.Http.text("404 Not Found", "no such file"))

# view.get: one file's bytes (a 404 when it is not a plain file inside the
# folder, a 413 over Fv.cap())
def Fvs.get(+root: String, +rel: String) -> IO(List<&2, U32>):
  IO.bind(P.Ran, List<&2, U32>, P.Proc.run("sh", ["-c", Fvs.get.sh(), "sh", root, rel], "/"), Fvs.get.done)

# The hub the client is on
# ------------------------

# a signed request to the owning hub; each carries a nonce, so two alike in
# one second are not taken for a replay
def Fvs.call(+home: String, +link: String, +url: String, +method: String, +p: List<&2, J.KV>, +out: String, +secs: Nat, +max: Nat) -> IO(BN.Resp):
  do IO<BN.Resp>:
    now : Nat <- Fvs.now()
    +n : String <- BN.Bn.random(4n)
    BN.Bn.to_peer.long(home, url, link, now, "/far/rpc",
      J.Json.show(J.Json.obj([J.KV{"id", J.Num{"0"}}, J.KV{"m", J.Str{method}}, J.KV{"p", J.Json.obj(List.append(&2, J.KV, p, [J.KV{"n", J.Str{n}}]))}])), out, secs, max)

def Fvs.code(r: BN.Resp) -> Nat:
  match r:
    case BN.Resp{c, _}:
      c

def Fvs.body(r: BN.Resp) -> String:
  match r:
    case BN.Resp{_, b}:
      b

# the answer for a request that did not come back 200
def Fvs.fail(r: BN.Resp) -> String:
  match r:
    case BN.Resp{+c, +b}:
      Fvs.err(Bool.pick(String, Nat.is_eq(c, 0n), "that machine is away", "that machine did not take it: " ++ String.take(b, 120n)))

def Fvs.lines.k(blank: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      rest
    case False{}:
      l <> rest

def Fvs.lines.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Fvs.lines.k(String.is_empty(String.trim(l)), l, Fvs.lines.go(t))

# the non-blank lines of a text
def Fvs.lines(+text: String) -> List<&2, String>:
  Fvs.lines.go(String.lines(text))

# the path a list line names (a line is "path<TAB>size<TAB>mtime")
def Fvs.rel(+line: String) -> String:
  Fvs.field(String.split(line, '\t'), 0n)

def Fvs.idx.go(ls: List<&2, String>, m: Map<&2, String>) -> Map<&2, String>:
  match ls:
    case Nil{}:
      m
    case +l <> t:
      Fvs.idx.go(t, Map.set(&2, String, m, Fvs.rel(l), l))

def Fvs.same.k(r: Map<&2, String> & String, +line: String) -> Bool:
  (_, v) = r
  String.eq(v, line)

# whether the map holds this very line (the same file, size and time)
def Fvs.same(+m: Map<&2, String>, +line: String) -> Bool:
  Fvs.same.k(Map.get(String, "", m, Fvs.rel(line)), line)

# what the cache holds: the lines of the list it was brought up to
def Fvs.idx(+cache: String) -> IO(Map<&2, String>):
  do IO<Map<&2, String>>:
    +t : String <- BN.Bf.text(cache ++ "/.farver")
    return Fvs.idx.go(Fvs.lines(t), Map.new(&2, String))

def Fvs.todo.k(need: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match need:
    case True{}:
      l <> rest
    case False{}:
      rest

# the lines the cache lacks (or holds as another version), safe paths only
def Fvs.todo(ls: List<&2, String>, +m: Map<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Fvs.todo.k(Bool.and(FV.Fv.file.ok(Fvs.rel(l)), Bool.not(Fvs.same(m, l))), l, Fvs.todo(t, m))

def Fvs.keep.k(keep: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      l <> rest
    case False{}:
      rest

# the lines the cache now holds: those it held and those that came
def Fvs.keep(ls: List<&2, String>, +old: Map<&2, String>, +new: Map<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Fvs.keep.k(Bool.or(Fvs.same(old, l), Fvs.same(new, l)), l, Fvs.keep(t, old, new))

def Fvs.save(+cache: String, +ls: List<&2, String>) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/.farver\"", "sh", cache, String.join(ls, "\n")], "/"), r => IO.pure(Unit, Unit{}))

def Fvs.moved(r: P.Ran) -> Bool:
  match r:
    case P.Ran{0, _}:
      True{}
    case P.Ran{_, _}:
      False{}

# one file brought into the cache: written beside its place, then moved
# there whole, so nothing reads half a file
def Fvs.pull.done(ok: Bool, +tmp: String, +dest: String) -> IO(Bool):
  match ok:
    case True{}:
      IO.bind(P.Ran, Bool, P.Proc.run("sh", ["-c", "mkdir -p \"$(dirname \"$2\")\" && mv -f \"$1\" \"$2\"", "sh", tmp, dest], "/"), r => IO.pure(Bool, Fvs.moved(r)))
    case False{}:
      IO.bind(P.Ran, Bool, P.Proc.run("rm", ["-f", tmp], "/"), r => IO.pure(Bool, False{}))

def Fvs.pull(+home: String, +link: String, +url: String, +thread: String, +rel: String, +cache: String) -> IO(Bool):
  do IO<Bool>:
    +n : String <- BN.Bn.random(4n)
    +tmp : String = cache ++ "/.farpart-" ++ n
    r : BN.Resp <- Fvs.call(home, link, url, "view.get", [J.KV{"thread", J.Str{thread}}, J.KV{"path", J.Str{rel}}], tmp, 120n, Nat.add(FV.Fv.cap(), 1048576n))
    Fvs.pull.done(Nat.is_eq(Fvs.code(r), 200n), tmp, cache ++ "/" ++ rel)

# a lane: each line's file in turn; the lines that came
def Fvs.lane(ls: List<&2, String>, +home: String, +link: String, +url: String, +thread: String, +cache: String) -> IO(List<&2, String>):
  match ls:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case +l <> t:
      do IO<List<&2, String>>:
        ok : Bool <- Fvs.pull(home, link, url, thread, Fvs.rel(l), cache)
        rest : List<&2, String> <- Fvs.lane(t, home, link, url, thread, cache)
        return Fvs.keep.k(ok, l, rest)

def Fvs.lane.job(ls: List<&2, String>, +home: String, +link: String, +url: String, +thread: String, +cache: String, +out: Chan(List<&2, String>)) -> IO(Unit):
  do IO<Unit>:
    +r : List<&2, String> <- Fvs.lane(ls, home, link, url, thread, cache)
    ok : Bool <- Chan.send(List<&2, String>, out, r)
    return Unit{}

def Fvs.pick.k(mine: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match mine:
    case True{}:
      l <> rest
    case False{}:
      rest

# every fourth line from the kth
def Fvs.pick(ls: List<&2, String>, +k: Nat, +i: Nat) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Fvs.pick.k(Nat.is_eq(Nat.mod(i, 4n), k), l, Fvs.pick(t, k, 1n+i))

def Fvs.got(m: Maybe<&1, List<&2, String>>) -> List<&2, String>:
  match m:
    case Some{+xs}:
      xs
    case None{}:
      Nil{}

# the files in four lanes at once; the lines that came
def Fvs.fetch(+todo: List<&2, String>, +home: String, +link: String, +url: String, +thread: String, +cache: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    +out : Chan(List<&2, String>) <- Chan.new(List<&2, String>, 4)
    IO.spawn(Unit, Fvs.lane.job(Fvs.pick(todo, 1n, 0n), home, link, url, thread, cache, out))
    IO.spawn(Unit, Fvs.lane.job(Fvs.pick(todo, 2n, 0n), home, link, url, thread, cache, out))
    IO.spawn(Unit, Fvs.lane.job(Fvs.pick(todo, 3n, 0n), home, link, url, thread, cache, out))
    +a : List<&2, String> <- Fvs.lane(Fvs.pick(todo, 0n, 0n), home, link, url, thread, cache)
    b : Maybe<&1, List<&2, String>> <- Chan.recv(List<&2, String>, out)
    c : Maybe<&1, List<&2, String>> <- Chan.recv(List<&2, String>, out)
    d : Maybe<&1, List<&2, String>> <- Chan.recv(List<&2, String>, out)
    return List.append(&2, String, a, List.append(&2, String, Fvs.got(b), List.append(&2, String, Fvs.got(c), Fvs.got(d))))

def Fvs.at.k(r: Map<&2, String> & String) -> String:
  (_, v) = r
  v

def Fvs.at(+m: Map<&2, String>, +rel: String) -> String:
  Fvs.at.k(Map.get(String, "", m, rel))

def Fvs.ready.k(has: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match has:
    case True{}:
      l <> rest
    case False{}:
      rest

# the wanted paths the cache holds
def Fvs.ready(ls: List<&2, String>, +m: Map<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Fvs.ready.k(Bool.not(String.is_empty(Fvs.rel(Fvs.at(m, l)))), l, Fvs.ready(t, m))

# far.view: the thread's files the viewers want, kept in the cache. The
# owner's list is asked for with the digest this client holds; when that
# changes (or after a while: same) the files that differ are brought in
# and the answer says what the cache holds now, for the client to go on.
def Fvs.sync.done(+home: String, +link: String, +thread: String, +cache: String, +want: String, +ver: String, +files: String, +old: Map<&2, String>, +todo: List<&2, String>, +got: List<&2, String>) -> IO(String):
  do IO<String>:
    +ls : List<&2, String> = Fvs.lines(files)
    +keep : List<&2, String> = Fvs.keep(ls, old, Fvs.idx.go(got, Map.new(&2, String)))
    Fvs.save(cache, keep)
    return Fvs.ok([J.KV{"farView", J.Flag{True{}}}, J.KV{"thread", J.Str{FR.Fr.id(link, thread)}}, J.KV{"root", J.Str{cache}}, J.KV{"ver", J.Str{ver}}, J.KV{"same", J.Flag{False{}}},
      J.KV{"want", J.Str{want}}, J.KV{"ready", J.Str{String.join(Fvs.ready(Fvs.lines(want), Fvs.idx.go(keep, Map.new(&2, String))), "\n")}},
      J.KV{"changed", J.Json.nat(List.length(&2, String, got))}, J.KV{"failed", J.Json.nat(Nat.sub(List.length(&2, String, todo), List.length(&2, String, got)))}])

def Fvs.sync.fetch(+home: String, +link: String, +url: String, +thread: String, +cache: String, +want: String, +ver: String, +files: String) -> IO(String):
  do IO<String>:
    +old : Map<&2, String> <- Fvs.idx(cache)
    +todo : List<&2, String> = Fvs.todo(Fvs.lines(files), old)
    mk : P.Ran <- P.Proc.run("mkdir", ["-p", cache], "/")
    +got : List<&2, String> <- Fvs.fetch(todo, home, link, url, thread, cache)
    Fvs.sync.done(home, link, thread, cache, want, ver, files, old, todo, got)

def Fvs.sync.at(+cache: String, +ver: String, +files: String, +home: String, +link: String, +url: String, +thread: String, +want: String, +have: String) -> IO(String):
  Bool.pick(IO(String), String.is_empty(cache), IO.pure(String, Fvs.err("that folder cannot be kept here")),
    Bool.pick(IO(String), Bool.and(String.eq(ver, have), Bool.not(String.is_empty(have))),
      IO.pure(String, Fvs.ok([J.KV{"farView", J.Flag{True{}}}, J.KV{"thread", J.Str{FR.Fr.id(link, thread)}}, J.KV{"root", J.Str{cache}}, J.KV{"ver", J.Str{ver}}, J.KV{"same", J.Flag{True{}}}, J.KV{"want", J.Str{want}}])),
      Fvs.sync.fetch(home, link, url, thread, cache, want, ver, files)))

def Fvs.sync.res(+res: J.Json, +home: String, +link: String, +url: String, +thread: String, +want: String, +have: String) -> IO(String):
  Fvs.sync.at(FV.Fv.cache(home, link, J.Json.get_str(res, "root", "")), J.Json.get_str(res, "ver", ""), J.Json.get_str(res, "files", ""), home, link, url, thread, want, have)

def Fvs.sync.body(m: Maybe<&2, J.Json>, +home: String, +link: String, +url: String, +thread: String, +want: String, +have: String) -> IO(String):
  match m:
    case Some{+o}:
      Bool.pick(IO(String), J.Json.get_bool(o, "ok", False{}), Fvs.sync.res(J.Json.get_obj(o, "result"), home, link, url, thread, want, have),
        IO.pure(String, Fvs.err(J.Json.get_str(o, "error", "that machine did not take it"))))
    case None{}:
      IO.pure(String, Fvs.err("invalid reply from that machine"))

def Fvs.sync.got(+r: BN.Resp, +home: String, +link: String, +url: String, +thread: String, +want: String, +have: String) -> IO(String):
  Bool.pick(IO(String), Nat.is_eq(Fvs.code(r), 200n), Fvs.sync.body(J.Json.parse(Fvs.body(r)), home, link, url, thread, want, have), IO.pure(String, Fvs.fail(r)))

def Fvs.sync(+home: String, +link: String, +url: String, +thread: String, +want: String, +have: String) -> IO(String):
  IO.bind(BN.Resp, String, Fvs.call(home, link, url, "view.ver", [J.KV{"thread", J.Str{thread}}, J.KV{"want", J.Str{want}}, J.KV{"have", J.Str{have}}], "", 40n, 1048576n),
    r => Fvs.sync.got(r, home, link, url, thread, want, have))

# mech.list: the owner's part listing, with its renders brought into the
# cache first, so a picture is there when a client asks for it
def Fvs.shots.k(png: Bool, +p: String, rest: List<&2, String>) -> List<&2, String>:
  match png:
    case True{}:
      p <> rest
    case False{}:
      rest

def Fvs.shots(fs: List<&2, MC.MFile>) -> List<&2, String>:
  match fs:
    case Nil{}:
      Nil{}
    case MC.MFile{+p, _} <> t:
      Fvs.shots.k(Bool.and(String.ends_with(p, ".png"), FV.Fv.file.ok(p)), p, Fvs.shots(t))

def Fvs.mech.shots(+text: String, +home: String, +link: String, +url: String, +thread: String, +body: String) -> IO(String):
  do IO<String>:
    s : String <- Fvs.sync(home, link, url, thread, String.join(Fvs.shots(MC.Mech.files(text)), "\n"), "")
    return FV.Fv.fix(home, link, body)

def Fvs.mech.got(m: Maybe<&2, J.Json>, +home: String, +link: String, +url: String, +thread: String, +body: String) -> IO(String):
  match m:
    case Some{+o}:
      Fvs.mech.shots(J.Json.get_str(J.Json.get_obj(o, "result"), "mech", ""), home, link, url, thread, body)
    case None{}:
      IO.pure(String, Fvs.err("invalid reply from that machine"))

def Fvs.mech.r(+r: BN.Resp, +home: String, +link: String, +url: String, +thread: String) -> IO(String):
  Bool.pick(IO(String), Nat.is_eq(Fvs.code(r), 200n), Fvs.mech.got(J.Json.parse(Fvs.body(r)), home, link, url, thread, Fvs.body(r)), IO.pure(String, Fvs.fail(r)))

def Fvs.mech(+home: String, +link: String, +url: String, +thread: String) -> IO(String):
  IO.bind(BN.Resp, String, Fvs.call(home, link, url, "mech.list", [J.KV{"thread", J.Str{thread}}], "", 30n, 4194304n), r => Fvs.mech.r(r, home, link, url, thread))
