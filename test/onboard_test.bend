import Base
import ./check.bend as C
import ../src/core/onboard.bend as OB
import ../src/core/tools.bend as TO
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/mobile/screen.bend as S
import ../src/core/json.bend as J

# The first-run tour (core/onboard.bend, client.bend's Tour.*): the words,
# the moves between steps, and when it shows.

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def cmds(a: U.Act) -> List<&2, U.Cmd>:
  match a:
    case U.Act{_, cs}:
      cs

def sent(a: U.Act) -> String:
  Nat.show(List.length(&2, U.Cmd, cmds(a)))

# the focus a step leaves: "composer", "" or none
def focus.of(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case U.Focus{id} <> _:
      "focus:" ++ id
    case _:
      "none"

def focus(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      focus.of(cs)

def logged() -> M.State:
  M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}], M.State.empty())

def finished() -> M.State:
  M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}, M.SettingSet{"onboard.done", "1", 2n}], M.State.empty())

# a client that holds this connection's state, with no setting yet
def fresh() -> U.Ui:
  U.Ui.scratch_set(U.Ui.adopt.raw(U.Ui.init(1000n), logged()), "@sync", "1")

def done() -> U.Ui:
  U.Ui.scratch_set(U.Ui.adopt.raw(U.Ui.init(1000n), finished()), "@sync", "1")

def at(u: U.Ui) -> String:
  Nat.show(U.Tour.at(u))

def act(u: U.Ui, a: String) -> U.Ui:
  ui(U.Ui.act(u, a, ""))

# a string holds a piece (found by splitting on it)
def holds(+s: String, +p: String) -> Bool:
  String.contains(s, p)

