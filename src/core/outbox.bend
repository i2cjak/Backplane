import Base

# A client's outgoing frames (pure; server.bend's Wire.offer does the IO)
# ======================================================================
# Every frame the hub offers a client is counted (sent, bytes) and its
# writer reports what it has put on the socket (Drained: acked, backed,
# both running totals, so a lost or late report only lags). A client more
# than Cr.margin() frames or Cr.cap() bytes behind is dropped at once: its
# socket is shut, its channel closed, and it reconnects from its sequence.
# The channel (1024 slots) can then never fill, so no send of the hub's
# waits on a client. A report from another connection with the same id
# (the window's client 0 joins again) names an older generation and is
# ignored. A client still taking its log (boot) gets no live changes: the
# rest of its log, then the far mirrors, go out a chunk at a time while it
# has room (Cr.room), and the last frame ("boot": false) makes it live.

type Cr is Data:
  Cr{gen: U32, sent: Nat, acked: Nat, bytes: Nat, backed: Nat, native: Bool, boot: Bool, at: Nat, fl: Nat, fseq: Nat, wait: Bool, rest: List<&2, String>}

def Cr.margin() -> Nat:
  768n

def Cr.cap() -> Nat:
  8388608n

# a new connection: generation, whether it is the window in this process
# (frames as text, never counted in bytes), whether it still takes its log
# and from which item
def Cr.new(+gen: U32, +native: Bool, +boot: Bool, +at: Nat) -> Cr:
  Cr{gen, 0n, 0n, 0n, 0n, native, boot, at, 0n, 0n, False{}, Nil{}}

def Cr.gen(c: Cr) -> U32:
  match c:
    case Cr{g, _, _, _, _, _, _, _, _, _, w, rs}:
      g

def Cr.native(c: Cr) -> Bool:
  match c:
    case Cr{_, _, _, _, _, n, _, _, _, _, w, rs}:
      n

def Cr.boot(c: Cr) -> Bool:
  match c:
    case Cr{_, _, _, _, _, _, b, _, _, _, w, rs}:
      b

def Cr.at(c: Cr) -> Nat:
  match c:
    case Cr{_, _, _, _, _, _, _, a, _, _, w, rs}:
      a

def Cr.fl(c: Cr) -> Nat:
  match c:
    case Cr{_, _, _, _, _, _, _, _, f, _, w, rs}:
      f

def Cr.fseq(c: Cr) -> Nat:
  match c:
    case Cr{_, _, _, _, _, _, _, _, _, q, w, rs}:
      q

def Cr.wait(c: Cr) -> Bool:
  match c:
    case Cr{_, _, _, _, _, _, _, _, _, _, w, rs}:
      w

# a JoinMore is (or is no longer) on its way: at most one at a time
def Cr.wait.set(c: Cr, +w: Bool) -> Cr:
  match c:
    case Cr{g, s, a, b, k, nv, bt, at, fl, fq, _, rs}:
      Cr{g, s, a, b, k, nv, bt, at, fl, fq, w, rs}

# what of the log is still to go, oldest first, found once when it joined
# (each chunk is then taken from its front, never by walking the log)
def Cr.rest(c: Cr) -> List<&2, String>:
  match c:
    case Cr{_, _, _, _, _, _, _, _, _, _, _, rs}:
      rs

def Cr.rest.set(c: Cr, rs: List<&2, String>) -> Cr:
  match c:
    case Cr{g, s, a, b, k, nv, bt, at, fl, fq, w, _}:
      Cr{g, s, a, b, k, nv, bt, at, fl, fq, w, rs}

def Cr.sent(c: Cr) -> Nat:
  match c:
    case Cr{_, s, _, _, _, _, _, _, _, _, w, rs}:
      s

# a frame of n bytes offered
def Cr.offer(c: Cr, +n: Nat) -> Cr:
  match c:
    case Cr{g, s, a, b, k, nv, bt, at, fl, fq, w, rs}:
      Cr{g, 1n+s, a, Nat.add(b, n), k, nv, bt, at, fl, fq, w, rs}

def Cr.over.k(+s: Nat, +a: Nat, +b: Nat, +k: Nat) -> Bool:
  Bool.or(Nat.is_gt(Nat.sub(s, a), Cr.margin()), Nat.is_gt(Nat.sub(b, k), Cr.cap()))

# too far behind: dropped (law credit_drop_over_margin)
def Cr.over(c: Cr) -> Bool:
  match c:
    case Cr{_, s, a, b, k, _, _, _, _, _, w, rs}:
      Cr.over.k(s, a, b, k)

def Cr.room.k(+s: Nat, +a: Nat, +b: Nat, +k: Nat) -> Bool:
  Bool.and(Nat.is_le(Nat.sub(s, a), 48n), Nat.is_le(Nat.sub(b, k), 1048576n))

# room for the next chunk of a log: the writer reports every 32 frames or
# 256 KB, so a writer that has put everything out always leaves room
def Cr.room(c: Cr) -> Bool:
  match c:
    case Cr{_, s, a, b, k, _, _, _, _, _, w, rs}:
      Cr.room.k(s, a, b, k)

