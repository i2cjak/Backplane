import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../core/codec.bend as C
import ./screen.bend as S
import ./notify.bend as N
import ./view.bend as VW
import ./picker.bend as PK
import ../core/botui.bend as BU
import ../core/bot.bend as BT
import ../core/once.bend as O
import ../core/far.bend as FR

# The phone keeps every hub it paired with connected at once, each with
# its own client (Ui). A hub's key is its socket's host:port, which the
# app names it by. The screen is all of them in one: every hub's projects
# (tagged with the machine when there are several), alerts and the island
# from all, and the thread of the hub in focus.
#
# Everything a phone sends back names a thread or project by the id the
# screen gave it, and those ids carry their hub: "key|id". Actions on a
# row are routed by that prefix; the rest go to the hub in focus, which
# is the one whose thread was last opened.

type Hub is Data:
  Hub{key: String, ui: U.Ui}

type Hubs is Data:
  Hubs{cid: String, now: Nat, cur: String, hs: List<&2, Hub>}

# a command for one hub's socket
type HCmd is Data:
  HCmd{hub: String, cmd: U.Cmd}

type HAct is Data:
  HAct{hubs: Hubs, cmds: List<&2, HCmd>, alerts: List<&2, J.Json>}

def Hubs.cmds(a: HAct) -> List<&2, HCmd>:
  match a:
    case HAct{_, cs, _}:
      cs

def Hubs.after(a: HAct) -> Hubs:
  match a:
    case HAct{h, _, _}:
      h

def Hub.ui(h: Hub) -> U.Ui:
  match h:
    case Hub{_, u}:
      u

def Hub.key(h: Hub) -> String:
  match h:
    case Hub{k, _}:
      k

def Hubs.init(now: Nat, +cid: String) -> Hubs:
  Hubs{cid, now, "", Nil{}}

# Ids
# ---

# an id of hub k (no id stays none: law hubs_no_id)
def Hubs.id.k(none: Bool, +k: String, +s: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      k ++ "|" ++ s

def Hubs.id(+k: String, +s: String) -> String:
  Hubs.id.k(String.is_empty(s), k, s)

# the hub a value names ("" when it names none), and the value without it
def Hubs.key_of(+v: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(v, '|')), "")

