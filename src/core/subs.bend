import Base
import ./model.bend as M
import ./fold.bend as FO
import ./client.bend as U

# Subagents
# ---------
# What a thread has working for it, as rows every client draws the same
# way: the tasks it delegated (child threads; a click opens one) and the
# agent's own subagents (Claude's Agent calls, model.bend's Bg; a click
# opens or shuts the steps it took). Rows at work come with what they do
# now, and a subagent at work shows its newest steps unless shut, so the
# person sees them go (laws subs_*).
#
# A subagent's steps are read from its log (M.Bg.log), newest first and
# never more than Subs.window() of them, so a frame's work stays bounded
# however long the thread runs.

type SubStep is Data:
  SubStep{kind: String, text: String}

type SubRow is Data:
  SubRow{key: String, agent: Bool, title: String, who: String, word: String, doing: String, live: Bool, open: Bool, n: Nat, steps: List<&2, SubStep>}

# a subagent as its log tells it: the call that started it, its kind
# (model.bend's Bg.kind), what it was asked, how it ended ("" while it
# runs), how many steps it took and its newest steps (oldest first)
type SubAgg is Data:
  SubAgg{call: String, kind: String, title: String, end: String, n: Nat, steps: List<&2, SubStep>}

# how many log entries a frame reads, and steps a row shows
def Subs.window() -> Nat:
  400n

def Subs.shown() -> Nat:
  6n

# finished subagents still listed (the newest)
def Subs.done_kept() -> Nat:
  3n

def Subs.line(+t: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(t, '\n')), "")

# Reading the log
# ---------------

def Agg.call(a: SubAgg) -> String:
  match a:
    case SubAgg{c, _, _, _, _, _}:
      c

# a step taken, kept while fewer than Subs.shown() are (the walk goes newest
# first, so what it keeps are the newest)
def Agg.step(+kind: String, +text: String, +n: Nat, +ss: List<&2, SubStep>) -> List<&2, SubStep>:
  Bool.pick(List<&2, SubStep>, Nat.is_lt(n, Subs.shown()), SubStep{kind, Subs.line(text)} <> ss, ss)

# "start:<kind>" names its kind ("start" alone, none)
def Agg.upd(i: Nat, a: SubAgg, +kind: String, +text: String) -> SubAgg:
  match i a:
    case 0n SubAgg{c, _, _, e, n, ss}:
      SubAgg{c, String.drop(kind, 6n), text, e, n, ss}
    case 1n SubAgg{c, k, ti, _, n, ss}:
      SubAgg{c, k, ti, text, n, ss}
    case _ SubAgg{c, k, ti, e, +n, ss}:
      SubAgg{c, k, ti, e, 1n+n, Agg.step(kind, text, n, ss)}

def Agg.kind(+kind: String) -> Nat:
  Bool.pick(Nat, String.starts_with(kind, "start"), 0n, Bool.pick(Nat, String.eq(kind, "end"), 1n, 2n))

def Agg.upd.if(hit: Bool, a: SubAgg, +kind: String, +text: String) -> SubAgg:
  match hit:
    case True{}:
      Agg.upd(Agg.kind(kind), a, kind, text)
    case False{}:
      a

def Agg.fresh(done: Bool, +call: String, +kind: String, +text: String) -> List<&2, SubAgg>:
  match done:
    case True{}:
      Nil{}
    case False{}:
      [Agg.upd(Agg.kind(kind), SubAgg{call, "", "", "", 0n, Nil{}}, kind, text)]

# an entry of call's put to its subagent, or a new one last
def Agg.put(as: List<&2, SubAgg>, +call: String, +kind: String, +text: String, +done: Bool) -> List<&2, SubAgg>:
  match as:
    case Nil{}:
      Agg.fresh(done, call, kind, text)
    case +a <> t:
      +hit = Bool.and(Bool.not(done), String.eq(Agg.call(a), call))
      Agg.upd.if(hit, a, kind, text) <> Agg.put(t, call, kind, text, Bool.or(done, hit))

def Agg.entry(e: M.Entry, as: List<&2, SubAgg>) -> List<&2, SubAgg>:
  match e:
    case M.Act{_, _, +call, +kind, +text, _}:
      Agg.put(as, call, kind, text, False{})
    case M.Msg{_, _, _, _, _}:
      as

def Agg.walk(k: Nat, es: List<&2, M.Entry>, as: List<&2, SubAgg>) -> List<&2, SubAgg>:
  match k es:
    case 0n _:
      as
    case 1n+_ Nil{}:
      as
    case 1n+j e <> t:
      Agg.walk(j, t, Agg.entry(e, as))

