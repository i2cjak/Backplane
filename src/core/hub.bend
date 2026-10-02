import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./attach.bend as AT
import ./agent.bend as AG
import ./handoff.bend as HD
import ./todo.bend as TD
import ./fm.bend as FM
import ./refs.bend as RF
import ./emb.bend as EM

# The decider. Requests from clients and lines from agents come in; changes
# (persisted, folded into the read model) and effects (run by the server)
# come out. Nothing here does IO, so the server's behaviour is these defs.

# what the server must do after a step
type Out is Data:
  # to one client
  Send{client: U32, text: String}
  # to every client
  Broadcast{text: String}
  # ensure an agent process runs for a thread, then write a line to it
  AgentStart{thread: String, cwd: String, provider: String, model: String, session: String, runtime: M.RuntimeMode, interaction: M.InteractionMode}
  AgentSend{thread: String, line: String}
  AgentStop{thread: String}
  # show a client a project's board or schematic (kind "board",
  # "schematic"; anything else stops), or the file at path when set
  Watch{client: U32, kind: String, root: String, path: String}
  # install the latest release and restart
  Upgrade{}
  KiCadInstall{}
  # run one Codex turn (a process per turn; `session` resumes)
  CodexTurn{thread: String, cwd: String, model: String, session: String, runtime: M.RuntimeMode, text: String}
  GrokTurn{thread: String, cwd: String, model: String, session: String, runtime: M.RuntimeMode, text: String}
  TurnEnded{thread: String, state: String}
  AskAnswered{id: String, answer: String}
  Git{client: U32, id: String, job: String, thread: String, cwd: String, a: String, b: String}
  TermOp{op: String, thread: String, cwd: String, data: List<&2, U32>, cols: U32, rows: U32}
  # a terminal in the chat (core/emb.bend): its command run (again: a
  # restart), a client's snapshot of it, hung up
  TermRun{key: String, title: String, cwd: String, cmd: String, cols: U32, rows: U32, again: Bool}
  TermSnap{client: U32, key: String}
  TermKill{key: String}
  Fs{client: U32, id: String, op: String, path: String}
  # what a piece a phone tapped is: the info of piece idx of the chunk at
  # `at` of the plot key it holds (the plot actor answers)
  PlotInfo{client: U32, id: String, key: String, at: Nat, idx: Nat}
  # a bot effect the server runs with IO or secrets (bothub.bend): kind
  # home, gone, hook, unhook, send, invite, join, unpeer, google
  BotFx{kind: String, a: String, b: String, c: String}
  # a desk client (the window, the web page) shows thread, with or
  # without the focus (core/desk.bend; the server keeps it per client)
  DeskLook{client: U32, thread: String, focused: Bool}

type Step is Data:
  Step{changes: List<&2, M.Change>, outs: List<&2, Out>}

def Step.none() -> Step:
  Step{Nil{}, Nil{}}

def Step.outs(os: List<&2, Out>) -> Step:
  Step{Nil{}, os}

# Replies
# -------

def Reply.ok(+client: U32, +id: String) -> Out:
  Send{client, J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{True{}}}]))}

def Reply.err(+client: U32, +id: String, msg: String) -> Out:
  Send{client, J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{False{}}}, J.KV{"error", J.Str{msg}}]))}

def Step.reply(+client: U32, +id: String, cs: List<&2, M.Change>) -> Step:
  Step{cs, [Reply.ok(client, id)]}

# Ids
# ---

# unique and replay-stable: the event sequence never repeats
def Hub.id(prefix: String, +now: Nat, +seq: Nat) -> String:
  prefix ++ Nat.show(now) ++ "-" ++ Nat.show(seq)

def Hub.seq(s: M.State) -> Nat:
  match s:
    case M.State{_, _, _, n, _, _, _, _, _, _, _}:
      n

def Hub.thread.k(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

# Lookups
# -------

def Hub.thread(s: M.State, +id: String) -> M.Thread:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _, _}:
      Hub.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id))

def Hub.project.k(r: Map<&2, M.Project> & M.Project) -> M.Project:
  (_, p) = r
  p

def Hub.project(s: M.State, +id: String) -> M.Project:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _, _, _}:
      Hub.project.k(Map.get(M.Project, M.Project.blank(id), ps, id))

# the base name of a path, for a default project title
def Hub.base.k(parts: List<&2, String>) -> String:
  Maybe.default(&2, String, List.last(&2, String, List.filter(~String, ~(x => Bool.not(String.is_empty(x))), parts)), "project")

def Hub.base(p: String) -> String:
  Hub.base.k(String.split(p, '/'))

def Hub.project.root(p: M.Project) -> String:
  match p:
    case M.Project{_, _, root, _, _}:
      root

# the directory a thread's agent works in
def Hub.cwd(+s: M.State, t: M.Thread) -> String:
  match t:
    case M.Thread{_, +project, _, _, _, _, _, _, _, _, _, _, _, _, +worktree, _, _, _, _, _, _}:
      Bool.pick(String, String.is_empty(worktree), Hub.project.root(Hub.project(s, project)), worktree)

# Claude's stream-json input line for one user message
def Claude.user(text: String) -> String:
  J.Json.show(J.Json.obj([
    J.KV{"type", J.Str{"user"}},
    J.KV{"message", J.Json.obj([
      J.KV{"role", J.Str{"user"}},
      J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{text}}])])}])}]))

def Claude.interrupt(+id: String) -> String:
  J.Json.show(J.Json.obj([
    J.KV{"type", J.Str{"control_request"}},
    J.KV{"request_id", J.Str{id}},
    J.KV{"request", J.Json.obj([J.KV{"subtype", J.Str{"interrupt"}}])}]))

# a user message for Claude: straight in, or, when it attaches images, by
# the server, which reads them into image content blocks first
def Claude.send(+thread: String, +cwd: String, +text: String) -> Out:
  Bool.pick(Out, List.is_empty(&2, String, AT.Att.images(text)), AgentSend{thread, Claude.user(text)},
    Git{0, "", "attach.claude", thread, cwd, text, ""})

def Hub.title.cut(long: Bool, +line: String) -> String:
  match long:
    case True{}:
      String.take(line, 57n) ++ "..."
    case False{}:
      line

def Hub.title.of(+text: String) -> String:
  +line = String.trim(Maybe.default(&2, String, List.head(&2, String, String.lines(text)), ""))
  Hub.title.cut(Nat.is_gt(String.length(line), 60n), line)

# Requests
# --------

