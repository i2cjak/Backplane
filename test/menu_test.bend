import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/badge.bend as BG
import ../src/app/nui.bend as N
import ../src/app/win.bend as W
import ../src/app/layout.bend as L

# The window's menus with real state: the model picker opens and closes
# (a press off it closes it, one on it does not, Esc does), its wheel
# scrolls within the list, a project's badge editor behaves the same, and
# settings scroll. Layout runs with the bitmap face here.

def ui_sel(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def hits(o: L.Out) -> List<&2, N.Hit>:
  match o:
    case L.Out{_, hs}:
      hs

def with_hits(n: N.Nui, hs: List<&2, N.Hit>, +ms: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, _, _, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hs, ms, vw}

def step_nui(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

def again(+ty: L.Ty, +n0: N.Nui) -> N.Nui:
  +n = N.Nui.prepare(n0)
  with_hits(n, hits(L.Lay.frame(ty, L.Lay.memo(ty, n, L.TL.memo.none()), n)), 0n)

def ev(+n: N.Nui, e: W.WinEv) -> N.Nui:
  step_nui(N.Nui.event(n, e))

def act(+n: N.Nui, +a: String, +v: String) -> N.Nui:
  step_nui(N.Nui.act(n, a, v))

# the first hit named a: its top-left corner, nudged in by 2
def at.x(hs: List<&2, N.Hit>, +a: String) -> U32:
  match hs:
    case Nil{}:
      0
    case N.Hit{+x0, _, _, _, +b, _} <> t:
      Bool.pick(U32, String.eq(a, b), (x0 + 2 : U32), at.x(t, a))

def at.y(hs: List<&2, N.Hit>, +a: String) -> U32:
  match hs:
    case Nil{}:
      0
    case N.Hit{_, +y0, _, _, +b, _} <> t:
      Bool.pick(U32, String.eq(a, b), (y0 + 2 : U32), at.y(t, a))

def value(hs: List<&2, N.Hit>, +a: String) -> String:
  match hs:
    case Nil{}:
      ""
    case N.Hit{_, _, _, _, +b, +v} <> t:
      Bool.pick(String, String.eq(a, b), v, value(t, a))

def info() -> String:
  "{\"claude\":[\"default\",\"fable\",\"opus\",\"sonnet\",\"haiku\",\"claude-opus-5-5[1m]\",\"claude-fable-5-1[1m]\"],\"about\":{\"claude\":{\"cli\":\"2.9\",\"labels\":{\"opus\":\"Opus 5.5 · claude-opus-5-5\"},\"efforts\":{\"default\":[\"low\",\"high\"]}}}}"

def log(+at: Nat) -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "board", "/tmp/board", at}, M.ThreadCreated{"t0", "p1", "Power sequencing", M.Local{}, "", "", "claude", "opus", at},
   M.SettingSet{"project.color.p1", "amber", at}, M.SettingSet{"project.icon.p1", "rocket-ship", at}]

def ui() -> U.Ui:
  ui_sel(U.Ui.act(U.Ui.recv(U.Ui.fold(log(1790000000n), U.Ui.init(1790000100n)),
    J.Json.obj([J.KV{"t", J.Str{"info"}}, J.KV{"info", J.Json.obj([J.KV{"models", J.Str{info()}}])}])), "select", "t0"))

