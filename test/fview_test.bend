import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/core/far.bend as FR
import ../src/core/fview.bend as FV

# Viewers for threads elsewhere (core/fview.bend, client.bend's Fv.*): the
# client names the file on screen to its hub (far.view), reads the folder
# the hub keeps the owner's files in, and shows a file only once it is
# there.

def items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> items(t)

def log(+since: Nat, cs: List<&2, M.Change>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"since", J.Json.nat(since)}, J.KV{"items", J.Json.arr(items(cs))}])

def numbered(cs: List<&2, M.Change>, +n: Nat) -> List<&2, FR.Item>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      FR.Item{n, K.Change.wire(c)} <> numbered(t, 1n+n)

def far(+since: Nat, +head: Nat, xs: List<&2, FR.Item>) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(FR.Fr.msg("p1", "box", False{}, since, head, xs)), J.Null{})

def theirs() -> List<&2, FR.Item>:
  numbered([M.ProjectCreated{"p", "Board", "/board", 1n}, M.ThreadCreated{"pt", "p", "Layout", M.Local{}, "", "", "claude", "", 2n}], 15n)

def here() -> List<&2, M.Change>:
  [M.PeerSet{"p1", "box", "http://box:3792", False{}, 1n}, M.ProjectCreated{"q", "Mine", "/mine", 1n}, M.ThreadCreated{"mt", "q", "Own", M.Local{}, "", "", "claude", "", 2n}]

def act_ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def cmds.go(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case U.Send{+t} <> r:
      t ++ "\n" ++ cmds.go(r)
    case _ <> r:
      cmds.go(r)

def cmds(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      cmds.go(cs)

def reply(+id: String, +body: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("reply")}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{True{}}}, J.KV{"result", J.Json.obj(body)}])

def answer(+want: String, +ver: String, same: Bool) -> J.Json:
  reply("9", [J.KV{"farView", J.Flag{True{}}}, J.KV{"thread", J.Str{"p1~pt"}}, J.KV{"root", J.Str{"/h/farfs/p1/board"}}, J.KV{"ver", J.Str{ver}}, J.KV{"same", J.Flag{same}}, J.KV{"want", J.Str{want}}])

def down(+want: String) -> J.Json:
  reply("9", [J.KV{"farView", J.Flag{True{}}}, J.KV{"thread", J.Str{"p1~pt"}}, J.KV{"want", J.Str{want}}, J.KV{"down", J.Str{"that machine is away"}}])

# a thread elsewhere selected, its panel open on the board
def start() -> U.Ui:
  act_ui(U.Ui.act(U.Ui.recv(U.Ui.recv(U.Ui.init(1000n), log(0n, here())), far(0n, 16n, theirs())), "select", "p1~pt"))

def asked() -> U.Act:
  U.Ui.act(start(), "panel", "")

def opened() -> U.Ui:
  act_ui(asked())

def yn(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def aq(b: Bool) -> String:
  Bool.pick(String, b, "asked", "quiet")

def main() -> IO(Unit):
  do IO<Unit>:
    +u : U.Ui = opened()
    C.Check.str("selected thread elsewhere, panel open", U.Ui.sel(u) ++ " " ++ Bool.show(U.Ui.panel(u)), "p1~pt True")
    C.Check.str("no folder before the hub answers", "[" ++ U.Ui.root(u) ++ "]", "[]")
    +a1 : U.Act = asked()
    C.Check.str("opening the panel asks its hub for the folder", cmds(a1), "{\"id\":0,\"m\":\"far.view\",\"p\":{\"thread\":\"p1~pt\",\"want\":\"\",\"have\":\"\"}}\n")
    +a2 : U.Act = U.Fv.sync(U.Act{u, Nil{}})
    C.Check.str("one ask at a time", "[" ++ cmds(a2) ++ "]", "[]")
    +r1 : U.Ui = U.Ui.recv(u, answer("", "111", False{}))
    C.Check.str("the folder is the hub's cache", U.Ui.root(r1), "/h/farfs/p1/board")
    +a3 : U.Act = U.Fv.sync(U.Act{r1, Nil{}})
    C.Check.str("then it holds on the digest", yn(String.contains(cmds(a3), "\"have\":\"111\"")), "yes")
    +r2 : U.Ui = U.Ui.recv(act_ui(a3), answer("", "222", True{}))
    C.Check.str("an unchanged answer asks again", yn(String.contains(cmds(U.Fv.sync(U.Act{r2, Nil{}})), "far.view")), "yes")
    +s1 : U.Ui = U.Ui.view_put(r1, "3d", "/h/farfs/p1/board/hw/a.step")
    C.Check.str("a file not in the cache shows as the Files tab", U.Ui.view_get(s1, "view.kind") ++ "|" ++ U.Ui.view_get(s1, "view.path"), "files|")
    +b1 : U.Act = U.Fv.sync(U.Act{s1, Nil{}})
    C.Check.str("it asks for that file, from the owner's folder", yn(String.contains(cmds(b1), "\"want\":\"hw/a.step\",\"have\":\"\"")), "yes")
    +b2 : U.Ui = U.Ui.recv(act_ui(b1), answer("hw/a.step", "333", False{}))
    C.Check.str("it shows once the file is in", U.Ui.view_get(b2, "view.kind") ++ "|" ++ U.Ui.view_get(b2, "view.path"), "3d|/h/farfs/p1/board/hw/a.step")
    +b3 : U.Ui = U.Ui.recv(act_ui(b1), answer("other.step", "444", False{}))
    C.Check.str("an answer for a file no longer asked for is dropped", U.Ui.view_get(b3, "view.kind"), "files")
    +d1 : U.Ui = U.Ui.recv(act_ui(b1), down("hw/a.step"))
    C.Check.str("a machine away shows the file as it is, and is not asked again at once",
      U.Ui.view_get(d1, "view.kind") ++ " " ++ aq(String.contains(cmds(U.Fv.sync(U.Act{d1, Nil{}})), "far.view")), "3d quiet")
    +m : U.Ui = act_ui(U.Ui.act(U.Ui.recv(U.Ui.recv(U.Ui.init(1000n), log(0n, here())), far(0n, 16n, theirs())), "select", "mt"))
    C.Check.str("a thread here is left alone", aq(String.contains(cmds(U.Fv.sync(U.Act{act_ui(U.Ui.act(m, "panel", "")), Nil{}})), "far.view")), "quiet")
    C.Check.str("and keeps its own folder", U.Ui.root(m), "/mine")
    C.Check.str("paths: a file from the owner's folder", U.Fv.rel.of("/h/farfs/p1/board", "/h/farfs/p1/board/hw/a.step") ++ "|" ++ U.Fv.rel.of("/h/farfs/p1/board", "/etc/passwd") ++ "|" ++ U.Fv.rel.of("", "/x/y"), "hw/a.step||")
    C.Check.str("reply fix", FV.Fv.fix("/h", "p1", "{\"t\":\"reply\",\"id\":3,\"ok\":true,\"result\":{\"thread\":\"pt\",\"fmRoot\":\"/board\",\"fmDir\":\"hw\"}}"),
      "{\"t\":\"reply\",\"id\":3,\"ok\":true,\"result\":{\"thread\":\"p1~pt\",\"fmRoot\":\"/h/farfs/p1/board\",\"fmDir\":\"hw\"}}")