# a thread still called "New thread" takes its first message as its title
def Hub.title.k(fresh: Bool, +thread: String, +text: String, +now: Nat, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match fresh:
    case True{}:
      M.ThreadRenamed{thread, Hub.title.of(text), now} <> rest
    case False{}:
      rest

# the effects that run one turn of a thread's agent, by provider: Claude
# keeps one process per thread fed with stream-json; Codex and Grok run a
# process per turn, resuming their session (Grok over ACP, reported in
# Codex's event shapes)
def Hub.run.k(i: Nat, +thread: String, +cwd: String, +provider: String, +model: String, +session: String, runtime: M.RuntimeMode, interaction: M.InteractionMode, +text: String) -> List<&2, Out>:
  match i:
    case 1n:
      [CodexTurn{thread, cwd, model, session, runtime, text}]
    case 2n:
      [GrokTurn{thread, cwd, model, session, runtime, text}]
    case _:
      [AgentStart{thread, cwd, provider, model, session, runtime, interaction}, Claude.send(thread, cwd, text)]

def Hub.run(t: M.Thread, +cwd: String, +text: String) -> List<&2, Out>:
  match t:
    case M.Thread{+id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +provider, model, runtime, interaction, session, _}:
      Hub.run.k(C.Codec.pos(["claude", "codex", "grok"], provider), id, cwd, provider, model, session, runtime, interaction, text)

def Hub.post.go(wait: Bool, +t: M.Thread, +cwd: String, +queued: String, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  match wait:
    case True{}:
      Step{[M.MessagePosted{thread, msg, role, text, now}, M.TurnQueued{thread, msg, text, now}], Nil{}}
    case False{}:
      Step{List.concat(&2, M.Change, [[M.MessagePosted{thread, msg, role, text, now}],
          Bool.pick(List<&2, M.Change>, String.is_empty(queued), Nil{}, [M.QueueTaken{thread, now}]),
          [M.TurnChanged{thread, M.Running{}, now}]]),
        Git{0, "", "checkpoint0", thread, cwd, "", ""} <> Git{0, "", "step", thread, cwd, msg, ""} <> Hub.run(t, cwd, M.Queue.join(queued, text))}

def Step.after(st: Step, more: List<&2, M.Change>) -> Step:
  match st:
    case Step{cs, os}:
      Step{List.append(&2, M.Change, cs, more), os}

def Step.before(cs: List<&2, M.Change>, os: List<&2, Out>, st: Step) -> Step:
  match st:
    case Step{c2, o2}:
      Step{List.append(&2, M.Change, cs, c2), List.append(&2, Out, os, o2)}

# whether a message with this id is in the entries: a tail walk that stops
# at the first hit
def Hub.has_msg.go(es: List<&2, M.Entry>, +id: String, found: Bool) -> Bool:
  match es found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case M.Msg{i, _, _, _, _} <> t False{}:
      Hub.has_msg.go(t, id, String.eq(i, id))
    case M.Act{_, _, _, _, _, _} <> t False{}:
      Hub.has_msg.go(t, id, False{})

def Hub.has_msg(es: List<&2, M.Entry>, +id: String) -> Bool:
  Hub.has_msg.go(es, id, False{})

def Hub.entries(s: M.State) -> List<&2, M.Entry>:
  match s:
    case M.State{_, _, es, _, _, _, _, _, _, _, _}:
      es

# a message the client named and the hub already stored: only a named one
# looks anything up
def Hub.dup(named: Bool, +s: M.State, +msg: String) -> Bool:
  match named:
    case True{}:
      Hub.has_msg(Hub.entries(s), msg)
    case False{}:
      False{}

# a thread works in its own worktree unless asked for the project folder
# ("local"): "auto" (the default) and "worktree" both ask the server for
# one, which falls back to the folder outside a repository
def Hub.env.of(+mode: String) -> M.EnvMode:
  Bool.pick(M.EnvMode, String.eq(mode, "local"), M.Local{}, M.Worktree{})

def Hub.env.outs(e: M.EnvMode, +th: String, +root: String, +mode: String) -> List<&2, Out>:
  match e:
    case M.Worktree{}:
      [Git{0, "", "worktree", th, root, mode, ""}]
    case M.Local{}:
      Nil{}

# a scratch thread (M.Scratch) works in a folder of its own that the
# server makes (<home>/scratch/<thread>, a git repository like a bot's
# home); any other thread as its project and mode say
def Hub.new.env(scratch: Bool, +mode: String) -> M.EnvMode:
  match scratch:
    case True{}:
      M.Local{}
    case False{}:
      Hub.env.of(mode)

# a scratch thread's folder, known from the start so its first turn runs
# there (the server makes it before anything else runs)
def Hub.new.wt(scratch: Bool, +root: String, +th: String) -> String:
  match scratch:
    case True{}:
      root ++ "/" ++ th
    case False{}:
      ""

def Hub.new.outs(scratch: Bool, +th: String, +root: String, +mode: String) -> List<&2, Out>:
  match scratch:
    case True{}:
      [BotFx{"scratch", th, "", ""}]
    case False{}:
      Hub.env.outs(Hub.env.of(mode), th, root, mode)

def Hub.thread_create(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  +project = J.Json.get_str(p, "project", "")
  +title = J.Json.get_str(p, "title", "New thread")
  +env = J.Json.get_str(p, "env", M.Setting.get(s, "thread.env", "auto"))
  +th = Hub.id("t", now, Hub.seq(s))
  Step{[M.ThreadCreated{th, project, title,
    Hub.new.env(M.Scratch.is(project), env), "", Hub.new.wt(M.Scratch.is(project), Hub.project.root(Hub.project(s, project)), th), J.Json.get_str(p, "provider", M.Setting.get(s, "agent.provider", "claude")),
    J.Json.get_str(p, "model", M.Setting.get(s, "agent.model", "")), now}],
    Reply.ok(client, id) <> Hub.new.outs(M.Scratch.is(project), th, Hub.project.root(Hub.project(s, project)), env)}

# the project's first thread, made as thread.create would, after it
def Hub.project_add.thread(+s: M.State, +now: Nat, +client: U32, +id: String, +pid: String, +made: M.Change) -> Step:
  Step.before([made], Nil{}, Hub.thread_create(s, now, client, id, J.Json.obj([J.KV{"project", J.Str{pid}}, J.KV{"title", J.Str{"New thread"}}])))

def Hub.root.norm.fin(+r: String) -> String:
  Bool.pick(String, String.is_empty(r), "/", r)

def Hub.root.slashes.k(slash: Bool, rest: Nat) -> Nat:
  match slash:
    case True{}:
      1n+rest
    case False{}:
      0n

def Hub.root.slashes(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Hub.root.slashes.k(U32.is_eq(c, 47), Hub.root.slashes(t))

def Hub.root.norm.go(+rev: String) -> String:
  Hub.root.norm.fin(String.reverse(String.drop(rev, Hub.root.slashes(rev))))

# a root without trailing slashes ("/" stays)
def Hub.root.norm(+r: String) -> String:
  Bool.pick(String, Bool.and(String.ends_with(r, "/"), Nat.is_gt(String.length(r), 1n)),
    Hub.root.norm.go(String.reverse(r)), r)

# whether a live project has this root (trailing slashes aside)
def Hub.has_root(ps: List<&2, M.Project>, +root: String) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case M.Project{_, _, r, _, rm} <> t:
      Bool.or(Bool.and(String.eq(Hub.root.norm(r), Hub.root.norm(root)), Bool.not(rm)), Hub.has_root(t, root))

# the id of a removed project with this root ("" when none): adding its
# folder again brings it back, threads and all
def Hub.removed_id(ps: List<&2, M.Project>, +root: String) -> String:
  match ps:
    case Nil{}:
      ""
    case M.Project{+i, _, r, _, rm} <> t:
      Bool.pick(String, Bool.and(rm, String.eq(Hub.root.norm(r), Hub.root.norm(root))), i, Hub.removed_id(t, root))

def Hub.projects(s: M.State) -> List<&2, M.Project>:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _, _, _}:
      Map.values(&2, M.Project, ps)

# a new project's id, or the removed one's it brings back
def Hub.project_id(+old: String, +s: M.State, +now: Nat) -> String:
  Bool.pick(String, String.is_empty(old), Hub.id("p", now, Hub.seq(s)), old)

# a project made afresh starts with a thread (the client that asked selects
# it); one brought back has its own
def Hub.project_add.new(old: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +pid: String, +made: M.Change) -> Step:
  match old:
    case True{}:
      Step.reply(client, id, [made])
    case False{}:
      Hub.project_add.thread(M.State.apply(s, made), now, client, id, pid, made)

def Hub.project_add.k(dup: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +root: String) -> Step:
  match dup:
    case True{}:
      Step.outs([Reply.err(client, id, "already a project: " ++ root)])
    case False{}:
      Hub.project_add.new(Bool.not(String.is_empty(Hub.removed_id(Hub.projects(s), root))), s, now, client, id, Hub.project_id(Hub.removed_id(Hub.projects(s), root), s, now),
        M.ProjectCreated{Hub.project_id(Hub.removed_id(Hub.projects(s), root), s, now), J.Json.get_str(p, "title", Hub.base(root)), Hub.root.norm(root), now})

# a folder becomes a project once (the same root twice is refused; a
# removed project's folder brings that project back). The
# server resolves project.add's path first (~, relative, symlinks; it must
# be a folder it can open) and sends it back here as project.create
def Hub.project_add.p(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +root: String) -> Step:
  Bool.pick(Step, String.is_empty(String.trim(root)), Step.outs([Reply.err(client, id, "no folder given")]),
    Hub.project_add.k(Hub.has_root(Hub.projects(s), root), s, now, client, id, p, root))

def Hub.project_add(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Hub.project_add.p(s, now, client, id, p, J.Json.get_str(p, "path", ""))

# change a thread's modes; what the request leaves out stays as it is
def Hub.modes(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, t: M.Thread) -> Step:
  match t:
    case M.Thread{+th, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, mo, rt, im, _, _}:
      Step.before([M.ModesSet{th, C.Runtime.of(J.Json.get_str(p, "runtime", C.Runtime.name(rt))),
        C.Interaction.of(J.Json.get_str(p, "interaction", C.Interaction.name(im))), J.Json.get_str(p, "model", mo), now}], [Reply.ok(client, id)], Step.none())

# Answering asks
# --------------

def Ask.find(as: List<&2, M.Ask>, +id: String) -> M.Ask:
  match as:
    case Nil{}:
      M.Ask.blank(id)
    case M.Ask{+i, th, k, t, d, o, op, an} <> rest:
      Bool.pick(M.Ask, String.eq(i, id), M.Ask{i, th, k, t, d, o, op, an}, Ask.find(rest, id))

def Hub.implement.k(t: M.Thread, +now: Nat) -> List<&2, M.Change>:
  match t:
    case M.Thread{+th, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, mo, rt, _, _, _}:
      [M.ModesSet{th, rt, M.DefaultMode{}, mo, now}]

# the state the implementing turn starts from: the plan is out of the way
def Hub.impl.state(+s: M.State, +th: String, +now: Nat) -> M.State:
  M.State.replay(Hub.implement.k(Hub.thread(s, th), now), s)

# Git: worktrees, checkpoints, diffs, stacked actions
# ---------------------------------------------------
# The hub decides; the server runs git (src/server/git.bend) and reports
# back: thread.worktree and thread.note come from the server itself.

# a commit made from a thread says what the thread was about
def Hub.thread_title(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, ti, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      ti

def Rename.changes(+th: String, +title: String, +now: Nat) -> List<&2, M.Change>:
  Bool.pick(List<&2, M.Change>, Bool.or(String.is_empty(title), String.is_empty(th)), Nil{}, [M.ThreadRenamed{th, title, now}])

def Hub.methods.git() -> List<&2, String>:
  ["git.diff", "git.revert", "git.act", "git.status", "thread.worktree", "thread.note", "term.open", "term.input", "term.resize", "term.snap", "term.restart"]

def Hub.git(+s: M.State, +client: U32, +id: String, +job: String, +thread: String, +a: String, +b: String) -> Step:
  Step.outs([Git{client, id, job, thread, Hub.cwd(s, Hub.thread(s, thread)), a, b}])

def Term.bytes(xs: List<&2, J.Json>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      U32.from_nat(Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(Some{x}, "0")), 0n)) <> Term.bytes(t)

# a thread's terminal: open (in the thread's directory), keys in, resize
def Hub.term(+s: M.State, +client: U32, +id: String, +op: String, +p: J.Json) -> Step:
  Step.outs([Reply.ok(client, id), TermOp{op, J.Json.get_str(p, "thread", ""), Hub.cwd(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))),
    Term.bytes(J.Json.elems(J.Json.get_obj(p, "b"))), J.Json.get_u32(p, "cols", 80), J.Json.get_u32(p, "rows", 24)}])

# a terminal in the chat starts again: live from now (core/emb.bend)
def Emb.restart.k(+sum: String, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +term: String) -> Step:
  Bool.pick(Step, String.is_empty(sum), Step.outs([Reply.err(client, id, "no such terminal")]),
    Step{[M.SettingSet{EM.Emb.at.key(EM.Emb.key(thread, term)), Nat.show(now), now}],
      [Reply.ok(client, id), TermRun{EM.Emb.key(thread, term), EM.Emb.title(sum), Hub.cwd(s, Hub.thread(s, thread)), EM.Emb.cmd(sum), EM.Emb.wide(sum), EM.Emb.tall(sum), True{}}]})

def Emb.restart(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +term: String) -> Step:
  Emb.restart.k(EM.Emb.sum(M.State.mine(s, thread), term), s, now, client, id, thread, term)

# Phones
# ------

# a push token or bundle id: letters, digits and . _ : - only (APNs tokens
# are hex, FCM tokens base64url with a colon), so neither can bend a URL
# or a header
def Device.char(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.or(Bool.or(U32.is_eq(c, 46), U32.is_eq(c, 95)), Bool.or(U32.is_eq(c, 58), U32.is_eq(c, 45)))))

def Device.chars(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(Device.char(c), Device.chars(t))

def Device.safe(+s: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(s)), Bool.and(Nat.is_le(String.length(s), 512n), Device.chars(s)))

def Device.one_of(+names: List<&2, String>, +s: String) -> Bool:
  Nat.is_lt(C.Codec.pos(names, s), List.length(&2, String, names))

def Device.ok(+p: J.Json) -> Bool:
  Bool.and(Bool.and(Device.safe(J.Json.get_str(p, "token", "")), Device.safe(J.Json.get_str(p, "bundle", ""))),
    Bool.and(Bool.and(Device.one_of(["ios", "android"], J.Json.get_str(p, "platform", "")), Device.one_of(["alert", "activity", "start"], J.Json.get_str(p, "kind", ""))),
      Device.one_of(["sandbox", "production"], J.Json.get_str(p, "env", "production"))))

def Device.register.k(ok: Bool, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  match ok:
    case True{}:
      Step.reply(client, id, [M.DeviceRegistered{J.Json.get_str(p, "token", ""), J.Json.get_str(p, "platform", ""), J.Json.get_str(p, "kind", ""),
        J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "env", "production"), J.Json.get_str(p, "bundle", ""), now}])
    case False{}:
      Step.outs([Reply.err(client, id, "bad device")])

# a phone registers a push token (never echoed: clients get the event
# without it)
def Device.register(+now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Device.register.k(Device.ok(p), now, client, id, p)

# Method groups (each appended to only by its own feature area)
# ------------------------------------------------------------

# folders for the project picker (listing, creating, creating as a
# project, finding projects on disk); the server answers. project.create
# is the server's own, with a path it has resolved
def Hub.methods.fs() -> List<&2, String>:
  ["fs.list", "fs.mkdir", "project.new", "project.create", "fs.find"]

# sidebar and navigation
def Hub.methods.nav() -> List<&2, String>:
  ["thread.snooze", "thread.reorder", "files.list", "kicad.open", "project.reorder", "mech.list", "mech.render", "file.open", "files.dir", "pdf.page"]

# snooze a thread: {thread, for: "1h" | "1w" | "tomorrow" | "off"} or
# {thread, until}. Tomorrow 9:00 is local time, which the server knows:
# it answers with the time (thread.snooze {thread, until})
def Hub.snooze.k(i: Nat, +now: Nat, +client: U32, +id: String, +th: String, +p: J.Json) -> Step:
  match i:
    case 0n:
      Step.reply(client, id, [M.ThreadSnoozed{th, Nat.add(now, M.Snooze.hour()), now}])
    case 1n:
      Step.reply(client, id, [M.ThreadSnoozed{th, Nat.add(now, M.Snooze.week()), now}])
    case 2n:
      Step.reply(client, id, [M.ThreadSnoozed{th, 0n, now}])
    case 3n:
      Step.outs([Git{client, id, "snooze", th, "", Nat.show(now), ""}])
    case _:
      Step.reply(client, id, [M.ThreadSnoozed{th, J.Json.get_nat(p, "until", 0n), now}])

def Hub.snooze(+now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Hub.snooze.k(C.Codec.pos(["1h", "1w", "off", "tomorrow"], J.Json.get_str(p, "for", "")), now, client, id, J.Json.get_str(p, "thread", ""), p)

def Reorder.okeys(xs: List<&2, J.Json>, +navs: Map<&2, M.Nav>, +section: String) -> List<&2, M.OKey>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Str{+i} <> t:
      M.OKey{i, M.Nav.key(M.Nav.get(navs, i), section)} <> Reorder.okeys(t, navs, section)
    case _ <> t:
      Reorder.okeys(t, navs, section)

def Reorder.changes(ks: List<&2, M.OKey>, +section: String, +now: Nat) -> List<&2, M.Change>:
  match ks:
    case Nil{}:
      Nil{}
    case M.OKey{i, k} <> t:
      M.ThreadOrdered{i, section, k, now} <> Reorder.changes(t, section, now)

def Hub.reorder.k(ok: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +section: String, +p: J.Json) -> Step:
  match ok:
    case True{}:
      Step.reply(client, id, Reorder.changes(M.Order.plan(Reorder.okeys(J.Json.elems(J.Json.get_obj(p, "ids")), M.State.navs(s), section), J.Json.get_str(p, "thread", "")), section, now))
    case False{}:
      Step.outs([Reply.err(client, id, "only pinned and active threads reorder")])

# a shelf's new order after a drag: {section: "pinned" | "active", thread:
# the one moved, ids: the shelf's threads in their new order}
def Hub.reorder(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Hub.reorder.k(Bool.or(String.eq(J.Json.get_str(p, "section", ""), "pinned"), String.eq(J.Json.get_str(p, "section", ""), "active")), s, now, client, id, J.Json.get_str(p, "section", ""), p)

def Reorder.pkeys(xs: List<&2, J.Json>, +navs: Map<&2, M.Nav>) -> List<&2, M.OKey>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Str{+i} <> t:
      M.OKey{i, M.Nav.project_key(navs, i)} <> Reorder.pkeys(t, navs)
    case _ <> t:
      Reorder.pkeys(t, navs)

def Reorder.projects(ks: List<&2, M.OKey>, +now: Nat) -> List<&2, M.Change>:
  match ks:
    case Nil{}:
      Nil{}
    case M.OKey{i, k} <> t:
      M.ProjectOrdered{i, k, now} <> Reorder.projects(t, now)

# the sidebar's projects in their new order after a drag: {project: the one
# moved, ids: every project in the new order}
def Hub.reorder_projects(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Step.reply(client, id, Reorder.projects(M.Order.plan(Reorder.pkeys(J.Json.elems(J.Json.get_obj(p, "ids")), M.State.navs(s)), J.Json.get_str(p, "project", "")), now))

# Summaries (refs.bend's Sum.*): the text generation model writes one
# when a thread's turn ends and one is due; the time it was asked for is
# kept (summary.at.<id>) so a failed answer is not asked for again at once.
# A thread's summary makes its project's when that is due too.

def Sum.at(due: Bool, +id: String, +now: Nat) -> List<&2, M.Change>:
  match due:
    case True{}:
      [M.SettingSet{RF.Sum.at.key(id), Nat.show(now), now}]
    case False{}:
      Nil{}

def Sum.input(+kind: String, +s: M.State, +id: String) -> String:
  Bool.pick(String, String.eq(kind, "project"), RF.Sum.project.input(s, id), RF.Sum.thread.input(s, id))

def Sum.out(due: Bool, +s: M.State, +id: String, +kind: String) -> List<&2, Out>:
  match due:
    case True{}:
      [Git{0, "", "summary", id, "", kind, Sum.input(kind, s, id)}]
    case False{}:
      Nil{}

def Sum.keep(+id: String, +text: String, +now: Nat) -> List<&2, M.Change>:
  Bool.pick(List<&2, M.Change>, String.is_empty(text), Nil{}, [M.SettingSet{RF.Sum.key(id), text, now}])

# a thread's project summarized next, when it has one and it is due
def Sum.next(thread: Bool, +s: M.State, +now: Nat, +pid: String) -> Step:
  match thread:
    case True{}:
      Step{Sum.at(RF.Sum.due(s, pid, now), pid, now), Sum.out(RF.Sum.due(s, pid, now), s, pid, "project")}
    case False{}:
      Step{Nil{}, Nil{}}

# the writer's summary of a thread or project ({id, kind, text})
def Sum.got(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Step.before(Sum.keep(J.Json.get_str(p, "id", ""), RF.Sum.clean(J.Json.get_str(p, "text", "")), now), [Reply.ok(client, id)],
    Sum.next(Bool.and(String.eq(J.Json.get_str(p, "kind", ""), "thread"), Bool.not(String.is_empty(RF.Refs.t.project(RF.Sum.thread.of(s, J.Json.get_str(p, "id", "")))))),
      s, now, RF.Refs.t.project(RF.Sum.thread.of(s, J.Json.get_str(p, "id", "")))))

# agent features (skills, effort, naming)
def Hub.methods.agent() -> List<&2, String>:
  ["thread.branch", "skills.list", "thread.effort", "thread.local", "thread.merged", "thread.unrooted", "thread.titled", "thread.btw", "summary.set"]

# a side question (/btw {thread, q}): the writing model answers it off
# the hub (Git job "btw": a is the question, b what it reads), only to the
# client that asked. Nothing is logged: the thread never holds it (law
# btw_never_logged)
def Hub.btw(+s: M.State, +client: U32, +id: String, +th: String, +q: String) -> Step:
  Step.outs([Git{client, id, "btw", th, "", q, HD.Hand.btw(Hub.entries(s), th, HD.Hand.title(Hub.thread(s, th)), q)}])

def Hub.provider_of(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, p, _, _, _, _, _}:
      p

def Hub.worktree(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, wt, _, _, _, _, _, _}:
      wt

# a thread's reasoning effort: kept in the settings map (effort.<thread>),
# only as a level its provider offers ("" is the provider's default)
def Hub.effort(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +e: String) -> Step:
  Step.reply(client, id, [M.SettingSet{AG.Effort.key(thread), AG.Effort.of(Hub.provider_of(Hub.thread(s, thread)), e), now}])

# a worktree thread's first message names its branch: the server asks a
# small model for a name while the turn runs, renames the temporary
# backplane/<hex> branch and reports it (thread.branch)
def Name.out.k(go: Bool, +thread: String, +wt: String, +branch: String, +text: String) -> List<&2, Out>:
  match go:
    case True{}:
      [Git{0, "", "name", thread, wt, branch, text}]
    case False{}:
      Nil{}

def Name.out(t: M.Thread, +text: String) -> List<&2, Out>:
  match t:
    case M.Thread{+id, _, +title, _, _, _, _, _, _, _, _, _, _, +br, +wt, _, _, _, _, _, _}:
      Name.out.k(Bool.and(Bool.and(String.eq(title, "New thread"), AG.Name.temp(br)), Bool.not(String.is_empty(wt))), id, wt, br, text)

# a worktree thread's first turn, run once its worktree exists
def Name.first(t: M.Thread, +text: String) -> List<&2, Out>:
  match t:
    case M.Thread{+id, _, _, _, _, _, _, _, _, _, _, _, _, +br, +wt, _, _, _, _, _, _}:
      Name.out.k(Bool.and(AG.Name.temp(br), Bool.not(String.is_empty(wt))), id, wt, br, text)

# A thread's first message titles it at once with its first line (the
# placeholder); the server asks the text generation model for a better
# title (Git job "title": a is the placeholder, b the message) and answers
# with thread.titled {thread, placeholder, title}
def Title.out(fresh: Bool, +thread: String, +text: String) -> List<&2, Out>:
  match fresh:
    case True{}:
      Bool.pick(List<&2, Out>, String.is_empty(Hub.title.of(text)), Nil{}, [Git{0, "", "title", thread, "", Hub.title.of(text), String.take(text, 4000n)}])
    case False{}:
      Nil{}

def Title.changes.ok(ok: Bool, +thread: String, +title: String, +now: Nat) -> List<&2, M.Change>:
  match ok:
    case True{}:
      [M.ThreadRenamed{thread, title, now}]
    case False{}:
      Nil{}

def Title.changes.k(same: Bool, ok: Bool, +thread: String, +title: String, +now: Nat) -> List<&2, M.Change>:
  match same:
    case True{}:
      Title.changes.ok(ok, thread, title, now)
    case False{}:
      Nil{}

# the writer's title replaces the placeholder only while the thread still
# has it (a rename by the user wins) and only when there is an answer
def Title.changes(+current: String, +placeholder: String, +answer: String, +thread: String, +now: Nat) -> List<&2, M.Change>:
  Title.changes.k(Bool.and(String.eq(current, placeholder), Bool.not(String.is_empty(placeholder))), Bool.not(String.is_empty(AG.Title.clean(answer))), thread, AG.Title.clean(answer), now)

def Title.got(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +p: J.Json) -> Step:
  Step.reply(client, id, Title.changes(Hub.thread_title(Hub.thread(s, thread)), J.Json.get_str(p, "placeholder", ""), J.Json.get_str(p, "title", ""), thread, now))

# Commit & push and Open PR without a message: the server writes one from
# the thread's diff (the thread's title when it cannot)
def Hub.act(+s: M.State, +client: U32, +id: String, +thread: String, +action: String, +p: J.Json) -> Step:
  Bool.pick(Step, Bool.and(String.contains(action, "commit"), String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(p, "message"), J.Null{})), "null")),
    Hub.git(s, client, id, "act_gen", thread, action, Hub.thread_title(Hub.thread(s, thread))),
    Hub.git(s, client, id, "act", thread, action, J.Json.get_str(p, "message", Hub.thread_title(Hub.thread(s, thread)))))

# A thread's worktree is ready (thread.worktree) or cannot be made
# (thread.local): what waited for it runs now, in the thread's directory.
# The first message of a worktree thread names its branch here, since the
# worktree did not exist when it was sent.
def Wt.name(first: Bool, t: M.Thread, +text: String) -> List<&2, Out>:
  match first:
    case True{}:
      Name.first(t, text)
    case False{}:
      Nil{}

def Wt.start.k(go: Bool, +first: Bool, +t: M.Thread, +cwd: String, +queued: String, +now: Nat, +thread: String) -> Step:
  match go:
    case True{}:
      Step{[M.QueueTaken{thread, now}, M.TurnChanged{thread, M.Running{}, now}],
        Git{0, "", "checkpoint0", thread, cwd, "", ""} <> Git{0, "", "step", thread, cwd, "", ""} <> List.append(&2, Out, Wt.name(first, t, queued), Hub.run(t, cwd, queued))}
    case False{}:
      Step.none()

# gh saw the thread's branch merged: it settles, once (a recorded merge is
# not due again)
def Merge.found(due: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +url: String) -> Step:
  match due:
    case True{}:
      Step.reply(client, id, [M.ThreadMerged{thread, url, now},
        M.ActivityLogged{thread, Hub.id("g", now, Hub.seq(s)), "info", "git", "merged" ++ Bool.pick(String, String.is_empty(url), "", ": " ++ url), now}])
    case False{}:
      Step.outs([Reply.ok(client, id)])

# attachments, files and the web client's panes
def Hub.methods.media() -> List<&2, String>:
  ["attach.put", "attach.file", "update.check", "history.refs"]

# one piece of an upload: "<index>|<1 when last>|<stored name>"
def Attach.piece(+p: J.Json) -> String:
  Nat.show(J.Json.get_nat(p, "i", 0n)) ++ "|" ++ Bool.pick(String, J.Json.get_bool(p, "last", True{}), "1", "0") ++ "|" ++
    AT.Att.stored(J.Json.get_str(p, "key", "u"), J.Json.get_str(p, "name", "file"))

# uploads are stored per thread; a thread must be named
def Attach.go(ok: Bool, +client: U32, +id: String, o: Out) -> Step:
  match ok:
    case True{}:
      Step.outs([o])
    case False{}:
      Step.outs([Reply.err(client, id, "no thread to attach to")])

# attach.put: a piece of an uploaded file (base64); attach.file: a file on
# this machine, copied in; update.check: look for a release now
# desk.look {thread, focused}: no reply (a desk says it often)
def Desk.request(look: Bool, +client: U32, +id: String, +p: J.Json) -> Step:
  match look:
    case True{}:
      Step.outs([DeskLook{client, J.Json.get_str(p, "thread", ""), J.Json.get_bool(p, "focused", False{})}])
    case False{}:
      Step.outs([Reply.err(client, id, "unknown method")])

def Hub.media(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Attach.go(Bool.not(String.is_empty(J.Json.get_str(p, "thread", ""))), client, id,
        Git{client, id, "attach.put", J.Json.get_str(p, "thread", ""), "", Attach.piece(p), J.Json.get_str(p, "data", "")})
    case 1n:
      Attach.go(Bool.not(String.is_empty(J.Json.get_str(p, "thread", ""))), client, id,
        Git{client, id, "attach.file", J.Json.get_str(p, "thread", ""), "", AT.Att.from_uri(J.Json.get_str(p, "path", "")),
          AT.Att.stored(Hub.id("a", now, Hub.seq(s)), AT.Att.base(AT.Att.from_uri(J.Json.get_str(p, "path", ""))))})
    case 2n:
      Step.outs([Git{client, id, "update.check", "", "", M.Setting.get(s, "update.channel", "stable"), ""}])
    case 3n:
      Hub.git(s, client, id, "refs", J.Json.get_str(p, "thread", ""), "", "")
    case _:
      Desk.request(String.eq(m, "desk.look"), client, id, p)

def Hub.methods() -> List<&2, String>:
  ["project.add", "project.remove", "thread.create", "turn.start", "turn.interrupt",
   "thread.settle", "thread.unsettle", "thread.archive", "thread.unarchive",
   "thread.pin", "thread.unpin", "thread.rename", "thread.delete", "kicad.watch", "thread.modes", "app.update", "setting.set", "kicad.install",
   "ask.answer", "device.register", "device.drop", "kicad.info", "queue.resume",
   "queue.edit", "queue.remove", "queue.move", "queue.steer", "thread.fork", "thread.back", "thread.provider"]

# Agent output (Claude stream-json)
# ---------------------------------

def Delta.push(thread: String, text: String) -> Out:
  Broadcast{J.Json.show(J.Json.obj([J.KV{"t", J.Str{"delta"}}, J.KV{"thread", J.Str{thread}}, J.KV{"text", J.Str{text}}]))}

# Claude streams a token a line, and each was a frame to every client: a
# phone rebuilt its screen per token. The lines of one read of the agent's
# stdout (as much as has come, up to 64 KB) go to the hub together, and a
# run of the main agent's text deltas to one block among them becomes one
# delta with their text: an agent writing fast sends a few frames a read,
# one writing slowly still sends each token as it comes. Every other line
# stays as it is, in its place (test/delta_test.bend).

# the merge so far: the lines out (last first), and the run open (its
# block's key and its texts, last first)
type DL is Data:
  DL{out: List<&2, String>, key: String, texts: List<&2, String>, open: Bool}

# a run's text as the one line that stands for it
def Delta.line(+ts: List<&2, String>) -> String:
  J.Json.show(J.Json.obj([J.KV{"type", J.Str{"stream_event"}}, J.KV{"event", J.Json.obj([J.KV{"type", J.Str{"content_block_delta"}},
    J.KV{"delta", J.Json.obj([J.KV{"type", J.Str{"text_delta"}}, J.KV{"text", J.Str{String.join(List.reverse(&2, String, ts), "")}}])}])}]))

def Delta.flush(open: Bool, +ts: List<&2, String>, out: List<&2, String>) -> List<&2, String>:
  match open:
    case True{}:
      Delta.line(ts) <> out
    case False{}:
      out

def Delta.step.k(delta: Bool, same: Bool, +key: String, text: String, line: String, st: DL) -> DL:
  match delta same st:
    case True{} True{} DL{out, k, ts, o}:
      DL{out, k, text <> ts, o}
    case True{} False{} DL{out, _, +ts, o}:
      DL{Delta.flush(o, ts, out), key, [text], True{}}
    case False{} _ DL{out, _, +ts, o}:
      DL{line <> Delta.flush(o, ts, out), "", Nil{}, False{}}

def DL.open(st: DL) -> Bool:
  match st:
    case DL{_, _, _, o}:
      o

def DL.key(st: DL) -> String:
  match st:
    case DL{_, k, _, _}:
      k

# a text delta of the main agent (not a subagent's), and its block
def Delta.step.j(+o: J.Json, line: String, +st: DL) -> DL:
  +ev = J.Json.get_obj(o, "event")
  +d = J.Json.get_obj(ev, "delta")
  +key = J.Json.show(J.Json.get_obj(ev, "index"))
  Delta.step.k(Bool.and(Bool.and(String.eq(J.Json.get_str(o, "type", ""), "stream_event"), String.is_empty(J.Json.get_str(o, "parent_tool_use_id", ""))),
      Bool.and(String.eq(J.Json.get_str(ev, "type", ""), "content_block_delta"), String.eq(J.Json.get_str(d, "type", ""), "text_delta"))),
    Bool.and(DL.open(st), String.eq(key, DL.key(st))), key, J.Json.get_str(d, "text", ""), line, st)

def Delta.step.m(m: Maybe<&2, J.Json>, line: String, +st: DL) -> DL:
  match m:
    case Some{+o}:
      Delta.step.j(o, line, st)
    case None{}:
      Delta.step.k(False{}, False{}, "", "", line, st)

def Delta.step.p(stream: Bool, +line: String, +st: DL) -> DL:
  match stream:
    case True{}:
      Delta.step.m(J.Json.parse(line), line, st)
    case False{}:
      Delta.step.k(False{}, False{}, "", "", line, st)

# (only a stream event is parsed: the other lines, a tool's whole output
# among them, pass as they are)
def Delta.step(+line: String, +st: DL) -> DL:
  Delta.step.p(String.starts_with(line, "{\"type\":\"stream_event\""), line, st)

def Delta.go(ls: List<&2, String>, st: DL) -> DL:
  match ls:
    case Nil{}:
      st
    case l <> t:
      Delta.go(t, Delta.step(l, st))

def Delta.fin(st: DL) -> List<&2, String>:
  match st:
    case DL{out, _, +ts, o}:
      List.reverse(&2, String, Delta.flush(o, ts, out))

# one read's lines with each run of text deltas as one
def Delta.merge(ls: List<&2, String>) -> List<&2, String>:
  Delta.fin(Delta.go(ls, DL{Nil{}, "", Nil{}, False{}}))

def Delta.last(ls: List<&2, String>, acc: Bool) -> Bool:
  match ls:
    case Nil{}:
      acc
    case l <> t:
      Delta.last(t, String.starts_with(l, "{\"type\":\"stream_event\""))

# whether a read ended in streamed text: the reader then waits Delta.pace()
# ms before reading again, so the tokens written meanwhile come in one read
# and go out as one delta (an agent streams tens of tokens a second, each a
# frame to every client, and a screen for a phone showing the thread);
# anything else is read at once
def Delta.streaming(ls: List<&2, String>) -> Bool:
  Delta.last(ls, False{})

def Delta.pace() -> U32:
  60

def Claude.stream.k(block: Bool, text: Bool, +thread: String, s: String) -> Step:
  match block text:
    case True{} True{}:
      Step.outs([Delta.push(thread, s)])
    case _ _:
      Step.none()

def Claude.stream(+thread: String, +ev: J.Json) -> Step:
  +d = J.Json.get_obj(ev, "delta")
  Claude.stream.k(String.eq(J.Json.get_str(ev, "type", ""), "content_block_delta"),
    String.eq(J.Json.get_str(d, "type", ""), "text_delta"), thread, J.Json.get_str(d, "text", ""))

# a short line describing a tool call, from its input
def Claude.tool_summary(+name: String, +input: J.Json) -> String:
  +cmd = J.Json.get_str(input, "command", "")
  +path = J.Json.get_str(input, "file_path", J.Json.get_str(input, "path", ""))
  +pat = J.Json.get_str(input, "pattern", "")
  Bool.pick(String, Bool.not(String.is_empty(cmd)), cmd,
    Bool.pick(String, Bool.not(String.is_empty(path)), path,
      Bool.pick(String, Bool.not(String.is_empty(pat)), pat, J.Json.get_str(input, "description", name))))

def Claude.block.k(i: Nat, +thread: String, +msg: String, +n: Nat, +now: Nat, +seq: Nat, +b: J.Json) -> List<&2, M.Change>:
  match i:
    case 0n:
      [M.MessagePosted{thread, msg ++ ":" ++ Nat.show(n), M.Assistant{}, J.Json.get_str(b, "text", ""), now}]
    case 1n:
      [M.ActivityLogged{thread, J.Json.get_str(b, "id", Hub.id("a", now, seq)), "tool", J.Json.get_str(b, "name", "tool"),
        Claude.tool_summary(J.Json.get_str(b, "name", "tool"), J.Json.get_obj(b, "input")), now}]
    case _:
      Nil{}

def Claude.blocks(bs: List<&2, J.Json>, +thread: String, +msg: String, +n: Nat, +now: Nat, +seq: Nat) -> List<&2, M.Change>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      List.append(&2, M.Change,
        Claude.block.k(C.Codec.pos(["text", "tool_use"], J.Json.get_str(b, "type", "")), thread, msg, n, now, seq, b),
        Claude.blocks(t, thread, msg, 1n+n, now, seq))

def Claude.assistant(+thread: String, +now: Nat, +seq: Nat, +m: J.Json) -> Step:
  Step{Claude.blocks(J.Json.elems(J.Json.get_obj(m, "content")), thread, J.Json.get_str(m, "id", "msg"), 0n, now, seq),
    [Broadcast{J.Json.show(J.Json.obj([J.KV{"t", J.Str{"delta_end"}}, J.KV{"thread", J.Str{thread}}]))}]}

def Claude.result.k(err: Bool, +thread: String, +now: Nat, text: String) -> Step:
  match err:
    case True{}:
      Step{[M.ActivityLogged{thread, Hub.id("e", now, 0n), "error", "result", text, now}, M.TurnChanged{thread, M.Failed{}, now}], Nil{}}
    case False{}:
      Step{[M.TurnChanged{thread, M.Completed{}, now}], Nil{}}

def Claude.result(+thread: String, +now: Nat, +o: J.Json) -> Step:
  Claude.result.k(J.Json.get_bool(o, "is_error", False{}), thread, now, J.Json.get_str(o, "result", ""))

# Claude keeps its process across a Stop, and what it still says for the
# stopped turn (its partial text, its result) changes nothing: only a
# running turn completes or fails, and only a running turn's text streams
# (laws claude_result_after_stop_quiet, claude_delta_after_stop_quiet). Its
# whole messages, tool results and background tasks still land. (A result
# for the old turn that comes after a new one started is still taken: the
# lines carry no turn of their own.)
def Claude.stream.if(run: Bool, +thread: String, +ev: J.Json) -> Step:
  match run:
    case True{}:
      Claude.stream(thread, ev)
    case False{}:
      Step.none()

def Claude.result.if(run: Bool, +thread: String, +now: Nat, +o: J.Json) -> Step:
  match run:
    case True{}:
      Claude.result(thread, now, o)
    case False{}:
      Step.none()

# Claude's todo tools
# -------------------
# TodoWrite sets the whole list; TaskCreate adds a step and TaskUpdate
# changes one, so the hub folds them over the thread's list, and a
# TaskCreate's result (a "user" line) names the step it made.

def Claude.todo.k(i: Nat, +b: J.Json, ts: List<&2, TD.Todo>) -> List<&2, TD.Todo>:
  match i:
    case 0n:
      TD.Todo.write(J.Json.get_obj(b, "input"))
    case 1n:
      TD.Todo.create(ts, J.Json.get_str(b, "id", ""), J.Json.get_obj(b, "input"))
    case 2n:
      TD.Todo.update(ts, J.Json.get_obj(b, "input"))
    case _:
      ts

def Claude.todo.kind(+b: J.Json) -> Nat:
  Bool.pick(Nat, String.eq(J.Json.get_str(b, "type", ""), "tool_use"), C.Codec.pos(["TodoWrite", "TaskCreate", "TaskUpdate"], J.Json.get_str(b, "name", "")), 3n)

def Claude.todo.go(bs: List<&2, J.Json>, ts: List<&2, TD.Todo>) -> List<&2, TD.Todo>:
  match bs:
    case Nil{}:
      ts
    case +b <> t:
      Claude.todo.go(t, Claude.todo.k(Claude.todo.kind(b), b, ts))

def Claude.todo.any(bs: List<&2, J.Json>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case +b <> t:
      Bool.or(Nat.is_lt(Claude.todo.kind(b), 3n), Claude.todo.any(t))

def Claude.todos.of(+s: M.State, +th: String) -> List<&2, TD.Todo>:
  TD.Todo.read(M.Setting.get(s, "todos." ++ th, ""))

def Claude.todos.set(changed: Bool, +th: String, +now: Nat, +ts: String) -> List<&2, M.Change>:
  match changed:
    case True{}:
      [M.TodosSet{th, ts, now}]
    case False{}:
      Nil{}

# an assistant message's todo tools, folded over the thread's list
def Claude.todos(+s: M.State, +th: String, +now: Nat, +bs: List<&2, J.Json>) -> List<&2, M.Change>:
  Claude.todos.set(Claude.todo.any(bs), th, now, TD.Todo.show(Claude.todo.go(bs, Claude.todos.of(s, th))))

# Context usage (Claude)
# ----------------------
# Each model call reports its usage: what it read (input and both caches)
# plus what it wrote is what the session now holds. The result line names
# the model's window; a compaction says what is left. A reading goes to the
# log only when it changes (law usage_same_nothing).

def Usage.now(+s: M.State, +th: String) -> String:
  M.Setting.get(s, M.Usage.key(th), "")

def Usage.set(fresh: Bool, +th: String, +used: Nat, +window: Nat, +now: Nat) -> List<&2, M.Change>:
  match fresh:
    case True{}:
      [M.UsageSet{th, used, window, now}]
    case False{}:
      Nil{}

def Usage.sum(+u: J.Json) -> Nat:
  Nat.add(Nat.add(J.Json.get_nat(u, "input_tokens", 0n), J.Json.get_nat(u, "cache_creation_input_tokens", 0n)),
    Nat.add(J.Json.get_nat(u, "cache_read_input_tokens", 0n), J.Json.get_nat(u, "output_tokens", 0n)))

def Usage.used.k(+s: M.State, +th: String, +now: Nat, +n: Nat) -> List<&2, M.Change>:
  Usage.set(Bool.and(Nat.is_gt(n, 0n), Bool.not(Nat.is_eq(n, M.Usage.used(Usage.now(s, th))))), th, n, 0n, now)

# an assistant message's usage
def Usage.claude(+s: M.State, +th: String, +now: Nat, +m: J.Json) -> List<&2, M.Change>:
  Usage.used.k(s, th, now, Usage.sum(J.Json.get_obj(m, "usage")))

def Usage.widest(fs: J.Json, +acc: Nat) -> Nat:
  match fs:
    case J.Field{_, +v, t}:
      Usage.widest(t, Bool.pick(Nat, Nat.is_gt(J.Json.get_nat(v, "contextWindow", 0n), acc), J.Json.get_nat(v, "contextWindow", 0n), acc))
    case _:
      acc

def Usage.fields(o: J.Json) -> J.Json:
  match o:
    case J.Obj{fs}:
      fs
    case _:
      J.Null{}

def Usage.window.k(+s: M.State, +th: String, +now: Nat, +w: Nat) -> List<&2, M.Change>:
  Usage.set(Bool.and(Nat.is_gt(w, 0n), Bool.not(Nat.is_eq(w, M.Usage.window(Usage.now(s, th))))), th, 0n, w, now)

# the result's window: the widest model it used (the main one; helpers
# such as a small model have smaller windows)
def Usage.window(+s: M.State, +th: String, +now: Nat, +o: J.Json) -> List<&2, M.Change>:
  Usage.window.k(s, th, now, Usage.widest(Usage.fields(J.Json.get_obj(o, "modelUsage")), 0n))

# a compaction: what the session holds after it
def Usage.compact(+s: M.State, +th: String, +now: Nat, +o: J.Json) -> List<&2, M.Change>:
  Bool.pick(List<&2, M.Change>, String.eq(J.Json.get_str(o, "subtype", ""), "compact_boundary"),
    Usage.used.k(s, th, now, J.Json.get_nat(J.Json.get_obj(o, "compact_metadata"), "post_tokens", 0n)), Nil{})

# an assistant message and what its todo tools do to the thread's list
def Claude.assistant.t(+s: M.State, +thread: String, +now: Nat, +m: J.Json) -> Step:
  Step.after(Step.after(Claude.assistant(thread, now, Hub.seq(s), m), Claude.todos(s, thread, now, J.Json.elems(J.Json.get_obj(m, "content")))), Usage.claude(s, thread, now, m))

def Claude.result.text(+c: J.Json) -> String:
  J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.elems(c)), J.Null{}), "text", J.Json.as_str(Some{c}, ""))

def Claude.named.go(bs: List<&2, J.Json>, ts: List<&2, TD.Todo>) -> List<&2, TD.Todo>:
  match bs:
    case Nil{}:
      ts
    case +b <> t:
      Claude.named.go(t, TD.Todo.named(ts, J.Json.get_str(b, "tool_use_id", ""), TD.Todo.result(Claude.result.text(J.Json.get_obj(b, "content")))))

# a "user" line carries tool results: a TaskCreate's names its step
def Claude.named(+s: M.State, +th: String, +now: Nat, +o: J.Json) -> Step:
  +before = TD.Todo.show(Claude.todos.of(s, th))
  +after = TD.Todo.show(Claude.named.go(J.Json.elems(J.Json.get_obj(J.Json.get_obj(o, "message"), "content")), Claude.todos.of(s, th)))
  Step{Claude.todos.set(Bool.not(String.eq(before, after)), th, now, after), Nil{}}

def Claude.init.same(t: M.Thread, +sid: String) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, session, _}:
      String.eq(session, sid)

def Claude.init.k(same: Bool, thread: String, sid: String, +now: Nat) -> Step:
  match same:
    case True{}:
      Step.none()
    case False{}:
      Step{[M.SessionSet{thread, sid, now}], Nil{}}

# the session id arrives in the init line; record it once
def Claude.init(+s: M.State, +thread: String, +now: Nat, +o: J.Json) -> Step:
  +sid = J.Json.get_str(o, "session_id", "")
  Claude.init.k(Claude.init.same(Hub.thread(s, thread), sid), thread, sid, now)

# Claude's subagents (model.bend's Bg): a local agent started, what it
# does now, and its end; the list is written only when it changes
def Bg.put.k(same: Bool, +th: String, +now: Nat, +after: String) -> List<&2, M.Change>:
  match same:
    case True{}:
      Nil{}
    case False{}:
      [M.SettingSet{M.Bg.key(th), after, now}]

def Bg.put(+s: M.State, +th: String, +now: Nat, ls: List<&2, String>) -> List<&2, M.Change>:
  +after = M.Bg.show(ls)
  Bg.put.k(String.eq(M.Setting.get(s, M.Bg.key(th), ""), after), th, now, after)

# a mark in a subagent's log (model.bend's Bg.log): it started, or ended
# with a status; none for one no tool call started
def Bg.mark.k(none: Bool, +th: String, +now: Nat, +call: String, +kind: String, +text: String) -> List<&2, M.Change>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [M.ActivityLogged{M.Bg.log(th), call ++ "/" ++ kind, call, kind, text, now}]

def Bg.mark(+th: String, +now: Nat, +call: String, +kind: String, +text: String) -> List<&2, M.Change>:
  Bg.mark.k(String.is_empty(call), th, now, call, kind, text)

def Bg.started(agent: Bool, +s: M.State, +th: String, +now: Nat, +o: J.Json) -> List<&2, M.Change>:
  match agent:
    case True{}:
      +call = J.Json.get_str(o, "tool_use_id", "")
      +what = J.Json.get_str(o, "description", "Subagent")
      +kind = M.Bg.kind(J.Json.get_str(o, "task_type", ""))
      List.append(&2, M.Change, Bg.put(s, th, now, M.Bg.start(M.Bg.of(s, th), J.Json.get_str(o, "task_id", ""), what, call, what, kind)),
        Bg.mark(th, now, call, "start:" ++ kind, what))
    case False{}:
      Nil{}

# a foreground shell Claude moved to the background when it ran past its
# timeout (task_updated sets is_backgrounded; the patch has no description)
def Bg.moved(bg: Bool, +s: M.State, +th: String, +now: Nat, +id: String) -> List<&2, M.Change>:
  match bg:
    case True{}:
      Bg.put(s, th, now, M.Bg.start(M.Bg.of(s, th), id, "Background shell", "", "Background shell", "shell"))
    case False{}:
      Nil{}

def Bg.ended(done: Bool, bg: Bool, +s: M.State, +th: String, +now: Nat, +id: String) -> List<&2, M.Change>:
  match done:
    case True{}:
      Bg.put(s, th, now, M.Bg.drop(M.Bg.of(s, th), id))
    case False{}:
      Bg.moved(bg, s, th, now, id)

# a task the agent left running: a subagent, a background shell or
# monitor, a workflow; not one a subagent runs for itself, and not a
# foreground shell (listed only if Claude moves it to the background,
# Bg.moved)
def Bg.listed(+o: J.Json) -> Bool:
  Bool.and(Nat.is_lt(C.Codec.pos(["local_agent", "local_bash", "local_workflow", "remote_agent", "monitor_mcp", "monitor_ws", "in_process_teammate"], J.Json.get_str(o, "task_type", "")), 7n),
    Bool.and(Bool.not(J.Json.get_bool(o, "owned_by_subagent", False{})), J.Json.get_bool(o, "is_backgrounded", True{})))

def Bg.system.k(i: Nat, +s: M.State, +th: String, +now: Nat, +o: J.Json) -> List<&2, M.Change>:
  match i:
    case 0n:
      Bg.started(Bg.listed(o), s, th, now, o)
    case 1n:
      Bg.put(s, th, now, M.Bg.set(M.Bg.of(s, th), J.Json.get_str(o, "task_id", ""), J.Json.get_str(o, "description", "")))
    case 2n:
      List.append(&2, M.Change, Bg.put(s, th, now, M.Bg.drop(M.Bg.of(s, th), J.Json.get_str(o, "task_id", ""))),
        Bg.mark(th, now, J.Json.get_str(o, "tool_use_id", ""), "end", J.Json.get_str(o, "status", "completed")))
    case 3n:
      Bg.ended(Nat.is_lt(C.Codec.pos(["completed", "failed", "killed", "stopped", "cancelled"], J.Json.get_str(J.Json.get_obj(o, "patch"), "status", "")), 5n),
        J.Json.get_bool(J.Json.get_obj(o, "patch"), "is_backgrounded", False{}), s, th, now, J.Json.get_str(o, "task_id", ""))
    case _:
      Nil{}

def Bg.system(+s: M.State, +th: String, +now: Nat, +o: J.Json) -> List<&2, M.Change>:
  Bg.system.k(C.Codec.pos(["task_started", "task_progress", "task_notification", "task_updated"], J.Json.get_str(o, "subtype", "")), s, th, now, o)

# none left at work (the agent's process ended)
def Bg.clear(+s: M.State, +th: String, +now: Nat) -> List<&2, M.Change>:
  Bg.put(s, th, now, Nil{})

# Design steps
# ------------
# After a tool call the server snapshots the thread's KiCad files (job
# "step", its `a` the entry the step follows; core/hist.bend). Claude's
# tool calls end with a "user" line of tool results; Codex's and Grok's
# are logged when they have run.

def Steps.out(+thread: String, +cwd: String, +entry: String) -> Out:
  Git{0, "", "step", thread, cwd, entry, ""}

def Step.also(st: Step, os: List<&2, Out>) -> Step:
  match st:
    case Step{cs, o}:
      Step{cs, List.append(&2, Out, o, os)}

def Steps.hit(bs: List<&2, J.Json>) -> Bool:
  match bs:
    case +b <> _:
      String.eq(J.Json.get_str(b, "type", ""), "tool_result")
    case Nil{}:
      False{}

# the first tool result's call
def Steps.first(bs: List<&2, J.Json>, hit: Bool) -> String:
  match bs hit:
    case Nil{} _:
      ""
    case +b <> +r True{}:
      J.Json.get_str(b, "tool_use_id", "")
    case +b <> t False{}:
      Steps.first(t, Steps.hit(t))

def Steps.claude.k(+id: String, +thread: String, +cwd: String) -> List<&2, Out>:
  Bool.pick(List<&2, Out>, String.is_empty(id), Nil{}, [Steps.out(thread, cwd, id)])

# a line of tool results: a step after the first of them
def Steps.claude(+bs: List<&2, J.Json>, +thread: String, +cwd: String) -> List<&2, Out>:
  Steps.claude.k(Steps.first(bs, Steps.hit(bs)), thread, cwd)

def Steps.acts(cs: List<&2, M.Change>, +thread: String, +cwd: String) -> List<&2, Out>:
  match cs:
    case Nil{}:
      Nil{}
    case M.ActivityLogged{_, +id, +tone, _, _, _} <> t:
      List.append(&2, Out, Bool.pick(List<&2, Out>, String.eq(tone, "tool"), [Steps.out(thread, cwd, id)], Nil{}), Steps.acts(t, thread, cwd))
    case _ <> t:
      Steps.acts(t, thread, cwd)

def Steps.after(st: Step, +thread: String, +cwd: String) -> Step:
  match st:
    case Step{+cs, os}:
      Step{cs, List.append(&2, Out, os, Steps.acts(cs, thread, cwd))}

# Grok's calls are logged before they run: its step waits for the call's
# end (acp.bend's "tool.done")
def Steps.after.if(on: Bool, st: Step, +thread: String, +cwd: String) -> Step:
  match on:
    case True{}:
      Steps.after(st, thread, cwd)
    case False{}:
      st

# A subagent's own lines (parent_tool_use_id names the Agent call that
# started it): what it writes and the tools it calls go to its log, not the
# thread's timeline, and its partial text, tool results and usage are not
# the agent's
def Sub.block.k(i: Nat, +log: String, +call: String, +msg: String, +n: Nat, +now: Nat, +b: J.Json) -> List<&2, M.Change>:
  match i:
    case 0n:
      [M.ActivityLogged{log, call ++ "/" ++ msg ++ ":" ++ Nat.show(n), call, "say", J.Json.get_str(b, "text", ""), now}]
    case 1n:
      [M.ActivityLogged{log, call ++ "/" ++ J.Json.get_str(b, "id", msg ++ ":" ++ Nat.show(n)), call, J.Json.get_str(b, "name", "tool"),
        Claude.tool_summary(J.Json.get_str(b, "name", "tool"), J.Json.get_obj(b, "input")), now}]
    case _:
      Nil{}

def Sub.blocks(bs: List<&2, J.Json>, +log: String, +call: String, +msg: String, +n: Nat, +now: Nat) -> List<&2, M.Change>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      List.append(&2, M.Change,
        Sub.block.k(C.Codec.pos(["text", "tool_use"], J.Json.get_str(b, "type", "")), log, call, msg, n, now, b),
        Sub.blocks(t, log, call, msg, 1n+n, now))

def Sub.line(i: Nat, +thread: String, +now: Nat, +call: String, +o: J.Json) -> Step:
  match i:
    case 2n:
      Step{Sub.blocks(J.Json.elems(J.Json.get_obj(J.Json.get_obj(o, "message"), "content")), M.Bg.log(thread), call,
        J.Json.get_str(J.Json.get_obj(o, "message"), "id", "msg"), 0n, now), Nil{}}
    case _:
      Step.none()

def Hub.provider(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, p, _, _, _, _, _}:
      p

def Hub.running(t: M.Thread) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, M.Running{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      True{}
    case _:
      False{}

def Claude.line.k(i: Nat, +s: M.State, +thread: String, +now: Nat, +o: J.Json) -> Step:
  match i:
    case 0n:
      Step.after(Step.after(Claude.init(s, thread, now, o), Usage.compact(s, thread, now, o)), Bg.system(s, thread, now, o))
    case 1n:
      Claude.stream.if(Hub.running(Hub.thread(s, thread)), thread, J.Json.get_obj(o, "event"))
    case 2n:
      Claude.assistant.t(s, thread, now, J.Json.get_obj(o, "message"))
    case 3n:
      Step.after(Claude.result.if(Hub.running(Hub.thread(s, thread)), thread, now, o), Usage.window(s, thread, now, o))
    case 4n:
      Step.also(Claude.named(s, thread, now, o), Steps.claude(J.Json.elems(J.Json.get_obj(J.Json.get_obj(o, "message"), "content")), thread, Hub.cwd(s, Hub.thread(s, thread))))
    case _:
      Step.none()

def Claude.line.who(main: Bool, i: Nat, +s: M.State, +thread: String, +now: Nat, +call: String, +o: J.Json) -> Step:
  match main:
    case True{}:
      Claude.line.k(i, s, thread, now, o)
    case False{}:
      Sub.line(i, thread, now, call, o)

def Claude.line.parsed(m: Maybe<&2, J.Json>, +s: M.State, +thread: String, +now: Nat) -> Step:
  match m:
    case Some{+o}:
      +call = J.Json.get_str(o, "parent_tool_use_id", "")
      Claude.line.who(String.is_empty(call), C.Codec.pos(["system", "stream_event", "assistant", "result", "user"], J.Json.get_str(o, "type", "")), s, thread, now, call, o)
    case None{}:
      Step.none()

# first: the thread's first worktree (not one made again), whose waiting
# message names its branch
def Wt.start(+s: M.State, +now: Nat, +thread: String, +first: Bool) -> Step:
  Wt.start.k(Bool.and(Bool.not(Hub.running(Hub.thread(s, thread))), M.Queue.waiting(s, thread)), first,
    Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), M.Queue.of(s, thread), now, thread)

def Wt.ready(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +c: M.Change) -> Step:
  Step.before([c], [Reply.ok(client, id)], Wt.start(M.State.replay([c], s), now, thread, String.is_empty(M.Merge.branch(Hub.thread(s, thread)))))

def Hub.agentm(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Step.reply(client, id, [M.WorktreeSet{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "branch", ""), Hub.worktree(Hub.thread(s, J.Json.get_str(p, "thread", ""))), now}])
    case 1n:
      Hub.git(s, client, id, "skills", J.Json.get_str(p, "thread", ""), "", "")
    case 2n:
      Hub.effort(s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "effort", ""))
    case 3n:
      Wt.ready(s, now, client, id, J.Json.get_str(p, "thread", ""), M.WorktreeSkipped{J.Json.get_str(p, "thread", ""), now})
    case 4n:
      Merge.found(M.Merge.due(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))), s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "url", ""))
    case 5n:
      Step.reply(client, id, [M.WorktreeRemoved{J.Json.get_str(p, "thread", ""), now}])
    case 6n:
      Title.got(s, now, client, id, J.Json.get_str(p, "thread", ""), p)
    case 7n:
      Hub.btw(s, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "q", ""))
    case 8n:
      Sum.got(s, now, client, id, p)
    case _:
      Hub.media(C.Codec.pos(Hub.methods.media(), m), s, now, client, id, p, m)