# a thread's subagents from their log, the most recently busy first
def Subs.aggs(+st: M.State, +th: String) -> List<&2, SubAgg>:
  Agg.walk(Subs.window(), M.State.mine(st, M.Bg.log(th)), Nil{})

def Agg.find(as: List<&2, SubAgg>, +call: String) -> SubAgg:
  match as:
    case Nil{}:
      SubAgg{call, "", "", "", 0n, Nil{}}
    case +a <> t:
      Bool.pick(SubAgg, String.eq(Agg.call(a), call), a, Agg.find(t, call))

# Rows
# ----

def Subs.fold(+call: String) -> String:
  "sub:" ++ call

# whether a subagent's steps show: as the person left them, else while it
# runs
def Subs.open(+info: Map<&2, String>, +call: String, live: Bool) -> Bool:
  FO.Fold.open(FO.Fold.user(info, Subs.fold(call)), live)

# what a click on a subagent's row asks (FO.Fold.ask, the "fold" action)
def Subs.ask(+open: Bool, +call: String) -> String:
  FO.Fold.ask(open, Subs.fold(call))

def Subs.steps(open: Bool, ss: List<&2, SubStep>) -> List<&2, SubStep>:
  match open:
    case True{}:
      ss
    case False{}:
      Nil{}

def Subs.or(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, a)

# the word for how a subagent ended
def Subs.ended(+status: String) -> String:
  Bool.pick(String, String.eq(status, "completed"), "done",
    Bool.pick(String, String.is_empty(status), "stopped", status))

# what a row is titled: what it was asked, after its kind unless it is a
# subagent ("shell: scripts/check.sh")
def Subs.named(+kind: String, +title: String) -> String:
  Bool.pick(String, Bool.or(String.is_empty(kind), String.eq(kind, "subagent")), title, kind ++ ": " ++ title)

def Subs.agg.row(a: SubAgg, +info: Map<&2, String>, +kind: String, +title: String, +doing: String, +live: Bool) -> SubRow:
  match a:
    case SubAgg{+call, +k, ti, +en, n, ss}:
      +open = Subs.open(info, call, live)
      +kd = Subs.or(kind, k)
      SubRow{call, True{}, Subs.named(kd, Subs.or(Subs.or(title, ti), "Subagent")), Subs.or(kd, "subagent"), Bool.pick(String, live, "running", Subs.ended(en)),
        doing, live, open, n, Subs.steps(open, ss)}

# what an ended row (M.Bg.ended: finished, its outcome not yet handed to
# the agent) shows in place of what it does
def Subs.reporting() -> String:
  "finished, reporting"

def Subs.word.k(ended: Bool, r: SubRow) -> SubRow:
  match ended r:
    case True{} SubRow{k, a, ti, who, _, _, live, o, n, ss}:
      SubRow{k, a, ti, who, "reporting", Subs.reporting(), live, o, n, ss}
    case False{} _:
      r

# a subagent at work (a line of the thread's Bg); an ended one still
# counts, "reporting"
def Subs.bg.row(+l: String, +as: List<&2, SubAgg>, +info: Map<&2, String>) -> SubRow:
  Subs.word.k(M.Bg.ended(l), Subs.agg.row(Agg.find(as, Subs.or(M.Bg.call(l), M.Bg.field(l, 0n))), info, M.Bg.kind.of(l), M.Bg.title(l), M.Bg.doing(l), True{}))

def Subs.bg.rows(ls: List<&2, String>, +as: List<&2, SubAgg>, +info: Map<&2, String>) -> List<&2, SubRow>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Subs.bg.row(l, as, info) <> Subs.bg.rows(t, as, info)

