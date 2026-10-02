import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./bot.bend as BT

# Threads that live on a linked machine (docs/bots.md, "Threads elsewhere").
#
# A hub shares its bots and their threads with the owner's other machines
# it is linked to. The owning hub stays the authority: it pushes each
# shared change, as its own log numbers it, to every such peer (POST
# /far/push), and a peer that missed some asks for them (POST /far/log,
# paged). The peer keeps what it got (its mirror, one per link) and hands
# it to its clients, which fold it into their read model under ids of
# their own: a thing that lives elsewhere is named by the link and its
# id there ("<link>~<id>", Fr.id), so nothing here can be mistaken for it
# and nothing shows twice. What a client does to such a thread (write,
# stop, answer) goes back to its hub (Fr.route, POST /far/rpc).
#
# Order and loss: a batch says which log number it follows (`since`) and
# where it ends (`to`). A mirror takes a batch only when it follows what it
# has (since <= head), and only the items it lacks (n > head); a batch past
# a gap changes nothing and asks for what is missing (Fr.take). So a
# batch that comes twice, late, or out of order is harmless, and a restart
# or a partition on either side ends in one pull.

# Ids
# ---

# a thing on the machine a link reaches, named here
def Fr.id(+link: String, +id: String) -> String:
  link ++ "~" ++ id

# the same, keeping "" (no project, no parent) as it is
def Fr.opt(+link: String, +id: String) -> String:
  Bool.pick(String, String.is_empty(id), "", Fr.id(link, id))

# whether an id names a thing elsewhere (local ids never hold a "~")
def Fr.is(+id: String) -> Bool:
  String.contains(id, "~")

def Fr.link.k(ps: List<&2, String>) -> String:
  match ps:
    case l <> _ <> _:
      l
    case _:
      ""

# the link an id elsewhere lives behind ("" for an id here)
def Fr.link(+id: String) -> String:
  Fr.link.k(String.split(id, '~'))

def Fr.local.k(ps: List<&2, String>, +id: String) -> String:
  match ps:
    case _ <> +t <> +r:
      String.join(t <> r, "~")
    case _:
      id

# its id on its own machine (an id here is itself)
def Fr.local(+id: String) -> String:
  Fr.local.k(String.split(id, '~'), id)

# Changes, as a client here reads them
# ------------------------------------
# The owning hub's change renamed into this hub's ids. Only what shows a
# thread, a bot and its space goes; settings, devices, links, webhooks,
# rooms (shared rooms travel on their own), ordering and usage stay home
# (None).

def Fr.change(+l: String, c: M.Change) -> Maybe<&2, M.Change>:
  match c:
    case M.ProjectCreated{+id, title, root, at}:
      Some{M.ProjectCreated{Fr.id(l, id), title, root, at}}
    case M.ProjectRemoved{+id, at}:
      Some{M.ProjectRemoved{Fr.id(l, id), at}}
    case M.ThreadCreated{+id, +project, title, env, branch, worktree, provider, model, at}:
      Some{M.ThreadCreated{Fr.id(l, id), Fr.opt(l, project), title, env, branch, worktree, provider, model, at}}
    case M.ThreadRenamed{+id, title, at}:
      Some{M.ThreadRenamed{Fr.id(l, id), title, at}}
    case M.MessagePosted{+thread, msg, role, text, at}:
      Some{M.MessagePosted{Fr.id(l, thread), msg, role, text, at}}
    case M.TurnChanged{+thread, state, at}:
      Some{M.TurnChanged{Fr.id(l, thread), state, at}}
    case M.PendingChanged{+thread, count, at}:
      Some{M.PendingChanged{Fr.id(l, thread), count, at}}
    case M.ActivityLogged{+thread, act, tone, kind, summary, at}:
      Some{M.ActivityLogged{Fr.id(l, thread), act, tone, kind, summary, at}}
    case M.ThreadSettled{+id, manual, at}:
      Some{M.ThreadSettled{Fr.id(l, id), manual, at}}
    case M.ThreadUnsettled{+id, at}:
      Some{M.ThreadUnsettled{Fr.id(l, id), at}}
    case M.ThreadArchived{+id, b, at}:
      Some{M.ThreadArchived{Fr.id(l, id), b, at}}
    case M.ThreadDeleted{+id, at}:
      Some{M.ThreadDeleted{Fr.id(l, id), at}}
    case M.ModesSet{+id, runtime, interaction, model, at}:
      Some{M.ModesSet{Fr.id(l, id), runtime, interaction, model, at}}
    case M.TaskDelegated{+task, +parent, +child, depth, provider, model, at}:
      Some{M.TaskDelegated{Fr.id(l, task), Fr.opt(l, parent), Fr.opt(l, child), depth, provider, model, at}}
    case M.TaskStateSet{+task, state, summary, at}:
      Some{M.TaskStateSet{Fr.id(l, task), state, summary, at}}
    case M.TaskDelivered{+task, at}:
      Some{M.TaskDelivered{Fr.id(l, task), at}}
    case M.TurnQueued{+thread, msg, text, at}:
      Some{M.TurnQueued{Fr.id(l, thread), msg, text, at}}
    case M.QueueTaken{+thread, at}:
      Some{M.QueueTaken{Fr.id(l, thread), at}}
    case M.AskOpened{+id, +thread, kind, tool, detail, options, at}:
      Some{M.AskOpened{Fr.id(l, id), Fr.id(l, thread), kind, tool, detail, options, at}}
    case M.AskClosed{+id, answer, at}:
      Some{M.AskClosed{Fr.id(l, id), answer, at}}
    case M.QueueEdited{+thread, msg, text, at}:
      Some{M.QueueEdited{Fr.id(l, thread), msg, text, at}}
    case M.QueueRemoved{+thread, msg, at}:
      Some{M.QueueRemoved{Fr.id(l, thread), msg, at}}
    case M.QueueMoved{+thread, msg, to, at}:
      Some{M.QueueMoved{Fr.id(l, thread), msg, to, at}}
    case M.QueueTakenOne{+thread, msg, at}:
      Some{M.QueueTakenOne{Fr.id(l, thread), msg, at}}
    case M.ProviderSet{+id, provider, model, at}:
      Some{M.ProviderSet{Fr.id(l, id), provider, model, at}}
    case M.TodosSet{+thread, todos, at}:
      Some{M.TodosSet{Fr.id(l, thread), todos, at}}
    case M.BotSet{+id, name, +thread, look, persona, at}:
      Some{M.BotSet{Fr.id(l, id), name, Fr.id(l, thread), look, persona, at}}
    case M.BotDeleted{+id, at}:
      Some{M.BotDeleted{Fr.id(l, id), at}}
    case M.RoutineSet{+id, +bot, name, cron, prompt, on, at}:
      Some{M.RoutineSet{Fr.id(l, id), Fr.id(l, bot), name, cron, prompt, on, at}}
    case M.RoutineDeleted{+id, at}:
      Some{M.RoutineDeleted{Fr.id(l, id), at}}
    case M.RoutineFired{+id, at}:
      Some{M.RoutineFired{Fr.id(l, id), at}}
    case M.MemorySaved{+bot, key, kind, text, tags, at}:
      Some{M.MemorySaved{Fr.id(l, bot), key, kind, text, tags, at}}
    case M.MemoryForgot{+bot, key, at}:
      Some{M.MemoryForgot{Fr.id(l, bot), key, at}}
    case M.SpaceSet{+bot, spec, at}:
      Some{M.SpaceSet{Fr.id(l, bot), spec, at}}
    case M.SpacePageSet{+bot, html, at}:
      Some{M.SpacePageSet{Fr.id(l, bot), html, at}}
    case _:
      None{}