def Hub.dir.k(ok: Bool, +client: U32, +id: String, +th: String, +cwd: String, +path: String) -> Step:
  match ok:
    case True{}:
      Step.outs([Git{client, id, "dir", th, cwd, path, ""}])
    case False{}:
      Step.outs([Reply.err(client, id, "that folder is not in this project")])

def Hub.nav(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Hub.snooze(now, client, id, p)
    case 1n:
      Hub.reorder(s, now, client, id, p)
    case 2n:
      Step.outs([Git{client, id, "files", J.Json.get_str(p, "thread", ""), Hub.cwd(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))), "", ""}])
    case 3n:
      Step.outs([Git{client, id, "kicad", J.Json.get_str(p, "thread", ""), Hub.cwd(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))), "", ""}])
    case 4n:
      Hub.reorder_projects(s, now, client, id, p)
    case 5n:
      Step.outs([Git{client, id, "mech", J.Json.get_str(p, "thread", ""), Hub.cwd(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))), "", ""}])
    case 6n:
      Step.outs([Git{client, id, "render", J.Json.get_str(p, "thread", ""), Hub.cwd(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))), J.Json.get_str(p, "path", ""), ""}])
    # a file link opened on this machine, or shown in its folder: {path, how}
    case 7n:
      Step.outs([Git{client, id, "open", "", "/", J.Json.get_str(p, "path", ""), J.Json.get_str(p, "how", "open")}])
    # the viewer's Files tab: a folder of the thread's project, {thread, path}
    # (from its root, never leaving it: core/fm.bend's Fm.safe)
    case 8n:
      Hub.dir.k(FM.Fm.safe(J.Json.get_str(p, "path", "")), client, id, J.Json.get_str(p, "thread", ""), Hub.cwd(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))), J.Json.get_str(p, "path", ""))
    # a PDF's page as a picture, for the window, {path, page}
    case 9n:
      Step.outs([Git{client, id, "pdf", "", "/", J.Json.get_str(p, "path", ""), J.Json.as_raw(J.Json.get(p, "page"), "1")}])
    case _:
      Hub.agentm(C.Codec.pos(Hub.methods.agent(), m), s, now, client, id, p, m)