def Hubs.rest.k(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case _ <> t:
      String.join(t, "|")

def Hubs.rest(+v: String) -> String:
  Hubs.rest.k(String.split(v, '|'))

# what a field of the screen holds: 1 left alone (a thread's entries, the
# viewer's, model picker's and project picker's own values; the bot, room
# or remote bot shown and the bot and room forms, all of the hub in focus,
# whose actions go there), 2 an id of this hub, 0 anything else
# (asked of every field of the screen, thousands a screen: on a phone a
# chain of every name tried for every key was a third of a screen. A hash
# of the key's first two letters turns away two in three keys at once
# (Q.may: a bit a hash, set for the names' first letters), "value" and
# "id", most of the rest, are tried first, and the rare names last)
type QN is Data:
  QN{name: String, kind: Nat}

def Q.names() -> List<&2, QN>:
  [QN{"sel", 2n}, QN{"thread", 2n}, QN{"entries", 1n}, QN{"live", 1n}, QN{"viewer", 1n}, QN{"blocks", 1n}, QN{"bot", 1n},
    QN{"picker", 1n}, QN{"folders", 1n}, QN{"find", 1n}, QN{"asks", 1n}, QN{"attaching", 1n}, QN{"menu", 1n}, QN{"diff", 1n},
    QN{"term", 1n}, QN{"skills", 1n}, QN{"settings", 1n}, QN{"newBot", 1n}, QN{"newRoom", 1n}]

def Q.hash(+a: U32, +b: U32) -> U32:
  U32.and(U32.shrn(((a * 29 : U32) + b : U32), 2n), 31)

def Q.bit(+a: U32, +b: U32) -> Bool:
  U32.is_eq(U32.and(U32.shrn(3100017230, U32.to_nat(Q.hash(a, b))), 1), 1)

# whether a key could be one of the names (never false for one of them:
# law q_may_names)
def Q.may(+k: String) -> Bool:
  match k:
    case SCon{Chr{+a}, SCon{Chr{+b}, _}}:
      Q.bit(a, b)
    case _:
      False{}

def Q.step.k(hit: Bool, n: QN, st: Nat) -> Nat:
  match hit n:
    case True{} QN{_, kind}:
      kind
    case False{} _:
      st

def Q.step(+st: Nat, n: QN, +k: String) -> Nat:
  match st n:
    case 0n QN{+name, kind}:
      Q.step.k(String.eq(name, k), QN{name, kind}, 0n)
    case 1n+j _:
      1n+j

def Q.find(ns: List<&2, QN>, +k: String, +st: Nat) -> Nat:
  match ns:
    case Nil{}:
      st
    case n <> t:
      Q.find(t, k, Q.step(st, n, k))

def Q.rare(id: Bool, +k: String) -> Nat:
  match id:
    case True{}:
      2n
    case False{}:
      Q.find(Q.names(), k, 0n)

def Q.named(value: Bool, +k: String) -> Nat:
  match value:
    case True{}:
      2n
    case False{}:
      Q.rare(String.eq(k, "id"), k)

def Q.kind.k(may: Bool, +k: String) -> Nat:
  match may:
    case True{}:
      Q.named(String.eq(k, "value"), k)
    case False{}:
      0n

def Q.kind(+k: String) -> Nat:
  Q.kind.k(Q.may(k), k)

# whether every name is its own kind through Q.kind (law q_kind_names)
def Q.own(ns: List<&2, QN>) -> Bool:
  match ns:
    case Nil{}:
      True{}
    case QN{+name, +kind} <> t:
      Bool.and(Nat.is_eq(Q.kind(name), kind), Q.own(t))

# a hub's screen (or alerts) with every id made that hub's
def Q.walk(j: J.Json, +p: String, mode: Nat) -> J.Json:
  match j mode:
    case x 1n:
      x
    case J.Str{s} 2n:
      J.Str{Hubs.id(p, s)}
    case J.Obj{fs} _:
      J.Obj{Q.walk(fs, p, 0n)}
    case J.Arr{xs} _:
      J.Arr{Q.walk(xs, p, 0n)}
    case J.Item{h, t} _:
      J.Item{Q.walk(h, p, 0n), Q.walk(t, p, 0n)}
    case J.Field{+k, v, t} _:
      J.Field{k, Q.walk(v, p, Q.kind(k)), Q.walk(t, p, 0n)}
    case x _:
      x

def Q.all(j: J.Json, +p: String) -> J.Json:
  Q.walk(j, p, 0n)

# One hub's client
# ----------------

# a bot form shut (only those: the value names a scratch key)
def One.close(+u: U.Ui, +k: String) -> U.Ui:
  Bool.pick(U.Ui, Nat.is_lt(C.Codec.pos(["@bnew", "@rnew", "@onew"], k), 3n), U.Ui.scratch_set(u, k, ""), u)

# an action, as a phone's one client takes it: "view" opens or closes the
# board viewer ("board", "schematic", "3d", ""), "view-pick" inspects a
# tap, "view-unpick" closes the card, "view-mention" puts the inspected
# item into the draft; "picker-open" opens the project picker at ~/,
# "picker-type" is its field's new text (typed, or a folder tapped),
# "picker-mkdir" makes a folder and goes into it; "find-open" opens
# thread search ("search") or the file picker ("files", which asks for the
# thread's files), "find-q" sets its query, "find-close" closes it; "form-close" shuts a bot
# form ("@bnew", "@rnew", "@onew"; the phones' cancel); any action that moves to another project re-aims
# the viewer
def One.find(files: Bool, +u: U.Ui, +mode: String) -> U.Act:
  match files:
    case True{}:
      U.Ui.act(U.Palette.open(u, mode), "files", "")
    case False{}:
      U.Act{U.Palette.open(u, mode), Nil{}}

# the design history's actions run with the phone's board or schematic as
# the client's view (VW.View.hist.act)
def One.act.rest(hist: Bool, +u: U.Ui, +action: String, +value: String) -> U.Act:
  match hist:
    case True{}:
      VW.View.hist.act(u, action, value)
    case False{}:
      VW.View.sync(U.Ui.act(u, action, value))

def One.act.k(i: Nat, +u: U.Ui, +action: String, +value: String) -> U.Act:
  match i:
    case 0n:
      VW.View.open(u, value)
    case 1n:
      VW.View.mention(u, value)
    case 2n:
      VW.View.pick(u, value)
    case 3n:
      U.Act{VW.Pick.clear(u), Nil{}}
    case 4n:
      PK.MPick.open(u)
    case 5n:
      PK.MPick.type(u, value)
    case 6n:
      PK.MPick.mkdir(u, value)
    case 7n:
      One.find(String.eq(value, "files"), u, value)
    case 8n:
      U.Act{U.Palette.set(u, value, 0n), Nil{}}
    case 9n:
      U.Act{U.Ui.flag_off(u, "palette"), Nil{}}
    case 10n:
      U.Act{One.close(u, value), Nil{}}
    case 11n:
      VW.View.sheet.pick(u, value)
    case 12n:
      VW.View.layer(u, value)
    case 13n:
      VW.View.parts(u)
    case 14n:
      VW.View.mech.act(u, action, value, "mech")
    case 15n:
      VW.View.mech.act(u, action, value, "renders")
    case 16n:
      VW.View.fm.act(u, action, value)
    case 17n:
      VW.View.fm.act(u, action, value)
    case 18n:
      VW.View.fm.act(u, action, value)
    case 19n:
      VW.View.fm.act(u, action, value)
    case 20n:
      VW.View.fm.act(u, action, value)
    case _:
      One.act.rest(Bool.or(String.starts_with(action, "hist-"), String.starts_with(action, "cmp")), u, action, value)

def One.act(+u: U.Ui, +action: String, +value: String) -> U.Act:
  One.act.k(C.Codec.pos(["view", "view-mention", "view-pick", "view-unpick", "picker-open", "picker-type", "picker-mkdir", "find-open", "find-q", "find-close", "form-close", "view-sheet", "view-layer", "view-parts", "mech-3d", "mech-renders", "fm", "fm-cd", "fm-up", "fm-open", "fm-page"], action), u, action, value)

# what a step does to one hub's client
type Op is Data:
  Do{action: String, value: String}
  Got{o: J.Json}
  On{b: Bool}
  Tick{now: Nat}
  Reg{platform: String, token: String, kind: String, thread: String, env: String, bundle: String}

type Did is Data:
  Did{act: U.Act, alerts: List<&2, J.Json>}

def One.got.k(+seen: List<&2, N.Seen>, a: U.Act) -> Did:
  match a:
    case U.Act{+u, cmds}:
      Did{U.Act{u, cmds}, N.Note.alerts.st(U.Ui.threads(S.Mob.st(u)), seen, S.Mob.st(u), U.Ui.info(u, "desk"))}

def Did.alerts(d: Did) -> List<&2, J.Json>:
  match d:
    case Did{_, als}:
      als

def One.got.seen(a: U.Act) -> U.Act:
  match a:
    case U.Act{u, cmds}:
      U.Act{PK.MPick.seen(S.Mob.imgs.seen(u)), cmds}

# a frame from the hub, and the alerts it raised
# (streamed text ends no turn: it raises none, and nothing is compared;
# every other message, far ones included, is: law alerts_none_for_delta)
def One.got.b2(booting: Bool, +seen: List<&2, N.Seen>, a: U.Act) -> Did:
  match booting:
    case True{}:
      Did{a, Nil{}}
    case False{}:
      One.got.k(seen, a)

# a frame of a log still arriving in chunks (or its last) is history: it
# raises no alert; the next frame compares against all of it (law
# boot_no_alerts)
def One.got.b(booting: Bool, +seen: List<&2, N.Seen>, +a: U.Act) -> Did:
  match booting:
    case True{}:
      Did{a, Nil{}}
    case False{}:
      One.got.b2(U.Boot.on(U.Act.ui(a)), seen, a)

def One.got.d(delta: Bool, +u: U.Ui, +o: J.Json) -> Did:
  match delta:
    case True{}:
      Did{One.got.seen(U.Ui.recv_act(VW.View.sheets(VW.View.picked(u, o), o), o)), Nil{}}
    case False{}:
      One.got.b(U.Boot.on(u), N.Note.seen(U.Ui.threads(S.Mob.st(u))), One.got.seen(U.Ui.recv_act(VW.View.sheets(VW.View.picked(u, o), o), o)))

def One.got(+u: U.Ui, +o: J.Json) -> Did:
  One.got.d(String.eq(J.Json.get_str(o, "t", ""), "delta"), u, o)

def One.run(op: Op, +u: U.Ui) -> Did:
  match op:
    case Do{+a, +v}:
      Did{One.act(u, a, v), Nil{}}
    case Got{+o}:
      One.got(u, o)
    case On{b}:
      Did{VW.View.online(u, b), Nil{}}
    case Tick{now}:
      Did{U.Act{U.Ui.tick(u, now), Nil{}}, Nil{}}
    case Reg{p, t, k, th, e, b}:
      Did{U.Ui.rpc.keep(u, "device.register", [J.KV{"platform", J.Json.str(p)}, J.KV{"token", J.Json.str(t)},
        J.KV{"kind", J.Json.str(k)}, J.KV{"thread", J.Json.str(th)}, J.KV{"env", J.Json.str(e)}, J.KV{"bundle", J.Json.str(b)}]), Nil{}}

# Steps over the hubs
# -------------------

type Step is Data:
  Step{hs: List<&2, Hub>, cmds: List<&2, HCmd>, alerts: List<&2, J.Json>}

def Step.hs(s: Step) -> List<&2, Hub>:
  match s:
    case Step{hs, _, _}:
      hs

def Hubs.tag(cs: List<&2, U.Cmd>, +k: String) -> List<&2, HCmd>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      HCmd{k, c} <> Hubs.tag(t, k)

def Hubs.qual(xs: List<&2, J.Json>, +k: String) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Q.all(x, k) <> Hubs.qual(t, k)

def Hubs.put(d: Did, +k: String, rest: Step) -> Step:
  match d rest:
    case Did{U.Act{u, cs}, al} Step{hs, cmds, als}:
      Step{Hub{k, u} <> hs, List.append(&2, HCmd, Hubs.tag(cs, k), cmds), List.append(&2, J.Json, Hubs.qual(al, k), als)}

def Hubs.keep(h: Hub, rest: Step) -> Step:
  match rest:
    case Step{hs, cmds, als}:
      Step{h <> hs, cmds, als}

def Hubs.one(h: Hub, +op: Op, rest: Step) -> Step:
  match h:
    case Hub{+k, +u}:
      Hubs.put(One.run(op, u), k, rest)

def Hubs.pick(hit: Bool, h: Hub, +op: Op, rest: Step) -> Step:
  match hit:
    case True{}:
      Hubs.one(h, op, rest)
    case False{}:
      Hubs.keep(h, rest)

# op on hub `key`, or on every hub
def Hubs.run(hs: List<&2, Hub>, +all: Bool, +key: String, +op: Op) -> Step:
  match hs:
    case Nil{}:
      Step{Nil{}, Nil{}, Nil{}}
    case +h <> t:
      Hubs.pick(Bool.or(all, String.eq(Hub.key(h), key)), h, op, Hubs.run(t, all, key, op))

def Hubs.done(+cid: String, +now: Nat, +cur: String, s: Step) -> HAct:
  match s:
    case Step{hs, cmds, als}:
      HAct{Hubs{cid, now, cur, hs}, cmds, als}

def Hubs.step(hs: Hubs, +all: Bool, +key: String, +op: Op) -> HAct:
  match hs:
    case Hubs{+cid, +now, +cur, list}:
      Hubs.done(cid, now, cur, Hubs.run(list, all, key, op))

def Hubs.has(hs: List<&2, Hub>, +key: String) -> Bool:
  match hs:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(String.eq(Hub.key(h), key), Hubs.has(t, key))

# The bridge's calls
# ------------------

def Hubs.find(hs: List<&2, Hub>, +key: String) -> Maybe<&2, Hub>:
  match hs:
    case Nil{}:
      None{}
    case +h <> t:
      Bool.pick(Maybe<&2, Hub>, String.eq(Hub.key(h), key), Some{h}, Hubs.find(t, key))

def Hubs.made(+m: Maybe<&2, Hub>, +k: String, +cid: String, +now: Nat) -> Hub:
  match m:
    case Some{h}:
      h
    case None{}:
      Hub{k, U.Ui.info_set(U.Ui.set_cid(U.Ui.init(now), cid), "local.fixed", "1")}

def Hubs.set.go(ks: List<&2, String>, +old: List<&2, Hub>, +cid: String, +now: Nat) -> List<&2, Hub>:
  match ks:
    case Nil{}:
      Nil{}
    case +k <> t:
      Hubs.made(Hubs.find(old, k), k, cid, now) <> Hubs.set.go(t, old, cid, now)

def Hubs.first(hs: List<&2, Hub>) -> String:
  match hs:
    case Nil{}:
      ""
    case h <> _:
      Hub.key(h)

def Hubs.set.k(+cid: String, +now: Nat, +cur: String, +hs: List<&2, Hub>) -> Hubs:
  Hubs{cid, now, Bool.pick(String, Hubs.has(hs, cur), cur, Hubs.first(hs)), hs}

# the hubs the phone is paired with, in its order: a new one gets a new
# client, one no longer paired is dropped with all it held, and the focus
# stays where it was while that hub stays
def Hubs.set(hs: Hubs, ks: List<&2, String>) -> Hubs:
  match hs:
    case Hubs{+cid, +now, +cur, +list}:
      Hubs.set.k(cid, now, cur, Hubs.set.go(ks, list, cid, now))

# a hub's client (a fresh one for a key it does not hold)
def Hubs.ui(hs: Hubs, +key: String) -> U.Ui:
  match hs:
    case Hubs{+cid, +now, _, +list}:
      Hub.ui(Hubs.made(Hubs.find(list, key), key, cid, now))

def Hubs.recv(hs: Hubs, +key: String, o: J.Json) -> HAct:
  Hubs.step(hs, False{}, key, Got{o})

def Hubs.online(hs: Hubs, +key: String, b: Bool) -> HAct:
  Hubs.step(hs, False{}, key, On{b})

def Hubs.now(hs: Hubs, now: Nat) -> Hubs:
  match hs:
    case Hubs{cid, _, cur, list}:
      Hubs{cid, now, cur, list}

def Hubs.tick(hs: Hubs, +now: Nat) -> HAct:
  Hubs.step(Hubs.now(hs, now), True{}, "", Tick{now})

# this phone's push tokens go to every hub it is paired with
def Hubs.register(hs: Hubs, p: String, t: String, k: String, th: String, e: String, b: String) -> HAct:
  Hubs.step(hs, True{}, "", Reg{p, t, k, th, e, b})

# Actions
# -------

# actions whose value names a row, a project, a bot or room, or (opening
# the project picker or a bot or room form, adding a project) a hub: they
# go to the hub it names; the first nine also bring it into focus, so the
# picker's, the bot's and the forms' own actions follow it (the history's
# playback ticks go to the hub that asked: bridge.js names it)
def Hubs.routed(+action: String) -> Nat:
  C.Codec.pos(["select", "new-thread", "picker-open", "bot", "room", "remote", "bot-new", "room-new", "proj-go",
    "row-settle", "row-unsettle", "row-snooze", "row-delete", "toggle-settled", "add-project", "proj-remove",
    "row-menu", "proj-menu", "row-pin", "row-unpin", "row-archive", "row-unarchive", "hist-tick", "row-rename", "rename-save"], action)

def Hubs.moves() -> Nat:
  9n

def Hubs.routes() -> Nat:
  25n

# answers to what any hub may be showing (its error, a delete or remove
# to confirm); the project search is every hub's at once, since the list
# it filters spans them all ("proj-find", "proj-find-q", unrouted, go to all)
def Hubs.everywhere(+action: String) -> Bool:
  Nat.is_lt(C.Codec.pos(["dismiss", "delete-no", "proj-keep", "proj-find", "proj-find-q", "menu-close", "side-older", "side-settled", "rename-no"], action), 9n)

# The merged phone sidebar has one view preference across paired hubs.
def Hubs.every.op(op: Op) -> Bool:
  match op:
    case Do{+a, +v}:
      Bool.or(Hubs.everywhere(a), Bool.and(String.eq(a, "setting"), String.starts_with(v, "sidebar.view=")))
    case _:
      False{}

# of what the hub let go says, only what it sends (its viewer's watch
# ends); its focus and scroll are for a screen no longer shown
def Hubs.sends(cs: List<&2, HCmd>) -> List<&2, HCmd>:
  match cs:
    case Nil{}:
      Nil{}
    case HCmd{k, U.Send{t}} <> r:
      HCmd{k, U.Send{t}} <> Hubs.sends(r)
    case _ <> r:
      Hubs.sends(r)

def Hubs.then.k(cmds: List<&2, HCmd>, als: List<&2, J.Json>, +cid: String, +now: Nat, +cur: String, s: Step) -> HAct:
  match s:
    case Step{hs2, cmds2, als2}:
      HAct{Hubs{cid, now, cur, hs2}, List.append(&2, HCmd, cmds, cmds2), List.append(&2, J.Json, als, als2)}

def Hubs.then(s: Step, +cid: String, +now: Nat, +cur: String, +key: String, +op: Op) -> HAct:
  match s:
    case Step{hs, cmds, als}:
      Hubs.then.k(Hubs.sends(cmds), als, cid, now, cur, Hubs.run(hs, False{}, key, op))

def Op.action(op: Op) -> String:
  match op:
    case Do{a, _}:
      a
    case _:
      ""

# into another hub's thread: the hub in focus lets go of its own first
# (closing its viewer), then the other takes the action
def Hubs.focus(move: Bool, hs: Hubs, +key: String, +op: Op) -> HAct:
  match move hs:
    case True{} Hubs{+cid, +now, +cur, list}:
      Hubs.then(Hubs.run(list, False{}, cur, Do{"select", ""}), cid, now, key, key, op)
    case False{} Hubs{+cid, +now, +cur, list}:
      Hubs.step(Hubs{cid, now, cur, list}, Hubs.every.op(op), key, op)

# (matches, not Bool.pick: an unrouted value, which may be a big piece of
# an upload, is never split)
def Hubs.act.k(+hs: Hubs, +cur: String, known: Bool, +action: String, +value: String) -> HAct:
  match known:
    case True{}:
      Hubs.focus(Bool.and(Nat.is_lt(Hubs.routed(action), Hubs.moves()), Bool.not(String.eq(Hubs.key_of(value), cur))), hs, Hubs.key_of(value), Do{action, Hubs.rest(value)})
    case False{}:
      Hubs.focus(False{}, hs, cur, Do{action, value})

def Hubs.cur(hs: Hubs) -> String:
  match hs:
    case Hubs{_, _, c, _}:
      c

def Hubs.shows.k(focus: Bool, +hs: Hubs, +key: String, +o: J.Json) -> Bool:
  match focus:
    case True{}:
      U.Ui.shows(Hubs.ui(hs, key), o)
    case False{}:
      False{}

# whether a message from hub key can change the screen: a thread's streamed
# text shows only in the thread open on the hub in focus, so any other
# thread's delta (every token of every agent at work, on every hub) builds
# no screen (laws hubs_delta_elsewhere, hubs_delta_other_thread)
def Hubs.shows(+hs: Hubs, +key: String, +o: J.Json) -> Bool:
  Hubs.shows.k(String.eq(key, Hubs.cur(hs)), hs, key, o)

def Hubs.redraw.k(delta: Bool, +hs: Hubs, +key: String, +o: J.Json) -> Bool:
  match delta:
    case True{}:
      Hubs.shows(hs, key, o)
    case False{}:
      True{}

# whether the phone builds a screen for a frame from hub key: any message
# from any paired hub can change the merged sidebar and the island; only
# streamed text is held to Hubs.shows (laws hubs_redraw_*)
def Hubs.redraw(+hs: Hubs, +key: String, +o: J.Json) -> Bool:
  Hubs.redraw.k(String.eq(J.Json.get_str(o, "t", ""), "delta"), hs, key, o)

def Hubs.list(hs: Hubs) -> List<&2, Hub>:
  match hs:
    case Hubs{_, _, _, l}:
      l

def Hubs.act.r(routed: Bool, +hs: Hubs, +action: String, +value: String) -> HAct:
  match routed:
    case True{}:
      Hubs.act.k(hs, Hubs.cur(hs), Hubs.has(Hubs.list(hs), Hubs.key_of(value)), action, value)
    case False{}:
      Hubs.act.k(hs, Hubs.cur(hs), False{}, action, value)

def Hubs.act.one(+hs: Hubs, +action: String, +value: String) -> HAct:
  Hubs.act.r(Nat.is_lt(Hubs.routed(action), Hubs.routes()), hs, action, value)

def Hubs.act.then(a: HAct, b: HAct) -> HAct:
  match a b:
    case HAct{_, cs, als} HAct{h, cs2, als2}:
      HAct{h, List.append(&2, HCmd, cs, cs2), List.append(&2, J.Json, als, als2)}

def Hubs.act.go.after(+a: HAct, +action: String, +value: String) -> HAct:
  Hubs.act.then(a, Hubs.act.one(Hubs.after(a), action, value))

def Hubs.act.go.k(go: Bool, +hs: Hubs, +action: String, +value: String) -> HAct:
  match go:
    case True{}:
      Hubs.act.go.after(Hubs.act.one(hs, "proj-find", "off"), action, value)
    case False{}:
      Hubs.act.one(hs, action, value)

# going to a found project shuts the search on every hub, then goes
def Hubs.act(+hs: Hubs, +action: String, +value: String) -> HAct:
  Hubs.act.go.k(String.eq(action, "proj-go"), hs, action, value)

def Hubs.self(+u: U.Ui) -> String:
  J.Json.get_str(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(U.Ui.info(u, "machines")), J.Null{}), "self"), "name", "")

