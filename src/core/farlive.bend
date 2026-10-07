import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./live.bend as LV
import ./far.bend as FR

# Live text of threads elsewhere (pure; server.bend does the IO)
# ================================================================
# The owning hub's streamed reply is not a change (it is not in the log or
# the mirror file), so far.bend's push never carries it. It travels on its
# own, ephemeral channel: a POST /far/push whose body has `live` and no
# items, `{"name", "live": [{"th", "gen", "off", "text", "snap", "trunc"}]}`,
# sent as a delta of the owner's Live buffer (live.bend's Buf) for a shared
# thread. The receiving hub keeps the text in its own Live buffers under
# the far id (`<link>~<thread>`), so the snapshot a joining client gets
# already holds it, and tells its clients the same {"t":"delta"} a local
# stream sends. Nothing here is ever a Change, an Item or a line of a file.
#
# Order and loss. `off` is the length of the buffer before the delta: the
# receiver takes a delta only at that length and otherwise asks (`need`)
# for the whole buffer, which comes as a snapshot (`snap`) that replaces
# its text. Each request says `at`: the owner's log sequence when it was
# sent, and the owner sends only deltas of a stream still open then (a
# delta of a buffer that ended since, or truncated, is left out or becomes
# a snapshot: FL.fill). So a stream is older than a durable change numbered
# n exactly when its `at` is below n. The receiver keeps, as its buffer's
# `gen`, the `at` of the last request it took for the thread; a durable end
# numbered n (the message posted, the turn over: FL.ended) clears only a
# buffer whose `at` is below n, and leaves an empty one at n where there
# was none, so a late delta (at < n) of a posted reply never shows, while a
# newer stream that came first is kept (laws `flive_stale_ignored`,
# `flive_end_blocks_old`, `flive_end_keeps_newer`). A snapshot holds at
# most FL.snap.cap() characters, the end of the text (`trunc` then).
#
# Sender: one queue per peer (LQ), one item per thread (a delta joins the
# one waiting when it follows it, else the thread's snapshot is owed), one
# request out at a time: the more slowly a peer answers, the more each
# request carries. A peer with no client at all says `watch: false` and is
# left alone for FL.quiet() seconds; the delta after that finds a gap, asks,
# and gets the snapshot.

def FL.quiet() -> Nat:
  8n

# the most of a buffer a snapshot carries (its end), so a request stays far
# under /far/push's limit
def FL.snap.cap() -> Nat:
  16384n

# The receiver
# ------------

# the buffer for a thread (an empty one when none)
def FL.pickb(hit: Bool, b: LV.Buf, other: LV.Buf) -> LV.Buf:
  match hit:
    case True{}:
      b
    case False{}:
      other

def FL.get(bs: List<&2, LV.Buf>, +th: String) -> LV.Buf:
  match bs:
    case Nil{}:
      LV.Buf{th, Nil{}, 0n, False{}, 0n}
    case +b <> rest:
      FL.pickb(LV.Live.is(b, th), b, FL.get(rest, th))

def FL.size(bs: List<&2, LV.Buf>, +th: String) -> Nat:
  match bs:
    case Nil{}:
      0n
    case LV.Buf{+t, _, +n, _, _} <> rest:
      Nat.add(Bool.pick(Nat, String.eq(t, th), n, 0n), FL.size(rest, th))

def FL.gen(bs: List<&2, LV.Buf>, +th: String) -> Nat:
  match bs:
    case Nil{}:
      0n
    case LV.Buf{+t, _, _, _, +g} <> rest:
      Nat.add(Bool.pick(Nat, String.eq(t, th), g, 0n), FL.gen(rest, th))

def FL.keep(hit: Bool, b: LV.Buf, rest: List<&2, LV.Buf>) -> List<&2, LV.Buf>:
  match hit:
    case True{}:
      rest
    case False{}:
      b <> rest

# the buffers without a thread's
def FL.drop(bs: List<&2, LV.Buf>, +th: String) -> List<&2, LV.Buf>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> rest:
      FL.keep(LV.Live.is(b, th), b, FL.drop(rest, th))