def Hub.fs(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Step.outs([Fs{client, id, "list", J.Json.get_str(p, "path", "")}])
    case 1n:
      Step.outs([Fs{client, id, "mkdir", J.Json.get_str(p, "path", "")}])
    case 2n:
      Step.outs([Fs{client, id, "new", J.Json.get_str(p, "path", "")}])
    case 3n:
      Hub.project_add(s, now, client, id, p)
    case 4n:
      Step.outs([Fs{client, id, "find", ""}])
    case _:
      Hub.nav(C.Codec.pos(Hub.methods.nav(), m), s, now, client, id, p, m)

def Hub.more(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Hub.git(s, client, id, "diff", J.Json.get_str(p, "thread", ""), J.Json.as_raw(J.Json.get(p, "from"), "0"), J.Json.as_raw(J.Json.get(p, "to"), "-1"))
    case 1n:
      Hub.git(s, client, id, "revert", J.Json.get_str(p, "thread", ""), J.Json.as_raw(J.Json.get(p, "turn"), "0"), "")
    case 2n:
      Hub.act(s, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "action", "commit"), p)
    case 3n:
      Hub.git(s, client, id, "status", J.Json.get_str(p, "thread", ""), "", "")
    case 4n:
      Wt.ready(s, now, client, id, J.Json.get_str(p, "thread", ""), M.WorktreeSet{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "branch", ""), J.Json.get_str(p, "path", ""), now})
    case 5n:
      Step.reply(client, id, [M.ActivityLogged{J.Json.get_str(p, "thread", ""), Hub.id("g", now, Hub.seq(s)), J.Json.get_str(p, "tone", "info"),
        J.Json.get_str(p, "kind", "git"), J.Json.get_str(p, "summary", ""), now}])
    case 6n:
      Hub.term(s, client, id, "open", p)
    case 7n:
      Hub.term(s, client, id, "input", p)
    case 8n:
      Hub.term(s, client, id, "resize", p)
    case 9n:
      Step.outs([Reply.ok(client, id), TermSnap{client, J.Json.get_str(p, "key", "")}])
    case 10n:
      Emb.restart(s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "id", ""))
    case _:
      Hub.fs(C.Codec.pos(Hub.methods.fs(), m), s, now, client, id, p, m)

