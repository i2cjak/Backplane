import Base
import ./json.bend as J

# Who is at a desk. The window and the web page (desk clients; phones never
# are) tell the hub which thread they show and whether they have the focus
# (desk.look), and say it again at most every Desk.beat() seconds while the
# person keeps using them. A thread that a focused desk shows, used in the
# last Desk.window() seconds, is watched: its turn's end raises no phone
# alert, pushed or the phone's own (laws desk_seen_holds, alert_watched_quiet),
# and no desktop notification either. Any other alert also goes to the desk
# used last as a desktop notification (Desk.to; law desk_seen_nobody).

# how long a focused desk counts as watched with no input (seconds)
def Desk.window() -> Nat:
  180n

# how often a desk in use says its look again (seconds)
def Desk.beat() -> Nat:
  60n

# one client's look: whether it is a desk at all, the thread it shows,
# whether it has the focus, and when it last said so (the hub's clock)
type Look is Data:
  Look{desk: Bool, thread: String, focused: Bool, at: Nat}

# a client that never said desk.look (a phone)
def Look.none() -> Look:
  Look{False{}, "", False{}, 0n}

def Look.at(l: Look) -> Nat:
  match l:
    case Look{_, _, _, a}:
      a

def Look.desk(l: Look) -> Bool:
  match l:
    case Look{d, _, _, _}:
      d

def Look.sees.k(focused: Bool, +th: String, +at: Nat, +thread: String, +now: Nat) -> Bool:
  match focused:
    case True{}:
      Bool.and(String.eq(th, thread), Nat.is_lt(now, Nat.add(at, Desk.window())))
    case False{}:
      False{}

# does this look watch thread now
def Look.sees(l: Look, +thread: String, +now: Nat) -> Bool:
  match l:
    case Look{True{}, +th, f, +at}:
      Look.sees.k(f, th, at, thread, now)
    case Look{False{}, _, _, _}:
      False{}

# a desk.look request's params, stamped now
def Look.of(+p: J.Json, +now: Nat) -> Look:
  Look{True{}, J.Json.get_str(p, "thread", ""), J.Json.get_bool(p, "focused", False{}), now}

# every client's look, with its id
type At is Data:
  At{client: U32, look: Look}

def Desk.seen(xs: List<&2, At>, +thread: String, +now: Nat) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case At{_, l} <> t:
      Bool.or(Look.sees(l, thread, now), Desk.seen(t, thread, now))

def Desk.thread.k(sees: Bool, +th: String, rest: List<&2, String>) -> List<&2, String>:
  match sees:
    case True{}:
      th <> rest
    case False{}:
      rest

def Desk.look.thread(l: Look) -> String:
  match l:
    case Look{_, th, _, _}:
      th

def Desk.threads.go(xs: List<&2, At>, +now: Nat) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case At{_, +l} <> t:
      Desk.thread.k(Look.sees(l, Desk.look.thread(l), now), Desk.look.thread(l), Desk.threads.go(t, now))

# the threads watched now, one a line: what the hub tells every client
# (info "desk"), so a phone holds its own alerts for them too
def Desk.text(xs: List<&2, At>, +now: Nat) -> String:
  String.join(Desk.threads.go(xs, now), "\n")

# the desk used last: the one a desktop notification goes to
def Desk.lead.k(later: Bool, +c: U32, +at: Nat, best: Maybe<&2, At>) -> Maybe<&2, At>:
  match later:
    case True{}:
      Some{At{c, Look{True{}, "", False{}, at}}}
    case False{}:
      best

def Desk.best.at(m: Maybe<&2, At>) -> Nat:
  match m:
    case Some{At{_, l}}:
      Look.at(l)
    case None{}:
      0n

def Desk.best.none(m: Maybe<&2, At>) -> Bool:
  match m:
    case Some{_}:
      False{}
    case None{}:
      True{}

def Desk.lead.one(desk: Bool, +c: U32, +at: Nat, +best: Maybe<&2, At>) -> Maybe<&2, At>:
  match desk:
    case True{}:
      Desk.lead.k(Bool.or(Desk.best.none(best), Nat.is_gt(at, Desk.best.at(best))), c, at, best)
    case False{}:
      best