def Cr.most(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), a, b)

def Cr.drained.k(same: Bool, c: Cr, +n: Nat, +by: Nat) -> Cr:
  match same c:
    case True{} Cr{g, s, +a, b, +k, nv, bt, at, fl, fq, w, rs}:
      Cr{g, s, Cr.most(a, n), b, Cr.most(k, by), nv, bt, at, fl, fq, w, rs}
    case False{} _:
      c

def Cr.behind.k(+s: Nat, +a: Nat, +b: Nat, +k: Nat) -> Bool:
  Bool.or(Nat.is_gt(Nat.sub(s, a), 96n), Nat.is_gt(Nat.sub(b, k), 1048576n))

# a live client this far behind takes the log's changes as a join does,
# from where it is, in chunks as it has room (Cr.catch), so a slow reader
# (or a writer slower than the hub) is never dropped for a burst: it gets
# fewer, larger frames
def Cr.behind(c: Cr) -> Bool:
  match c:
    case Cr{_, s, a, b, k, _, _, _, _, _, w, rs}:
      Cr.behind.k(s, a, b, k)

# back to taking the log from item at, the far mirrors before fl left out
def Cr.catch(c: Cr, +at: Nat, +fl: Nat) -> Cr:
  match c:
    case Cr{g, s, a, b, k, nv, _, _, _, _, w, _}:
      Cr{g, s, a, b, k, nv, True{}, at, fl, 0n, w, Nil{}}

# the writer of generation gen has put n frames (by bytes) out in all; a
# report from another generation changes nothing (law credit_stale_gen_quiet)
def Cr.drained(+c: Cr, +gen: U32, +n: Nat, +by: Nat) -> Cr:
  Cr.drained.k(U32.is_eq(gen, Cr.gen(c)), c, n, by)

# the log sent up to item at
def Cr.at.set(c: Cr, +at: Nat) -> Cr:
  match c:
    case Cr{g, s, a, b, k, nv, bt, _, fl, fq, w, rs}:
      Cr{g, s, a, b, k, nv, bt, at, fl, fq, w, rs}

# the far mirrors: mirror fl next, from after its item fseq
def Cr.far.set(c: Cr, +fl: Nat, +fq: Nat) -> Cr:
  match c:
    case Cr{g, s, a, b, k, nv, bt, at, _, _, w, rs}:
      Cr{g, s, a, b, k, nv, bt, at, fl, fq, w, rs}

# the log is all out: live
def Cr.live(c: Cr) -> Cr:
  match c:
    case Cr{g, s, a, b, k, nv, _, at, fl, fq, w, rs}:
      Cr{g, s, a, b, k, nv, False{}, at, fl, fq, w, rs}

# The writer's reports
# --------------------
# what a writer has put out (frames, bytes) and what it last reported

type Wr is Data:
  Wr{n: Nat, b: Nat, ln: Nat, lb: Nat}

def Wr.new() -> Wr:
  Wr{0n, 0n, 0n, 0n}

def Wr.put(w: Wr, +by: Nat) -> Wr:
  match w:
    case Wr{n, b, ln, lb}:
      Wr{1n+n, Nat.add(b, by), ln, lb}

# time to report: 32 frames or 256 KB since the last report
def Wr.due(w: Wr) -> Bool:
  match w:
    case Wr{+n, +b, +ln, +lb}:
      Bool.or(Nat.is_ge(Nat.sub(n, ln), 32n), Nat.is_ge(Nat.sub(b, lb), 262144n))

def Wr.said(w: Wr) -> Wr:
  match w:
    case Wr{+n, +b, _, _}:
      Wr{n, b, n, b}

def Wr.n(w: Wr) -> Nat:
  match w:
    case Wr{n, _, _, _}:
      n

def Wr.b(w: Wr) -> Nat:
  match w:
    case Wr{_, b, _, _}:
      b

# Pongs
# -----
# A client's reader answers a ping at most once a second (ms clock), so a
# ping flood costs a bounded load (law pong_rate_bounded)

def Pong.due(+last: Nat, +now: Nat) -> Bool:
  Nat.is_ge(now, Nat.add(last, 1000n))

# Joining
# -------
# A log goes out in chunks of at most Join.most() items and Join.bytes()
# bytes (one item larger than that goes alone), oldest first

def Join.most() -> Nat:
  2000n

def Join.bytes() -> Nat:
  131072n

# a chunk being measured: room left, items taken, full
type JC is Data:
  JC{room: Nat, n: Nat, full: Bool}

def JC.n(c: JC) -> Nat:
  match c:
    case JC{_, n, _}:
      n

def JC.take(fits: Bool, +len: Nat, c: JC) -> JC:
  match fits c:
    case True{} JC{r, n, False{}}:
      JC{Nat.sub(r, len), 1n+n, False{}}
    case _ JC{r, n, _}:
      JC{r, n, True{}}

def JC.step(+x: String, c: JC) -> JC:
  match c:
    case JC{+r, n, f}:
      JC.take(Nat.is_le(String.length(x), r), String.length(x), JC{r, n, f})