# a message for a thread's agent: it starts a turn, or, while a Codex or
# Grok turn runs (one turn at a time) or the thread's worktree is still
# being made, it is stored and waits in the thread's queue (Claude takes
# input mid-turn itself)
def Hub.thread_project(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

# the worktree made again from a thread's kept branch
def Wt.revive(+s: M.State, +th: String) -> Out:
  Git{0, "", "worktree", th, Hub.project.root(Hub.project(s, Hub.thread_project(Hub.thread(s, th)))), "again", M.Merge.branch(Hub.thread(s, th))}

# whether a message makes a thread's removed worktree again first: the
# thread is idle, its worktree is gone, and it is not being made already
def Hub.revive(+running: Bool, gone: Bool, +pending: Bool) -> Bool:
  Bool.and(Bool.not(running), Bool.and(gone, Bool.not(pending)))

def Hub.post.v(revive: Bool, +running: Bool, +pending: Bool, +s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  match revive:
    case True{}:
      Step.before(Nil{}, [Wt.revive(s, thread)], Hub.post.go(True{}, Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), M.Queue.of(s, thread), now, thread, msg, role, text))
    case False{}:
      Hub.post.go(Bool.or(Bool.and(running, Bool.not(String.eq(Hub.provider(Hub.thread(s, thread)), "claude"))), pending),
        Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), M.Queue.of(s, thread), now, thread, msg, role, text)

def Hub.post.w(+running: Bool, gone: Bool, +pending: Bool, +s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  Hub.post.v(Hub.revive(running, gone, pending), running, pending, s, now, thread, msg, role, text)

def Hub.post(+s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  Hub.post.w(Hub.running(Hub.thread(s, thread)), M.Worktree.gone(Hub.thread(s, thread)), M.Worktree.pending(Hub.thread(s, thread), now), s, now, thread, msg, role, text)

# a message from another thread (thread_send, a delegated task's result):
# it lands in the target's inbox and waits while the target works, for
# every provider (it never interrupts a running turn, Claude's included);
# its id names the sender, which is what the link visuals read
def Hub.inbox.v(revive: Bool, +running: Bool, +pending: Bool, +s: M.State, +now: Nat, +from: String, +to: String, role: M.Role, +text: String) -> Step:
  match revive:
    case True{}:
      Step.before(Nil{}, [Wt.revive(s, to)], Hub.post.go(True{}, Hub.thread(s, to), Hub.cwd(s, Hub.thread(s, to)), M.Queue.of(s, to), now, to,
        M.Link.id(from, Hub.id("m", now, Hub.seq(s))), role, text))
    case False{}:
      Hub.post.go(Bool.or(running, pending), Hub.thread(s, to), Hub.cwd(s, Hub.thread(s, to)), M.Queue.of(s, to), now, to,
        M.Link.id(from, Hub.id("m", now, Hub.seq(s))), role, text)

def Hub.inbox.w(+running: Bool, gone: Bool, +pending: Bool, +s: M.State, +now: Nat, +from: String, +to: String, role: M.Role, +text: String) -> Step:
  Hub.inbox.v(Hub.revive(running, gone, pending), running, pending, s, now, from, to, role, text)

def Hub.inbox(+s: M.State, +now: Nat, +from: String, +to: String, role: M.Role, +text: String) -> Step:
  Hub.inbox.w(Hub.running(Hub.thread(s, to)), M.Worktree.gone(Hub.thread(s, to)), M.Worktree.pending(Hub.thread(s, to), now), s, now, from, to, role, text)

def Hub.answer.plan(impl: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +ask: String, +answer: String, +th: String) -> Step:
  match impl:
    case True{}:
      Step.before(M.AskClosed{ask, answer, now} <> Hub.implement.k(Hub.thread(s, th), now), [Reply.ok(client, id)],
        Hub.post(Hub.impl.state(s, th, now), now, th, Hub.id("m", now, Hub.seq(s)), M.User{}, "Implement the proposed plan."))
    case False{}:
      Step{[M.AskClosed{ask, answer, now}], [Reply.ok(client, id), AskAnswered{ask, answer}]}

# the user's answer: the ask closes (once; law ask_closes_once), a parked
# agent request gets its reply, and implementing a plan leaves plan mode
# and asks the agent to carry it out
def Hub.answer.k(a: M.Ask, +s: M.State, +now: Nat, +client: U32, +id: String, +ask: String, +answer: String) -> Step:
  match a:
    case M.Ask{_, +th, +k, _, _, _, True{}, _}:
      Hub.answer.plan(Bool.and(String.eq(k, "plan"), String.eq(answer, "implement")), s, now, client, id, ask, answer, th)
    case M.Ask{_, _, _, _, _, _, False{}, _}:
      Step.outs([Reply.ok(client, id)])

def Hub.answer(+s: M.State, +now: Nat, +client: U32, +id: String, +ask: String, +answer: String) -> Step:
  Hub.answer.k(Ask.find(M.Asks.all(s), ask), s, now, client, id, ask, answer)

def Hub.turn.go(+s: M.State, +t: M.Thread, +now: Nat, +client: U32, +id: String, +thread: String, +msg: String, +text: String) -> Step:
  match t:
    case M.Thread{_, _, +title, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Step.before(Hub.title.k(String.eq(title, "New thread"), thread, text, now, Nil{}),
        Reply.ok(client, id) <> List.append(&2, Out, Name.out(Hub.thread(s, thread), text), Title.out(String.eq(title, "New thread"), thread, text)),
        Hub.post(s, now, thread, msg, M.User{}, text))

def Hub.turn.k(dup: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +msg: String, +text: String) -> Step:
  match dup:
    case True{}:
      Step.outs([Reply.ok(client, id)])
    case False{}:
      Hub.turn.go(s, Hub.thread(s, thread), now, client, id, thread, msg, text)

def Hub.turn.m(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +text: String, +msg: String, named: Bool) -> Step:
  Hub.turn.k(Hub.dup(named, s, msg), s, now, client, id, thread, msg, text)

# a user message. The client names it (msg), so a message resent after a
# dropped connection is stored once; the hub names it otherwise
def Hub.turn(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +text: String, +msg: String) -> Step:
  Hub.turn.m(s, now, client, id, thread, text, Bool.pick(String, String.is_empty(msg), Hub.id("m", now, Hub.seq(s)), msg), Bool.not(String.is_empty(msg)))

# Follow-ups: queue or steer
# --------------------------
# A message sent while a turn runs either waits in the queue for a later
# turn or steers the running one. Claude takes it in place, on its input;
# a Codex or Grok turn cannot, so its process stops and the turn starts
# again on the same session with the steering message (law
# steer_codex_restarts). With no turn running, either starts at once.
# "auto" (or no mode) keeps the provider's default: Claude steers, the
# others queue.

def Steer.stop(+provider: String, +thread: String) -> List<&2, Out>:
  Bool.pick(List<&2, Out>, String.eq(provider, "claude"), Nil{}, [AgentStop{thread}])

def Steer.note(+provider: String, +thread: String, +now: Nat, +seq: Nat) -> List<&2, M.Change>:
  Bool.pick(List<&2, M.Change>, String.eq(provider, "claude"), Nil{},
    [M.ActivityLogged{thread, Hub.id("s", now, seq), "info", "steer", "Steered: the turn starts again with this message", now}])

# the running turn takes `text` now (the message itself is already posted)
def Steer.go(+t: M.Thread, +cwd: String, +now: Nat, +seq: Nat, +thread: String, +text: String) -> Step:
  Step{List.append(&2, M.Change, Steer.note(Hub.provider(t), thread, now, seq), [M.TurnChanged{thread, M.Running{}, now}]),
    List.append(&2, Out, Steer.stop(Hub.provider(t), thread), Hub.run(t, cwd, text))}

def Hub.post.q(run: Bool, +s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  match run:
    case True{}:
      Step{[M.MessagePosted{thread, msg, role, text, now}, M.TurnQueued{thread, msg, text, now}], Nil{}}
    case False{}:
      Hub.post(s, now, thread, msg, role, text)

def Hub.post.st(run: Bool, +s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  match run:
    case True{}:
      Step.before([M.MessagePosted{thread, msg, role, text, now}], Nil{}, Steer.go(Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), now, Hub.seq(s), thread, text))
    case False{}:
      Hub.post(s, now, thread, msg, role, text)

def Hub.post.mode.k(i: Nat, +s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  match i:
    case 0n:
      Hub.post.q(Hub.running(Hub.thread(s, thread)), s, now, thread, msg, role, text)
    case 1n:
      Hub.post.st(Hub.running(Hub.thread(s, thread)), s, now, thread, msg, role, text)
    case _:
      Hub.post(s, now, thread, msg, role, text)

# a message with its follow-up mode: "queue", "steer", or "auto"
def Hub.post.mode(+mode: String, +s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  Hub.post.mode.k(C.Codec.pos(["queue", "steer"], mode), s, now, thread, msg, role, text)

def Hub.turnx.go(+mode: String, +s: M.State, +t: M.Thread, +now: Nat, +client: U32, +id: String, +thread: String, +msg: String, +text: String) -> Step:
  match t:
    case M.Thread{_, _, +title, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Step.before(Hub.title.k(String.eq(title, "New thread"), thread, text, now, Nil{}),
        Reply.ok(client, id) <> List.append(&2, Out, Name.out(Hub.thread(s, thread), text), Title.out(String.eq(title, "New thread"), thread, text)),
        Hub.post.mode(mode, s, now, thread, msg, M.User{}, text))

def Hub.turnx.k(dup: Bool, +mode: String, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +msg: String, +text: String) -> Step:
  match dup:
    case True{}:
      Step.outs([Reply.ok(client, id)])
    case False{}:
      Hub.turnx.go(mode, s, Hub.thread(s, thread), now, client, id, thread, msg, text)

# a user message with an explicit follow-up mode (Hub.turn is "auto")
def Hub.turnx(+mode: String, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +text: String, +msg: String) -> Step:
  Hub.turnx.k(Hub.dup(Bool.not(String.is_empty(msg)), s, msg), mode, s, now, client, id, thread,
    Bool.pick(String, String.is_empty(msg), Hub.id("m", now, Hub.seq(s)), msg), text)

def Hub.turn.mode(auto: Bool, +mode: String, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +text: String, +msg: String) -> Step:
  match auto:
    case True{}:
      Hub.turn(s, now, client, id, thread, text, msg)
    case False{}:
      Hub.turnx(mode, s, now, client, id, thread, text, msg)

# The queue, message by message
# -----------------------------

def Queue.steer.k(m: Maybe<&2, M.QItem>, +run: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String) -> Step:
  match m run:
    case Some{M.QItem{+msg, +text}} True{}:
      Step.before([M.QueueTakenOne{thread, msg, now}], [Reply.ok(client, id)], Steer.go(Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), now, Hub.seq(s), thread, text))
    case Some{M.QItem{+msg, +text}} False{}:
      Step{[M.QueueTakenOne{thread, msg, now}, M.TurnChanged{thread, M.Running{}, now}],
        Reply.ok(client, id) <> Git{0, "", "checkpoint0", thread, Hub.cwd(s, Hub.thread(s, thread)), "", ""} <> Git{0, "", "step", thread, Hub.cwd(s, Hub.thread(s, thread)), "", ""} <> Hub.run(Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), text)}
    case None{} _:
      Step.outs([Reply.err(client, id, "no such queued message")])

# a queued message sent now: into the running turn (a steer), or as a turn
# of its own when none runs
def Queue.steer(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +msg: String) -> Step:
  Queue.steer.k(M.Queue.find(M.Queue.items(s, thread), msg), Hub.running(Hub.thread(s, thread)), s, now, client, id, thread)

def Queue.op(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  match i:
    case 0n:
      Step.reply(client, id, [M.QueueEdited{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "msg", ""), J.Json.get_str(p, "text", ""), now}])
    case 1n:
      Step.reply(client, id, [M.QueueRemoved{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "msg", ""), now}])
    case 2n:
      Step.reply(client, id, [M.QueueMoved{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "msg", ""), Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(J.Json.get(p, "to"), "0")), 0n), now}])
    case _:
      Queue.steer(s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "msg", ""))

# Forks
# -----
# A fork is a new thread that continues another from where it stands (V2's
# thread lineage). It records its source (ThreadForked), works in its own
# worktree made from the source's last checkpoint when the source has one,
# and carries the source's conversation as handed-over context, queued
# ahead of its first message (HD.Hand). Bringing a fork back queues the
# fork's conversation into its source the same way, for the source's next
# message; the fork's files stay on its own branch.

def Fork.env(+wt: String) -> M.EnvMode:
  Bool.pick(M.EnvMode, String.is_empty(wt), M.Local{}, M.Worktree{})

def Fork.outs(+wt: String, +th: String, +root: String, +src: String) -> List<&2, Out>:
  Bool.pick(List<&2, Out>, String.is_empty(wt), Nil{}, [Git{0, "", "worktree", th, root, "fork", src}])

# a scratch thread's fork is a scratch thread with a folder of its own
def Fork.env.s(scratch: Bool, +wt: String) -> M.EnvMode:
  match scratch:
    case True{}:
      M.Local{}
    case False{}:
      Fork.env(wt)

def Fork.outs.s(scratch: Bool, +wt: String, +th: String, +root: String, +src: String) -> List<&2, Out>:
  match scratch:
    case True{}:
      [BotFx{"scratch", th, "", ""}]
    case False{}:
      Fork.outs(wt, th, root, src)

def Hub.fork.k(t: M.Thread, +s: M.State, +now: Nat, +client: U32, +id: String, +src: String) -> Step:
  match t:
    case M.Thread{_, +p, +ti, _, _, _, _, _, _, _, _, _, _, _, +wt, +pr, +mo, rt, im, _, _}:
      +th = Hub.id("t", now, Hub.seq(s))
      Step{[M.ThreadCreated{th, p, "Fork: " ++ ti, Fork.env.s(M.Scratch.is(p), wt), "", Hub.new.wt(M.Scratch.is(p), Hub.project.root(Hub.project(s, p)), th), pr, mo, now}, M.ModesSet{th, rt, im, mo, now}, M.ThreadForked{th, src, now},
          M.TurnQueued{th, HD.Hand.prefix() ++ src, HD.Hand.fork(Hub.entries(s), src, ti), now},
          M.ActivityLogged{src, Hub.id("k", now, Hub.seq(s)), "info", "fork", "Forked into \"Fork: " ++ ti ++ "\"", now}],
        Reply.ok(client, id) <> Fork.outs.s(M.Scratch.is(p), wt, th, Hub.project.root(Hub.project(s, p)), src)}

# a new thread that goes on from this one
def Hub.fork(+s: M.State, +now: Nat, +client: U32, +id: String, +src: String) -> Step:
  Hub.fork.k(Hub.thread(s, src), s, now, client, id, src)

def Hub.back.k(none: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +fork: String, +src: String) -> Step:
  match none:
    case True{}:
      Step.outs([Reply.err(client, id, "this thread is not a fork")])
    case False{}:
      Step.reply(client, id, [M.TurnQueued{src, HD.Hand.prefix() ++ "back:" ++ fork ++ ":" ++ Nat.show(Hub.seq(s)), HD.Hand.back(Hub.entries(s), fork, HD.Hand.title(Hub.thread(s, fork))), now},
        M.ActivityLogged{src, Hub.id("k", now, Hub.seq(s)), "info", "fork", "The work of \"" ++ HD.Hand.title(Hub.thread(s, fork)) ++ "\" goes with the next message", now},
        M.ActivityLogged{fork, Hub.id("k", now, 1n+Hub.seq(s)), "info", "fork", "Brought back to \"" ++ HD.Hand.title(Hub.thread(s, src)) ++ "\"", now}])

# a fork's work, queued into its source for the source's next message
def Hub.back(+s: M.State, +now: Nat, +client: U32, +id: String, +fork: String) -> Step:
  Hub.back.k(String.is_empty(M.Fork.source(s, fork)), s, now, client, id, fork, M.Fork.source(s, fork))

# Switching providers
# -------------------
# Between turns a thread may go on with another provider (and its default
# model). The provider left keeps its session and how much it saw; the one
# taken up resumes its own session if it had one, and gets what it missed
# as handed-over context with the next message (a full handoff when it
# never took part). A context from an earlier switch not sent yet is
# dropped for the new one. A running turn is never switched (law
# switch_between_turns).