def Desk.lead.go(xs: List<&2, At>, +best: Maybe<&2, At>) -> Maybe<&2, At>:
  match xs:
    case Nil{}:
      best
    case At{+c, +l} <> t:
      Desk.lead.go(t, Desk.lead.one(Look.desk(l), c, Look.at(l), best))

def Desk.lead.id(m: Maybe<&2, At>) -> Maybe<&2, U32>:
  match m:
    case Some{At{c, _}}:
      Some{c}
    case None{}:
      None{}

def Desk.lead(xs: List<&2, At>) -> Maybe<&2, U32>:
  Desk.lead.id(Desk.lead.go(xs, None{}))

def Desk.to.k(seen: Bool, xs: List<&2, At>) -> Maybe<&2, U32>:
  match seen:
    case True{}:
      None{}
    case False{}:
      Desk.lead(xs)

# where a thread's alert shows on a desk: nowhere when a desk watches the
# thread (law desk_seen_nobody), else the desk used last (none when no
# desk is connected)
def Desk.to(+xs: List<&2, At>, +thread: String, +now: Nat) -> Maybe<&2, U32>:
  Desk.to.k(Desk.seen(xs, thread, now), xs)

# a push's alert key: none when a desk watches the thread
def Desk.hold(seen: Bool, key: String) -> String:
  match seen:
    case True{}:
      ""
    case False{}:
      key

# does the hub's "desk" info (Desk.text) name thread
def Desk.watched(+text: String, +thread: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(thread)), String.contains("\n" ++ text ++ "\n", "\n" ++ thread ++ "\n"))

# Messages
# --------

def Desk.info(+text: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"info"}}, J.KV{"info", J.Json.obj([J.KV{"desk", J.Str{text}}])}]))

# a desktop notification for one desk: {"t":"notify", thread, title, body,
# kind ("done" or "fail"), key (alerts with one key replace each other)}
def Desk.notify(+thread: String, +title: String, +body: String, +kind: String, +key: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"notify"}}, J.KV{"thread", J.Str{thread}}, J.KV{"title", J.Str{title}},
    J.KV{"body", J.Str{body}}, J.KV{"kind", J.Str{kind}}, J.KV{"key", J.Str{key}}]))

# The desk's side
# ---------------

def Desk.num(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Desk.num(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))))

# what a desk last said (the client keeps it in its scratch, "@desk",
# with when in "@desk.at")
def Desk.said(+thread: String, focused: Bool) -> String:
  Bool.pick(String, focused, "1 ", "0 ") ++ thread

# should the desk say its look now: when the thread or the focus changed
# since it last did (or it never has), or a beat has passed with the focus
def Desk.due(+last: String, +last_at: String, +thread: String, +focused: Bool, +now: Nat) -> Bool:
  Bool.or(Bool.or(String.is_empty(last), Bool.not(String.eq(last, Desk.said(thread, focused)))),
    Bool.and(focused, Nat.is_ge(now, Nat.add(Desk.num(last_at, 0n), Desk.beat()))))

def Desk.params(+thread: String, focused: Bool) -> List<&2, J.KV>:
  [J.KV{"thread", J.Str{thread}}, J.KV{"focused", J.Flag{focused}}]

# Heartbeat
# ---------
# The hub sends {"t":"hb"} every Alive.every() ms through the same path as
# every other frame, so a link that carries nothing at all for longer than
# Alive.limit() ms is dead (a half-open socket shows no error): the client
# closes it and reconnects from its sequence (Alive.due, all four clients).
# The frame carries nothing and every client's fold leaves it alone.

def Alive.every() -> Nat:
  15000n

def Alive.limit() -> Nat:
  40000n

def Alive.frame() -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"hb"}}]))

# whether a link last heard from at `last` is dead at `now` (ms)
def Alive.due(+last: Nat, +now: Nat) -> Bool:
  Nat.is_gt(Nat.sub(now, last), Alive.limit())
