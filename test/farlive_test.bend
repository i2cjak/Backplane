import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/live.bend as LV
import ../src/core/far.bend as FR
import ../src/core/farlive.bend as FLV
import ../src/core/client.bend as U

# Live text of threads elsewhere (farlive.bend): what the owner queues goes
# over as a body, a receiver takes it into its buffers and tells its
# clients, a gap asks for the whole text, an end blocks what is late.

def parsed(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def body(+q: FLV.LQ) -> J.Json:
  parsed(FLV.FL.body("alpha", FLV.LQ.pend(q)))

def got(+a: FLV.Applied) -> String:
  FLV.FL.text(FLV.FL.get(FLV.Applied.bs(a), "b~t"))

def dms(ds: List<&2, FLV.Dm>) -> String:
  match ds:
    case Nil{}:
      ""
    case FLV.Dm{+t, +x} <> r:
      t ++ ":" ++ x ++ "|" ++ dms(r)

def items(+q: FLV.LQ) -> List<&2, J.Json>:
  J.Json.elems(J.Json.get_obj(body(q), "live"))

def main() -> IO(Unit):
  do IO<Unit>:
    # three deltas of one reply, queued behind one request, are one item
    +q1 : FLV.LQ = FLV.LQ.add(FLV.LQ.add(FLV.LQ.add(FLV.LQ.new("b"), 10n, "t", 5n, 0n, "Hel"), 10n, "t", 5n, 3n, "lo "), 10n, "t", 5n, 6n, "world")
    C.Check.str("deltas of a thread queue as one item", Nat.show(List.length(&2, J.Json, items(q1))) ++ " " ++ J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, items(q1)), J.Null{}), "text", ""), "1 Hello world")
    C.Check.str("a body carries live and never items", Nat.show(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(body(q1), "items")))) ++ " " ++ J.Json.get_str(body(q1), "name", ""), "0 alpha")
    # the receiver takes it under the far id and tells its clients
    +a1 : FLV.Applied = FLV.FL.apply(items(q1), "b", Nil{})
    C.Check.str("the receiver's buffer holds it under the far id", got(a1), "Hello world")
    C.Check.str("and its clients get the delta", dms(FLV.Applied.dms(a1)), "b~t:Hello world|")
    C.Check.str("no whole text asked, no snapshot told", Nat.show(List.length(&2, String, FLV.Applied.needs(a1))) ++ " " ++ Bool.show(FLV.Applied.snap(a1)), "0 False")
    # a delta later in the stream joins what the receiver holds
    +q2 : FLV.LQ = FLV.LQ.add(FLV.LQ.new("b"), 11n, "t", 5n, 11n, "!")
    +a2 : FLV.Applied = FLV.FL.apply(items(q2), "b", FLV.Applied.bs(a1))
    C.Check.str("a later delta is appended", got(a2), "Hello world!")
    # a receiver that missed the start (a new client, a quiet time) asks
    +a3 : FLV.Applied = FLV.FL.apply(items(q2), "b", Nil{})
    C.Check.str("a gap asks for the whole text", String.join(FLV.Applied.needs(a3), ",") ++ " [" ++ got(a3) ++ "]", "t []")
    # the owner answers from its own buffer
    +own : List<&2, LV.Buf> = LV.Live.add.at(LV.Live.add.at(Nil{}, "t", "Hello world", 5n), "t", "!", 5n)
    +q3 : FLV.LQ = FLV.LQ.need(FLV.LQ.new("b"), "t", 0n)
    +a4 : FLV.Applied = FLV.FL.apply(J.Json.elems(J.Json.get_obj(parsed(FLV.FL.body("alpha", FLV.FL.fill(FLV.LQ.pend(q3), own))), "live")), "b", FLV.Applied.bs(a3))
    C.Check.str("the whole text replaces it", got(a4) ++ " " ++ Bool.show(FLV.Applied.snap(a4)), "Hello world! True")
    # the durable message arrives first: a late delta of that reply is stale
    +ended : List<&2, LV.Buf> = FLV.FL.ends(FLV.FL.ended([FR.Item{9n, J.Json.obj([J.KV{"$", J.Str{"MessagePosted"}}, J.KV{"thread", J.Str{"t"}}, J.KV{"msg", J.Str{"m"}}, J.KV{"role", J.Str{"assistant"}}, J.KV{"text", J.Str{"Hello world!"}}, J.KV{"at", J.Json.nat(3n)}])}], "b"), FLV.Applied.bs(a2))
    +a5 : FLV.Applied = FLV.FL.apply(items(q1), "b", ended)
    C.Check.str("a late delta after the message changes nothing", "[" ++ got(a5) ++ "] " ++ dms(FLV.Applied.dms(a5)), "[] ")
    # the next reply (the owner's next generation) streams again
    +q4 : FLV.LQ = FLV.LQ.add(FLV.LQ.new("b"), 12n, "t", 6n, 0n, "Next")
    +a6 : FLV.Applied = FLV.FL.apply(items(q4), "b", ended)
    C.Check.str("the next reply streams", got(a6), "Next")
    # a peer with no client is left alone for a few seconds, then the next delta asks
    +q5 : FLV.LQ = FLV.LQ.done(FLV.LQ.start(FLV.LQ.add(FLV.LQ.new("b"), 20n, "t", 5n, 0n, "a")), False{}, 100n)
    C.Check.str("a quiet peer is sent nothing", Nat.show(List.length(&2, FLV.LI, FLV.LQ.pend(FLV.LQ.add(q5, 103n, "t", 5n, 1n, "b")))) ++ " " ++ Nat.show(List.length(&2, FLV.LI, FLV.LQ.pend(FLV.LQ.add(q5, 108n, "t", 5n, 3n, "c")))), "0 1")
    # on a client: the delta shows, the far message ends it
    +u1 : U.Ui = U.Ui.recv(U.Ui.init(0n), J.Json.obj([J.KV{"t", J.Str{"delta"}}, J.KV{"thread", J.Str{"b~t"}}, J.KV{"text", J.Str{"Hel"}}]))
    C.Check.str("a far thread's delta shows live", U.Ui.live.of(u1, "b~t"), "Hel")
    +u2 : U.Ui = U.Ui.recv(u1, parsed(FR.Fr.msg("b", "Beta", False{}, 8n, 9n, [FR.Item{9n, J.Json.obj([J.KV{"$", J.Str{"TurnChanged"}}, J.KV{"thread", J.Str{"t"}}, J.KV{"state", J.Str{"completed"}}, J.KV{"at", J.Json.nat(3n)}])}])))
    C.Check.str("a far turn's end clears it", "[" ++ U.Ui.live.of(u2, "b~t") ++ "]", "[]")
    +u3 : U.Ui = U.Ui.recv(u1, parsed(FR.Fr.msg("b", "Beta", False{}, 8n, 9n, [FR.Item{9n, J.Json.obj([J.KV{"$", J.Str{"TurnChanged"}}, J.KV{"thread", J.Str{"other"}}, J.KV{"state", J.Str{"completed"}}, J.KV{"at", J.Json.nat(3n)}])}])))
    C.Check.str("another thread's end keeps it", U.Ui.live.of(u3, "b~t"), "Hel")
    return Unit{}