def Join.count.go(xs: List<&2, String>, left: Nat, c: JC) -> JC:
  match xs left:
    case Nil{} _:
      c
    case _ 0n:
      c
    case +x <> t 1n+l:
      Join.count.go(t, l, JC.step(x, c))

# how many of xs (oldest first) a chunk of at most `most` items and
# `bytes` bytes takes: at least one
def Join.count.at(xs: List<&2, String>, +most: Nat, +bytes: Nat) -> Nat:
  match xs:
    case Nil{}:
      0n
    case +x <> t:
      JC.n(Join.count.go(t, Nat.sub(most, 1n), JC{Nat.sub(bytes, String.length(x)), 1n, False{}}))

# the same for a log's chunk
def Join.count(xs: List<&2, String>) -> Nat:
  Join.count.at(xs, Join.most(), Join.bytes())

def JC.room(c: JC) -> Nat:
  match c:
    case JC{r, _, _}:
      r

# about how many bytes the next chunk of xs holds (counted while it is
# measured, never by walking its text again)
def Join.size(xs: List<&2, String>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case +x <> t:
      Nat.sub(Join.bytes(), JC.room(Join.count.go(t, Nat.sub(Join.most(), 1n), JC{Nat.sub(Join.bytes(), String.length(x)), 1n, False{}})))

# the items of a log (newest first, n of them) from item at, oldest first
def Join.from(+ls: List<&2, String>, +n: Nat, +at: Nat) -> List<&2, String>:
  List.reverse(&2, String, List.take(&2, String, ls, Nat.sub(n, at)))

# the same, at most Join.most() of them (all a chunk can take): walks
# past the rest without copying it
def Join.window(+ls: List<&2, String>, +n: Nat, +at: Nat) -> List<&2, String>:
  List.reverse(&2, String, List.take(&2, String, List.drop(&2, String, ls, Nat.sub(Nat.sub(n, at), Join.most())), Nat.sub(Nat.sub(n, at), Nat.sub(Nat.sub(n, at), Join.most()))))

# the next chunk of xs (oldest first)
def Join.chunk(+xs: List<&2, String>) -> List<&2, String>:
  List.take(&2, String, xs, Join.count(xs))

# A join's chunks as the hub sends them: a number of lines, never their
# bytes (reading a line's text on the hub copies it: the writer reads it
# once, as it puts the frame together)
def Join.lines() -> Nat:
  64n

def Join.next(+xs: List<&2, String>) -> List<&2, String>:
  List.take(&2, String, xs, Join.lines())

# every chunk of xs in order under the given limits (for laws: together
# they are xs, law join_chunks_cover)
def Join.chunks.at(fuel: Nat, +xs: List<&2, String>, +most: Nat, +bytes: Nat) -> List<&2, List<&2, String>>:
  match fuel xs:
    case _ Nil{}:
      Nil{}
    case 0n _:
      [xs]
    case 1n+f _:
      List.take(&2, String, xs, Join.count.at(xs, most, bytes)) <> Join.chunks.at(f, List.drop(&2, String, xs, Join.count.at(xs, most, bytes)), most, bytes)

def Join.flat(cs: List<&2, List<&2, String>>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      List.append(&2, String, c, Join.flat(t))

# A join frame's lines as the writer sends them: in frames of at most
# Join.most() lines and Join.bytes() bytes (a line larger than that goes
# alone), so no message nears a client's limit however big the events are.
# The first is hd, lines, tl as the hub offered it; each later one is a
# "changes" frame with "boot": true, the very last "boot": false when the
# offered frame was the join's last (ends). Counted as one frame by the
# writer (its bytes are not charged: Wr.put, law items_frames_one)
def Items.cont(last: Bool, c: List<&2, String>) -> String:
  "{\"t\":\"changes\",\"boot\":" ++ Bool.pick(String, last, "false", "true") ++ ",\"items\":[" ++ String.join(c, ",") ++ "]}"

def Items.more(fuel: Nat, +ends: Bool, +xs: List<&2, String>, +most: Nat, +bytes: Nat) -> List<&2, String>:
  match fuel xs:
    case _ Nil{}:
      Nil{}
    case 0n _:
      [Items.cont(False{}, xs)]
    case 1n+f _:
      Items.cont(Bool.and(ends, List.is_empty(&2, String, List.drop(&2, String, xs, Join.count.at(xs, most, bytes)))), List.take(&2, String, xs, Join.count.at(xs, most, bytes))) <> Items.more(f, ends, List.drop(&2, String, xs, Join.count.at(xs, most, bytes)), most, bytes)

def Items.texts.at(+hd: String, +xs: List<&2, String>, +tl: String, +ends: Bool, +most: Nat, +bytes: Nat) -> List<&2, String>:
  (hd ++ String.join(List.take(&2, String, xs, Join.count.at(xs, most, bytes)), ",") ++ tl) <> Items.more(List.length(&2, String, xs), ends, List.drop(&2, String, xs, Join.count.at(xs, most, bytes)), most, bytes)

def Items.texts(+hd: String, +xs: List<&2, String>, +tl: String, +ends: Bool) -> List<&2, String>:
  Items.texts.at(hd, xs, tl, ends, Join.most(), Join.bytes())