def end() -> String:
  Nat.show(OB.Ob.count())

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("steps are sound", Bool.show(OB.Ob.sound()), "True")
    C.Check.str("moves stay in range", Bool.show(OB.Ob.nav(20n)), "True")
    C.Check.str("first step", OB.Ob.title(0n), "Welcome to Backplane")
    C.Check.str("a step past the end is blank", OB.Ob.title(40n) ++ OB.Ob.body(1n, "7", 40n), "")
    # when it shows
    C.Check.str("waits for the hub's state", at(U.Ui.init(1000n)), end())
    C.Check.str("a cached state is not current", at(U.Ui.adopt.raw(U.Ui.init(1000n), logged())), end())
    C.Check.str("a log makes it current", at(U.Ui.adopt_log(U.Ui.init(1000n), logged(), U.Reset.demo("o"))), "0")
    C.Check.str("a new connection is not current", at(U.Ui.online(fresh(), False{})), end())
    C.Check.str("first run shows step 0", at(fresh()), "0")
    C.Check.str("done never shows by itself", at(done()), end())
    C.Check.str("reopened after done", at(act(done(), "ob-open")), "0")
    C.Check.str("reopen shuts Settings", Bool.show(U.Ui.flag(act(U.Ui.flag_on(done(), "settings"), "ob-open"), "settings")), "False")
    # moves
    C.Check.str("next", at(act(fresh(), "ob-next")), "1")
    C.Check.str("next, next, back", at(act(act(act(fresh(), "ob-next"), "ob-next"), "ob-back")), "1")
    C.Check.str("back stays at the first", at(act(fresh(), "ob-back")), "0")
    C.Check.str("a move sends nothing", sent(U.Ui.act(fresh(), "ob-next", "")), "0")
    C.Check.str("skip ends it", at(act(fresh(), "ob-skip")), end())
    C.Check.str("skip tells the hub", sent(U.Ui.act(fresh(), "ob-skip", "")), "2")
    C.Check.str("skip is kept as a setting", M.Setting.get(U.Ui.state(act(fresh(), "ob-skip")), "onboard.done", ""), "1")
    C.Check.str("last step reads Done", OB.Ob.forward(8n) ++ " " ++ OB.Ob.forward(7n), "Done Next")
    C.Check.str("next from the last ends it", Bool.show(OB.Ob.live(OB.Ob.next(8n))), "False")
    C.Check.str("a stray next with no tour does nothing", sent(U.Ui.act(done(), "ob-next", "")), "0")
    C.Check.str("a stray next leaves it done", at(act(done(), "ob-next")), end())
    C.Check.str("counter", OB.Ob.counter(2n), "3 of 9")
    # a done from another client
    C.Check.str("done elsewhere closes an auto tour that moved on", at(U.Ui.adopt.raw(act(act(fresh(), "ob-next"), "ob-next"), finished())), end())
    C.Check.str("done elsewhere leaves a hand-opened tour", at(U.Ui.adopt.raw(act(done(), "ob-open"), finished())), "0")
    C.Check.str("a hand-opened tour moves on and stays", at(act(act(done(), "ob-open"), "ob-next")), "1")
    C.Check.str("a hand-opened tour works offline", at(act(U.Ui.online(done(), False{}), "ob-open")), "0")
    # the keyboard goes back
    C.Check.str("skip with no thread leaves no focus", focus(U.Ui.act(fresh(), "ob-skip", "")), "focus:")
    C.Check.str("skip in a thread focuses its composer", focus(U.Ui.act(U.Ui.select.k(fresh(), "t1"), "ob-skip", "")), "focus:composer")
    C.Check.str("showing it again takes the keyboard off Settings", focus(U.Ui.act(U.Ui.flag_on(done(), "settings"), "ob-open", "")), "focus:")
    # the words
    C.Check.str("settle says tools.bend's own sentence", Bool.show(holds(OB.Ob.body(0n, "7", 3n), TO.Tools.said(TO.Tools.settle(False{})))), "True")
    C.Check.str("snooze says tools.bend's own sentence", Bool.show(holds(OB.Ob.body(1n, "7", 3n), TO.Tools.said(TO.Tools.snooze(False{}, "", "")))), "True")
    C.Check.str("scratch expires, with its days", Bool.show(holds(OB.Ob.body(0n, "9", 1n), "9 days is deleted with its folder, unless it is pinned")), "True")
    C.Check.str("days come from the setting", U.Tour.days(U.Ui.adopt.raw(U.Ui.init(1n), M.State.replay([M.SettingSet{"scratch.days", "3", 1n}], M.State.empty()))), "3")
    C.Check.str("days default to 7", U.Tour.days(U.Ui.init(1n)), "7")
    C.Check.str("keys: no guarantee claimed", Bool.show(holds(OB.Ob.body(0n, "7", 6n), "nothing enforces it")), "True")
    C.Check.str("agents: signed in on the hub", Bool.show(holds(OB.Ob.body(0n, "7", 5n), "sign in to it on the machine that runs this hub")), "True")
    C.Check.str("tailnet: sign in, restart", Bool.show(holds(OB.Ob.body(1n, "7", 7n), "sign in and restart Backplane")), "True")
    C.Check.str("pairing: the QR code", Bool.show(holds(OB.Ob.body(0n, "7", 8n), "Pairing link, QR code")), "True")
    C.Check.str("phones: folder-plus, not the sidebar", Bool.show(holds(OB.Ob.body(2n, "7", 1n), "folder-plus")) ++ Bool.show(holds(OB.Ob.body(0n, "7", 1n), "folder-plus")), "TrueFalse")
    C.Check.str("phones: no voice-key field", Bool.show(holds(OB.Ob.body(2n, "7", 6n), "on a computer or the web page")), "True")
    C.Check.str("phones point at nothing, the head needs a thread", OB.Ob.target(2n, 3n) ++ "|" ++ U.Tour.target(0n, act(fresh(), "ob-next")) ++ "|" ++ U.Tour.target(0n, act(act(act(U.Ui.select.k(fresh(), "t1"), "ob-next"), "ob-next"), "ob-next")), "|add|head")
    C.Check.str("the head's highlight waits for a thread", U.Tour.target(0n, act(act(act(fresh(), "ob-next"), "ob-next"), "ob-next")), "")
    C.Check.str("keys: one policy", OB.Ob.dom("Enter") ++ OB.Ob.dom("ArrowRight") ++ OB.Ob.dom("ArrowLeft") ++ OB.Ob.dom("Escape") ++ "|" ++ OB.Ob.dom("a"), "ob-nextob-nextob-backob-skip|")
    # the phones' screen
    C.Check.str("phone screen carries the tour", J.Json.get_str(J.Json.get_obj(S.Mob.screen(fresh()), "tour"), "title", ""), "Welcome to Backplane")
    C.Check.str("phone body is the phone's", Bool.show(holds(J.Json.get_str(J.Json.get_obj(S.Mob.screen(act(fresh(), "ob-next")), "tour"), "body", ""), "folder-plus")), "True")
    C.Check.str("phone screen has none once done", J.Json.show(J.Json.get_obj(S.Mob.screen(done()), "tour")), "null")
