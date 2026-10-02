import Base
import ./json.bend as J
import ./model.bend as M

# Live text (pure; server.bend keeps the buffers, client.bend shows them)
# ======================================================================
# A thread's streamed reply is not in the log until its message is
# posted. The hub keeps what has streamed since (Buf: chunks newest first,
# at most Live.cap() bytes, the oldest dropped and the cut noted), clears
# it when the message is posted or the turn ends (Live.ends, the same
# changes that clear a client's live text: client.bend's Ui.see), and a
# client that joins (or catches up) gets every buffer at once as a
# snapshot that replaces its live text: a reconnect never shows a reply
# twice or with a gap (laws live_*). Each clearing bumps the thread's gen,
# so a snapshot older than one already shown changes nothing.

type Buf is Data:
  Buf{thread: String, cs: List<&2, String>, size: Nat, trunc: Bool, gen: Nat}

def Live.cap() -> Nat:
  262144n

def Buf.thread(b: Buf) -> String:
  match b:
    case Buf{t, _, _, _, _}:
      t

def Live.cut(+c: String, +room: Nat) -> String:
  Bool.pick(String, Nat.is_le(String.length(c), room), c, String.drop(c, Nat.sub(String.length(c), room)))

def Live.cons(+c: String, +t: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(c), t, c <> t)

# the newest chunks that fit in room (the oldest kept one cut to fit)
def Live.keep(cs: List<&2, String>, +room: Nat) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Live.cons(Live.cut(c, room), Live.keep(t, Nat.sub(room, String.length(c))))

def Live.size(cs: List<&2, String>) -> Nat:
  match cs:
    case Nil{}:
      0n
    case c <> t:
      Nat.add(String.length(c), Live.size(t))

def Buf.trimmed(+t: String, +cs: List<&2, String>, +g: Nat) -> Buf:
  Buf{t, cs, Live.size(cs), True{}, g}

def Buf.trim(over: Bool, b: Buf) -> Buf:
  match over b:
    case True{} Buf{t, cs, _, _, g}:
      Buf.trimmed(t, Live.keep(cs, Live.cap()), g)
    case False{} _:
      b

def Buf.add(b: Buf, +text: String) -> Buf:
  match b:
    case Buf{t, cs, +n, tr, g}:
      Buf.trim(Nat.is_gt(Nat.add(n, String.length(text)), Live.cap()), Buf{t, text <> cs, Nat.add(n, String.length(text)), tr, g})

def Buf.clear(b: Buf) -> Buf:
  match b:
    case Buf{t, _, _, _, g}:
      Buf{t, Nil{}, 0n, False{}, 1n+g}

def Live.is(b: Buf, +thread: String) -> Bool:
  match b:
    case Buf{t, _, _, _, _}:
      String.eq(t, thread)

def Live.has(bs: List<&2, Buf>, +thread: String) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case +b <> t:
      Bool.or(Live.is(b, thread), Live.has(t, thread))

def Live.add.one(hit: Bool, b: Buf, +text: String) -> Buf:
  match hit:
    case True{}:
      Buf.add(b, text)
    case False{}:
      b

def Live.add.go(bs: List<&2, Buf>, +thread: String, +text: String) -> List<&2, Buf>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      Live.add.one(Live.is(b, thread), b, text) <> Live.add.go(t, thread, text)

def Live.add.k(has: Bool, bs: List<&2, Buf>, +thread: String, +text: String, +base: Nat) -> List<&2, Buf>:
  match has:
    case True{}:
      Live.add.go(bs, thread, text)
    case False{}:
      Buf.add(Buf{thread, Nil{}, 0n, False{}, base}, text) <> bs

# text streamed for a thread, appended to its buffer (made when new, its
# gen starting at base: the server passes its clock, so a hub started
# again never numbers a buffer below one a client took from the last run)
def Live.add.at(+bs: List<&2, Buf>, +thread: String, +text: String, +base: Nat) -> List<&2, Buf>:
  Live.add.k(Live.has(bs, thread), bs, thread, text, base)

def Live.add(+bs: List<&2, Buf>, +thread: String, +text: String) -> List<&2, Buf>:
  Live.add.at(bs, thread, text, 0n)

def Live.end.k(hit: Bool, b: Buf) -> Buf:
  match hit:
    case True{}:
      Buf.clear(b)
    case False{}:
      b

# a thread's reply posted or its turn over: its buffer is empty again
def Live.end(bs: List<&2, Buf>, +thread: String) -> List<&2, Buf>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      Live.end.k(Live.is(b, thread), b) <> Live.end(t, thread)

def Live.ended(c: M.Change) -> String:
  match c:
    case M.MessagePosted{t, _, M.Assistant{}, _, _}:
      t
    case M.TurnChanged{t, M.Completed{}, _}:
      t
    case M.TurnChanged{t, M.Failed{}, _}:
      t
    case M.TurnChanged{t, M.Interrupted{}, _}:
      t
    case _:
      ""

def Live.ends.k(none: Bool, +t: String, bs: List<&2, Buf>) -> List<&2, Buf>:
  match none:
    case True{}:
      bs
    case False{}:
      Live.end(bs, t)

