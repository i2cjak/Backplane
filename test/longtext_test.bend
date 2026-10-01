import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/diff.bend as DF

# Long texts the clients label or search a line at a time: a fork's
# handed-over context (thousands of characters) went through String.lines,
# which recurses once per character, and the browser stopped drawing the
# fork (it could not be opened or deleted). These walks never nest.

# a long text: s doubled n times (tail-recursive)
def Long.go(n: Nat, +s: String) -> String:
  match n:
    case 0n:
      s
    case 1n+k:
      Long.go(k, s ++ s)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("first line", DF.Diff.first("one\ntwo"), "one")
    C.Check.str("first line, no break", DF.Diff.first("one"), "one")
    C.Check.str("first line, empty", DF.Diff.first(""), "")
    C.Check.str("a fork's context labels its first line", U.Qu.label("handoff:t1", "[Backplane] This thread is a fork of Board bringup\n" ++ Long.go(16n, "earlier conversation. ")), "This thread is a fork of Board bringup (goes with the next message)")
    C.Check.str("a long text's first line", Nat.show(String.length(DF.Diff.first(Long.go(16n, "x") ++ "\nnext"))), "65536")
    C.Check.str("a long text's lines", Nat.show(String.length(String.join(DF.Diff.lines(Long.go(16n, "word ") ++ "\n" ++ Long.go(16n, "more ")), "|"))), "655361")
