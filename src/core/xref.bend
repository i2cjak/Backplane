import Base
import ./json.bend as J
import ./model.bend as M
import ./far.bend as FR
import ./refs.bend as RF
import ./mcp.bend as MC

# Threads on another machine, named in a message or read by an agent
# --------------------------------------------------------------------
# A thread synced from another of the owner's machines is written
# `>machine:slug` (refs.bend's Refs.x.*: the composer offers it, and
# `>machine:` narrows the offer to that machine). Clients hold such
# threads in their read model; a hub holds only its mirror of each link
# (far.bend's In: the owning hub's changes as it sent them). So the hub
# finds them here, only when it must: a message that names one (its
# agent's <references> block says what it is), and thread_read on one (an
# agent reading it). Each folds that one mirror into a read model under
# the far ids clients use ("<link>~<id>"), the same fold a client makes.

# the mirror of the machine a word names: by its name as a slug, or its
# link id
def Xref.pick(ins: List<&2, FR.In>, +m: String) -> Maybe<&2, FR.In>:
  match ins:
    case Nil{}:
      None{}
    case +i <> t:
      Bool.pick(Maybe<&2, FR.In>, Bool.or(String.eq(RF.Slug.of(FR.In.name.of(i)), m), String.eq(FR.In.link(i), m)), Some{i}, Xref.pick(t, m))

# a mirror as a read model, named as clients name it
def Xref.state(+i: FR.In) -> M.State:
  FR.Fr.mark(FR.Fr.apply(FR.In.items(i), FR.In.link(i), M.State.empty()), FR.In.link(i), FR.In.name.of(i), FR.In.away(i))

def Xref.threads(s: M.State) -> List<&2, M.Thread>:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _, _}:
      Map.values(&2, M.Thread, ts)

# the line a word gets: what the thread is, where it lives, how to read it
def Xref.line.k(m: Maybe<&2, RF.Cand>, +s: M.State, +mach: String, +word: String) -> List<&2, String>:
  match m:
    case Some{RF.Cand{+id, +name, _, _}}:
      [RF.Refs.line.go(1n, s, id, name, word) ++ " It is on the machine " ++ mach ++ "; thread_read reads it from here, thread_send writes to it there."]
    case None{}:
      Nil{}

# (the mirror folded once)
def Xref.line.s(+s: M.State, +mach: String, +slug: String, +word: String) -> List<&2, String>:
  Xref.line.k(List.head(&2, RF.Cand, List.sort(~RF.Cand, ~RF.Cand.before, RF.Refs.t.hits(Xref.threads(s), slug, ""))), s, mach, word)

def Xref.line.m(m: Maybe<&2, FR.In>, +slug: String, +word: String) -> List<&2, String>:
  match m:
    case Some{+i}:
      Xref.line.s(Xref.state(i), FR.In.name.of(i), slug, word)
    case None{}:
      Nil{}

def Xref.line(+ins: List<&2, FR.In>, +word: String) -> List<&2, String>:
  Xref.line.m(Xref.pick(ins, RF.Slug.of(RF.Refs.x.m(String.drop(word, 1n)))), RF.Slug.of(RF.Slug.take(RF.Refs.x.q(String.drop(word, 1n)))), word)

def Xref.named(+w: String) -> Bool:
  Bool.and(String.eq(RF.Refs.kind(w), "thread"), RF.Refs.x.word(String.drop(w, 1n)))

def Xref.lines(ws: List<&2, String>, +ins: List<&2, FR.In>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      List.append(&2, String, Bool.pick(List<&2, String>, Xref.named(w), Xref.line(ins, w), Nil{}), Xref.lines(t, ins))

# what a message's agent reads after it: a block naming the threads
# elsewhere it names ("" for none; a cheap test first)
def Xref.block(+text: String, +ins: List<&2, FR.In>) -> String:
  Bool.pick(String, Bool.and(String.contains(text, ">"), String.contains(text, ":")),
    RF.Refs.block.k(Xref.lines(RF.Refs.sigil.words(text), ins)), "")

# thread_read on a thread elsewhere ("<link>~<id>"): its mirror read
def Xref.read.is(+o: J.Json) -> Bool:
  Bool.and(Bool.and(String.eq(J.Json.get_str(o, "method", ""), "tools/call"), String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "thread_read")),
    FR.Fr.is(J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), "threadId", "")))

def Xref.read.m(m: Maybe<&2, FR.In>, +target: String, +limit: Nat) -> MC.Res:
  match m:
    case Some{+i}:
      MC.Mcp.read.k(True{}, Xref.state(i), target, limit)
    case None{}:
      MC.Res.fail("no machine of yours syncs that thread here")

def Xref.out(o: MC.McpOut) -> String:
  match o:
    case MC.McpOut{+text, _, _}:
      text

# the JSON-RPC answer to such a thread_read (limit: its last 40 entries,
# or the `limit` asked)
def Xref.read(+o: J.Json, +ins: List<&2, FR.In>) -> String:
  Xref.out(MC.Mcp.reply(Maybe.default(&2, J.Json, J.Json.get(o, "id"), J.Null{}),
    Xref.read.m(Xref.pick(ins, FR.Fr.link(J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), "threadId", ""))),
      J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), "threadId", ""),
      U32.to_nat(J.Json.get_u32(J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), "limit", 40)))))