def Live.ends.c(+t: String, bs: List<&2, Buf>) -> List<&2, Buf>:
  Live.ends.k(String.is_empty(t), t, bs)

# the buffers after a step's changes: those whose reply was posted or
# whose turn ended are cleared (law live_end_clears)
def Live.ends(cs: List<&2, M.Change>, bs: List<&2, Buf>) -> List<&2, Buf>:
  match cs:
    case Nil{}:
      bs
    case c <> t:
      Live.ends(t, Live.ends.c(Live.ended(c), bs))

def Buf.json(b: Buf) -> J.Json:
  match b:
    case Buf{+t, cs, _, tr, g}:
      J.Json.obj([J.KV{"thread", J.Str{t}}, J.KV{"text", J.Str{String.join(List.reverse(&2, String, cs), "")}}, J.KV{"trunc", J.Json.bool(tr)}, J.KV{"gen", J.Json.nat(g)}])

def Live.items(bs: List<&2, Buf>) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      Nil{}
    case Buf{_, Nil{}, _, _, _} <> rest:
      Live.items(rest)
    case b <> rest:
      Buf.json(b) <> Live.items(rest)

# the snapshot a client gets when it is live again: every thread's
# streamed text so far ({"t":"live","items":[...]}; a thread not in it has
# none)
def Live.msg(bs: List<&2, Buf>) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"live"}}, J.KV{"items", J.Json.arr(Live.items(bs))}]))

# A client's side
# ---------------
# the snapshot replaces the live text; a thread in it shows its text ("…"
# first when the start was cut); a thread not in it shows none; an item
# older (gen) than what the client last took for that thread is ignored

def Live.shown(+o: J.Json) -> String:
  Bool.pick(String, J.Json.get_bool(o, "trunc", False{}), "…", "") ++ J.Json.get_str(o, "text", "")

def Live.get.k(r: Map<&2, String> & String) -> String:
  (_, v) = r
  v

def Live.get(m: Map<&2, String>, +k: String) -> String:
  Live.get.k(Map.get(String, "", m, k))

def Live.gen.key(+t: String) -> String:
  "live.gen:" ++ t

# a snapshot item's gen as it was written (decimal digits; never parsed:
# Nat.read makes laws crawl)
def Live.gen.of(+o: J.Json) -> String:
  J.Json.as_raw(J.Json.get(o, "gen"), "0")

def Live.take.k(old: Bool, +o: J.Json, +prev: Map<&2, String>, m: Map<&2, String>, nf: Map<&2, String>) -> Map<&2, String> & Map<&2, String>:
  match old:
    case True{}:
      (Map.set(&2, String, m, J.Json.get_str(o, "thread", ""), Live.get(prev, J.Json.get_str(o, "thread", ""))), nf)
    case False{}:
      (Map.set(&2, String, m, J.Json.get_str(o, "thread", ""), Live.shown(o)), Map.set(&2, String, nf, Live.gen.key(J.Json.get_str(o, "thread", "")), Live.gen.of(o)))

def Live.cmp.lt(r: (String & String) & Cmp) -> Bool:
  (_, c) = r
  match c:
    case LT{}:
      True{}
    case _:
      False{}

def Live.lt.k(+la: Nat, +lb: Nat, a: String, b: String) -> Bool:
  Bool.or(Nat.is_lt(la, lb), Bool.and(Nat.is_eq(la, lb), Live.cmp.lt(String.cmp(a, b))))

# a < b for decimal numbers without leading zeros (an empty b: nothing is
# below it, so the first snapshot always counts)
def Live.lt(+a: String, +b: String) -> Bool:
  Live.lt.k(String.length(a), String.length(b), a, b)

def Live.take(+o: J.Json, +prev: Map<&2, String>, r: Map<&2, String> & Map<&2, String>) -> Map<&2, String> & Map<&2, String>:
  (m, +nf) = r
  Live.take.k(Live.lt(Live.gen.of(o), Live.get(nf, Live.gen.key(J.Json.get_str(o, "thread", "")))), o, prev, m, nf)

def Live.fold(xs: List<&2, J.Json>, +prev: Map<&2, String>, r: Map<&2, String> & Map<&2, String>) -> Map<&2, String> & Map<&2, String>:
  match xs:
    case Nil{}:
      r
    case +x <> t:
      Live.fold(t, prev, Live.take(x, prev, r))

# (the new live map, the new info map) from a snapshot
def Live.set(+o: J.Json, +live: Map<&2, String>, nf: Map<&2, String>) -> Map<&2, String> & Map<&2, String>:
  Live.fold(J.Json.elems(J.Json.get_obj(o, "items")), live, (Map.new(&2, String), nf))

# a snapshot of one thread (for laws)
def Live.demo(+t: String, +text: String, trunc: Bool, +gen: Nat) -> J.Json:
  J.Json.obj([J.KV{"t", J.Str{"live"}}, J.KV{"items", J.Json.arr([J.Json.obj([J.KV{"thread", J.Str{t}}, J.KV{"text", J.Str{text}}, J.KV{"trunc", J.Json.bool(trunc)}, J.KV{"gen", J.Json.nat(gen)}])])}])