# What the owning hub shares
# --------------------------
# Its projects, bots and threads, shared only over an owner-trusted link
# by the server. Settings, devices, links, hooks and rooms stay home.

def Fr.st.threads(s: M.State) -> Map<&2, M.Thread>:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _, _}:
      ts

def Fr.st.asks(s: M.State) -> Map<&2, M.Ask>:
  match s:
    case M.State{_, _, _, _, _, _, _, ak, _, _, _}:
      ak

def Fr.st.tasks(s: M.State) -> Map<&2, M.Task>:
  match s:
    case M.State{_, _, _, _, tk, _, _, _, _, _, _}:
      tk

def Fr.thread.project(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

def Fr.got.thread(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

# A thread owned here. Mirrors are client projections, never re-exported.
def Fr.has(r: Map<&2, M.Thread> & Bool) -> Bool:
  (_, b) = r
  b

def Fr.thread.shared(+s: M.State, +th: String) -> Bool:
  Bool.and(Fr.has(Map.has(&2, M.Thread, Fr.st.threads(s), th)),
    Bool.not(Fr.is(th)))

def Fr.ask.thread(r: Map<&2, M.Ask> & M.Ask) -> String:
  match r:
    case (_, M.Ask{_, t, _, _, _, _, _, _}):
      t

def Fr.task.parent(r: Map<&2, M.Task> & M.Task) -> String:
  match r:
    case (_, M.Task{_, p, _, _, _, _, _, _, _}):
      p

def Fr.ask.shared(+s: M.State, +id: String) -> Bool:
  Fr.thread.shared(s, Fr.ask.thread(Map.get(M.Ask, M.Ask{id, "", "", "", "", "", False{}, ""}, Fr.st.asks(s), id)))

def Fr.task.shared(+s: M.State, +id: String) -> Bool:
  Fr.thread.shared(s, Fr.task.parent(Map.get(M.Task, M.Task.blank(id), Fr.st.tasks(s), id)))

# whether a change (with the state after it) goes to the owner's other
# machines
def Fr.shared(+s: M.State, c: M.Change) -> Bool:
  match c:
    case M.ProjectCreated{+id, _, _, _}:
      Bool.not(Fr.is(id))
    case M.ProjectRemoved{+id, _}:
      Bool.not(Fr.is(id))
    case M.ThreadCreated{+id, _, _, _, _, _, _, _, _}:
      Fr.thread.shared(s, id)
    case M.ThreadRenamed{+id, _, _}:
      Fr.thread.shared(s, id)
    case M.MessagePosted{+thread, _, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.TurnChanged{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.PendingChanged{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.ActivityLogged{+thread, _, _, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.ThreadSettled{+id, _, _}:
      Fr.thread.shared(s, id)
    case M.ThreadUnsettled{+id, _}:
      Fr.thread.shared(s, id)
    case M.ThreadArchived{+id, _, _}:
      Fr.thread.shared(s, id)
    case M.ThreadDeleted{+id, _}:
      Fr.thread.shared(s, id)
    case M.ModesSet{+id, _, _, _, _}:
      Fr.thread.shared(s, id)
    case M.TaskDelegated{_, +parent, _, _, _, _, _}:
      Fr.thread.shared(s, parent)
    case M.TaskStateSet{+task, _, _, _}:
      Fr.task.shared(s, task)
    case M.TaskDelivered{+task, _}:
      Fr.task.shared(s, task)
    case M.TurnQueued{+thread, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueTaken{+thread, _}:
      Fr.thread.shared(s, thread)
    case M.AskOpened{_, +thread, _, _, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.AskClosed{+id, _, _}:
      Fr.ask.shared(s, id)
    case M.QueueEdited{+thread, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueRemoved{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueMoved{+thread, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueTakenOne{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.ProviderSet{+id, _, _, _}:
      Fr.thread.shared(s, id)
    case M.TodosSet{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.BotSet{_, _, _, _, _, _}:
      True{}
    case M.BotDeleted{_, _}:
      True{}
    case M.RoutineSet{_, _, _, _, _, _, _}:
      True{}
    case M.RoutineDeleted{_, _}:
      True{}
    case M.RoutineFired{_, _}:
      True{}
    case M.MemorySaved{_, _, _, _, _, _}:
      True{}
    case M.MemoryForgot{_, _, _}:
      True{}
    case M.SpaceSet{_, _, _}:
      True{}
    case M.SpacePageSet{_, _, _}:
      True{}
    case _:
      False{}

# Batches
# -------
# An item is a change as its own hub numbers it (its place in that log)
# and sends it (its wire JSON, ids its own).

type Item is Data:
  Item{n: Nat, c: J.Json}

def Item.n(i: Item) -> Nat:
  match i:
    case Item{n, _}:
      n

def Item.json(i: Item) -> J.Json:
  match i:
    case Item{n, c}:
      J.Json.obj([J.KV{"n", J.Json.nat(n)}, J.KV{"c", c}])

def Item.of(+o: J.Json) -> Item:
  Item{J.Json.get_nat(o, "n", 0n), Maybe.default(&2, J.Json, J.Json.get(o, "c"), J.Null{})}

def Fr.items.of(os: List<&2, J.Json>) -> List<&2, Item>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      Item.of(o) <> Fr.items.of(t)

def Fr.items.json(xs: List<&2, Item>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Item.json(x) <> Fr.items.json(t)

def Fr.fresh.k(keep: Bool, x: Item, rest: List<&2, Item>) -> List<&2, Item>:
  match keep:
    case True{}:
      x <> rest
    case False{}:
      rest

# the items after head, in order
def Fr.fresh(xs: List<&2, Item>, +head: Nat) -> List<&2, Item>:
  match xs:
    case Nil{}:
      Nil{}
    case Item{+n, c} <> t:
      Fr.fresh.k(Nat.is_gt(n, head), Item{n, c}, Fr.fresh(t, head))

# what a batch leaves: the new head, the items to take, and whether a gap
# came first (then nothing is taken and the rest is asked for)
type Got is Data:
  Got{head: Nat, items: List<&2, Item>, gap: Bool}

def Fr.take.k(gap: Bool, +head: Nat, +to: Nat, xs: List<&2, Item>) -> Got:
  match gap:
    case True{}:
      Got{head, Nil{}, True{}}
    case False{}:
      Got{Bool.pick(Nat, Nat.is_gt(to, head), to, head), Fr.fresh(xs, head), False{}}

# a batch that follows `since` and ends at `to`, for a mirror at `head`
def Fr.take(+head: Nat, +since: Nat, +to: Nat, xs: List<&2, Item>) -> Got:
  Fr.take.k(Nat.is_gt(since, head), head, to, xs)

def Got.head(g: Got) -> Nat:
  match g:
    case Got{h, _, _}:
      h

def Got.items(g: Got) -> List<&2, Item>:
  match g:
    case Got{_, xs, _}:
      xs

def Got.gap(g: Got) -> Bool:
  match g:
    case Got{_, _, x}:
      x

# A client's fold
# ---------------
# A client keeps how far it has each link's changes beside the read model
# (a Nav under "far~<link>", so a fresh log forgets both at once), folds
# in only what it lacks, and never counts those changes in its own log's
# sequence (M.State.apply.go: a reconnect still asks this hub for exactly
# the changes it missed).

def Fr.nav(+link: String) -> String:
  "far~" ++ link

def Fr.head(+s: M.State, +link: String) -> Nat:
  M.Nav.until(M.Nav.get(M.State.navs(s), Fr.nav(link)))

def Fr.head.set(s: M.State, +link: String, +h: Nat) -> M.State:
  M.State.nav((x => M.Nav.snoozed(x, h)), s, Fr.nav(link))

def Fr.apply.k(m: Maybe<&2, M.Change>, s: M.State) -> M.State:
  match m:
    case Some{c}:
      M.State.apply.go(s, c)
    case None{}:
      s

def Fr.apply.c(m: Maybe<&2, M.Change>, +link: String, s: M.State) -> M.State:
  match m:
    case Some{c}:
      Fr.apply.k(Fr.change(link, c), s)
    case None{}:
      s

def Fr.apply(xs: List<&2, Item>, +link: String, s: M.State) -> M.State:
  match xs:
    case Nil{}:
      s
    case Item{_, +c} <> t:
      Fr.apply(t, link, Fr.apply.c(C.Change.decode(c), link, s))

def Fr.fold.k(g: Got, +link: String, s: M.State) -> M.State:
  match g:
    case Got{_, _, True{}}:
      s
    case Got{h, xs, False{}}:
      Fr.head.set(Fr.apply(xs, link, s), link, h)

# a link's batch folded into a client's read model
def Fr.fold(+s: M.State, +link: String, +since: Nat, +to: Nat, xs: List<&2, Item>) -> M.State:
  Fr.fold.k(Fr.take(Fr.head(s, link), since, to, xs), link, s)

# Machine metadata lives beside the cursor in the client projection, so
# every UI can label a row from M.State without a separate info lookup.
def Fr.mark(s: M.State, +link: String, +name: String, +away: Bool) -> M.State:
  M.State.nav((x => M.Nav{M.Nav.until(x), name, Bool.pick(String, away, "away", "")}), s, Fr.nav(link))

def Fr.name(+s: M.State, +id: String) -> String:
  M.Nav.key(M.Nav.get(M.State.navs(s), Fr.nav(Fr.link(id))), "pinned")

def Fr.away(+s: M.State, +id: String) -> Bool:
  Bool.and(Fr.is(id), String.eq(M.Nav.key(M.Nav.get(M.State.navs(s), Fr.nav(Fr.link(id))), "active"), "away"))

def Fr.title.k(far: Bool, +s: M.State, +id: String, title: String) -> String:
  match far:
    case False{}:
      title
    case True{}:
      title ++ " · " ++ Bool.pick(String, String.is_empty(Fr.name(s, id)), Fr.link(id), Fr.name(s, id)) ++ Bool.pick(String, Fr.away(s, id), " (away)", "")

def Fr.title(+s: M.State, +id: String, title: String) -> String:
  Fr.title.k(Fr.is(id), s, id, title)

# A history reset removes only that link's projection; it never changes
# the local sequence, local entries, or another machine's mirror.
def Fr.map.step(-A: Data, remove: Bool, m: Map<&2, A>, key: String) -> Map<&2, A>:
  match remove:
    case True{}:
      Map.del(&2, A, m, key)
    case False{}:
      m

def Fr.map.go(-A: Data, ks: List<&2, String>, m: Map<&2, A>, +prefix: String) -> Map<&2, A>:
  match ks:
    case Nil{}:
      m
    case +k <> t:
      Fr.map.go(A, t, Fr.map.step(A, String.starts_with(k, prefix), m, k), prefix)

def Fr.map(-A: Data, +m: Map<&2, A>, +prefix: String) -> Map<&2, A>:
  Fr.map.go(A, Map.keys(&2, A, m), m, prefix)

def Fr.entries.keep(remove: Bool, e: M.Entry, acc: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match remove:
    case True{}:
      acc
    case False{}:
      e <> acc

def Fr.entries.go(es: List<&2, M.Entry>, +prefix: String, acc: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match es:
    case Nil{}:
      List.reverse(&2, M.Entry, acc)
    case +e <> t:
      Fr.entries.go(t, prefix, Fr.entries.keep(String.starts_with(M.Idx.thread(e), prefix), e, acc))

def Fr.index(es: List<&2, M.Entry>, by: Map<&2, List<&2, M.Entry>>) -> Map<&2, List<&2, M.Entry>>:
  match es:
    case Nil{}:
      by
    case +e <> t:
      Fr.index(t, M.Idx.post(by, e))

def Fr.world(w: BT.World, +prefix: String) -> BT.World:
  match w:
    case BT.World{bs, rs, ps, hs, ro, ms, pe, sp, ho, ta, pg}:
      BT.World{Fr.map(BT.Bot, bs, prefix), rs, ps, hs, Fr.map(BT.Routine, ro, prefix), Fr.map(BT.Mem, ms, prefix), pe,
        Fr.map(String, sp, prefix), Fr.map(BT.Hops, ho, prefix), Fr.map(Nat, ta, prefix), Fr.map(BT.Page, pg, prefix)}

def Fr.ext(bw: List<&2, M.Ext>, +prefix: String, es: List<&2, M.Entry>) -> List<&2, M.Ext>:
  [M.Ext{Fr.world(M.Ext.world(M.Ext.of(bw)), prefix), Fr.index(List.reverse(&2, M.Entry, es), Map.new(&2, List<&2, M.Entry>))}]

def Fr.forget(s: M.State, +link: String) -> M.State:
  match s:
    case M.State{ps, ts, +es, n, tk, sg, qu, ak, dv, +nv, bw}:
      +prefix = link ++ "~"
      +kept = Fr.entries.go(es, prefix, Nil{})
      M.State{Fr.map(M.Project, ps, prefix), Fr.map(M.Thread, ts, prefix), kept, n, Fr.map(M.Task, tk, prefix), sg,
        Fr.map(List<&2, M.QItem>, qu, prefix), Fr.map(M.Ask, ak, prefix), dv,
        Map.del(&2, M.Nav, Fr.map(M.Nav, nv, prefix), Fr.nav(link)), Fr.ext(bw, prefix, kept)}

def Fr.epoch.nav(+link: String) -> String:
  "epoch~" ++ link

def Fr.epoch.of(+s: M.State, +link: String) -> String:
  M.Nav.key(M.Nav.get(M.State.navs(s), Fr.epoch.nav(link)), "pinned")

def Fr.epoch.keep(s: M.State, +link: String, +epoch: String) -> M.State:
  M.State.nav((x => M.Nav.keyed(x, "pinned", epoch)), s, Fr.epoch.nav(link))

def Fr.recv.base(reset: Bool, s: M.State, +link: String) -> M.State:
  match reset:
    case True{}:
      Fr.forget(s, link)
    case False{}:
      s

def Fr.epoch.changed(+old: String, +epoch: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(epoch)), Bool.not(String.eq(old, epoch)))

def Fr.recv(+s: M.State, +link: String, +epoch: String, +since: Nat, +to: Nat, xs: List<&2, Item>) -> M.State:
  Fr.epoch.keep(Fr.fold(Fr.recv.base(Fr.epoch.changed(Fr.epoch.of(s, link), epoch), s, link), link, since, to, xs), link,
    Bool.pick(String, String.is_empty(epoch), Fr.epoch.of(s, link), epoch))

# A hub's mirror of a link
# ------------------------
# What the other end sent, in its order, how far it goes, its name, and
# whether it answered last time (away: shown, stale, until it does).

type In is Data:
  In{link: String, name: String, head: Nat, items: List<&2, Item>, away: Bool, epoch: String}

def In.new(+link: String, +name: String) -> In:
  In{link, name, 0n, Nil{}, True{}, ""}

def In.link(i: In) -> String:
  match i:
    case In{l, _, _, _, _, _}:
      l

def In.head(i: In) -> Nat:
  match i:
    case In{_, _, h, _, _, _}:
      h

def In.away(i: In) -> Bool:
  match i:
    case In{_, _, _, _, a, _}:
      a

def In.away.set(i: In, a: Bool) -> In:
  match i:
    case In{l, n, h, xs, _, e}:
      In{l, n, h, xs, a, e}

def In.name.set(i: In, +nm: String) -> In:
  match i:
    case In{l, n, h, xs, a, e}:
      In{l, Bool.pick(String, String.is_empty(nm), n, nm), h, xs, a, e}

def In.put.k(g: Got, i: In) -> In:
  match g i:
    case Got{_, _, True{}} _:
      i
    case Got{h, ys, False{}} In{l, n, _, xs, _, e}:
      In{l, n, h, List.append(&2, Item, xs, ys), False{}, e}

# a batch into the mirror (it answered, so it is here)
def In.put(+i: In, +since: Nat, +to: Nat, xs: List<&2, Item>) -> In:
  In.put.k(Fr.take(In.head(i), since, to, xs), i)

# what a batch brings that the mirror lacks (Nil on a gap)
def In.got(+i: In, +since: Nat, +to: Nat, xs: List<&2, Item>) -> Got:
  Fr.take(In.head(i), since, to, xs)

# the message a client folds: {"t":"far","link","name","away","since","head","items"}
def Fr.msg(+link: String, +name: String, away: Bool, +since: Nat, +head: Nat, xs: List<&2, Item>) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"far"}}, J.KV{"link", J.Str{link}}, J.KV{"name", J.Str{name}}, J.KV{"away", J.Json.bool(away)},
    J.KV{"since", J.Json.nat(since)}, J.KV{"head", J.Json.nat(head)}, J.KV{"items", J.Json.arr(Fr.items.json(xs))}]))

def Fr.epoch.fields(o: J.Json) -> J.Json:
  match o:
    case J.Obj{fs}:
      fs
    case _:
      J.End{}

def In.epoch(i: In) -> String:
  match i:
    case In{_, _, _, _, _, e}:
      e

def In.epoch.set(i: In, e: String) -> In:
  match i:
    case In{l, n, h, xs, a, _}:
      In{l, n, h, xs, a, e}

# Optional on the wire: old clients still decode the same far message.
def Fr.with.epoch(+text: String, epoch: String) -> String:
  J.Json.show(J.Obj{J.Field{"epoch", J.Str{epoch}, Fr.epoch.fields(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))}})

def Fr.msg.epoch(+link: String, +name: String, away: Bool, +since: Nat, +head: Nat, xs: List<&2, Item>, epoch: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"far"}}, J.KV{"link", J.Str{link}}, J.KV{"name", J.Str{name}}, J.KV{"away", J.Json.bool(away)},
    J.KV{"since", J.Json.nat(since)}, J.KV{"head", J.Json.nat(head)}, J.KV{"epoch", J.Str{epoch}}, J.KV{"items", J.Json.arr(Fr.items.json(xs))}]))

# all a mirror holds, for a client that just joined
def In.msg(i: In) -> String:
  match i:
    case In{+l, +n, +h, xs, a, +e}:
      Fr.msg.epoch(l, n, a, 0n, h, xs, e)

# Mirrors by link
# ---------------

def Ins.find(ms: List<&2, In>, +link: String) -> Maybe<&2, In>:
  match ms:
    case Nil{}:
      None{}
    case +i <> t:
      Bool.pick(Maybe<&2, In>, String.eq(In.link(i), link), Some{i}, Ins.find(t, link))

def Ins.get(+ms: List<&2, In>, +link: String, +name: String) -> In:
  Maybe.default(&2, In, Ins.find(ms, link), In.new(link, name))

# the mirror of `link` replaced (added when new)
def Ins.set(ms: List<&2, In>, +i: In) -> List<&2, In>:
  match ms:
    case Nil{}:
      [i]
    case +x <> +t:
      Bool.pick(List<&2, In>, String.eq(In.link(x), In.link(i)), i <> t, x <> Ins.set(t, i))

# Requests to a thread elsewhere
# ------------------------------
# A request naming a thread, an ask or a bot elsewhere goes to the hub it
# lives on, with that hub's ids; only these may (Fr.may): writing to it,
# stopping it, answering it, its queue, settling it, a side question, its
# modes, and a bot's space and routines. Anything else is refused here.

def Fr.methods() -> List<&2, String>:
  ["turn.start", "turn.interrupt", "ask.answer", "queue.move", "queue.remove", "queue.resume", "queue.steer", "queue.edit",
   "thread.settle", "thread.unsettle", "thread.rename", "thread.btw", "thread.modes", "thread.provider", "thread.effort", "bots.space", "bots.routine_run"]

def Fr.may.go(ms: List<&2, String>, +m: String) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case x <> t:
      Bool.or(String.eq(x, m), Fr.may.go(t, m))

def Fr.may(+m: String) -> Bool:
  Fr.may.go(Fr.methods(), m)

# the params that name a thing (the ones renamed on the way)
def Fr.keys() -> List<&2, String>:
  ["thread", "id", "bot", "routine", "task", "parent", "child", "project", "ask"]

def Fr.key(+k: String) -> Bool:
  Fr.may.go(Fr.keys(), k)

# the link a request's params name, "" when they name nothing elsewhere
def Fr.params.link(fs: J.Json) -> String:
  match fs:
    case J.Field{+k, J.Str{+v}, t}:
      Bool.pick(String, Bool.and(Fr.key(k), Fr.is(v)), Fr.link(v), Fr.params.link(t))
    case J.Field{_, _, t}:
      Fr.params.link(t)
    case _:
      ""

# the params with the link's ids made local
def Fr.params.local(fs: J.Json, +link: String) -> J.Json:
  match fs:
    case J.Field{+k, J.Str{+v}, t}:
      J.Field{k, J.Str{Bool.pick(String, Bool.and(Fr.key(k), String.eq(Fr.link(v), link)), Fr.local(v), v)}, Fr.params.local(t, link)}
    case J.Field{k, v, t}:
      J.Field{k, v, Fr.params.local(t, link)}
    case x:
      x

def Fr.obj.fields(o: J.Json) -> J.Json:
  match o:
    case J.Obj{fs}:
      fs
    case _:
      J.End{}

def Fr.is.some(m: Maybe<&2, M.Change>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# a request bound elsewhere: which link, and the request as that hub
# takes it (its method, its params in its ids; no request id)
type Route is Data:
  Route{link: String, m: String, body: String}

def Fr.route.k(+link: String, +m: String, +fs: J.Json) -> Maybe<&2, Route>:
  Bool.pick(Maybe<&2, Route>, String.is_empty(link), None{},
    Some{Route{link, m, J.Json.show(J.Json.obj([J.KV{"id", J.Num{"0"}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Obj{Fr.params.local(fs, link)}}]))}})

def Route.link.of(m: Maybe<&2, Route>) -> String:
  match m:
    case Some{Route{l, _, _}}:
      l
    case None{}:
      ""

# None: a request for this hub
def Fr.route(+o: J.Json) -> Maybe<&2, Route>:
  Fr.route.k(Fr.params.link(Fr.obj.fields(J.Json.get_obj(o, "p"))), J.Json.get_str(o, "m", ""), Fr.obj.fields(J.Json.get_obj(o, "p")))

# On the owning hub: a request from a linked machine is taken only when it
# is one of Fr.methods and what it names is shared (a bot's thread, an ask
# in one, a bot)
def Fr.allowed.k(+s: M.State, +m: String, +p: J.Json) -> Bool:
  Bool.pick(Bool, String.eq(m, "ask.answer"), Fr.ask.shared(s, J.Json.get_str(p, "id", "")),
    Bool.pick(Bool, Bool.or(String.eq(m, "bots.space"), String.eq(m, "bots.routine_run")), Bool.not(String.is_empty(J.Json.get_str(p, "bot", J.Json.get_str(p, "id", "")))),
      Fr.thread.shared(s, J.Json.get_str(p, "thread", ""))))

def Fr.allowed(+s: M.State, +o: J.Json) -> Bool:
  Bool.and(Fr.may(J.Json.get_str(o, "m", "")), Fr.allowed.k(s, J.Json.get_str(o, "m", ""), J.Json.get_obj(o, "p")))

# The owning hub's reply keeps its success/error and payload; only the
# caller's request id is restored on the receiving hub.
def Fr.reply.fields(fs: J.Json, +id: String) -> J.Json:
  match fs:
    case J.Field{+k, +v, t}:
      J.Field{k, Bool.pick(J.Json, String.eq(k, "id"), J.Num{id}, v), Fr.reply.fields(t, id)}
    case x:
      x

def Fr.reply(o: J.Json, +id: String) -> String:
  J.Json.show(J.Obj{Fr.reply.fields(Fr.obj.fields(o), id)})

# A late disk load never replaces a mirror already updated by traffic.
def In.loaded(+live: In, +disk: In) -> In:
  Bool.pick(In, Bool.and(In.away(live), Nat.is_ge(In.head(disk), In.head(live))), disk, live)

# How a thing elsewhere is shown
# ------------------------------
# its machine's name beside its own ("Kit · desk"); nothing for one here

def Fr.where(+id: String, +name: String) -> String:
  Bool.pick(String, Fr.is(id), " · " ++ name, "")

# The owning hub's feed
# ---------------------
# What it shares, as its log numbers it (newest first; each a wire line,
# kept as text so the hub holds no parsed copy): made once from the log
# (off the hub), then grown by each commit. A linked machine's pull reads
# a page of it after the number it has.

type Line is Data:
  Line{n: Nat, text: String}

def Line.n(l: Line) -> Nat:
  match l:
    case Line{n, _}:
      n

def Fr.line.k(sh: Bool, +n: Nat, +text: String, rest: List<&2, Line>) -> List<&2, Line>:
  match sh:
    case True{}:
      Line{n, text} <> rest
    case False{}:
      rest

def Fr.line.shared(m: Maybe<&2, M.Change>, +s: M.State) -> Bool:
  match m:
    case Some{c}:
      Fr.shared(s, c)
    case None{}:
      False{}

def Fr.line.parsed(m: Maybe<&2, J.Json>) -> Maybe<&2, M.Change>:
  match m:
    case Some{+o}:
      C.Change.decode(o)
    case None{}:
      None{}

# the shared lines of a log (newest first, `n` the number of the first),
# newest first; tail-recursive (a log holds tens of thousands)
def Fr.feed.go(ls: List<&2, String>, +n: Nat, +s: M.State, acc: List<&2, Line>) -> List<&2, Line>:
  match ls:
    case Nil{}:
      List.reverse(&2, Line, acc)
    case +l <> t:
      Fr.feed.go(t, Nat.sub(n, 1n), s, Fr.line.k(Fr.line.shared(Fr.line.parsed(J.Json.parse(l)), s), n, l, acc))

def Fr.feed(+ls: List<&2, String>, +s: M.State) -> List<&2, Line>:
  Fr.feed.go(ls, List.length(&2, String, ls), s, Nil{})

# a commit's changes (oldest first) with their wire lines (oldest first),
# numbered after `seq`, the shared ones newest first
def Fr.feed.add(cs: List<&2, M.Change>, ls: List<&2, String>, +seq: Nat, +s: M.State, acc: List<&2, Line>) -> List<&2, Line>:
  match cs ls:
    case +c <> t +l <> r:
      Fr.feed.add(t, r, 1n+seq, s, Fr.line.k(Fr.shared(s, c), 1n+seq, l, acc))
    case _ _:
      acc

def Fr.feed.keep(go: Bool, +n: Nat, +t: String, acc: List<&2, Line>) -> List<&2, Line>:
  match go:
    case True{}:
      Line{n, t} <> acc
    case False{}:
      acc

# the lines after `since`, oldest first (the feed is newest first, so they
# are the ones before the first at or below `since`)
# (it stops at the first line at or below since: law far_feed_after_stops)
def Fr.feed.after(fs: List<&2, Line>, +since: Nat, go: Bool, acc: List<&2, Line>) -> List<&2, Line>:
  match fs go:
    case _ False{}:
      acc
    case Nil{} True{}:
      acc
    case Line{+n, +t} <> r True{}:
      Fr.feed.after(r, since, Nat.is_gt(n, since), Fr.feed.keep(Nat.is_gt(n, since), n, t, acc))

# a page: the items after `since` up to about `cap` characters (one bigger
# line goes alone), where it ends (the last item's number when there is
# more, else the log's end), and whether there is more
type Page is Data:
  Page{head: Nat, items: List<&2, Item>, more: Bool}

type Pg is Data:
  Pg{room: Nat, last: Nat, count: Nat, items: List<&2, Item>, full: Bool}

def Fr.page.item(+n: Nat, +t: String) -> Item:
  Item{n, Maybe.default(&2, J.Json, J.Json.parse(t), J.Null{})}

def Fr.page.step.k(fits: Bool, first: Bool, p: Pg, +n: Nat, +t: String) -> Pg:
  match fits first p:
    case True{} _ Pg{r, _, c, xs, f}:
      Pg{Nat.sub(r, String.length(t)), n, 1n+c, Fr.page.item(n, t) <> xs, f}
    case False{} True{} Pg{_, _, c, xs, _}:
      Pg{0n, n, 1n+c, Fr.page.item(n, t) <> xs, True{}}
    case False{} False{} Pg{r, l, c, xs, _}:
      Pg{r, l, c, xs, True{}}

def Fr.page.step(p: Pg, +n: Nat, +t: String) -> Pg:
  match p:
    case Pg{+r, l, +c, xs, True{}}:
      Pg{r, l, c, xs, True{}}
    case Pg{+r, l, +c, xs, False{}}:
      Fr.page.step.k(Nat.is_le(String.length(t), r), Nat.is_eq(c, 0n), Pg{r, l, c, xs, False{}}, n, t)

def Fr.page.go(ls: List<&2, Line>, p: Pg) -> Pg:
  match ls:
    case Nil{}:
      p
    case Line{+n, +t} <> r:
      Fr.page.go(r, Fr.page.step(p, n, t))

def Fr.page.of(p: Pg, +total: Nat, +seq: Nat) -> Page:
  match p:
    case Pg{_, +l, +c, xs, _}:
      Page{Bool.pick(Nat, Nat.is_lt(c, total), l, seq), List.reverse(&2, Item, xs), Nat.is_lt(c, total)}

def Fr.page.k(+ls: List<&2, Line>, +since: Nat, +seq: Nat, +cap: Nat) -> Page:
  Fr.page.of(Fr.page.go(ls, Pg{cap, since, 0n, Nil{}, False{}}), List.length(&2, Line, ls), seq)

# what a pull from `since` gets (seq: this log's length)
def Fr.page(+fs: List<&2, Line>, +since: Nat, +seq: Nat, +cap: Nat) -> Page:
  Fr.page.k(Fr.feed.after(fs, since, True{}, Nil{}), since, seq, cap)

def Page.json(p: Page) -> String:
  match p:
    case Page{h, xs, m}:
      J.Json.show(J.Json.obj([J.KV{"head", J.Json.nat(h)}, J.KV{"items", J.Json.arr(Fr.items.json(xs))}, J.KV{"more", J.Json.bool(m)}]))

# Pushing to a linked machine
# ---------------------------
# One push at a time per link. A batch says it follows the last push that
# got through (`acked`) only while every push since did (`clean`); after a
# failure (or a restart: nothing is known) it says it follows only its own
# start, so the other end, missing what failed, finds the gap and pulls.
# Batches that come while one is out wait, merged, for it to end.

type Out is Data:
  Out{link: String, acked: Nat, clean: Bool, busy: Bool, from: Nat, to: Nat, items: List<&2, Item>}

def Out.new(+link: String) -> Out:
  Out{link, 0n, False{}, False{}, 0n, 0n, Nil{}}

def Out.link(o: Out) -> String:
  match o:
    case Out{l, _, _, _, _, _, _}:
      l

# a batch to send: what it follows, where it ends, its items
type Send is Data:
  Send{link: String, since: Nat, to: Nat, items: List<&2, Item>}

def Out.add.k(empty: Bool, o: Out, +from: Nat, +to: Nat, xs: List<&2, Item>) -> Out:
  match empty o:
    case True{} Out{l, a, c, b, f, _, ys}:
      Out{l, a, c, b, f, to, ys}
    case False{} Out{l, a, c, b, f, _, +ys}:
      Out{l, a, c, b, Bool.pick(Nat, List.is_empty(&2, Item, ys), from, f), to, List.append(&2, Item, ys, xs)}

# a commit that took the log from `from` to `to`, with what it shares
def Out.add(o: Out, +from: Nat, +to: Nat, +xs: List<&2, Item>) -> Out:
  Out.add.k(List.is_empty(&2, Item, xs), o, from, to, xs)

def Out.next.k(go: Bool, o: Out) -> Maybe<&2, Send> & Out:
  match go o:
    case True{} Out{+l, +a, +c, _, +f, +t, xs}:
      (Some{Send{l, Bool.pick(Nat, c, a, f), t, xs}}, Out{l, a, c, True{}, f, t, Nil{}})
    case False{} _:
      (None{}, o)

# the push to start now, if one is due (none out, something waiting)
def Out.next(o: Out) -> Maybe<&2, Send> & Out:
  match o:
    case Out{l, a, c, +b, f, t, +xs}:
      Out.next.k(Bool.and(Bool.not(b), Bool.not(List.is_empty(&2, Item, xs))), Out{l, a, c, b, f, t, xs})

# the push out ended: through (up to `to`), or not
def Out.done(o: Out, ok: Bool, +to: Nat) -> Out:
  match o ok:
    case Out{l, _, _, _, f, t, xs} True{}:
      Out{l, to, True{}, False{}, f, t, xs}
    case Out{l, a, _, _, f, t, xs} False{}:
      Out{l, a, False{}, False{}, f, t, xs}

def Outs.get(os: List<&2, Out>, +link: String) -> Out:
  match os:
    case Nil{}:
      Out.new(link)
    case +o <> t:
      Bool.pick(Out, String.eq(Out.link(o), link), o, Outs.get(t, link))

def Outs.set(os: List<&2, Out>, +o: Out) -> List<&2, Out>:
  match os:
    case Nil{}:
      [o]
    case +x <> +t:
      Bool.pick(List<&2, Out>, String.eq(Out.link(x), Out.link(o)), o <> t, x <> Outs.set(t, o))

def Send.body(s: Send, +name: String) -> String:
  match s:
    case Send{_, since, to, xs}:
      J.Json.show(J.Json.obj([J.KV{"name", J.Str{name}}, J.KV{"since", J.Json.nat(since)}, J.KV{"head", J.Json.nat(to)}, J.KV{"items", J.Json.arr(Fr.items.json(xs))}]))

# What a hub keeps for threads elsewhere
# --------------------------------------
# its mirrors (one per link), its pushes (one per link), its own feed
# (None until made from the log), and the lines committed meanwhile

type Fh is Data:
  Fh{ins: List<&2, In>, outs: List<&2, Out>, feed: Maybe<&2, List<&2, Line>>, early: List<&2, Line>, pulls: List<&2, String>, epoch: String}

def Fh.empty() -> Fh:
  Fh{Nil{}, Nil{}, None{}, Nil{}, Nil{}, ""}

def Fh.ins(f: Fh) -> List<&2, In>:
  match f:
    case Fh{i, _, _, _, _, _}:
      i

def Fh.in(+f: Fh, +link: String, +name: String) -> In:
  Ins.get(Fh.ins(f), link, name)

def Fh.in.set(f: Fh, i: In) -> Fh:
  match f:
    case Fh{ms, os, fd, e, p, ep}:
      Fh{Ins.set(ms, i), os, fd, e, p, ep}

def Fh.out(+f: Fh, +link: String) -> Out:
  match f:
    case Fh{_, os, _, _, _, _}:
      Outs.get(os, link)

def Fh.out.set(f: Fh, o: Out) -> Fh:
  match f:
    case Fh{ms, os, fd, e, p, ep}:
      Fh{ms, Outs.set(os, o), fd, e, p, ep}

# the feed, None until it is made from the log
def Fh.feed(f: Fh) -> Maybe<&2, List<&2, Line>>:
  match f:
    case Fh{_, _, fd, _, _, _}:
      fd

def Fh.feed.put(m: Maybe<&2, List<&2, Line>>, e: List<&2, Line>, ls: List<&2, Line>) -> Maybe<&2, List<&2, Line>> & List<&2, Line>:
  match m:
    case Some{fs}:
      (Some{List.append(&2, Line, ls, fs)}, e)
    case None{}:
      (None{}, List.append(&2, Line, ls, e))

def Fh.feed.at.k(f: Fh, fd: Maybe<&2, List<&2, Line>>, e: List<&2, Line>) -> Fh:
  match f:
    case Fh{ms, os, _, _, p, ep}:
      Fh{ms, os, fd, e, p, ep}

def Fh.feed.at(f: Fh, r: Maybe<&2, List<&2, Line>> & List<&2, Line>) -> Fh:
  (fd, e) = r
  Fh.feed.at.k(f, fd, e)

# a commit's shared lines (newest first) join the feed, or wait for it
def Fh.feed.add(f: Fh, ls: List<&2, Line>) -> Fh:
  match f:
    case Fh{ms, os, fd, e, p, ep}:
      Fh.feed.at(Fh{ms, os, None{}, Nil{}, p, ep}, Fh.feed.put(fd, e, ls))

# the feed made from the log (up to where it was when asked), with what
# was committed since on top
def Fh.feed.ready(f: Fh, ls: List<&2, Line>) -> Fh:
  match f:
    case Fh{ms, os, _, e, p, ep}:
      Fh{ms, os, Some{List.append(&2, Line, e, ls)}, Nil{}, p, ep}

def Fh.pulling(+f: Fh, +link: String) -> Bool:
  match f:
    case Fh{_, _, _, _, p, _}:
      Fr.may.go(p, link)

def Fh.pull.on(f: Fh, +link: String) -> Fh:
  match f:
    case Fh{ms, os, fd, e, p, ep}:
      Fh{ms, os, fd, e, link <> p, ep}

def Fh.pull.off.go(ps: List<&2, String>, +link: String) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case +x <> +t:
      Bool.pick(List<&2, String>, String.eq(x, link), t, x <> Fh.pull.off.go(t, link))

def Fh.pull.off(f: Fh, +link: String) -> Fh:
  match f:
    case Fh{ms, os, fd, e, p, ep}:
      Fh{ms, os, fd, e, Fh.pull.off.go(p, link), ep}

def Fh.epoch(f: Fh) -> String:
  match f:
    case Fh{_, _, _, _, _, ep}:
      ep

def Fh.epoch.set(f: Fh, +epoch: String) -> Fh:
  match f:
    case Fh{ms, os, fd, e, p, +ep}:
      Fh{ms, os, fd, e, p, Bool.pick(String, String.is_empty(epoch), ep, epoch)}

# lines (newest first) as items, oldest first
def Fr.lines.items(ls: List<&2, Line>, acc: List<&2, Item>) -> List<&2, Item>:
  match ls:
    case Nil{}:
      acc
    case Line{+n, +t} <> r:
      Fr.lines.items(r, Fr.page.item(n, t) <> acc)

# A mirror kept on disk
# ---------------------
# <home>/far/<link>.jsonl: each batch taken, its items as lines, then
# {"head": n}; read back at start (the mirror shows, away, until its
# machine answers)

def Fr.file.items(xs: List<&2, Item>) -> String:
  match xs:
    case Nil{}:
      ""
    case x <> t:
      J.Json.show(Item.json(x)) ++ "\n" ++ Fr.file.items(t)

def Fr.file.batch(xs: List<&2, Item>, +head: Nat) -> String:
  Fr.file.items(xs) ++ "{\"head\":" ++ Nat.show(head) ++ "}\n"

def Bool.is_some.j(m: Maybe<&2, J.Json>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

def Fr.some.j(m: Maybe<&2, J.Json>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# New files carry an epoch header before their batches. Old files remain
# readable; the first epoch-aware pull replaces that legacy projection.
def Fr.file.line(m: Maybe<&2, J.Json>, i: In) -> In:
  match m i:
    case Some{+o} In{+l, +n, +h, +xs, +a, +e}:
      Bool.pick(In, Fr.some.j(J.Json.get(o, "c")), In{l, n, h, Item.of(o) <> xs, a, e},
        In{l, n, J.Json.get_nat(o, "head", h), xs, a, J.Json.get_str(o, "epoch", e)})
    case None{} _:
      i

def Fr.file.scan(ls: List<&2, String>, i: In) -> In:
  match ls:
    case Nil{}:
      i
    case l <> t:
      Fr.file.scan(t, Fr.file.line(J.Json.parse(l), i))

def Fr.file.done(i: In) -> In:
  match i:
    case In{l, n, h, xs, a, e}:
      In{l, n, h, List.reverse(&2, Item, xs), a, e}

def Fr.file.read(+text: String, +link: String, +name: String) -> In:
  Fr.file.done(Fr.file.scan(String.lines(text), In.new(link, name)))

def In.name.of(i: In) -> String:
  match i:
    case In{_, n, _, _, _, _}:
      n

# a push that only says where it ends, as a gap: the other end pulls
def Send.gap(s: Send) -> Send:
  match s:
    case Send{l, _, +to, _}:
      Send{l, to, to, Nil{}}

# a mirrored bot's space page (its newest SpacePageSet; "" for none), for
# GET /bots/<link>~<id>/space.html on the hub that mirrors it
def Fr.page.html.k(hit: Bool, +o: J.Json, +cur: String) -> String:
  match hit:
    case True{}:
      J.Json.get_str(o, "html", "")
    case False{}:
      cur

def Fr.page.html.go(xs: List<&2, Item>, +bot: String, +cur: String) -> String:
  match xs:
    case Nil{}:
      cur
    case Item{_, +c} <> t:
      Fr.page.html.go(t, bot, Fr.page.html.k(Bool.and(String.eq(J.Json.get_str(c, "$", ""), "SpacePageSet"), String.eq(J.Json.get_str(c, "bot", ""), bot)), c, cur))

def In.page(i: In, +bot: String) -> String:
  match i:
    case In{_, _, _, xs, _, _}:
      Fr.page.html.go(xs, bot, "")