def Switch.old(qs: List<&2, M.QItem>, +th: String, +now: Nat) -> List<&2, M.Change>:
  match qs:
    case Nil{}:
      Nil{}
    case M.QItem{+m, _} <> t:
      List.append(&2, M.Change, Bool.pick(List<&2, M.Change>, String.starts_with(m, "handoff:switch:"), [M.QueueRemoved{th, m, now}], Nil{}), Switch.old(t, th, now))

def Switch.ctx(none: Bool, +th: String, +msg: String, +text: String, +now: Nat) -> List<&2, M.Change>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [M.TurnQueued{th, msg, text, now}]

def Switch.go(+s: M.State, +now: Nat, +client: U32, +id: String, +th: String, +from: String, +to: String) -> Step:
  +seen = M.Switch.seen(s, th, to)
  +missed = Nat.sub(M.Switch.count(Hub.entries(s), th), seen)
  Step{List.concat(&2, M.Change, [Switch.old(M.Queue.items(s, th), th, now), [M.ProviderSet{th, to, "", now}],
      Switch.ctx(Nat.is_eq(missed, 0n), th, HD.Hand.prefix() ++ "switch:" ++ Nat.show(Hub.seq(s)), HD.Hand.switch(Hub.entries(s), th, from, to, seen), now),
      [M.ActivityLogged{th, Hub.id("p", now, Hub.seq(s)), "info", "provider", "Now on " ++ to ++ Bool.pick(String, Nat.is_eq(missed, 0n), "", "; it gets what it missed with the next message"), now}]]),
    [Reply.ok(client, id), AgentStop{th}]}

def Switch.k(run: Bool, same: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +th: String, +from: String, +to: String) -> Step:
  match run same:
    case True{} _:
      Step.outs([Reply.err(client, id, "a provider changes between turns: stop this one first")])
    case False{} True{}:
      Step.outs([Reply.ok(client, id)])
    case False{} False{}:
      Switch.go(s, now, client, id, th, from, to)

# the thread goes on with provider `to` from its next turn
def Hub.switch(+s: M.State, +now: Nat, +client: U32, +id: String, +th: String, +to: String) -> Step:
  Switch.k(Hub.running(Hub.thread(s, th)), String.eq(Hub.provider(Hub.thread(s, th)), to), s, now, client, id, th, Hub.provider(Hub.thread(s, th)), to)

# Stopping a turn
# ---------------
# Claude takes an interrupt on its input and stays up; a Codex or Grok turn
# is a process of its own, which is stopped. Only a running turn is
# stopped (law interrupt_idle_nothing).

def Stop.outs(+provider: String, +thread: String, +rid: String) -> List<&2, Out>:
  Bool.pick(List<&2, Out>, String.eq(provider, "claude"), [AgentSend{thread, Claude.interrupt(rid)}], [AgentStop{thread}])

# the held queue of an idle thread (kept across a restart, or after a
# stop) starts now
def Hub.resume(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String) -> Step:
  Step.before(Nil{}, [Reply.ok(client, id)], Wt.start(s, now, thread, False{}))

def Hub.agent_gone.k(running: Bool, +thread: String, +now: Nat, +code: U32) -> Step:
  match running:
    case True{}:
      Step{[M.ActivityLogged{thread, Hub.id("x", now, 0n), "error", "exit", "agent exited with code " ++ U32.show(code), now},
        M.TurnChanged{thread, M.Failed{}, now}], Nil{}}
    case False{}:
      Step.none()

def Hub.settle.k(auto: Bool, sh: M.Shelf, t: M.Thread, +now: Nat, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match auto sh t:
    case True{} M.Active{} M.Thread{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      M.ThreadSettled{id, False{}, now} <> rest
    case _ _ _:
      rest

# Settle tick
# -----------

# whether a thread has a delegated task still at work: its parent waits
# for it, so it does not settle (law settle_waits_for_children)
def Kids.busy(ts: List<&2, M.Task>, +parent: String) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case M.Task{_, p, _, _, st, _, _, _, _} <> t:
      Bool.or(Bool.and(String.eq(p, parent), Bool.not(M.TaskState.terminal(st))), Kids.busy(t, parent))

def Hub.settle.go(ts: List<&2, M.Thread>, +navs: Map<&2, M.Nav>, +tasks: List<&2, M.Task>, +now: Nat, +w: Nat) -> List<&2, M.Change>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Hub.settle.k(Bool.and(M.Settle.auto.at(now, w, t, M.Nav.until(M.Nav.get(navs, M.Thread.id(t)))), Bool.not(Kids.busy(tasks, M.Thread.id(t)))), M.Shelf.of(t), t, now, Hub.settle.go(rest, navs, tasks, now, w))

# the settle window in seconds: the "settle.days" setting (1..90), else 3 days
def Hub.settle.window(+s: M.State) -> Nat:
  Nat.mul(Nat.max(1n, Nat.min(90n, Maybe.default(&2, Nat, Nat.read(M.Setting.get(s, "settle.days", "3")), 3n))), 86400n)

# Merges
# ------
# Each tick, a project with threads whose merge is due asks gh which of
# their branches were merged (one call per project); the server answers
# thread.merged for each.

def Merge.line.k(due: Bool, +in: Bool, +t: M.Thread, rest: List<&2, String>) -> List<&2, String>:
  match due in:
    case True{} True{}:
      (M.Merge.id(t) ++ "\t" ++ M.Merge.branch(t) ++ "\t" ++ Hub.worktree(t)) <> rest
    case _ _:
      rest

# "<thread>\t<branch>\t<worktree>" for each of a project's threads whose
# merge is due
def Merge.lines(ts: List<&2, M.Thread>, +s: M.State, +pid: String) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Merge.line.k(M.Merge.due(s, t), M.Thread.in_project(pid, t), t, Merge.lines(rest, s, pid))

def Merge.ask.k(ls: List<&2, String>, +root: String, rest: List<&2, Out>) -> List<&2, Out>:
  match ls:
    case Nil{}:
      rest
    case +l <> t:
      Git{0, "", "merged", "", root, String.join(l <> t, "\n"), ""} <> rest

def Merge.ask.p(removed: Bool, +ts: List<&2, M.Thread>, +s: M.State, +id: String, +root: String, rest: List<&2, Out>) -> List<&2, Out>:
  match removed:
    case True{}:
      rest
    case False{}:
      Merge.ask.k(Merge.lines(ts, s, id), root, rest)

def Merge.asks(ps: List<&2, M.Project>, +ts: List<&2, M.Thread>, +s: M.State) -> List<&2, Out>:
  match ps:
    case Nil{}:
      Nil{}
    case M.Project{+id, _, +root, _, rm} <> rest:
      Merge.ask.p(rm, ts, s, id, root, Merge.asks(rest, ts, s))

# gh's merged pull requests (gh pr list --json headRefName,headRefOid,url)
# against "<thread>\t<branch>[\t<worktree>[\t<commits>]]" lines, the
# commits (space separated) being the ones the thread's worktree has been on
# (its HEAD reflog): each thread whose branch was merged, with the pull
# request's url. A pull request is the thread's when its head branch is the
# thread's branch, or its head commit is one the worktree was on (agents
# often push from a branch of another name)
def Merge.has(cs: List<&2, String>, +c: String) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(String.eq(h, c), Merge.has(t, c))

def Merge.ours(+o: J.Json, +branch: String, +cs: List<&2, String>) -> Bool:
  +oid = J.Json.get_str(o, "headRefOid", "")
  Bool.or(Bool.and(Bool.not(String.is_empty(branch)), String.eq(J.Json.get_str(o, "headRefName", ""), branch)),
    Bool.and(Bool.not(String.is_empty(oid)), Merge.has(cs, oid)))

def Merge.find.k(ours: Bool, +o: J.Json, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match ours:
    case True{}:
      Some{J.Json.get_str(o, "url", "")}
    case False{}:
      rest

def Merge.find(prs: List<&2, J.Json>, +branch: String, +cs: List<&2, String>) -> Maybe<&2, String>:
  match prs:
    case Nil{}:
      None{}
    case +o <> t:
      Merge.find.k(Merge.ours(o, branch, cs), o, Merge.find(t, branch, cs))

def Merge.hit(m: Maybe<&2, String>, +th: String, rest: List<&2, J.KV>) -> List<&2, J.KV>:
  match m:
    case Some{u}:
      J.KV{th, J.Str{u}} <> rest
    case None{}:
      rest

def Merge.pair(parts: List<&2, String>, +prs: List<&2, J.Json>, rest: List<&2, J.KV>) -> List<&2, J.KV>:
  match parts:
    case +th <> +br <> _ <> +cs <> Nil{}:
      Merge.hit(Merge.find(prs, br, String.split(cs, ' ')), th, rest)
    case +th <> +br <> _:
      Merge.hit(Merge.find(prs, br, Nil{}), th, rest)
    case _:
      rest

def Merge.hits.go(ls: List<&2, String>, +prs: List<&2, J.Json>) -> List<&2, J.KV>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Merge.pair(String.split(l, '\t'), prs, Merge.hits.go(t, prs))

def Merge.hits(+json: String, +lines: String) -> List<&2, J.KV>:
  Merge.hits.go(String.lines(lines), J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(json), J.Null{})))

def Wt.stale.one.k(t: M.Thread, +now: Nat, +pending: Bool) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, M.Worktree{}, +br, +wt, _, _, _, _, _, _}:
      Bool.and(Bool.and(String.is_empty(wt), String.is_empty(br)), Bool.not(pending))
    case _:
      False{}

def Wt.stale.one(+t: M.Thread, +now: Nat) -> Bool:
  Wt.stale.one.k(t, now, M.Worktree.pending(t, now))

# a hardware project: KiCad files in the project folder. Its new worktrees
# bring the folder's uncommitted work along (board work is often not
# committed yet, and boards do not merge by hand)
def Wt.hardware(ns: List<&2, String>) -> Bool:
  match ns:
    case Nil{}:
      False{}
    case +n <> t:
      Bool.or(Bool.or(String.ends_with(n, ".kicad_pro"), String.ends_with(n, ".kicad_pcb")), Bool.or(String.ends_with(n, ".kicad_sch"), Wt.hardware(t)))

# what the hub tells the clients when an agent starts in a KiCad project:
# show the thread's board (its schematic when there is no board) as the
# hub's own view ("auto", which a panel shut by hand ignores); "" for a
# project with neither
def Auto.view.json(+thread: String, +pcb: String, +sch: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Str{"view"}}, J.KV{"thread", J.Str{thread}}, J.KV{"kind", J.Str{Bool.pick(String, String.is_empty(pcb), "schematic", "board")}},
    J.KV{"path", J.Str{Bool.pick(String, String.is_empty(pcb), sch, pcb)}}, J.KV{"auto", J.Json.bool(True{})}])

def Auto.view.k(none: Bool, +thread: String, +pcb: String, +sch: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      J.Json.show(Auto.view.json(thread, pcb, sch))

def Auto.view(+thread: String, +pcb: String, +sch: String) -> String:
  Auto.view.k(Bool.and(String.is_empty(pcb), String.is_empty(sch)), thread, pcb, sch)

def Wt.digit(keep: Bool, +c: U32, rest: String) -> String:
  match keep:
    case True{}:
      SCon{Chr{c}, rest}
    case False{}:
      rest

def Wt.digits(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+c}, t}:
      Wt.digit(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), c, Wt.digits(t))

# a thread's temporary branch seed: its id's digits (time and sequence), so
# two threads made in the same second get different branches
def Wt.seed(+id: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(Wt.digits(id)), 0n)

# Codex (codex exec --json)
# -------------------------

def Codex.item.k(i: Nat, +thread: String, +now: Nat, +seq: Nat, +it: J.Json) -> Step:
  match i:
    case 0n:
      Step{[M.MessagePosted{thread, J.Json.get_str(it, "id", Hub.id("c", now, seq)) ++ "-" ++ Nat.show(seq), M.Assistant{}, J.Json.get_str(it, "text", ""), now}], Nil{}}
    case 1n:
      Step{[M.ActivityLogged{thread, J.Json.get_str(it, "id", Hub.id("x", now, seq)) ++ "-" ++ Nat.show(seq), "tool", "shell", J.Json.get_str(it, "command", ""), now}], Nil{}}
    case 2n:
      Step{[M.ActivityLogged{thread, Hub.id("f", now, seq), "tool", "edit", J.Json.show(J.Json.get_obj(it, "changes")), now}], Nil{}}
    case 3n:
      Step{[M.TodosSet{thread, TD.Todo.show(TD.Todo.codex(it)), now}], Nil{}}
    case _:
      Step.none()

# a todo list as it starts or changes (only its completion goes through
# item.completed)
def Codex.todo(todo: Bool, +thread: String, +now: Nat, +it: J.Json) -> Step:
  match todo:
    case True{}:
      Step{[M.TodosSet{thread, TD.Todo.show(TD.Todo.codex(it)), now}], Nil{}}
    case False{}:
      Step.none()

# item.started and item.updated share a case: only todo lists are read there
def Codex.kind(+t: String) -> Nat:
  Bool.pick(Nat, String.eq(t, "tool.done"), 6n, Bool.pick(Nat, Bool.or(String.eq(t, "item.started"), String.eq(t, "item.updated")), 5n,
    C.Codec.pos(["thread.started", "item.completed", "turn.completed", "turn.failed", "item.delta"], t)))

def Codex.line.k(i: Nat, +s: M.State, +thread: String, +now: Nat, +o: J.Json) -> Step:
  match i:
    case 0n:
      Claude.init.k(Claude.init.same(Hub.thread(s, thread), J.Json.get_str(o, "thread_id", "")), thread, J.Json.get_str(o, "thread_id", ""), now)
    case 1n:
      Codex.item.k(C.Codec.pos(["agent_message", "command_execution", "file_change", "todo_list"], J.Json.get_str(J.Json.get_obj(o, "item"), "type", "")), thread, now, Hub.seq(s), J.Json.get_obj(o, "item"))
    case 2n:
      Step{[M.TurnChanged{thread, M.Completed{}, now}], Nil{}}
    case 4n:
      Step.outs([Delta.push(thread, J.Json.get_str(o, "text", ""))])
    case 5n:
      Codex.todo(String.eq(J.Json.get_str(J.Json.get_obj(o, "item"), "type", ""), "todo_list"), thread, now, J.Json.get_obj(o, "item"))
    case 6n:
      Step.outs([Steps.out(thread, Hub.cwd(s, Hub.thread(s, thread)), "")])
    case 3n:
      Step{[M.ActivityLogged{thread, Hub.id("e", now, Hub.seq(s)), "error", Hub.provider(Hub.thread(s, thread)), J.Json.get_str(J.Json.get_obj(o, "error"), "message", J.Json.get_str(o, "message", "turn failed")), now}, M.TurnChanged{thread, M.Failed{}, now}], Nil{}}
    case _:
      Step.none()

def Codex.line.parsed(m: Maybe<&2, J.Json>, +s: M.State, +thread: String, +now: Nat) -> Step:
  match m:
    case Some{+o}:
      Codex.line.k(Codex.kind(J.Json.get_str(o, "type", "")), s, thread, now, o)
    case None{}:
      Step.none()

# a Codex or Grok line counts only while its thread's turn runs: what a
# stopped turn's process still says is old news (law stopped_turn_quiet)
def Hub.agent_line.c(run: Bool, +s: M.State, +now: Nat, +thread: String, line: String) -> Step:
  match run:
    case True{}:
      Steps.after.if(Bool.not(String.eq(Hub.provider(Hub.thread(s, thread)), "grok")), Codex.line.parsed(J.Json.parse(line), s, thread, now), thread, Hub.cwd(s, Hub.thread(s, thread)))
    case False{}:
      Step.none()

def Hub.agent_line.k(codex: Bool, +s: M.State, +now: Nat, +thread: String, line: String) -> Step:
  match codex:
    case True{}:
      Hub.agent_line.c(Hub.running(Hub.thread(s, thread)), s, now, thread, line)
    case False{}:
      Claude.line.parsed(J.Json.parse(line), s, thread, now)

# Queued turns
# ------------

def Queue.ended.one(c: M.Change, +thread: String) -> Bool:
  match c:
    case M.TurnChanged{th, M.Completed{}, _}:
      String.eq(th, thread)
    case M.TurnChanged{th, M.Failed{}, _}:
      String.eq(th, thread)
    case _:
      False{}

# whether these changes end the thread's turn (an interrupt keeps the
# queue: it goes with the next message)
def Queue.ended(cs: List<&2, M.Change>, +thread: String) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case c <> t:
      Bool.or(Queue.ended.one(c, thread), Queue.ended(t, thread))

def Queue.drain.k(go: Bool, st: Step, +t: M.Thread, cwd: String, +queued: String, +now: Nat, +thread: String) -> Step:
  match go st:
    case True{} Step{cs, os}:
      Step{List.append(&2, M.Change, cs, [M.QueueTaken{thread, now}, M.TurnChanged{thread, M.Running{}, now}]), List.append(&2, Out, os, Hub.run(t, cwd, queued))}
    case False{} _:
      st

def Queue.changes(st: Step) -> List<&2, M.Change>:
  match st:
    case Step{cs, _}:
      cs

# the turn ended with messages waiting: start the next turn with them
def Ended.state(cs: List<&2, M.Change>, +thread: String) -> String:
  match cs:
    case Nil{}:
      ""
    case M.TurnChanged{+th, M.Completed{}, _} <> t:
      Bool.pick(String, String.eq(th, thread), "completed", Ended.state(t, thread))
    case M.TurnChanged{+th, M.Failed{}, _} <> t:
      Bool.pick(String, String.eq(th, thread), "failed", Ended.state(t, thread))
    case _ <> t:
      Ended.state(t, thread)