# The screen
# ----------

# what a hub calls itself, else its host
def Hubs.name(+key: String, +u: U.Ui) -> String:
  Bool.pick(String, String.is_empty(Hubs.self(u)), Maybe.default(&2, String, List.head(&2, String, String.split(key, ':')), key), Hubs.self(u))

type Shown is Data:
  Shown{key: String, name: String, j: J.Json}

# (a hub out of focus builds no thread, bot or viewer: the merged screen
# reads those from the hub in focus only)
def Hubs.shown(hs: List<&2, Hub>, +cur: String) -> List<&2, Shown>:
  match hs:
    case Nil{}:
      Nil{}
    case Hub{+k, +u} <> t:
      Shown{k, Hubs.name(k, u), Q.all(S.Mob.screen.f(String.eq(k, cur), u), k)} <> Hubs.shown(t, cur)

def Hubs.named(ss: List<&2, Shown>, +n: String) -> Nat:
  match ss:
    case Nil{}:
      0n
    case Shown{_, +m, _} <> t:
      Nat.add(Bool.pick(Nat, String.eq(String.to_lower(m), String.to_lower(n)), 1n, 0n), Hubs.named(t, n))

def Hubs.relabel.go(ss: List<&2, Shown>, +all: List<&2, Shown>) -> List<&2, Shown>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{+k, +n, j} <> t:
      Shown{k, Bool.pick(String, Nat.is_gt(Hubs.named(all, n), 1n), n ++ " (" ++ k ++ ")", n), j} <> Hubs.relabel.go(t, all)