# 0: taken, 1: stale (an older generation than the buffer's: ignored),
# 2: a gap (a delta not at the buffer's length: the whole buffer is asked)
def FL.verdict(has: Bool, +size: Nat, +cur: Nat, snap: Bool, +gen: Nat, +off: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(has, Nat.is_lt(gen, cur)), 1n,
    Bool.pick(Nat, Bool.or(snap, Nat.is_eq(off, size)), 0n, 2n))

def FL.base(snap: Bool, b: LV.Buf, +th: String, +gen: Nat, trunc: Bool) -> LV.Buf:
  match snap b:
    case True{} _:
      LV.Buf{th, Nil{}, 0n, trunc, gen}
    case False{} LV.Buf{t, cs, n, tr, _}:
      LV.Buf{t, cs, n, tr, gen}

def FL.put(+bs: List<&2, LV.Buf>, +th: String, +text: String, +gen: Nat, trunc: Bool, snap: Bool) -> List<&2, LV.Buf>:
  LV.Buf.add(FL.base(snap, FL.get(bs, th), th, gen, trunc), text) <> FL.drop(bs, th)

type Took is Data:
  Took{bs: List<&2, LV.Buf>, v: Nat}

def FL.take.k(+v: Nat, +bs: List<&2, LV.Buf>, +th: String, +text: String, +gen: Nat, trunc: Bool, snap: Bool) -> Took:
  match v:
    case 0n:
      Took{FL.put(bs, th, text, gen, trunc, snap), 0n}
    case _:
      Took{bs, v}

# a delta (or snapshot) for the thread `th` (its far id) taken into the buffers
def FL.take(+bs: List<&2, LV.Buf>, +th: String, +text: String, +gen: Nat, +off: Nat, trunc: Bool, +snap: Bool) -> Took:
  FL.take.k(FL.verdict(LV.Live.has(bs, th), FL.size(bs, th), FL.gen(bs, th), snap, gen, off), bs, th, text, gen, trunc, snap)

def Took.bs(t: Took) -> List<&2, LV.Buf>:
  match t:
    case Took{bs, _}:
      bs

def Took.v(t: Took) -> Nat:
  match t:
    case Took{_, v}:
      v

# the buffers of a link's threads (it went away: nothing more is coming)
def FL.drop.link(bs: List<&2, LV.Buf>, +prefix: String) -> List<&2, LV.Buf>:
  match bs:
    case Nil{}:
      Nil{}
    case LV.Buf{+t, +cs, +n, tr, g} <> rest:
      FL.keep(String.starts_with(t, prefix), LV.Buf{t, cs, n, tr, g}, FL.drop.link(rest, prefix))

# What ends a far thread's live text: the changes that end a local one
# (live.bend's Live.ended), named by their far id.
def FL.tag.end(+t: String) -> Bool:
  Bool.or(String.eq(t, "MessagePosted"), String.eq(t, "TurnChanged"))

# an end: the far id and the owner's number for the change that ended it
type End is Data:
  End{th: String, n: Nat}

def FL.ended.id(+link: String, +t: String, +n: Nat) -> List<&2, End>:
  Bool.pick(List<&2, End>, String.is_empty(t), Nil{}, [End{FR.Fr.id(link, t), n}])

def FL.ended.m(m: Maybe<&2, M.Change>, +link: String, +n: Nat) -> List<&2, End>:
  match m:
    case Some{c}:
      FL.ended.id(link, LV.Live.ended(c), n)
    case None{}:
      Nil{}

def FL.ended.k(end: Bool, +c: J.Json, +link: String, +n: Nat) -> List<&2, End>:
  match end:
    case True{}:
      FL.ended.m(C.Change.decode(c), link, n)
    case False{}:
      Nil{}

# the far ids whose live text a batch of items ends, with their numbers
def FL.ended(xs: List<&2, FR.Item>, +link: String) -> List<&2, End>:
  match xs:
    case Nil{}:
      Nil{}
    case FR.Item{+n, +c} <> t:
      List.append(&2, End, FL.ended.k(FL.tag.end(J.Json.get_str(c, "$", "")), c, link, n), FL.ended(t, link))

# the far ids alone (a client clears their live text as it folds the batch)
def FL.ended.ids(es: List<&2, End>) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case End{+th, _} <> t:
      th <> FL.ended.ids(t)