def main() -> IO(Unit):
  do IO<Unit>:
    +ty : L.Ty <- L.Ty.load()
    C.Check.str("menu lists default once", String.join(U.Models.menu(info(), "claude"), ","), ",fable,opus,sonnet,haiku,claude-opus-5-5[1m],claude-fable-5-1[1m]")
    # the picker, in a window tall enough for every model
    +n0 : N.Nui = again(ty, N.Nui.init(ui(), 1400, 900))
    +n1 : N.Nui = again(ty, act(n0, "flag", "models"))
    C.Check.str("opens", Bool.show(U.Ui.flag(N.Nui.ui(n1), "models")), "True")
    C.Check.str("all fit, none scrolled", value(N.Nui.hits(n1), "menu"), "0|0")
    +n2 : N.Nui = again(ty, ev(n1, W.WButton{at.x(N.Nui.hits(n1), "menu"), at.y(N.Nui.hits(n1), "menu"), 1, True{}}))
    C.Check.str("a press on its box keeps it open", Bool.show(U.Ui.flag(N.Nui.ui(n2), "models")), "True")
    +n3 : N.Nui = again(ty, ev(n2, W.WButton{at.x(N.Nui.hits(n2), "effort"), at.y(N.Nui.hits(n2), "effort"), 1, True{}}))
    C.Check.str("a press on an effort chip keeps it open", Bool.show(U.Ui.flag(N.Nui.ui(n3), "models")), "True")
    +n4 : N.Nui = again(ty, ev(n3, W.WButton{700, 200, 1, True{}}))
    C.Check.str("a press off it closes it", Bool.show(U.Ui.flag(N.Nui.ui(n4), "models")), "False")
    C.Check.str("and its box is gone", value(N.Nui.hits(n4), "menu"), "")
    +n5 : N.Nui = again(ty, ev(again(ty, act(n4, "flag", "models")), W.WKey{65307, 0, 0, True{}, 0}))
    C.Check.str("Esc closes it", Bool.show(U.Ui.flag(N.Nui.ui(n5), "models")), "False")
    # a short window: the models scroll
    +s0 : N.Nui = again(ty, act(again(ty, N.Nui.init(ui(), 1000, 420)), "flag", "models"))
    C.Check.str("short: some scroll", Bool.show(String.ends_with(value(N.Nui.hits(s0), "menu"), "|0")), "False")
    +s1 : N.Nui = again(ty, ev(s0, W.WWheel{at.x(N.Nui.hits(s0), "menu"), at.y(N.Nui.hits(s0), "menu"), 1}))
    C.Check.str("the wheel scrolls one model", U.Ui.scratch(N.Nui.ui(s1), "@menu.off"), "1")
    +s2 : N.Nui = again(ty, ev(ev(ev(ev(ev(ev(ev(ev(s1, W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}),
      W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}), W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}),
      W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}), W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}),
      W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}), W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}),
      W.WWheel{at.x(N.Nui.hits(s1), "menu"), at.y(N.Nui.hits(s1), "menu"), 1}))
    C.Check.str("never past the last page", Bool.show(String.eq(Maybe.default(&2, String, List.head(&2, String, String.split(value(N.Nui.hits(s2), "menu"), '|')), ""),
      Maybe.default(&2, String, List.last(&2, String, String.split(value(N.Nui.hits(s2), "menu"), '|')), "x"))), "True")
    +s3 : N.Nui = again(ty, ev(s2, W.WButton{700, 60, 1, True{}}))
    C.Check.str("closing forgets the scroll", U.Ui.scratch(N.Nui.ui(s3), "@menu.off"), "")
    # a project's badge
    C.Check.str("set colour", BG.Badge.color(U.Ui.state(N.Nui.ui(n0)), "p1"), "amber")
    C.Check.str("unknown icon is the folder", BG.Badge.icon(U.Ui.state(N.Nui.ui(n0)), "p1"), "folder")
    +b1 : N.Nui = again(ty, act(n0, "look", "p1"))
    C.Check.str("the editor opens", U.Ui.scratch(N.Nui.ui(b1), "@look"), "p1")
    C.Check.str("its pieces set this project's badge", Bool.show(String.starts_with(value(N.Nui.hits(b1), "look-set"), "project.icon.p1=")), "True")
    +b2 : N.Nui = again(ty, ev(b1, W.WButton{at.x(N.Nui.hits(b1), "look-bg"), at.y(N.Nui.hits(b1), "look-bg"), 1, True{}}))
    C.Check.str("a press in it keeps it open", U.Ui.scratch(N.Nui.ui(b2), "@look"), "p1")
    +b3 : N.Nui = again(ty, ev(b2, W.WButton{700, 200, 1, True{}}))
    C.Check.str("a press off it closes it", U.Ui.scratch(N.Nui.ui(b3), "@look"), "")
    C.Check.str("look toggles", U.Ui.scratch(N.Nui.ui(act(act(n0, "look", "p1"), "look", "p1")), "@look"), "")
    # settings scroll, and stop at the end
    +g0 : N.Nui = again(ty, act(again(ty, N.Nui.init(ui(), 1400, 500)), "flag", "settings"))
    +g1 : N.Nui = again(ty, ev(g0, W.WWheel{700, 300, 1}))
    C.Check.str("settings scroll", U.Ui.scratch(N.Nui.ui(g1), "@set.sc"), "48")
    +g2 : N.Nui = again(ty, ev(g1, W.WWheel{700, 300, 0}))
    C.Check.str("and back", U.Ui.scratch(N.Nui.ui(g2), "@set.sc"), "0")
    C.Check.str("never past the end", U.Ui.scratch(N.Nui.ui(ev(g0, W.WWheel{700, 300, 1})), "@set.sc"), "48")
    C.Check.str("the end is known", Bool.show(Nat.is_gt(Maybe.default(&2, Nat, Nat.read(value(N.Nui.hits(g0), "set-bg")), 0n), 100n)), "True")