def Subs.calls(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      M.Bg.call(l) <> Subs.calls(t)

def Subs.has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case +y <> t:
      Bool.or(String.eq(x, y), Subs.has(t, x))

def Subs.done.k(busy: Bool, a: SubAgg, +info: Map<&2, String>, rest: List<&2, SubRow>) -> List<&2, SubRow>:
  match busy:
    case True{}:
      rest
    case False{}:
      Subs.agg.row(a, info, "", "", "", False{}) <> rest

# the finished ones: those in the log that are not at work
def Subs.done(as: List<&2, SubAgg>, +busy: List<&2, String>, +info: Map<&2, String>) -> List<&2, SubRow>:
  match as:
    case Nil{}:
      Nil{}
    case +a <> t:
      Subs.done.k(Subs.has(busy, Agg.call(a)), a, info, Subs.done(t, busy, info))

# the agent's own subagents: those at work in the order they started, then
# the newest finished ones
def Subs.agents(+st: M.State, +info: Map<&2, String>, +th: String) -> List<&2, SubRow>:
  +as = Subs.aggs(st, th)
  +ls = M.Bg.of(st, th)
  List.append(&2, SubRow, Subs.bg.rows(ls, as, info), List.take(&2, SubRow, Subs.done(as, Subs.calls(ls), info), Subs.done_kept()))

# what a thread did last: its newest entry's first line
def Subs.latest.of(es: List<&2, M.Entry>) -> String:
  match es:
    case Nil{}:
      ""
    case M.Msg{_, _, _, +text, _} <> _:
      Subs.line(text)
    case M.Act{_, _, _, +kind, +text, _} <> _:
      kind ++ "  " ++ Subs.line(text)

def Subs.latest(live: Bool, +st: M.State, +th: String) -> String:
  match live:
    case True{}:
      Subs.latest.of(M.State.mine(st, th))
    case False{}:
      ""

def Subs.task(t: M.Task, +st: M.State) -> SubRow:
  match t:
    case M.Task{_, _, +child, _, +s, _, _, +pr, +mo}:
      +live = Bool.not(M.TaskState.terminal(s))
      SubRow{child, False{}, U.Tasks.title(st, child), U.Models.label(pr, mo), U.Task.word(s), Subs.latest(live, st, child), live, False{}, 0n, Nil{}}

def Subs.tasks(ts: List<&2, M.Task>, +st: M.State) -> List<&2, SubRow>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      Subs.task(t, st) <> Subs.tasks(rest, st)

# every row of a thread's subagents: its delegated tasks, then the agent's
def Subs.rows(+st: M.State, +info: Map<&2, String>, +th: String) -> List<&2, SubRow>:
  List.append(&2, SubRow, Subs.tasks(U.Tasks.of(st, th), st), Subs.agents(st, info, th))

def Subs.live(rs: List<&2, SubRow>) -> Nat:
  match rs:
    case Nil{}:
      0n
    case SubRow{_, _, _, _, _, _, live, _, _, _} <> t:
      Nat.add(Bool.pick(Nat, live, 1n, 0n), Subs.live(t))

# "3 at work", or "" with none
def Subs.busy(+n: Nat) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), "", Nat.show(n) ++ " at work")

# The panel as a whole
# --------------------
# Open while anything in it is at work; once all of it is done it folds to
# its head ("3 done"), so finished subagents never hold the top of the
# thread. A click on the head opens or shuts it (the "fold" action, key
# subs:<thread>), and the person's choice holds until they click again.

def Subs.panel.key(+th: String) -> String:
  "subs:" ++ th

def Subs.panel.open(+info: Map<&2, String>, +th: String, +rs: List<&2, SubRow>) -> Bool:
  FO.Fold.open(FO.Fold.user(info, Subs.panel.key(th)), Nat.is_gt(Subs.live(rs), 0n))

# what a click on the head asks
def Subs.panel.ask(+open: Bool, +th: String) -> String:
  FO.Fold.ask(open, Subs.panel.key(th))

# the head's word: "3 at work", else "3 done"
def Subs.panel.word(+rs: List<&2, SubRow>) -> String:
  Subs.or(Subs.busy(Subs.live(rs)), Nat.show(List.length(&2, SubRow, rs)) ++ " done")

# the rows a panel shows: all of them open, none shut
def Subs.panel.rows(open: Bool, rs: List<&2, SubRow>) -> List<&2, SubRow>:
  match open:
    case True{}:
      rs
    case False{}:
      Nil{}

def Subs.agent_n(ls: List<&2, String>) -> Nat:
  match ls:
    case Nil{}:
      0n
    case +l <> t:
      Nat.add(Bool.pick(Nat, String.eq(M.Bg.kind.of(l), "subagent"), 1n, 0n), Subs.agent_n(t))

# how many subagents a thread has at work (its sidebar row's count): what
# it delegated that is not finished, and the agent's own (its shells and
# monitors are not agents)
def Subs.count(+st: M.State, +th: String) -> Nat:
  Nat.add(U.Side.live(U.Tasks.of(st, th)), Subs.agent_n(M.Bg.of(st, th)))

# a sidebar row's badge: "1 agent", "3 agents", or "" with none
def Subs.badge(+n: Nat) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), "", Nat.show(n) ++ Bool.pick(String, Nat.is_eq(n, 1n), " agent", " agents"))

# a step as a row shows it: the tool, or "" for what it wrote
def Subs.step.label(+kind: String) -> String:
  Bool.pick(String, String.eq(kind, "say"), "", kind)
