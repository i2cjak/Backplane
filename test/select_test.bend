import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/app/nui.bend as N
import ../src/app/win.bend as W
import ../src/app/layout.bend as L
import ../src/app/theme.bend as T
import ../src/gfx/raster.bend as R
import ../src/gfx/tiles.bend as TI

# Selecting text in a thread with the pointer (the window's timeline): a
# press on a line and a drag select what lies between, ctrl+c copies it,
# a press on nothing drops it. Layout runs with the bitmap face here.

def para(+i: Nat) -> String:
  "Message " ++ Nat.show(i) ++ ": the regulator's enable pin is pulled up through R12 to VBAT, so the output comes up before the MCU "
    ++ "drives it low. Moving R12 to the 3V3 rail fixes the sequencing, and C7 can stay where it is. **Next:** check the footprint "
    ++ "of U3 against the datasheet, then rerun DRC.\n\n- item one\n- item two with `code`\n"

def msg(+k: Nat, +th: String, +at: Nat) -> M.Change:
  M.MessagePosted{th, th ++ "m" ++ Nat.show(k), Bool.pick(M.Role, Nat.is_eq(Nat.mod(k, 2n), 0n), M.User{}, M.Assistant{}), para(k), Nat.add(at, k)}

def msgs(+n: Nat, +th: String, +at: Nat) -> List<&2, M.Change>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      msg(k, th, at) <> msgs(k, th, at)

def short(+k: Nat, +at: Nat) -> List<&2, M.Change>:
  M.ThreadCreated{"t" ++ Nat.show(1n+k), "p1", "Thread " ++ Nat.show(k), M.Local{}, "", "", "claude", "", at} <> msgs(20n, "t" ++ Nat.show(1n+k), at)

def threads(+n: Nat, +at: Nat) -> List<&2, M.Change>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      List.append(&2, M.Change, short(k, at), threads(k, at))

def log(+at: Nat) -> List<&2, M.Change>:
  List.concat(&2, M.Change, [[M.ProjectCreated{"p1", "board", "/tmp/board", at}, M.ThreadCreated{"t0", "p1", "Power sequencing", M.Local{}, "", "", "claude", "", at}],
    msgs(12n, "t0", at), threads(2n, at)])

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

def prepared(+n: N.Nui, +ms: Nat) -> N.Nui:
  N.Lbx.stamp(N.Blink.stamp(N.Hover.stamp(N.Nui.prepare(n), ms), ms), ms)

def step_nui(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

def again(+ty: L.Ty, +n0: N.Nui) -> N.Nui:
  +n = prepared(n0, 0n)
  with_hits(n, hits(L.Lay.frame(ty, L.Lay.memo(ty, n, L.TL.memo.none()), n)), 0n)

def ev(+n: N.Nui, e: W.WinEv) -> N.Nui:
  step_nui(N.Nui.event(n, e))

def lines(hs: List<&2, N.Hit>) -> String:
  match hs:
    case Nil{}:
      ""
    case N.Hit{+x0, +y0, +x1, +y1, +a, +v} <> t:
      Bool.pick(String, String.eq(a, "tl-line"), v ++ "@" ++ U32.show(x0) ++ "," ++ U32.show(y0) ++ "-" ++ U32.show(x1) ++ "," ++ U32.show(y1) ++ " ", "") ++ lines(t)

def copied.go(cs: List<&2, N.NCmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case N.NCopy{t} <> _:
      t
    case _ <> r:
      copied.go(r)

def copied(s: N.Step) -> String:
  match s:
    case N.Step{_, cs, _}:
      copied.go(cs)

def main() -> IO(Unit):
  do IO<Unit>:
    +ty : L.Ty <- L.Ty.load()
    +u : U.Ui = ui_sel(U.Ui.act(U.Ui.fold(log(1790000000n), U.Ui.init(1790000100n)), "select", "t0"))
    +n : N.Nui = again(ty, N.Nui.init(u, 1400, 900))
    +n1 : N.Nui = again(ty, ev(n, W.WButton{460, 300, 1, True{}}))
    +n2 : N.Nui = again(ty, ev(n1, W.WMove{800, 380, 0}))
    +n3 : N.Nui = again(ty, ev(n2, W.WButton{800, 380, 1, False{}}))
    +n4 : N.Nui = again(ty, ev(n3, W.WButton{20, 880, 1, True{}}))
    C.Check.str("press starts", Bool.show(String.starts_with(U.Ui.scratch(N.Nui.ui(n1), "@ts"), "t0|")), "True")
    C.Check.str("a click selects nothing", N.Sel.text(n1), "")
    C.Check.str("drag selects", Bool.show(Nat.is_gt(String.length(N.Sel.text(n3)), 20n)), "True")
    C.Check.str("spans lines", Bool.show(String.contains(N.Sel.text(n3), "\n")), "True")
    C.Check.str("release ends the drag", U.Ui.scratch(N.Nui.ui(n3), "@ts.on"), "")
    C.Check.str("ctrl+c copies it", copied(N.Nui.event(n3, W.WKey{99, 99, 2, True{}, 0})), N.Sel.text(n3))
    C.Check.str("a press on nothing drops it", N.Sel.text(n4), "")