def Ended.out.k(none: Bool, +s: M.State, +now: Nat, +state: String, +thread: String, +cwd: String, st: Step) -> Step:
  match none st:
    case True{} _:
      st
    case False{} Step{cs, os}:
      Step{List.append(&2, M.Change, cs, Sum.at(RF.Sum.due(s, thread, now), thread, now)),
        List.append(&2, Out, os, TurnEnded{thread, state} <> Git{0, "", "step", thread, cwd, "", ""} <> Git{0, "", "checkpoint", thread, cwd, "", ""} <> Sum.out(RF.Sum.due(s, thread, now), s, thread, "thread"))}

def Ended.out.s(+s: M.State, +now: Nat, +state: String, +thread: String, +cwd: String, st: Step) -> Step:
  Ended.out.k(String.is_empty(state), s, now, state, thread, cwd, st)

# a turn that ends tells the server (phone notifications hang off this),
# and has the thread summarized when its summary is due
def Ended.out(+s: M.State, +now: Nat, +thread: String, +st: Step) -> Step:
  Ended.out.s(s, now, Ended.state(Queue.changes(st), thread), thread, Hub.cwd(s, Hub.thread(s, thread)), st)

def Queue.drain(+s: M.State, +now: Nat, +thread: String, +st: Step) -> Step:
  Queue.drain.k(Bool.and(Queue.ended(Queue.changes(st), thread), M.Queue.waiting(s, thread)), st,
    Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), M.Queue.of(s, thread), now, thread)

# Delegated tasks finishing
# -------------------------

def Task.child.hit(ts: List<&2, M.Task>, +child: String) -> Bool:
  match ts:
    case M.Task{_, _, c, _, _, _, _, _, _} <> _:
      String.eq(c, child)
    case Nil{}:
      False{}

def Task.child.go(ts: List<&2, M.Task>, hit: Bool, +child: String) -> Maybe<&2, M.Task>:
  match ts hit:
    case t <> _ True{}:
      Some{t}
    case _ <> +rest False{}:
      Task.child.go(rest, Task.child.hit(rest, child), child)
    case Nil{} _:
      None{}

def Task.of_child.k(+ts: List<&2, M.Task>, +child: String) -> Maybe<&2, M.Task>:
  Task.child.go(ts, Task.child.hit(ts, child), child)

# the task a child thread is working on, if any
def Task.of_child(s: M.State, +child: String) -> Maybe<&2, M.Task>:
  match s:
    case M.State{_, _, _, _, tk, _, _, _, _, _, _}:
      Task.of_child.k(Map.values(&2, M.Task, tk), child)

def Task.depth.k(m: Maybe<&2, M.Task>) -> Nat:
  match m:
    case Some{M.Task{_, _, _, d, _, _, _, _, _}}:
      d
    case None{}:
      0n

# the depth of a thread: 0 at the top, its task's depth for a child
def Task.depth(+s: M.State, +thread: String) -> Nat:
  Task.depth.k(Task.of_child(s, thread))

# the newest assistant message of a thread (a child's result)
def Task.last.k(same: Bool, e: M.Entry, rest: String) -> String:
  match same e:
    case True{} M.Msg{_, _, M.Assistant{}, text, _}:
      text
    case _ _:
      rest

def Task.last.hit(es: List<&2, M.Entry>, +th: String) -> Bool:
  match es:
    case M.Msg{_, t, M.Assistant{}, _, _} <> _:
      String.eq(t, th)
    case _:
      False{}

def Task.last.go(es: List<&2, M.Entry>, hit: Bool, +th: String) -> String:
  match es hit:
    case M.Msg{_, _, _, text, _} <> _ True{}:
      text
    case _ <> +t False{}:
      Task.last.go(t, Task.last.hit(t, th), th)
    case _ _:
      ""

def Task.last.of(+es: List<&2, M.Entry>, +th: String) -> String:
  Task.last.go(es, Task.last.hit(es, th), th)

# read from the thread's own entries (M.State.mine), never the whole log
def Task.last(+s: M.State, +th: String) -> String:
  Task.last.of(M.State.mine(s, th), th)

# the turn outcome a step reports for a thread, if it ended one
type Ended is Data:
  NotEnded{}
  EndedOk{}
  EndedBad{}

def Task.ended(cs: List<&2, M.Change>) -> Ended:
  match cs:
    case Nil{}:
      NotEnded{}
    case M.TurnChanged{_, M.Completed{}, _} <> _:
      EndedOk{}
    case M.TurnChanged{_, M.Failed{}, _} <> _:
      EndedBad{}
    case M.TurnChanged{_, M.Interrupted{}, _} <> _:
      EndedBad{}
    case _ <> t:
      Task.ended(t)

def Task.state_of(e: Ended) -> M.TaskState:
  match e:
    case EndedOk{}:
      M.TaskDone{}
    case _:
      M.TaskFailed{}

def Task.word(e: Ended) -> String:
  match e:
    case EndedOk{}:
      "finished"
    case _:
      "failed"

def Task.note(+id: String, +provider: String, +model: String, +word: String, +summary: String) -> String:
  "[Backplane] Delegated task " ++ id ++ " (" ++ provider ++ Bool.pick(String, String.is_empty(model), "", "/" ++ model) ++ ") " ++ word ++ ":\n\n" ++ summary

def Task.finish.go(deliver: Bool, +s: M.State, +now: Nat, +id: String, +thread: String, +parent: String, +provider: String, +model: String, +word: String, st: M.TaskState, +summary: String, cs: List<&2, M.Change>, os: List<&2, Out>) -> Step:
  match deliver:
    case True{}:
      Step.before(List.append(&2, M.Change, cs, [M.TaskStateSet{id, st, summary, now}, M.TaskDelivered{id, now}]), os,
        Hub.inbox(s, now, thread, parent, M.System{}, Task.note(id, provider, model, word, summary)))
    case False{}:
      Step{List.append(&2, M.Change, cs, [M.TaskStateSet{id, st, summary, now}]), os}

def Task.finish.k(e: Ended, m: Maybe<&2, M.Task>, +s: M.State, +now: Nat, +thread: String, cs: List<&2, M.Change>, os: List<&2, Out>) -> Step:
  match e m:
    case NotEnded{} _:
      Step{cs, os}
    case _ None{}:
      Step{cs, os}
    case +ended Some{M.Task{+id, +parent, _, _, +cur, _, +dl, +provider, +model}}:
      Task.finish.go(M.Task.pending(M.Task{id, parent, thread, 0n, M.TaskState.next(cur, Task.state_of(ended)), "", dl, provider, model}),
        s, now, id, thread, parent, provider, model, Task.word(ended), Task.state_of(ended), Task.last(s, thread), cs, os)

# when a child thread's turn ends, its task ends and the result goes to the
# parent once (the pending check makes delivery exactly-once)
# (the task is looked up only once the step is known to end a turn: every
# agent line comes through here)
def Task.finish.e(e: Ended, +s: M.State, +now: Nat, +thread: String, cs: List<&2, M.Change>, os: List<&2, Out>) -> Step:
  match e:
    case NotEnded{}:
      Step{cs, os}
    case EndedOk{}:
      Task.finish.k(EndedOk{}, Task.of_child(s, thread), s, now, thread, cs, os)
    case EndedBad{}:
      Task.finish.k(EndedBad{}, Task.of_child(s, thread), s, now, thread, cs, os)

def Task.finish(+s: M.State, +now: Nat, +thread: String, st: Step) -> Step:
  match st:
    case Step{+cs, os}:
      Task.finish.e(Task.ended(cs), s, now, thread, cs, os)

# Retiring a run
# --------------
# Whenever a thread's process is retired (Stop, archive, delete, a crash,
# a process that could not start) nothing it held is left waiting: its
# open asks close, and each parked request gets the empty answer (deny for
# an approval, "dismissed" for a question: Perm.verdict.k in mcp.bend); a
# plan card parks nothing and stays. A turn still running ends as
# interrupted and a delegated child's task ends with it (laws
# archive_*, interrupt_closes_approval, interrupt_keeps_plan,
# interrupt_ends_child_task, gone_closes_approval).

def Retire.hit(a: M.Ask, +th: String) -> Bool:
  match a:
    case M.Ask{_, t, kind, _, _, _, op, _}:
      Bool.and(op, Bool.and(String.eq(t, th), Bool.not(String.eq(kind, "plan"))))

def Retire.id(a: M.Ask) -> String:
  match a:
    case M.Ask{id, _, _, _, _, _, _, _}:
      id

def Retire.close(hit: Bool, +id: String, +now: Nat, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match hit:
    case True{}:
      M.AskClosed{id, "", now} <> rest
    case False{}:
      rest

def Retire.answer(hit: Bool, +id: String, rest: List<&2, Out>) -> List<&2, Out>:
  match hit:
    case True{}:
      AskAnswered{id, ""} <> rest
    case False{}:
      rest

# the open asks of th that wait on its process, closed unanswered
def Retire.asks(as: List<&2, M.Ask>, +th: String, +now: Nat) -> List<&2, M.Change>:
  match as:
    case Nil{}:
      Nil{}
    case +a <> t:
      Retire.close(Retire.hit(a, th), Retire.id(a), now, Retire.asks(t, th, now))

# the same asks' parked requests, answered empty
def Retire.answers(as: List<&2, M.Ask>, +th: String) -> List<&2, Out>:
  match as:
    case Nil{}:
      Nil{}
    case +a <> t:
      Retire.answer(Retire.hit(a, th), Retire.id(a), Retire.answers(t, th))

# a turn still running ends as interrupted, and its task with it
def Retire.turn(run: Bool, +s: M.State, +now: Nat, +th: String, st: Step) -> Step:
  match run:
    case True{}:
      Task.finish(s, now, th, Step.before([M.TurnChanged{th, M.Interrupted{}, now}], Nil{}, st))
    case False{}:
      st

# Stop: the running turn is interrupted (Stop.outs), its asks close
def Retire.stop(+s: M.State, +now: Nat, +th: String, os: List<&2, Out>) -> Step:
  Retire.turn(True{}, s, now, th, Step{Retire.asks(M.Asks.all(s), th, now),
    List.append(&2, Out, os, List.append(&2, Out, Stop.outs(Hub.provider(Hub.thread(s, th)), th, Hub.id("i", now, Hub.seq(s))), Retire.answers(M.Asks.all(s), th)))})

def Hub.interrupt.k(run: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String) -> Step:
  match run:
    case True{}:
      Retire.stop(s, now, thread, [Reply.ok(client, id)])
    case False{}:
      Step.outs([Reply.ok(client, id)])

def Hub.interrupt(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String) -> Step:
  Hub.interrupt.k(Hub.running(Hub.thread(s, thread)), s, now, client, id, thread)

# archive and delete kill the process whatever it was doing: its asks and
# background rows go, and a running turn ends
def Retire.archive(+s: M.State, +now: Nat, +th: String, base: Step) -> Step:
  Retire.turn(Hub.running(Hub.thread(s, th)), s, now, th,
    Step.also(Step.after(base, List.append(&2, M.Change, Retire.asks(M.Asks.all(s), th, now), Bg.clear(s, th, now))), Retire.answers(M.Asks.all(s), th)))

def Hub.request.k(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Step.outs([Fs{client, id, "add", J.Json.get_str(p, "path", "")}])
    case 1n:
      Step.reply(client, id, [M.ProjectRemoved{J.Json.get_str(p, "project", ""), now}])
    case 2n:
      Hub.thread_create(s, now, client, id, p)
    case 3n:
      Hub.turn.mode(Bool.or(String.is_empty(J.Json.get_str(p, "mode", "")), String.eq(J.Json.get_str(p, "mode", ""), "auto")), J.Json.get_str(p, "mode", ""),
        s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "text", ""), J.Json.get_str(p, "msg", ""))
    case 4n:
      Hub.interrupt(s, now, client, id, J.Json.get_str(p, "thread", ""))
    case 5n:
      Step.reply(client, id, [M.ThreadSettled{J.Json.get_str(p, "thread", ""), True{}, now}])
    case 6n:
      Step.reply(client, id, [M.ThreadUnsettled{J.Json.get_str(p, "thread", ""), now}])
    case 7n:
      Retire.archive(s, now, J.Json.get_str(p, "thread", ""), Step{[M.ThreadArchived{J.Json.get_str(p, "thread", ""), True{}, now}], [Reply.ok(client, id), AgentStop{J.Json.get_str(p, "thread", "")}]})
    case 8n:
      Step.reply(client, id, [M.ThreadArchived{J.Json.get_str(p, "thread", ""), False{}, now}])
    case 9n:
      Step.reply(client, id, [M.ThreadPinned{J.Json.get_str(p, "thread", ""), True{}, now}])
    case 10n:
      Step.reply(client, id, [M.ThreadPinned{J.Json.get_str(p, "thread", ""), False{}, now}])
    # a rename: the title trimmed; a blank one changes nothing
    case 11n:
      Step.reply(client, id, Rename.changes(J.Json.get_str(p, "thread", ""), String.trim(J.Json.get_str(p, "title", "")), now))
    case 12n:
      Retire.archive(s, now, J.Json.get_str(p, "thread", ""), Step{[M.ThreadDeleted{J.Json.get_str(p, "thread", ""), now}], [Reply.ok(client, id), AgentStop{J.Json.get_str(p, "thread", "")}, BotFx{"gone", J.Json.get_str(p, "thread", ""), "", ""}]})
    case 13n:
      Step.outs([Reply.ok(client, id), Watch{client, J.Json.get_str(p, "kind", ""), J.Json.get_str(p, "root", ""), J.Json.get_str(p, "path", "")}])
    case 14n:
      Hub.modes(s, now, client, id, p, Hub.thread(s, J.Json.get_str(p, "thread", "")))
    case 15n:
      Step.outs([Reply.ok(client, id), Upgrade{}])
    case 16n:
      Step.reply(client, id, [M.SettingSet{J.Json.get_str(p, "key", ""), J.Json.get_str(p, "value", ""), now}])
    case 17n:
      Step.outs([Reply.ok(client, id), KiCadInstall{}])
    case 18n:
      Hub.answer(s, now, client, id, J.Json.get_str(p, "id", ""), J.Json.get_str(p, "answer", ""))
    case 19n:
      Device.register(now, client, id, p)
    case 20n:
      Step.reply(client, id, [M.DeviceDropped{J.Json.get_str(p, "token", ""), now}])
    case 21n:
      Step.outs([PlotInfo{client, id, J.Json.get_str(p, "key", ""), Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(J.Json.get(p, "at"), "0")), 0n),
        Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(J.Json.get(p, "idx"), "0")), 0n)}])
    case 22n:
      Hub.resume(s, now, client, id, J.Json.get_str(p, "thread", ""))
    case 23n:
      Queue.op(0n, s, now, client, id, p)
    case 24n:
      Queue.op(1n, s, now, client, id, p)
    case 25n:
      Queue.op(2n, s, now, client, id, p)
    case 26n:
      Queue.op(3n, s, now, client, id, p)
    case 27n:
      Hub.fork(s, now, client, id, J.Json.get_str(p, "thread", ""))
    case 28n:
      Hub.back(s, now, client, id, J.Json.get_str(p, "thread", ""))
    case 29n:
      Hub.switch(s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "provider", ""))
    case _:
      Hub.more(C.Codec.pos(Hub.methods.git(), m), s, now, client, id, p, m)

# one client request {"id": n, "m": method, "p": params}
def Hub.request(+s: M.State, +now: Nat, +client: U32, +o: J.Json) -> Step:
  Hub.request.k(C.Codec.pos(Hub.methods(), J.Json.get_str(o, "m", "")), s, now, client,
    J.Json.as_raw(J.Json.get(o, "id"), "0"), J.Json.get_obj(o, "p"), J.Json.get_str(o, "m", ""))

def Hub.request_text.k(m: Maybe<&2, J.Json>, +s: M.State, +now: Nat, +client: U32) -> Step:
  match m:
    case Some{o}:
      Hub.request(s, now, client, o)
    case None{}:
      Step.outs([Reply.err(client, "0", "malformed request")])

def Hub.request_text(+s: M.State, +now: Nat, +client: U32, text: String) -> Step:
  Hub.request_text.k(J.Json.parse(text), s, now, client)

# one line of an agent's stdout
def Hub.agent_line(+s: M.State, +now: Nat, +thread: String, line: String) -> Step:
  Task.finish(s, now, thread, Queue.drain(s, now, thread, Ended.out(s, now, thread, Hub.agent_line.k(Bool.not(String.eq(Hub.provider(Hub.thread(s, thread)), "claude")), s, now, thread, line))))

# an agent process ended; a turn still running ends with it
def Hub.agent_gone(+s: M.State, +now: Nat, +thread: String, +code: U32) -> Step:
  Step.before(Nil{}, Retire.answers(M.Asks.all(s), thread),
    Step.after(Task.finish(s, now, thread, Queue.drain(s, now, thread, Ended.out(s, now, thread, Hub.agent_gone.k(Hub.running(Hub.thread(s, thread)), thread, now, code)))),
      List.append(&2, M.Change, Bg.clear(s, thread, now), Retire.asks(M.Asks.all(s), thread, now))))

def Step.outs_of(st: Step) -> List<&2, Out>:
  match st:
    case Step{_, os}:
      os

# Worktrees on the tick
# ---------------------
# A new thread whose worktree never came (the server restarted while
# making it) runs what waited for it in the project folder once the wait
# is over. A thread whose worktree was removed never does: its next
# message makes the worktree again.

