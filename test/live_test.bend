import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/live.bend as LV

# Live text (core/live.bend): the hub keeps each thread's streamed text
# until its reply is posted or its turn ends, and a client that joins (or
# catches up) takes all of it at once, replacing what it showed.

def delta(+t: String, +text: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Str{"delta"}}, J.KV{"thread", J.Str{t}}, J.KV{"text", J.Str{text}}])

def snap(bs: List<&2, LV.Buf>) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(LV.Live.msg(bs)), J.Null{})

# 2^n x's
def xs(n: Nat, +s: String) -> String:
  match n:
    case 0n:
      s
    case 1n+k:
      xs(k, s ++ s)

# the chunks of a long reply, the buffer's cap passed a few times over
def big(n: Nat, bs: List<&2, LV.Buf>) -> List<&2, LV.Buf>:
  match n:
    case 0n:
      bs
    case 1n+k:
      big(k, LV.Live.add(bs, "t1", xs(16n, "x") ++ "|"))

def main() -> IO(Unit):
  do IO<Unit>:
    +u0 : U.Ui = U.Ui.init(0n)
    # a reconnect: the client had "abc", the hub has streamed "abcdef"
    +u1 : U.Ui = U.Ui.recv(U.Ui.recv(u0, delta("t1", "abc")), LV.Live.demo("t1", "abcdef", False{}, 0n))
    C.Check.str("a snapshot replaces, never appends", U.Ui.live.of(u1, "t1"), "abcdef")
    C.Check.str("deltas after it append", U.Ui.live.of(U.Ui.recv(u1, delta("t1", "gh")), "t1"), "abcdefgh")
    C.Check.str("the same snapshot twice is once", U.Ui.live.of(U.Ui.recv(u1, LV.Live.demo("t1", "abcdef", False{}, 0n)), "t1"), "abcdef")
    C.Check.str("a thread not in it shows none", U.Ui.live.of(U.Ui.recv(U.Ui.recv(u0, delta("t2", "zz")), LV.Live.demo("t1", "a", False{}, 0n)), "t2"), "")
    C.Check.str("an older gen changes nothing", U.Ui.live.of(U.Ui.recv(U.Ui.recv(u0, LV.Live.demo("t1", "new", False{}, 5n)), LV.Live.demo("t1", "old", False{}, 4n)), "t1"), "new")
    C.Check.str("a newer gen replaces", U.Ui.live.of(U.Ui.recv(U.Ui.recv(u0, LV.Live.demo("t1", "old", False{}, 4n)), LV.Live.demo("t1", "new", False{}, 5n)), "t1"), "new")
    C.Check.str("a cut start is marked", U.Ui.live.of(U.Ui.recv(u0, LV.Live.demo("t1", "tail", True{}, 0n)), "t1"), "…tail")
    # the hub's side
    +b1 : List<&2, LV.Buf> = LV.Live.add(LV.Live.add(LV.Live.add(Nil{}, "t1", "ab"), "t2", "zz"), "t1", "cd")
    C.Check.str("what streamed is what a joiner shows", U.Ui.live.of(U.Ui.recv(u0, snap(b1)), "t1"), "abcd")
    C.Check.str("each thread its own", U.Ui.live.of(U.Ui.recv(u0, snap(b1)), "t2"), "zz")
    C.Check.str("a posted reply clears its buffer", LV.Live.msg(LV.Live.ends([M.MessagePosted{"t1", "m:0", M.Assistant{}, "abcd", 3n}], LV.Live.add(Nil{}, "t1", "abcd"))), "{\"t\":\"live\",\"items\":[]}")
    C.Check.str("a user's message does not", Bool.show(String.contains(LV.Live.msg(LV.Live.ends([M.MessagePosted{"t1", "m:0", M.User{}, "hi", 3n}], LV.Live.add(Nil{}, "t1", "abcd"))), "abcd")), "True")
    C.Check.str("an ended turn clears it", LV.Live.msg(LV.Live.ends([M.TurnChanged{"t1", M.Failed{}, 3n}], LV.Live.add(Nil{}, "t1", "a"))), "{\"t\":\"live\",\"items\":[]}")
    C.Check.str("a Running turn does not", Bool.show(String.contains(LV.Live.msg(LV.Live.ends([M.TurnChanged{"t1", M.Running{}, 3n}], LV.Live.add(Nil{}, "t1", "a"))), "\"a\"")), "True")
    # after a clear the next reply's buffer is a newer gen
    +b2 : List<&2, LV.Buf> = LV.Live.add(LV.Live.ends([M.TurnChanged{"t1", M.Completed{}, 3n}], LV.Live.add(Nil{}, "t1", "one")), "t1", "two")
    C.Check.str("the next reply only", U.Ui.live.of(U.Ui.recv(U.Ui.recv(u0, LV.Live.demo("t1", "one", False{}, 0n)), snap(b2)), "t1"), "two")
    C.Check.str("the clock is the first gen", Bool.show(String.contains(LV.Live.msg(LV.Live.add.at(Nil{}, "t1", "a", 7000n)), "\"gen\":7000")), "True")
    # the cap: the newest text kept, the cut noted
    +b3 : List<&2, LV.Buf> = big(6n, Nil{})
    +s3 : String = U.Ui.live.of(U.Ui.recv(u0, snap(b3)), "t1")
    C.Check.str("capped", Bool.show(Nat.is_le(String.length(s3), Nat.add(LV.Live.cap(), 1n))), "True")
    C.Check.str("cut at the start", Bool.show(Bool.and(String.starts_with(s3, "…"), String.ends_with(s3, "x|"))), "True")