# one end: a buffer of an older stream (its `at` below n) is emptied and
# kept at n; none becomes an empty one at n; a newer one stays
def FL.end.b(older: Bool, b: LV.Buf, +th: String, +n: Nat) -> LV.Buf:
  match older:
    case True{}:
      LV.Buf{th, Nil{}, 0n, False{}, n}
    case False{}:
      b

def FL.end.k(has: Bool, +bs: List<&2, LV.Buf>, +th: String, +n: Nat) -> List<&2, LV.Buf>:
  match has:
    case True{}:
      FL.end.b(Nat.is_lt(FL.gen(bs, th), n), FL.get(bs, th), th, n) <> FL.drop(bs, th)
    case False{}:
      LV.Buf{th, Nil{}, 0n, False{}, n} <> bs

def FL.end.one(+bs: List<&2, LV.Buf>, +th: String, +n: Nat) -> List<&2, LV.Buf>:
  FL.end.k(LV.Live.has(bs, th), bs, th, n)

def FL.ends(es: List<&2, End>, +bs: List<&2, LV.Buf>) -> List<&2, LV.Buf>:
  match es:
    case Nil{}:
      bs
    case End{+th, +n} <> t:
      FL.ends(t, FL.end.one(bs, th, n))

# whether an end left a newer stream's text standing (the clients, which
# clear a thread's live text when they fold its end, then take the hub's
# snapshot again)
def FL.kept(es: List<&2, End>, +bs: List<&2, LV.Buf>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case End{+th, +n} <> t:
      Bool.or(Bool.and(Nat.is_ge(FL.gen(bs, th), n), Nat.is_gt(FL.size(bs, th), 0n)), FL.kept(t, bs))

# The sender
# ----------

# what is owed for one thread: a delta (its gen, the buffer's length before
# it, its text and that text's length), or the whole buffer (snap)
type LI is Data:
  LI{th: String, gen: Nat, off: Nat, text: String, n: Nat, snap: Bool}

type LQ is Data:
  LQ{link: String, busy: Bool, quiet: Nat, pend: List<&2, LI>}

def LQ.new(+link: String) -> LQ:
  LQ{link, False{}, 0n, Nil{}}

def LQ.link(q: LQ) -> String:
  match q:
    case LQ{l, _, _, _}:
      l

def LQ.busy(q: LQ) -> Bool:
  match q:
    case LQ{_, b, _, _}:
      b

def LQ.pend(q: LQ) -> List<&2, LI>:
  match q:
    case LQ{_, _, _, p}:
      p

def LI.th(i: LI) -> String:
  match i:
    case LI{t, _, _, _, _, _}:
      t

def LI.is.snap(i: LI) -> Bool:
  match i:
    case LI{_, _, _, _, _, s}:
      s

def FL.join.k(follows: Bool, +t: String, +g1: Nat, +o1: Nat, +x1: String, +n1: Nat, +g2: Nat, +x2: String, +n2: Nat) -> LI:
  match follows:
    case True{}:
      LI{t, g1, o1, x1 ++ x2, Nat.add(n1, n2), False{}}
    case False{}:
      LI{t, g2, 0n, "", 0n, True{}}

# two owed things for one thread as one: a delta that follows the waiting
# one joins it; a snapshot owed absorbs what comes after; anything else
# leaves a gap, so the whole buffer is owed
def FL.join(a: LI, b: LI) -> LI:
  match a b:
    case LI{+t, +g, +o, +x, +n, True{}} _:
      LI{t, g, o, x, n, True{}}
    case LI{+t, +g1, +o1, +x1, +n1, False{}} LI{_, +g2, +o2, +x2, +n2, False{}}:
      FL.join.k(Bool.and(Nat.is_eq(g1, g2), Nat.is_eq(Nat.add(o1, n1), o2)), t, g1, o1, x1, n1, g2, x2, n2)
    case LI{+t, _, _, _, _, False{}} LI{_, +g2, _, _, _, True{}}:
      LI{t, g2, 0n, "", 0n, True{}}

def LQ.has(ps: List<&2, LI>, +th: String) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case +p <> rest:
      Bool.or(String.eq(LI.th(p), th), LQ.has(rest, th))

def LQ.join.one(hit: Bool, p: LI, i: LI) -> LI:
  match hit:
    case True{}:
      FL.join(p, i)
    case False{}:
      p

def LQ.map(ps: List<&2, LI>, +i: LI) -> List<&2, LI>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> rest:
      LQ.join.one(String.eq(LI.th(p), LI.th(i)), p, i) <> LQ.map(rest, i)

def LQ.merge.k(has: Bool, ps: List<&2, LI>, i: LI) -> List<&2, LI>:
  match has:
    case True{}:
      LQ.map(ps, i)
    case False{}:
      List.append(&2, LI, ps, [i])

def LQ.merge(+ps: List<&2, LI>, +i: LI) -> List<&2, LI>:
  LQ.merge.k(LQ.has(ps, LI.th(i)), ps, i)

# a delta made at the owner (the buffer's `gen`, its length `off` before
# it); a peer in its quiet time is sent nothing
def LQ.add.k(quiet: Bool, +l: String, b: Bool, +qt: Nat, ps: List<&2, LI>, +i: LI) -> LQ:
  match quiet:
    case True{}:
      LQ{l, b, qt, Nil{}}
    case False{}:
      LQ{l, b, qt, LQ.merge(ps, i)}

def LQ.add(q: LQ, +now: Nat, +th: String, +gen: Nat, +off: Nat, +text: String) -> LQ:
  match q:
    case LQ{+l, b, +qt, +ps}:
      LQ.add.k(Nat.is_gt(qt, now), l, b, qt, ps, LI{th, gen, off, text, String.length(text), False{}})

# the peer asked for a thread's whole buffer
def LQ.need(q: LQ, +th: String, +gen: Nat) -> LQ:
  match q:
    case LQ{l, b, qt, +ps}:
      LQ{l, b, qt, LQ.merge(ps, LI{th, gen, 0n, "", 0n, True{}})}

# a request is due: none out, something owed
def LQ.due(q: LQ) -> Bool:
  match q:
    case LQ{_, +b, _, +ps}:
      Bool.and(Bool.not(b), Bool.not(List.is_empty(&2, LI, ps)))

# the request goes out with everything owed
def LQ.start(q: LQ) -> LQ:
  match q:
    case LQ{l, _, qt, _}:
      LQ{l, True{}, qt, Nil{}}

# the request ended: the peer watches, or it does not (or did not answer):
# nothing is sent for FL.quiet() seconds and nothing is owed
def LQ.done(q: LQ, watch: Bool, +now: Nat) -> LQ:
  match q watch:
    case LQ{l, _, qt, ps} True{}:
      LQ{l, False{}, qt, ps}
    case LQ{l, _, _, _} False{}:
      LQ{l, False{}, Nat.add(now, FL.quiet()), Nil{}}

def LQs.pick(hit: Bool, q: LQ, other: LQ) -> LQ:
  match hit:
    case True{}:
      q
    case False{}:
      other

def LQs.get(qs: List<&2, LQ>, +link: String) -> LQ:
  match qs:
    case Nil{}:
      LQ.new(link)
    case +q <> rest:
      LQs.pick(String.eq(LQ.link(q), link), q, LQs.get(rest, link))

def LQs.keep(hit: Bool, q: LQ, rest: List<&2, LQ>) -> List<&2, LQ>:
  match hit:
    case True{}:
      rest
    case False{}:
      q <> rest

def LQs.drop(qs: List<&2, LQ>, +link: String) -> List<&2, LQ>:
  match qs:
    case Nil{}:
      Nil{}
    case +q <> rest:
      LQs.keep(String.eq(LQ.link(q), link), q, LQs.drop(rest, link))

def LQs.set.k(+link: String, qs: List<&2, LQ>, q: LQ) -> List<&2, LQ>:
  q <> LQs.drop(qs, link)

def LQs.set(qs: List<&2, LQ>, +q: LQ) -> List<&2, LQ>:
  LQs.set.k(LQ.link(q), qs, q)

# The wire
# --------

def LI.json(i: LI) -> J.Json:
  match i:
    case LI{+t, +g, +o, +x, _, True{}}:
      J.Json.obj([J.KV{"th", J.Str{t}}, J.KV{"gen", J.Json.nat(g)}, J.KV{"off", J.Json.nat(0n)}, J.KV{"text", J.Str{x}}, J.KV{"snap", J.Json.bool(True{})}, J.KV{"trunc", J.Json.bool(Nat.is_gt(o, 0n))}])
    case LI{+t, +g, +o, +x, _, False{}}:
      J.Json.obj([J.KV{"th", J.Str{t}}, J.KV{"gen", J.Json.nat(g)}, J.KV{"off", J.Json.nat(o)}, J.KV{"text", J.Str{x}}])

def LI.items(xs: List<&2, LI>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      LI.json(x) <> LI.items(t)

# a request's body: `live`, never `items`
def FL.body(+name: String, +at: Nat, xs: List<&2, LI>) -> String:
  J.Json.show(J.Json.obj([J.KV{"name", J.Str{name}}, J.KV{"at", J.Json.nat(at)}, J.KV{"live", J.Json.arr(LI.items(xs))}]))

def FL.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      J.Str{x} <> FL.strs(t)

# the answer: whether the peer has a client, and the threads whose whole
# buffer it asks for
def FL.ack(watch: Bool, +needs: List<&2, String>) -> String:
  J.Json.show(J.Json.obj([J.KV{"ok", J.Json.bool(True{})}, J.KV{"watch", J.Json.bool(watch)}, J.KV{"need", J.Json.arr(FL.strs(needs))}]))

# What came in
# ------------

# a delta for a client: the far id and its text
type Dm is Data:
  Dm{th: String, text: String}

# the buffers after a request's items, the threads whose whole buffer is
# asked for (their id there), the deltas to tell clients (newest first), and
# whether a whole buffer replaced one (clients then take a snapshot)
type Applied is Data:
  Applied{bs: List<&2, LV.Buf>, needs: List<&2, String>, dms: List<&2, Dm>, snap: Bool}

def FL.apply.k(v: Nat, +bs: List<&2, LV.Buf>, a: Applied, +th: String, +local: String, +text: String, +snap: Bool) -> Applied:
  match v a:
    case 0n Applied{_, ns, +ds, sn}:
      Applied{bs, ns, Bool.pick(List<&2, Dm>, snap, ds, Dm{th, text} <> ds), Bool.or(sn, snap)}
    case 2n Applied{_, ns, ds, sn}:
      Applied{bs, local <> ns, ds, sn}
    case _ Applied{_, ns, ds, sn}:
      Applied{bs, ns, ds, sn}

def FL.apply.t(t: Took, a: Applied, +th: String, +local: String, +text: String, +snap: Bool) -> Applied:
  match t:
    case Took{+bs, +v}:
      FL.apply.k(v, bs, a, th, local, text, snap)

def FL.apply.one(+o: J.Json, +link: String, +at: Nat, a: Applied) -> Applied:
  match a:
    case Applied{+bs, ns, ds, sn}:
      FL.apply.t(FL.take(bs, FR.Fr.id(link, J.Json.get_str(o, "th", "")), J.Json.get_str(o, "text", ""), at, J.Json.get_nat(o, "off", 0n), J.Json.get_bool(o, "trunc", False{}), J.Json.get_bool(o, "snap", False{})),
        Applied{bs, ns, ds, sn}, FR.Fr.id(link, J.Json.get_str(o, "th", "")), J.Json.get_str(o, "th", ""), J.Json.get_str(o, "text", ""), J.Json.get_bool(o, "snap", False{}))

def FL.apply.go(xs: List<&2, J.Json>, +link: String, +at: Nat, a: Applied) -> Applied:
  match xs:
    case Nil{}:
      a
    case +x <> t:
      FL.apply.go(t, link, at, FL.apply.one(x, link, at, a))

# a request's `live` items taken into the buffers (`at`: the owner's
# sequence when it sent them, each buffer's `gen` here)
def FL.apply(xs: List<&2, J.Json>, +link: String, +at: Nat, +bs: List<&2, LV.Buf>) -> Applied:
  FL.apply.go(xs, link, at, Applied{bs, Nil{}, Nil{}, False{}})

def Applied.bs(a: Applied) -> List<&2, LV.Buf>:
  match a:
    case Applied{bs, _, _, _}:
      bs

def Applied.needs(a: Applied) -> List<&2, String>:
  match a:
    case Applied{_, ns, _, _}:
      ns

def Applied.dms(a: Applied) -> List<&2, Dm>:
  match a:
    case Applied{_, _, ds, _}:
      List.reverse(&2, Dm, ds)

def Applied.snap(a: Applied) -> Bool:
  match a:
    case Applied{_, _, _, sn}:
      sn

def Dm.th(d: Dm) -> String:
  match d:
    case Dm{t, _}:
      t

def Dm.text(d: Dm) -> String:
  match d:
    case Dm{_, x}:
      x

# the threads asked for, from an answer's `need`
def FL.needs.of(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      J.Json.as_str(Some{x}, "") <> FL.needs.of(t)

# What goes out
# -------------
# a snapshot owed is read from the buffer when the request is made (nothing
# for a thread whose buffer ended meanwhile)

def FL.text(b: LV.Buf) -> String:
  match b:
    case LV.Buf{_, cs, _, _, _}:
      String.join(List.reverse(&2, String, cs), "")

def FL.gen.b(b: LV.Buf) -> Nat:
  match b:
    case LV.Buf{_, _, _, _, g}:
      g

def FL.size.b(b: LV.Buf) -> Nat:
  match b:
    case LV.Buf{_, _, n, _, _}:
      n

def FL.trunc.b(b: LV.Buf) -> Bool:
  match b:
    case LV.Buf{_, _, _, tr, _}:
      tr

# a snapshot: the buffer's text, its end only past FL.snap.cap() (`off` 1
# says the text was cut, LI.json's `trunc`)
def FL.snap.li(+t: String, +g: Nat, +x: String, +tr: Bool) -> LI:
  Bool.pick(LI, Nat.is_gt(String.length(x), FL.snap.cap()),
    LI{t, g, 1n, String.drop(x, Nat.sub(String.length(x), FL.snap.cap())), FL.snap.cap(), True{}},
    LI{t, g, Bool.pick(Nat, tr, 1n, 0n), x, String.length(x), True{}})

def FL.fill.k(has: Bool, +t: String, +b: LV.Buf) -> List<&2, LI>:
  match has:
    case True{}:
      [FL.snap.li(t, FL.gen.b(b), FL.text(b), FL.trunc.b(b))]
    case False{}:
      Nil{}

# a delta: sent while its stream is the buffer's (same gen); a buffer that
# ended since sends nothing of it, a truncated one its snapshot
def FL.fill.d(open: Bool, trunc: Bool, +t: String, +b: LV.Buf, +i: LI) -> List<&2, LI>:
  match open trunc:
    case True{} False{}:
      [i]
    case True{} True{}:
      FL.fill.k(True{}, t, b)
    case False{} _:
      Nil{}

def FL.fill.one(i: LI, +bs: List<&2, LV.Buf>) -> List<&2, LI>:
  match i:
    case LI{+t, _, _, _, _, True{}}:
      FL.fill.k(Nat.is_gt(FL.size(bs, t), 0n), t, FL.get(bs, t))
    case LI{+t, +g, +o, +x, +n, False{}}:
      FL.fill.d(Bool.and(LV.Live.has(bs, t), Nat.is_eq(FL.gen(bs, t), g)), FL.trunc.b(FL.get(bs, t)), t, FL.get(bs, t), LI{t, g, o, x, n, False{}})

def FL.fill(xs: List<&2, LI>, +bs: List<&2, LV.Buf>) -> List<&2, LI>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      List.append(&2, LI, FL.fill.one(x, bs), FL.fill(t, bs))

# A turn's end on the owner's machine, told to its other machines
# -----------------------------------------------------------------
# `{"name", "note": {"th", "kind", "key", "title", "body"}}`: the owner
# decided it is news (core/notice.bend, nobody watching it there) and under
# which key; each peer raises it on its own desk and phones, unless one of
# its desks watches the thread. Best effort, never stored.

def FL.note.json(+th: String, +kind: String, +key: String, +title: String, +body: String) -> J.Json:
  J.Json.obj([J.KV{"th", J.Str{th}}, J.KV{"kind", J.Str{kind}}, J.KV{"key", J.Str{key}}, J.KV{"title", J.Str{title}}, J.KV{"body", J.Str{body}}])

def FL.note.body(+name: String, n: J.Json) -> String:
  J.Json.show(J.Json.obj([J.KV{"name", J.Str{name}}, J.KV{"note", n}]))