# two paired machines with one name (any case) are told apart by their key
def Hubs.relabel(+ss: List<&2, Shown>) -> List<&2, Shown>:
  Hubs.relabel.go(ss, ss)

def Shown.j(s: Shown) -> J.Json:
  match s:
    case Shown{_, _, j}:
      j

def Hubs.of(ss: List<&2, Shown>, +key: String) -> J.Json:
  match ss:
    case Nil{}:
      J.Null{}
    case Shown{+k, _, +j} <> t:
      Bool.pick(J.Json, String.eq(k, key), j, Hubs.of(t, key))

def Hubs.all_on(ss: List<&2, Shown>) -> Bool:
  match ss:
    case Nil{}:
      True{}
    case +s <> t:
      Bool.and(J.Json.get_bool(Shown.j(s), "online", False{}), Hubs.all_on(t))

# the first hub's non-empty string at k
def Hubs.said(ss: List<&2, Shown>, +k: String) -> String:
  match ss:
    case Nil{}:
      ""
    case +s <> t:
      Bool.pick(String, String.is_empty(J.Json.get_str(Shown.j(s), k, "")), Hubs.said(t, k), J.Json.get_str(Shown.j(s), k, ""))

def Hubs.nonnull(+j: J.Json) -> Bool:
  match j:
    case J.Null{}:
      False{}
    case _:
      True{}

def Hubs.first_obj(ss: List<&2, Shown>, +k: String) -> J.Json:
  match ss:
    case Nil{}:
      J.Null{}
    case +s <> t:
      Bool.pick(J.Json, Hubs.nonnull(J.Json.get_obj(Shown.j(s), k)), J.Json.get_obj(Shown.j(s), k), Hubs.first_obj(t, k))

# a project row, named by its machine when there are several
def Hubs.machine(p: J.Json, +name: String) -> J.Json:
  match p:
    case J.Obj{fs}:
      J.Obj{J.Field{"machine", J.Str{name}, fs}}
    case x:
      x

def Hubs.machines(ps: List<&2, J.Json>, +name: String) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Hubs.machine(p, name) <> Hubs.machines(t, name)

def Hubs.projects.all(ss: List<&2, Shown>, +many: Bool) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{_, +n, +j} <> t:
      List.append(&2, J.Json, Hubs.machines(J.Json.elems(J.Json.get_obj(j, "projects")), Bool.pick(String, many, n, "")), Hubs.projects.all(t, many))

