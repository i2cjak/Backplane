import Base
import ./check.bend as C
import ../src/core/onboard.bend as OB
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/mobile/screen.bend as S
import ../src/core/json.bend as J

# The first-run tour (core/onboard.bend, client.bend's Tour.*): the steps,
# the moves between them, and when it shows.

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def sent(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      Nat.show(List.length(&2, U.Cmd, cs))

# a client that has heard from a hub with no setting yet
def fresh() -> U.Ui:
  U.Ui.adopt.raw(U.Ui.init(1000n), M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}], M.State.empty()))

def done() -> U.Ui:
  U.Ui.adopt.raw(U.Ui.init(1000n), M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}, M.SettingSet{"onboard.done", "1", 2n}], M.State.empty()))

def at(u: U.Ui) -> String:
  Nat.show(U.Tour.at(u))

def title(i: Nat) -> String:
  OB.Ob.title(i)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("steps are filled", Bool.show(OB.Ob.sound(OB.Ob.steps())), "True")
    C.Check.str("count matches the list", Nat.show(List.length(&2, OB.Step, OB.Ob.steps())), Nat.show(OB.Ob.count()))
    C.Check.str("first step", title(0n), "Welcome to Backplane")
    C.Check.str("a step past the end is blank", title(40n), "")
    # when it shows
    C.Check.str("waits for the hub's state", at(U.Ui.init(1000n)), Nat.show(OB.Ob.count()))
    C.Check.str("first run shows step 0", at(fresh()), "0")
    C.Check.str("done never shows by itself", at(done()), Nat.show(OB.Ob.count()))
    C.Check.str("reopened after done", at(ui(U.Ui.act(done(), "ob-open", ""))), "0")
    C.Check.str("reopen shuts Settings", Bool.show(U.Ui.flag(ui(U.Ui.act(U.Ui.flag_on(done(), "settings"), "ob-open", "")), "settings")), "False")
    # moves
    C.Check.str("next", at(ui(U.Ui.act(fresh(), "ob-next", ""))), "1")
    C.Check.str("next, next, back", at(ui(U.Ui.act(ui(U.Ui.act(ui(U.Ui.act(fresh(), "ob-next", "")), "ob-next", "")), "ob-back", ""))), "1")
    C.Check.str("back stays at the first", at(ui(U.Ui.act(fresh(), "ob-back", ""))), "0")
    C.Check.str("a move sends nothing", sent(U.Ui.act(fresh(), "ob-next", "")), "0")
    # the end: next on the last step, and skip, set the hub's setting once
    C.Check.str("skip ends it", at(ui(U.Ui.act(fresh(), "ob-skip", ""))), Nat.show(OB.Ob.count()))
    C.Check.str("skip tells the hub", sent(U.Ui.act(fresh(), "ob-skip", "")), "1")
    C.Check.str("skip is kept as a setting", M.Setting.get(U.Ui.state(ui(U.Ui.act(fresh(), "ob-skip", ""))), "onboard.done", ""), "1")
    C.Check.str("last step reads Done", OB.Ob.forward(7n) ++ " " ++ OB.Ob.forward(6n), "Done Next")
    C.Check.str("next from the last ends it", Bool.show(OB.Ob.live(OB.Ob.next(7n))), "False")
    C.Check.str("a stray next with no tour does nothing", sent(U.Ui.act(done(), "ob-next", "")), "0")
    C.Check.str("a stray next leaves it done", at(ui(U.Ui.act(done(), "ob-next", ""))), Nat.show(OB.Ob.count()))
    C.Check.str("counter", OB.Ob.counter(2n), "3 of 8")
    # the phones' screen
    C.Check.str("phone screen carries the tour", J.Json.get_str(J.Json.get_obj(S.Mob.screen(fresh()), "tour"), "title", ""), "Welcome to Backplane")
    C.Check.str("phone screen has none once done", J.Json.show(J.Json.get_obj(S.Mob.screen(done()), "tour")), "null")