def Wt.stale.k(stale: Bool, +s: M.State, +now: Nat, +th: String, rest: Step) -> Step:
  match stale:
    case True{}:
      Step.before(Queue.changes(Wt.start(s, now, th, False{})), Step.outs_of(Wt.start(s, now, th, False{})), rest)
    case False{}:
      rest

def Wt.stale(ts: List<&2, M.Thread>, +s: M.State, +now: Nat) -> Step:
  match ts:
    case Nil{}:
      Step.none()
    case +t <> rest:
      Wt.stale.k(Bool.and(Wt.stale.one(t, now), M.Queue.waiting(s, M.Thread.id(t))), s, now, M.Thread.id(t), Wt.stale(rest, s, now))

# Removing worktrees
# ------------------
# Each tick, the worktrees of threads put away long enough (or merged) are
# removed by the server (M.Worktree.drop), which reports thread.unrooted.

# how long a settled thread keeps its worktree: the "worktree.days"
# setting (1..90), else 3 days
def Hub.wt.window(+s: M.State) -> Nat:
  Nat.mul(Nat.max(1n, Nat.min(90n, Maybe.default(&2, Nat, Nat.read(M.Setting.get(s, "worktree.days", "3")), 3n))), 86400n)

def Drop.k(go: Bool, +s: M.State, +t: M.Thread, rest: List<&2, Out>) -> List<&2, Out>:
  match go:
    case True{}:
      Git{0, "", "wt_remove", M.Thread.id(t), Hub.worktree(t), Hub.project.root(Hub.project(s, Hub.thread_project(t))), M.Merge.branch(t)} <> rest
    case False{}:
      rest

def Drop.asks(ts: List<&2, M.Thread>, +s: M.State, +now: Nat, +w: Nat) -> List<&2, Out>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Drop.k(M.Worktree.drop(s, t, now, w), s, t, Drop.asks(rest, s, now, w))

# Scratch threads left alone long enough (M.Scratch.expired) are deleted,
# like thread.delete, and the server removes their folders
def Scratch.gone.k(go: Bool, +th: String, +now: Nat, rest: Step) -> Step:
  match go:
    case True{}:
      Step.before([M.ThreadDeleted{th, now}], [AgentStop{th}, BotFx{"gone", th, "", ""}, BotFx{"scratch-gone", th, "", ""}], rest)
    case False{}:
      rest

def Scratch.sweep(ts: List<&2, M.Thread>, +now: Nat, +w: Nat) -> Step:
  match ts:
    case Nil{}:
      Step.none()
    case +t <> rest:
      Scratch.gone.k(M.Scratch.expired(now, w, t), M.Thread.id(t), now, Scratch.sweep(rest, now, w))

def Step.join(a: Step, b: Step) -> Step:
  match a:
    case Step{cs, os}:
      Step.before(cs, os, b)

# every thread that should settle now, settled (a snoozed one never is);
# gh asked about due merges; worktrees put away long enough removed;
# stranded worktree waits run; expired scratch threads deleted
def Hub.tick(+s: M.State, +now: Nat) -> Step:
  match s:
    case M.State{ps, +ts, _, _, +tk, _, _, _, _, _, _}:
      Step.before(Hub.settle.go(Map.values(&2, M.Thread, ts), M.State.navs(s), Map.values(&2, M.Task, tk), now, Hub.settle.window(s)),
        List.append(&2, Out, Merge.asks(Map.values(&2, M.Project, ps), Map.values(&2, M.Thread, ts), s), Drop.asks(Map.values(&2, M.Thread, ts), s, now, Hub.wt.window(s))),
        Step.join(Wt.stale(Map.values(&2, M.Thread, ts), s, now), Scratch.sweep(Map.values(&2, M.Thread, ts), now, M.Scratch.window(s))))

# Asks keep their thread busy
# ---------------------------
# A thread with an open ask (an approval, a question, a plan) waits on the
# user: every step that opens or closes one also sets the thread's pending
# count to its open asks, so it never auto-settles meanwhile (laws
# ask_makes_pending, answer_clears_pending).

def Pend.one(hit: Bool, n: Nat) -> Nat:
  match hit:
    case True{}:
      1n+n
    case False{}:
      n

def Pend.open(as: List<&2, M.Ask>, +th: String) -> Nat:
  match as:
    case Nil{}:
      0n
    case M.Ask{_, t, _, _, _, _, op, _} <> rest:
      Pend.one(Bool.and(op, String.eq(t, th)), Pend.open(rest, th))

def Pend.thread(a: M.Ask) -> String:
  match a:
    case M.Ask{_, th, _, _, _, _, _, _}:
      th

def Pend.go(cs: List<&2, M.Change>, +before: M.State, +after: M.State) -> List<&2, M.Change>:
  match cs:
    case Nil{}:
      Nil{}
    case M.AskOpened{_, +th, _, _, _, _, +at} <> t:
      M.PendingChanged{th, Pend.open(M.Asks.all(after), th), at} <> Pend.go(t, before, after)
    case M.AskClosed{+id, _, +at} <> t:
      M.PendingChanged{Pend.thread(Ask.find(M.Asks.all(before), id)), Pend.open(M.Asks.all(after), Pend.thread(Ask.find(M.Asks.all(before), id))), at} <> Pend.go(t, before, after)
    case _ <> t:
      Pend.go(t, before, after)

# a step's changes with the pending counts they move
def Pend.fix(+s: M.State, +cs: List<&2, M.Change>) -> List<&2, M.Change>:
  List.append(&2, M.Change, cs, Pend.go(cs, s, M.State.replay(cs, s)))

# Recovery
# --------
# After a restart nothing the old process held is left: no agent runs, no
# request waits parked for an answer. Every turn still marked running ends
# as interrupted (a delegated child's task fails, and its parent hears of
# it) and every open ask closes unanswered (laws recover_*). Queued
# messages stay held until the user resumes them (queue.resume) or sends
# another, unless the turn carries on (Carry, below).

type Rec is Data:
  Rec{s: M.State, cs: List<&2, M.Change>, os: List<&2, Out>}

def Rec.add(r: Rec, st: Step) -> Rec:
  match r st:
    case Rec{s, cs, os} Step{+c2, o2}:
      Rec{M.State.replay(c2, s), List.append(&2, M.Change, cs, c2), List.append(&2, Out, os, o2)}

def Rec.note(+th: String, +now: Nat, +seq: Nat, +text: String) -> M.Change:
  M.ActivityLogged{th, Hub.id("r", now, seq), "error", "restart", text, now}

def Rec.turn.k(run: Bool, +s: M.State, +now: Nat, +th: String) -> Step:
  match run:
    case True{}:
      Task.finish(s, now, th, Step{[Rec.note(th, now, Hub.seq(s), "Backplane restarted before this turn finished"), M.TurnChanged{th, M.Interrupted{}, now}], Nil{}})
    case False{}:
      Step.none()

def Rec.turn(r: Rec, +now: Nat, +th: String) -> Rec:
  match r:
    case Rec{+s, cs, os}:
      Rec.add(Rec{s, cs, os}, Rec.turn.k(Hub.running(Hub.thread(s, th)), s, now, th))

def Rec.turns(ts: List<&2, String>, r: Rec, +now: Nat) -> Rec:
  match ts:
    case Nil{}:
      r
    case +th <> t:
      Rec.turns(t, Rec.turn(r, now, th), now)

def Rec.ask.k(a: M.Ask, +s: M.State, +now: Nat) -> Step:
  match a:
    case M.Ask{+id, +th, _, _, _, _, True{}, _}:
      Step{[M.AskClosed{id, "", now}, Rec.note(th, now, Hub.seq(s), "Backplane restarted: this request can no longer be answered")], Nil{}}
    case _:
      Step.none()

def Rec.ask(r: Rec, a: M.Ask, +now: Nat) -> Rec:
  match r:
    case Rec{+s, cs, os}:
      Rec.add(Rec{s, cs, os}, Rec.ask.k(a, s, now))

def Rec.asks(as: List<&2, M.Ask>, r: Rec, +now: Nat) -> Rec:
  match as:
    case Nil{}:
      r
    case a <> t:
      Rec.asks(t, Rec.ask(r, a, now), now)

def Rec.ids(ts: List<&2, M.Thread>) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      M.Thread.id(t) <> Rec.ids(rest)

def Rec.threads(s: M.State) -> List<&2, M.Thread>:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _, _}:
      Map.values(&2, M.Thread, ts)

def Rec.step(r: Rec) -> Step:
  match r:
    case Rec{_, cs, os}:
      Step{cs, os}

# no agent survives a restart: none of their subagents are at work
def Bg.clear.all(ids: List<&2, String>, +s: M.State, +now: Nat) -> List<&2, M.Change>:
  match ids:
    case Nil{}:
      Nil{}
    case +id <> t:
      List.append(&2, M.Change, Bg.clear(s, id, now), Bg.clear.all(t, s, now))

# what a hub that just started from its log does first
def Hub.recover(+s: M.State, +now: Nat) -> Step:
  Step.after(Rec.step(Rec.turns(Rec.ids(Rec.threads(s)), Rec.asks(M.Asks.all(s), Rec{s, Nil{}, Nil{}}, now), now)), Bg.clear.all(Rec.ids(Rec.threads(s)), s, now))

# Carrying on
# -----------
# With the "restart.continue" setting on (M.Carry.on), every turn the
# restart interrupted goes on: the thread is told to continue (with any
# message held in its queue), and its agent resumes its session. A thread
# whose newest entry is already that message made no progress since the
# last restart and is left stopped, so a turn that brings the hub down
# never loops (laws carry_*). Runs after Hub.recover, over the state from
# before it.

# whether the newest entry is the "restart" note Carry.k adds after its
# message (it is no progress)
def Carry.restart(es: List<&2, M.Entry>) -> Bool:
  match es:
    case M.Act{_, _, _, +kind, _, _} <> _:
      String.eq(kind, "restart")
    case _:
      False{}

# progress since the last carry: the newest entry, past restart notes, is
# anything but the continue message
def Carry.fresh.go(es: List<&2, M.Entry>, skip: Bool) -> Bool:
  match es skip:
    case Nil{} _:
      True{}
    case _ <> +t True{}:
      Carry.fresh.go(t, Carry.restart(t))
    case M.Msg{_, _, _, +text, _} <> _ False{}:
      Bool.not(String.eq(text, M.Carry.text()))
    case _ False{}:
      True{}

def Carry.fresh(+es: List<&2, M.Entry>) -> Bool:
  Carry.fresh.go(es, Carry.restart(es))

# an archived or deleted thread never carries on
def Carry.live(t: M.Thread) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, _, _, ar, _, _, _, _, _, _, _, _, _, _, _, _, de}:
      Bool.not(Bool.or(ar, de))

def Carry.k(go: Bool, +s: M.State, +now: Nat, +th: String) -> Step:
  match go:
    case True{}:
      Step.after(Hub.post(s, now, th, Hub.id("c", now, Hub.seq(s)), M.User{}, M.Carry.text()),
        [M.ActivityLogged{th, Hub.id("r", now, 1n+Hub.seq(s)), "info", "restart", "Continuing after the restart", now}])
    case False{}:
      Step.none()

def Carry.one(r: Rec, +before: M.State, +now: Nat, +th: String) -> Rec:
  match r:
    case Rec{+s, cs, os}:
      Rec.add(Rec{s, cs, os}, Carry.k(Bool.and(Bool.and(Hub.running(Hub.thread(before, th)), Carry.live(Hub.thread(before, th))), Carry.fresh(M.State.mine(before, th))), s, now, th))

def Carry.all(ts: List<&2, String>, r: Rec, +before: M.State, +now: Nat) -> Rec:
  match ts:
    case Nil{}:
      r
    case +th <> t:
      Carry.all(t, Carry.one(r, before, now, th), before, now)

def Carry.go(on: Bool, +before: M.State, +after: M.State, +now: Nat) -> Step:
  match on:
    case True{}:
      Rec.step(Carry.all(Rec.ids(Rec.threads(before)), Rec{after, Nil{}, Nil{}}, before, now))
    case False{}:
      Step.none()

# before: the state Hub.recover started from; after: once its step applied
def Hub.carry(+before: M.State, +after: M.State, +now: Nat) -> Step:
  Carry.go(M.Carry.on(after), before, after, now)

# Turn processes
# --------------
# A Codex or Grok turn is a process of its own. Its lines reach the hub
# tagged "<thread>\t<pid>", and only the process the hub last started for a
# thread is heard (a stopped one may still be talking). Thread ids hold no
# tab; an untagged line (Claude's) is always heard.

def Tag.of(+thread: String, +pid: U32) -> String:
  thread ++ "\t" ++ U32.show(pid)

def Tag.thread.k(ps: List<&2, String>) -> String:
  match ps:
    case th <> _:
      th
    case Nil{}:
      ""

def Tag.thread(+tag: String) -> String:
  Tag.thread.k(String.split(tag, '\t'))

def Tag.digit(+c: U32) -> Bool:
  Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

# a pid's digits as a number (None for anything else)
def Tag.num(s: String, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match s acc:
    case SNil{} _:
      acc
    case SCon{Chr{+c}, t} Some{+n}:
      Tag.num(t, Bool.pick(Maybe<&2, U32>, Tag.digit(c), Some{((n * 10 : U32) + (c - 48 : U32) : U32)}, None{}))
    case SCon{Chr{+c}, t} None{}:
      None{}

def Tag.num.k(empty: Bool, p: String) -> Maybe<&2, U32>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Tag.num(p, Some{0})

def Tag.pid.k(ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case _ <> +p <> Nil{}:
      Tag.num.k(String.is_empty(p), p)
    case _:
      None{}

# the process a tag names (None: untagged)
def Tag.pid(+tag: String) -> Maybe<&2, U32>:
  Tag.pid.k(String.split(tag, '\t'))

# whether a line from this tag is heard, given the pid the hub runs for
# its thread (None: none)
def Tag.heard(m: Maybe<&2, U32>, run: Maybe<&2, U32>) -> Bool:
  match m run:
    case None{} _:
      True{}
    case Some{+p} Some{+q}:
      U32.is_eq(p, q)
    case Some{_} None{}:
      False{}

def Hub.pending(t: M.Thread) -> Nat:
  match t:
    case M.Thread{_, _, _, _, _, _, pe, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      pe

# Scenarios the recovery laws are stated over: a Codex thread whose turn
# runs (or finished), with an approval open
def Rec.demo.base() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "p", "/p", 1n}, M.ThreadCreated{"t1", "p1", "x", M.Local{}, "", "", "codex", "", 1n}]

def Rec.demo(+st: M.TurnState) -> M.State:
  M.State.replay(List.append(&2, M.Change, Rec.demo.base(), [M.TurnChanged{"t1", st, 2n}, M.AskOpened{"a1", "t1", "approval", "Bash", "ls", "", 3n}]), M.State.empty())

def Rec.after(+s: M.State, +now: Nat) -> M.State:
  M.State.replay(Queue.changes(Hub.recover(s, now)), s)

def Carry.after.k(+before: M.State, +after: M.State, +now: Nat) -> M.State:
  M.State.replay(Queue.changes(Hub.carry(before, after, now)), after)

# the recovery scenario carried on: the state after both steps
def Carry.after(+s: M.State, +now: Nat) -> M.State:
  Carry.after.k(s, Rec.after(s, now), now)

# the running scenario with more changes on top (for the carry laws)
def Carry.demo(cs: List<&2, M.Change>) -> M.State:
  M.State.replay(cs, Rec.demo(M.Running{}))

# a thread "t1" on `provider` whose turn is in state st (for laws)
def Demo.state(+provider: String, +st: M.TurnState) -> M.State:
  M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}, M.ThreadCreated{"t1", "p1", "x", M.Local{}, "", "", provider, "", 1n}, M.TurnChanged{"t1", st, 2n}], M.State.empty())

# a Claude thread "t1" with session S1 and two messages, then switched
# to Codex, whose session became S2 (for laws)
def Demo.switched() -> M.State:
  M.State.replay([M.SessionSet{"t1", "S1", 3n}, M.MessagePosted{"t1", "m1", M.User{}, "hi", 3n}, M.MessagePosted{"t1", "m2", M.Assistant{}, "hello", 3n},
    M.ProviderSet{"t1", "codex", "", 4n}, M.SessionSet{"t1", "S2", 5n}], Demo.state("claude", M.Completed{}))

# a step applied as the server does (with the pending counts it moves)
def Retire.after(+s: M.State, st: Step) -> M.State:
  M.State.replay(Pend.fix(s, Queue.changes(st)), s)

# thread.archive (or thread.delete: i 12n) of "t1" (for laws)
def Retire.request(i: Nat, +s: M.State) -> Step:
  Hub.request.k(i, s, 9n, 0, "r", J.Json.obj([J.KV{"thread", J.Str{"t1"}}]), "")

def Retire.task.k(m: Maybe<&2, M.Task>) -> Bool:
  match m:
    case Some{M.Task{_, _, _, _, st, _, _, _, _}}:
      M.TaskState.terminal(st)
    case None{}:
      False{}

# whether the task "t1" works on has ended (for laws)
def Retire.task(+s: M.State) -> Bool:
  Retire.task.k(Task.of_child(s, "t1"))

# the running scenario with an open plan card and a task t0 gave t1
def Retire.demo() -> M.State:
  M.State.replay([M.ThreadCreated{"t0", "p1", "x", M.Local{}, "", "", "codex", "", 1n}, M.TaskDelegated{"k1", "t0", "t1", 1n, "codex", "", 2n},
    M.AskOpened{"a2", "t1", "plan", "", "plan", "", 3n}], Rec.demo(M.Running{}))