# the projects of every hub are one list: the live ones of all first, then
# the quiet ones, each hub's own order kept; a project is named by its
# machine only when another has the same name
def Hubs.titles(ps: List<&2, J.Json>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      J.Json.get_str(p, "title", "") <> Hubs.titles(t)

def Hubs.count(ts: List<&2, String>, +x: String) -> Nat:
  match ts:
    case Nil{}:
      0n
    case +h <> t:
      Nat.add(Bool.pick(Nat, String.eq(h, x), 1n, 0n), Hubs.count(t, x))

def Hubs.dup(p: J.Json, +keep: Bool) -> J.Json:
  match p keep:
    case J.Obj{fs} False{}:
      J.Obj{J.Field{"machine", J.Str{""}, fs}}
    case x _:
      x

def Hubs.same(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}

def Hubs.part.k(keep: Bool, p: J.Json, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match keep:
    case True{}:
      p <> rest
    case False{}:
      rest

def Hubs.part(ps: List<&2, J.Json>, +quiet: Bool, +ts: List<&2, String>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Hubs.part.k(Hubs.same(J.Json.get_bool(p, "quiet", False{}), quiet), Hubs.dup(p, Nat.is_gt(Hubs.count(ts, J.Json.get_str(p, "title", "")), 1n)), Hubs.part(t, quiet, ts))

def Hubs.projects.p(+ps: List<&2, J.Json>) -> List<&2, J.Json>:
  List.append(&2, J.Json, Hubs.part(ps, False{}, Hubs.titles(ps)), Hubs.part(ps, True{}, Hubs.titles(ps)))

def Hubs.projects(ss: List<&2, Shown>, +many: Bool) -> List<&2, J.Json>:
  Hubs.projects.p(Hubs.projects.all(ss, many))

# Once a paired owner replaces a mirror, keep its machine visible too.
# A mirror already names its origin in its title; its relay is not its
# origin. Rows from the focused hub retain the usual collision label.
def Hubs.origin.name(ss: List<&2, Shown>, +key: String) -> String:
  match ss:
    case Nil{}:
      key
    case Shown{+k, +n, _} <> t:
      Bool.pick(String, String.eq(k, key), n, Hubs.origin.name(t, key))

def Hubs.origin.project(elsewhere: Bool, p: J.Json, +name: String) -> J.Json:
  match elsewhere:
    case True{}:
      Hubs.machine(p, name)
    case False{}:
      p

def Hubs.origin.projects(ps: List<&2, J.Json>, +ss: List<&2, Shown>, +cur: String) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      +id = J.Json.get_str(p, "id", "")
      Hubs.origin.project(Bool.and(Bool.not(String.eq(Hubs.key_of(id), cur)), Bool.not(FR.Fr.is(Hubs.rest(id)))), p,
        Hubs.origin.name(ss, Hubs.key_of(id))) <> Hubs.origin.projects(t, ss, cur)

# A directly paired owner survives mirror deduplication. Its Active rows
# and focused headers still name their machine, including when its socket
# is offline. Far and reported-only titles already name their origin.
def Hubs.origin.caption(online: Bool, title: String, name: String) -> String:
  match online:
    case True{}:
      title ++ " · " ++ name
    case False{}:
      title ++ " · " ++ name ++ " (away)"

def Hubs.origin.title(mark: Bool, title: String, +name: String, +online: Bool) -> String:
  match mark:
    case False{}:
      title
    case True{}:
      Hubs.origin.caption(online, title, name)

def Hubs.origin.fields(fs: J.Json, +name: String, +online: Bool) -> J.Json:
  match fs:
    case J.Field{+k, J.Str{+v}, t}:
      J.Field{k, J.Str{Hubs.origin.title(String.eq(k, "title"), v, name, online)}, Hubs.origin.fields(t, name, online)}
    case J.Field{k, v, t}:
      J.Field{k, v, Hubs.origin.fields(t, name, online)}
    case x:
      x

def Hubs.origin.object(v: J.Json, +name: String, +online: Bool) -> J.Json:
  match v:
    case J.Obj{fs}:
      J.Obj{Hubs.origin.fields(fs, name, online)}
    case _:
      v

def Hubs.origin.label(mark: Bool, v: J.Json, name: String, online: Bool) -> J.Json:
  match mark:
    case False{}:
      v
    case True{}:
      Hubs.origin.object(v, name, online)

def Hubs.origin.direct(+v: J.Json) -> Bool:
  +id = J.Json.get_str(v, "id", "")
  Bool.not(Bool.or(Bool.or(FR.Fr.is(id), FR.Fr.is(Hubs.rest(id))),
    Bool.or(J.Json.get_bool(v, "remote", False{}), String.eq(J.Json.get_str(v, "kind", ""), "remote"))))

def Hubs.origin.row(+many: Bool, +v: J.Json, +name: String, +online: Bool) -> J.Json:
  Hubs.origin.label(Bool.and(many, Hubs.origin.direct(v)), v, name, online)

def Hubs.origin.rows(rs: List<&2, J.Json>, +many: Bool, +name: String, +online: Bool) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      Hubs.origin.row(many, r, name, online) <> Hubs.origin.rows(t, many, name, online)

def Hubs.origin.focus(+ss: List<&2, Shown>, +cur: String, +field: String) -> J.Json:
  Hubs.origin.row(Nat.is_gt(List.length(&2, Shown, ss), 1n), J.Json.get_obj(Hubs.of(ss, cur), field),
    Hubs.origin.name(ss, cur), J.Json.get_bool(Hubs.of(ss, cur), "online", False{}))

# every hub's folded shelf at k ("older": older projects; "settled": the
# active view's settled rows) as one: how many in all, and open when any
# hub's is ("side-older", "side-settled" go to every hub)
def Hubs.older.n(ss: List<&2, Shown>, +k: String, +acc: Nat) -> Nat:
  match ss:
    case Nil{}:
      acc
    case Shown{_, _, +j} <> t:
      Hubs.older.n(t, k, Nat.add(acc, J.Json.get_nat(J.Json.get_obj(j, k), "count", 0n)))

def Hubs.older.open(ss: List<&2, Shown>, +k: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Shown{_, _, +j} <> t:
      Bool.or(J.Json.get_bool(J.Json.get_obj(j, k), "open", False{}), Hubs.older.open(t, k))

def Hubs.older(+ss: List<&2, Shown>, +k: String) -> J.Json:
  Bool.pick(J.Json, Nat.is_eq(Hubs.older.n(ss, k, 0n), 0n), J.Null{},
    J.Json.obj([J.KV{"count", J.Json.nat(Hubs.older.n(ss, k, 0n))}, J.KV{"open", J.Json.bool(Hubs.older.open(ss, k))}]))

# every hub's active rows as one list, in core's order (Active.rows): live
# rows first, by how much they wait on the person, then newest
def Hubs.arow.cmp(+a: J.Json, +b: J.Json) -> Bool:
  +fa = J.Json.get_bool(a, "faded", False{})
  +fb = J.Json.get_bool(b, "faded", False{})
  +ua = J.Json.get_nat(a, "urg", 0n)
  +ub = J.Json.get_nat(b, "urg", 0n)
  Bool.pick(Bool, Hubs.same(fa, fb), Bool.pick(Bool, Nat.is_eq(ua, ub), Nat.is_ge(J.Json.get_nat(a, "at", 0n), J.Json.get_nat(b, "at", 0n)), Nat.is_gt(ua, ub)), fb)

def Hubs.arow.before(a: J.Json, b: J.Json) -> Bool:
  Hubs.arow.cmp(a, b)

def Hubs.active.all(ss: List<&2, Shown>, +many: Bool) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{_, +name, +j} <> t:
      List.append(&2, J.Json, Hubs.origin.rows(J.Json.elems(J.Json.get_obj(j, "active")), many, name,
        J.Json.get_bool(j, "online", False{})), Hubs.active.all(t, many))

def Hubs.active(+ss: List<&2, Shown>) -> List<&2, J.Json>:
  List.sort(~J.Json, ~Hubs.arow.before, Hubs.active.all(ss, Nat.is_gt(List.length(&2, Shown, ss), 1n)))

# every hub's list at k (bots, rooms), named by machine when there are several
def Hubs.all(ss: List<&2, Shown>, +k: String, +many: Bool) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{_, +n, +j} <> t:
      List.append(&2, J.Json, Hubs.machines(J.Json.elems(J.Json.get_obj(j, k)), Bool.pick(String, many, n, "")), Hubs.all(t, k, many))

# rooms keyed by their id as their own hub gives it (a room shared by two
# machines is one room, whichever hub reports it)
def Hubs.rkeyed(rs: List<&2, J.Json>) -> List<&2, BU.RK<J.Json>>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      BU.RK{Hubs.rest(J.Json.get_str(r, "id", "")), r} <> Hubs.rkeyed(t)

# every hub's rooms, each room once (law hubs_rooms_listed_once)
def Hubs.rooms.keyed(ss: List<&2, Shown>, +many: Bool) -> List<&2, BU.RK<J.Json>>:
  BU.BU.once.of(J.Json, Hubs.rkeyed(Hubs.all(ss, "rooms", many)))

def Hubs.rooms(ss: List<&2, Shown>, +many: Bool) -> List<&2, J.Json>:
  BU.BU.once.vals(J.Json, Hubs.rooms.keyed(ss, many))

def Hubs.lines(ss: List<&2, Shown>) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      List.append(&2, J.Json, J.Json.elems(J.Json.get_obj(J.Json.get_obj(Shown.j(s), "island"), "lines")), Hubs.lines(t))

def Hubs.rows(ss: List<&2, Shown>) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{+k, +n, +j} <> t:
      J.Json.obj([J.KV{"key", J.Json.str(k)}, J.KV{"name", J.Json.str(n)}, J.KV{"online", J.Json.bool(J.Json.get_bool(j, "online", False{}))},
        J.KV{"version", J.Json.str(J.Json.get_str(j, "version", ""))}, J.KV{"changes", J.Json.nat(J.Json.get_nat(j, "seq", 0n))}]) <> Hubs.rows(t)

# the host:port of a hub's url (http://host:3787 -> host:3787)
def Hubs.auth(+url: String) -> String:
  Bool.pick(String, String.contains(url, "://"),
    Maybe.default(&2, String, List.get(&2, String, String.split(url, '/'), 2n), ""),
    Maybe.default(&2, String, List.head(&2, String, String.split(url, '/')), ""))

# Bots over every paired hub
# --------------------------
# A hub lists its own bots and those of the machines it is linked to, so a
# phone paired with two linked hubs would list each bot twice: from its own
# hub, and as name@machine from the other. Each bot is keyed by what it
# stands for and kept once (law hubs_bots_once): a hub's own bot as
# "key|id"; a bot elsewhere, when another paired hub holds that link (or is
# the machine at its url) and has a bot of that name, as that hub's own
# bot; else by its machine's host:port and its name, so two hubs reporting
# the same machine agree. Every hub's own bots come first, so a bot shows
# as its own hub's. A bot a hub mirrors from a linked machine (its threads
# kept there, far.bend) is dropped when that machine is paired too
# (Hubs.bot.dup): it shows once, as its own hub's.

def Hubs.state(h: Hub) -> M.State:
  U.Ui.state(Hub.ui(h))

def Hubs.bot.id(m: Maybe<&2, BT.Bot>) -> String:
  match m:
    case Some{b}:
      BT.Bot.id(b)
    case None{}:
      ""

def Hubs.peer.url(m: Maybe<&2, BT.Peer>) -> String:
  match m:
    case Some{BT.Peer{_, _, u, _, _}}:
      u
    case None{}:
      ""

def Hubs.twin.k(hit: Bool, +k: String, +id: String, +rest: String) -> String:
  Bool.pick(String, Bool.and(hit, Bool.not(String.is_empty(id))), k ++ "|" ++ id, rest)

# whether hub k (not `from`) is the machine a link or an url leads to
def Hubs.twin.is(+k: String, +st: M.State, +from: String, +link: String, +at: String) -> Bool:
  Bool.and(Bool.not(String.eq(k, from)),
    Bool.or(Bool.and(Bool.not(String.is_empty(link)), BT.Maybe.is(BT.Peer, BT.Peer.by.id(BT.World.peers(M.State.bots(st)), link))),
      Bool.and(Bool.not(String.is_empty(at)), String.eq(k, at))))

# that hub's own bot of the name, as "key|id" ("" when no paired hub is it)
def Hubs.twin(hs: List<&2, Hub>, +from: String, +link: String, +at: String, +name: String) -> String:
  match hs:
    case Nil{}:
      ""
    case +h <> t:
      Hubs.twin.k(Hubs.twin.is(Hub.key(h), Hubs.state(h), from, link, at), Hub.key(h),
        Hubs.bot.id(BT.World.find(M.State.bots(Hubs.state(h)), name)), Hubs.twin(t, from, link, at, name))

def Hubs.of.key(hs: List<&2, Hub>, +k: String) -> M.State:
  match hs:
    case Nil{}:
      M.State.empty()
    case +h <> t:
      Bool.pick(M.State, String.eq(Hub.key(h), k), Hubs.state(h), Hubs.of.key(t, k))

def Hubs.far.k(+twin: String, +at: String, +own: String, +name: String) -> String:
  Bool.pick(String, String.is_empty(twin), Bool.pick(String, String.is_empty(at), own, "@" ++ at ++ "|" ++ String.to_lower(name)), twin)

def Hubs.far.at(+st: M.State, +link: String) -> String:
  Bool.pick(String, String.is_empty(Hubs.peer.url(BT.Peer.by.id(BT.World.peers(M.State.bots(st)), link))), "",
    Hubs.auth(Hubs.peer.url(BT.Peer.by.id(BT.World.peers(M.State.bots(st)), link))))

def Hubs.far.key(+hs: List<&2, Hub>, +from: String, +at: String, +r: J.Json) -> String:
  Hubs.far.k(Hubs.twin(hs, from, J.Json.get_str(r, "link", ""), at, J.Json.get_str(r, "name", "")), at,
    from ++ "|" ++ J.Json.get_str(r, "key", ""), J.Json.get_str(r, "name", ""))

# what a row of hub `from` stands for
def Hubs.bot.key(+hs: List<&2, Hub>, +from: String, +r: J.Json) -> String:
  Bool.pick(String, J.Json.get_bool(r, "remote", False{}),
    Hubs.far.key(hs, from, Hubs.far.at(Hubs.of.key(hs, from), J.Json.get_str(r, "link", "")), r),
    from ++ "|" ++ J.Json.get_str(r, "key", ""))

# whether a paired hub other than `from` holds link l: a link's id is the
# same at both its ends, so that hub is the machine l reaches from `from`
# (or, for a link among more, one that reaches it too)
def Hubs.holds(hs: List<&2, Hub>, +from: String, +l: String) -> Bool:
  match hs:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(Bool.and(Bool.not(String.eq(Hub.key(h), from)), BT.Maybe.is(BT.Peer, BT.Peer.by.id(BT.World.peers(M.State.bots(Hubs.state(h))), l))),
        Hubs.holds(t, from, l))

# Projects and ordinary threads follow the same ownership rule as bots.
# Drop a mirror only when the paired owner actually has that entity;
# during initial connection its cached mirror must remain visible.
def Hubs.entity.got(-A: Data, r: Map<&2, A> & Bool) -> Bool:
  (_, b) = r
  b

def Hubs.entity.has(+s: M.State, project: Bool, +id: String) -> Bool:
  match s project:
    case M.State{ps, _, _, _, _, _, _, _, _, _, _} True{}:
      Hubs.entity.got(M.Project, Map.has(&2, M.Project, ps, id))
    case M.State{_, ts, _, _, _, _, _, _, _, _, _} False{}:
      Hubs.entity.got(M.Thread, Map.has(&2, M.Thread, ts, id))

def Hubs.entity.owner(hs: List<&2, Hub>, +from: String, +link: String, +at: String, +project: Bool, +id: String) -> Bool:
  match hs:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(Bool.and(Hubs.twin.is(Hub.key(h), Hubs.state(h), from, link, at), Hubs.entity.has(Hubs.state(h), project, id)),
        Hubs.entity.owner(t, from, link, at, project, id))

def Hubs.entity.dup(+hs: List<&2, Hub>, +from: String, +project: Bool, +id: String) -> Bool:
  Bool.and(FR.Fr.is(id), Hubs.entity.owner(hs, from, FR.Fr.link(id), Hubs.far.at(Hubs.of.key(hs, from), FR.Fr.link(id)), project, FR.Fr.local(id)))

def Hubs.catalog.rows(rs: List<&2, J.Json>, +hs: List<&2, Hub>, +from: String, +project: Bool) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Hubs.part.k(Bool.not(Hubs.entity.dup(hs, from, project, Hubs.rest(J.Json.get_str(r, "id", "")))), r,
        Hubs.catalog.rows(t, hs, from, project))

# Filter only catalog arrays, never timeline text or the focused view.
# A mirrored project contains only mirrored threads, so dropping its
# section also drops every shelf without touching local fold state.
def Hubs.catalog.value(catalog: Bool, v: J.Json, +hs: List<&2, Hub>, +from: String, +project: Bool) -> J.Json:
  match catalog:
    case True{}:
      J.Json.arr(Hubs.catalog.rows(J.Json.elems(v), hs, from, project))
    case False{}:
      v

# Fold counts include hidden rows. Apply the ownership filter to those
# rows too, so pairing the owner does not double Older or Settled.
def Hubs.fold.projects(rs: List<&2, U.SRow>, +hs: List<&2, Hub>, +from: String, acc: Nat) -> Nat:
  match rs:
    case Nil{}:
      acc
    case U.SRow{_, M.Project{+id, _, _, _, _}, _} <> t:
      Hubs.fold.projects(t, hs, from, Nat.add(acc, Bool.pick(Nat, Hubs.entity.dup(hs, from, True{}, id), 1n, 0n)))

def Hubs.fold.older(g: U.SGroups, +hs: List<&2, Hub>, +from: String) -> Nat:
  match g:
    case U.SGroups{_, _, o}:
      Hubs.fold.projects(o, hs, from, 0n)

def Hubs.fold.rows(rs: List<&2, U.ARow>, +hs: List<&2, Hub>, +from: String, acc: Nat) -> Nat:
  match rs:
    case Nil{}:
      acc
    case U.ARow{_, _, +t, _, _, _} <> rest:
      Hubs.fold.rows(rest, hs, from, Nat.add(acc, Bool.pick(Nat, Hubs.entity.dup(hs, from, False{}, M.Thread.id(t)), 1n, 0n)))

def Hubs.fold.settled(p: U.AParts, +hs: List<&2, Hub>, +from: String) -> Nat:
  match p:
    case U.AParts{_, f}:
      Hubs.fold.rows(f, hs, from, 0n)

def Hubs.fold.count(older: Bool, h: Maybe<&2, Hub>, +hs: List<&2, Hub>, +from: String) -> Nat:
  match older h:
    case True{} Some{Hub{_, U.Ui{+st, _, +dr, _, +o, _, +now, _, _, _, _, _, _, _, _, _, _}}}:
      Hubs.fold.older(U.Side.groups(U.Side.shown(st, now, U.Find.q(o, dr)), now), hs, from)
    case False{} Some{Hub{_, U.Ui{+st, _, +dr, _, +o, _, +now, _, _, _, _, _, _, _, _, _, _}}}:
      Hubs.fold.settled(U.Active.parts(U.Active.rows(st, now, U.Find.q(o, dr))), hs, from)
    case _ None{}:
      0n

def Hubs.fold.json(v: J.Json, +older: Bool, +hs: List<&2, Hub>, +from: String) -> J.Json:
  match v:
    case J.Obj{+fs}:
      S.Mob.older.j(Nat.sub(J.Json.get_nat(J.Obj{fs}, "count", 0n), Hubs.fold.count(older, Hubs.find(hs, from), hs, from)),
        J.Json.get_bool(J.Obj{fs}, "open", False{}), "")
    case x:
      x

def Hubs.catalog.field(kind: Nat, v: J.Json, +hs: List<&2, Hub>, +from: String) -> J.Json:
  match kind:
    case 0n:
      Hubs.catalog.value(True{}, v, hs, from, True{})
    case 1n:
      Hubs.catalog.value(True{}, v, hs, from, False{})
    case 2n:
      Hubs.fold.json(v, True{}, hs, from)
    case 3n:
      Hubs.fold.json(v, False{}, hs, from)
    case _:
      v

def Hubs.catalog.fields(fs: J.Json, +hs: List<&2, Hub>, +from: String) -> J.Json:
  match fs:
    case J.Field{+k, +v, t}:
      J.Field{k, Hubs.catalog.field(C.Codec.pos(["projects", "active", "older", "settled"], k), v, hs, from), Hubs.catalog.fields(t, hs, from)}
    case x:
      x

def Hubs.catalog.shown(ss: List<&2, Shown>, +hs: List<&2, Hub>) -> List<&2, Shown>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{+k, n, J.Obj{fs}} <> t:
      Shown{k, n, J.Obj{Hubs.catalog.fields(fs, hs, k)}} <> Hubs.catalog.shown(t, hs)
    case h <> t:
      h <> Hubs.catalog.shown(t, hs)

# a row a hub mirrors from a linked machine (far.bend): a bot elsewhere
# that opens as a bot (BU.act), its threads kept by this hub
def Hubs.mirrored(+r: J.Json) -> Bool:
  Bool.and(J.Json.get_bool(r, "remote", False{}), String.eq(J.Json.get_str(r, "act", ""), "bot"))

# a mirrored bot whose own machine is paired too: that hub lists it as its
# own, so the copy goes (law hubs_bots_mirror_dropped)
def Hubs.bot.dup(+hs: List<&2, Hub>, +from: String, +r: J.Json) -> Bool:
  Bool.and(Hubs.mirrored(r), Bool.and(Bool.not(String.is_empty(J.Json.get_str(r, "link", ""))), Hubs.holds(hs, from, J.Json.get_str(r, "link", ""))))

def Hubs.bot.keep.k(dup: Bool, +far: Bool, +want: Bool, +hs: List<&2, Hub>, +from: String, +r: J.Json, rest: List<&2, O.Ky<J.Json>>) -> List<&2, O.Ky<J.Json>>:
  match dup:
    case True{}:
      rest
    case False{}:
      BT.Post.keep(O.Ky<J.Json>, Bool.pick(Bool, want, far, Bool.not(far)), O.Ky{Hubs.bot.key(hs, from, r), r}, rest)

def Hubs.bot.keep(+far: Bool, +want: Bool, +hs: List<&2, Hub>, +from: String, +r: J.Json, rest: List<&2, O.Ky<J.Json>>) -> List<&2, O.Ky<J.Json>>:
  Hubs.bot.keep.k(Hubs.bot.dup(hs, from, r), far, want, hs, from, r, rest)

def Hubs.bot.rows(rs: List<&2, J.Json>, +want: Bool, +hs: List<&2, Hub>, +from: String) -> List<&2, O.Ky<J.Json>>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Hubs.bot.keep(J.Json.get_bool(r, "remote", False{}), want, hs, from, r, Hubs.bot.rows(t, want, hs, from))

# every hub's own bots (want False) or those elsewhere (want True), keyed
def Hubs.bots.of(ss: List<&2, Shown>, +want: Bool, +hs: List<&2, Hub>, +many: Bool) -> List<&2, O.Ky<J.Json>>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{+k, +n, +j} <> t:
      List.append(&2, O.Ky<J.Json>, Hubs.bot.rows(Hubs.machines(J.Json.elems(J.Json.get_obj(j, "bots")), Bool.pick(String, many, n, "")), want, hs, k),
        Hubs.bots.of(t, want, hs, many))

def Hubs.bots.src(+ss: List<&2, Shown>, +hs: List<&2, Hub>, +many: Bool) -> List<&2, O.Ky<J.Json>>:
  List.append(&2, O.Ky<J.Json>, Hubs.bots.of(ss, False{}, hs, many), Hubs.bots.of(ss, True{}, hs, many))

def Hubs.bots.keyed(+ss: List<&2, Shown>, +hs: List<&2, Hub>, +many: Bool) -> List<&2, O.Ky<J.Json>>:
  O.Once.of(J.Json, Hubs.bots.src(ss, hs, many))

# the cats of every paired hub, each bot once
def Hubs.bots(+ss: List<&2, Shown>, +hs: List<&2, Hub>, +many: Bool) -> List<&2, J.Json>:
  O.Once.vals(J.Json, Hubs.bots.keyed(ss, hs, many))

def Hubs.peer(skip: Bool, +p: J.Json, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match skip:
    case True{}:
      rest
    case False{}:
      J.Json.obj([J.KV{"name", J.Json.str(J.Json.get_str(p, "name", ""))}, J.KV{"url", J.Json.str(J.Json.get_str(p, "url", ""))}]) <> rest

def Hubs.known(ks: List<&2, String>, +a: String) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case k <> t:
      Bool.or(String.eq(k, a), Hubs.known(t, a))

# peers a hub knows of, not paired yet: each once, the first hub's first
def Hubs.peers(ps: List<&2, J.Json>, +ks: List<&2, String>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Hubs.peer(Bool.or(String.is_empty(J.Json.get_str(p, "url", "")), Hubs.known(ks, Hubs.auth(J.Json.get_str(p, "url", "")))), p,
        Hubs.peers(t, Hubs.auth(J.Json.get_str(p, "url", "")) <> ks))

def Hubs.peer_lists(hs: List<&2, Hub>) -> List<&2, J.Json>:
  match hs:
    case Nil{}:
      Nil{}
    case Hub{_, +u} <> t:
      List.append(&2, J.Json, J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(U.Ui.info(u, "machines")), J.Null{}), "peers")), Hubs.peer_lists(t))

def Hubs.keys(hs: List<&2, Hub>) -> List<&2, String>:
  match hs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Hub.key(h) <> Hubs.keys(t)

# the owner's machines the paired hubs know of that this phone is not
# paired with: one tap adds each
def Hubs.found(+hs: List<&2, Hub>) -> List<&2, J.Json>:
  Hubs.peers(Hubs.peer_lists(hs), Hubs.keys(hs))

def Hubs.empty(+n: Nat, +m: Nat, +finding: Bool) -> String:
  Bool.pick(String, Nat.is_eq(m, 0n), "Pair with a hub to start.",
    Bool.pick(String, Bool.and(finding, Nat.is_eq(n, 0n)), "No project matches.", S.Mob.empty(n)))

def Hubs.screen.k(+ss: List<&2, Shown>, +cur: String, +list: List<&2, Hub>) -> J.Json:
  J.Json.obj([J.KV{"online", J.Json.bool(Hubs.all_on(ss))}, J.KV{"version", J.Json.str(J.Json.get_str(Hubs.of(ss, cur), "version", ""))},
    J.KV{"error", J.Json.str(Hubs.said(ss, "error"))}, J.KV{"note", J.Json.str(Hubs.said(ss, "note"))},
    J.KV{"sel", J.Json.str(J.Json.get_str(Hubs.of(ss, cur), "sel", ""))},
    J.KV{"theme", J.Json.str(J.Json.get_str(Hubs.of(ss, cur), "theme", ""))},
    J.KV{"empty", J.Json.str(Hubs.empty(List.length(&2, J.Json, Hubs.projects(ss, False{})), List.length(&2, Shown, ss), J.Json.get_bool(Hubs.first_obj(ss, "search"), "open", False{})))},
    J.KV{"projects", J.Json.arr(Hubs.origin.projects(Hubs.projects(ss, Nat.is_gt(List.length(&2, Shown, ss), 1n)), ss, cur))},
    J.KV{"older", Hubs.older(ss, "older")},
    J.KV{"settled", Hubs.older(ss, "settled")},
    J.KV{"view", J.Json.str(J.Json.get_str(Hubs.of(ss, cur), "view", "projects"))},
    J.KV{"active", J.Json.arr(Hubs.active(ss))},
    J.KV{"rowMenu", Hubs.first_obj(ss, "rowMenu")},
    J.KV{"deleting", Hubs.first_obj(ss, "deleting")},
    J.KV{"renaming", Hubs.first_obj(ss, "renaming")},
    J.KV{"removing", Hubs.first_obj(ss, "removing")},
    J.KV{"search", Hubs.first_obj(ss, "search")},
    J.KV{"folders", J.Json.get_obj(Hubs.of(ss, cur), "folders")},
    J.KV{"settings", J.Json.get_obj(Hubs.of(ss, cur), "settings")},
    J.KV{"find", J.Json.get_obj(Hubs.of(ss, cur), "find")},
    J.KV{"island", N.Note.island.k(Hubs.lines(ss))},
    J.KV{"thread", Hubs.origin.focus(ss, cur, "thread")},
    J.KV{"bots", J.Json.arr(Hubs.bots(ss, list, Nat.is_gt(List.length(&2, Shown, ss), 1n)))},
    J.KV{"rooms", J.Json.arr(Hubs.rooms(ss, Nat.is_gt(List.length(&2, Shown, ss), 1n)))},
    J.KV{"newBot", J.Json.get_obj(Hubs.of(ss, cur), "newBot")},
    J.KV{"newRoom", J.Json.get_obj(Hubs.of(ss, cur), "newRoom")},
    J.KV{"bot", Hubs.origin.focus(ss, cur, "bot")},
    J.KV{"hub", J.Json.str(cur)},
    J.KV{"hubs", J.Json.arr(Hubs.rows(ss))},
    J.KV{"found", J.Json.arr(Hubs.found(list))}])

# the whole screen: every hub's in one
def Hubs.screen(hs: Hubs) -> J.Json:
  match hs:
    case Hubs{_, _, +cur, +list}:
      Hubs.screen.k(Hubs.relabel(Hubs.catalog.shown(Hubs.shown(list, cur), list)), cur, list)

# a running thread t1 that ran a tool, then sent a message to t2 (filed
# under t1 too), and t2 that did something else since (for laws)
def Island.demo() -> M.State:
  M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n},
    M.ThreadCreated{"t1", "p1", "x", M.Local{}, "", "", "claude", "", 1n}, M.ThreadCreated{"t2", "p1", "y", M.Local{}, "", "", "claude", "", 1n},
    M.TurnChanged{"t1", M.Running{}, 2n}, M.ActivityLogged{"t1", "a1", "info", "tool", "ran ls", 3n},
    M.MessagePosted{"t2", M.Link.id("t1", "m1"), M.User{}, "hello", 4n}, M.ActivityLogged{"t2", "a2", "info", "edit", "wrote", 5n}], M.State.empty())
