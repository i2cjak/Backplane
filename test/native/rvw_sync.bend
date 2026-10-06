import Base
import ../../src/app/rvw.bend as RW
import ../../src/core/rview.bend as RV

# The window's side of a remote hub (src/app/rvw.bend) against a running hub:
# one round of RW.Rvw.sync, then a version of a file of a commit.
#   build/rvw_sync URL THREAD CACHE HAVE [GITPATH]
# prints "round ok=<bool> ver=<digest> reread=<bool> why=<text>" and, with a
# GITPATH, "git <bytes>". Used by test/tools/remote_view_e2e.ts.

def arg(xs: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def show(g: RW.Got) -> String:
  match g:
    case RW.Got{ok, +ver, reread, +why}:
      "round ok=" ++ Bool.show(ok) ++ " ver=" ++ ver ++ " reread=" ++ Bool.show(reread) ++ " why=" ++ why

def run(+url: String, +cache: String, +thread: String, +have: String, +gitp: String) -> IO(Unit):
  do IO<Unit>:
    +pre : String = RV.Rview.pre(cache, url)
    g : RW.Got <- RW.Rvw.sync(url, pre, thread, "", have)
    IO.print(show(g))
    +bs : List<&2, U32> <- Bool.pick(IO(List<&2, U32>), String.is_empty(gitp), IO.pure(List<&2, U32>, Nil{}), RW.Rvw.git(url, pre, thread, gitp))
    Bool.pick(IO(Unit), String.is_empty(gitp), IO.pure(Unit, Unit{}), IO.print("git " ++ Nat.show(List.length(&2, U32, bs))))

def copy(xs: List<&1, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      h <> copy(t)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    +xs : List<&2, String> = copy(args)
    run(arg(xs, 0n), arg(xs, 2n), arg(xs, 1n), arg(xs, 3n), arg(xs, 4n))
