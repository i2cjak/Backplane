import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/todo.bend as TD
import ../src/app/nui.bend as N
import ../src/app/layout.bend as L

# Long threads' panes: the todo card opens and shuts with its head and shows
# every step on "Show all" (client.bend's Todos), and the window's scrolling
# panes (the subagents panel, the todo card) move by a row a wheel notch
# within their rows (nui.bend's Pane, layout.bend's Pane).

def todos.go(n: Nat, +i: Nat, acc: List<&2, TD.Todo>) -> List<&2, TD.Todo>:
  match n:
    case 0n:
      acc
    case 1n+k:
      todos.go(k, 1n+i, TD.Todo{Nat.show(i), "step " ++ Nat.show(i), "", Bool.pick(String, Nat.is_lt(i, 3n), "completed", "pending")} <> acc)

# n steps, the first three done
def todos(+n: Nat) -> List<&2, TD.Todo>:
  List.reverse(&2, TD.Todo, todos.go(n, 0n, Nil{}))

def ui.of(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def fold(+u: U.Ui, +v: String) -> U.Ui:
  ui.of(U.Ui.act(u, "fold", v))

def nui.of(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

def bool(b: Bool) -> String:
  Bool.pick(String, b, "true", "false")

def rows(+u: U.Ui, +ts: List<&2, TD.Todo>) -> String:
  Nat.show(List.length(&2, TD.TRow, U.Todos.rows(U.Ui.infos(u), "t1", U.Todos.cap.all(), ts)))

# a notch down over a pane, then where it is
def notch(+n: N.Nui, +last: Nat, +dir: U32) -> N.Nui:
  nui.of(N.Pane.step(n, "subs:t1", last, dir))

def at(+n: N.Nui) -> String:
  Nat.show(L.Pane.off(U.Ui.infos(N.Nui.ui(n)), "subs:t1"))

def main() -> IO(Unit):
  do IO<Unit>:
    +u : U.Ui = U.Ui.init(0n)
    +many : List<&2, TD.Todo> = todos(200n)
    C.Check.str("a short list has no last line", U.Todos.more(False{}, todos(4n)), "")
    C.Check.str("a long one offers every step", U.Todos.more(False{}, many), "Show all 200")
    C.Check.str("shown all, it offers fewer", U.Todos.more(True{}, many), "Show fewer")
    C.Check.str("the card starts open", bool(U.Todos.open(U.Ui.infos(u), "t1")), "true")
    C.Check.str("and shows the fitted few", rows(u, many), "8")
    C.Check.str("its head shuts it", bool(U.Todos.open(U.Ui.infos(fold(u, U.Todos.toggle(True{}, "t1"))), "t1")), "false")
    C.Check.str("shut, it shows no steps", rows(fold(u, U.Todos.toggle(True{}, "t1")), many), "0")
    C.Check.str("and opens again", bool(U.Todos.open(U.Ui.infos(fold(fold(u, U.Todos.toggle(True{}, "t1")), U.Todos.toggle(False{}, "t1"))), "t1")), "true")
    C.Check.str("show all shows every step", rows(fold(u, U.Todos.more.ask(False{}, "t1")), many), "200")
    C.Check.str("show fewer goes back", rows(fold(fold(u, U.Todos.more.ask(False{}, "t1")), U.Todos.more.ask(True{}, "t1")), many), "8")
    C.Check.str("another thread's card is its own", bool(U.Todos.open(U.Ui.infos(fold(u, U.Todos.toggle(True{}, "t2"))), "t1")), "true")
    C.Check.str("a pane's hit value: key", N.Pane.at("subs:t1|7", 0n), "subs:t1")
    C.Check.str("a pane's hit value: its last row", N.Pane.at("subs:t1|7", 1n), "7")
    +n : N.Nui = N.Nui.init(u, 1400, 860)
    C.Check.str("a pane starts at its first row", at(n), "0")
    C.Check.str("a notch down moves it a row", at(notch(n, 7n, 1)), "1")
    C.Check.str("three notches, three rows", at(notch(notch(notch(n, 7n, 1), 7n, 1), 7n, 1)), "3")
    C.Check.str("a notch up comes back", at(notch(notch(notch(n, 7n, 1), 7n, 1), 7n, 0)), "1")
    C.Check.str("up at the top stays there", at(notch(n, 7n, 0)), "0")
    C.Check.str("it stops at the last row", at(notch(notch(notch(n, 2n, 1), 2n, 1), 2n, 1)), "2")
    C.Check.str("an offset past the rows is clamped", Nat.show(L.Pane.clamp(9n, 4n)), "3")
    C.Check.str("an offset within them stays", Nat.show(L.Pane.clamp(2n, 4n)), "2")
    C.Check.str("the head says which rows show", L.Pane.range(3n, 4n, 12n), " · 4–7 of 12")
    C.Check.str("and nothing when all do", L.Pane.range(0n, 12n, 12n), "")
