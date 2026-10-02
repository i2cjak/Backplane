import Base
import ./host.bend as H
import ./proc.bend as P
import ../core/json.bend as J
import ../core/utf8.bend as U
import ../core/http.bend as W
import ../core/model.bend as M
import ../core/codec.bend as C
import ../core/hub.bend as B
import ../core/prompt.bend as Q
import ../core/mcp.bend as MC
import ./update.bend as UP
import ../core/version.bend as VR
import ./kicad.bend as K
import ./browser.bend as BR
import ../core/acp.bend as AC
import ../core/cbor.bend as CB
import ./push.bend as PU
import ./park.bend as PK
import ./git.bend as GT
import ./gh.bend as GH
import ./term.bend as TM
import ./plot.bend as PV
import ../core/agent.bend as AG
import ../core/tailnet.bend as TN
import ../core/images.bend as IM
import ../core/links.bend as LK
import ../core/attach.bend as ATT
import ../core/attach.bend as AT
import ../core/sha1.bend as SH
import ../core/boot.bend as BT
import ../core/store.bend as ST
import ./botnet.bend as BN
import ../core/far.bend as FR
import ../core/client.bend as UC
import ../core/bothub.bend as BH
import ../core/bot.bend as BO
import ../core/space.bend as SPC
import ../core/refs.bend as RF
import ../core/sign.bend as SG
import ./google.bend as GS
import ../core/google.bend as GG
import ../core/ring.bend as RG
import ./voice.bend as VO
import ./apikeys.bend as AKS
import ./perf.bend as PS
import ./freecad.bend as FC
import ../core/perf.bend as PF
import ../core/semver.bend as SV
import ../core/desk.bend as DK
import ../core/notice.bend as NO
import ../core/hist.bend as HI
import ../core/emb.bend as EM
import ../core/cmds.bend as CM
import ../core/outbox.bend as OB
import ../core/live.bend as LV
import ../core/contain.bend as CN

# The server. One hub computation owns the read model and the event log;
# every connection and agent process is its own computation and talks to
# the hub over channels. The hub runs the pure decider (core/hub.bend) and
# carries out the effects it answers.

# what a connection's writer sends
type Wire is Data:
  WText{text: String}
  WPong{payload: List<&2, U32>}
  # a message already encoded (a board's plot: never parsed again)
  WBin{cbor: List<&2, U32>}
  WClose{}
  # the hub's own window: the read model itself, with the log message's
  # head (no items), in place of the log as text
  WState{st: M.State, head: String}
  # a message made of a log's lines: head, the lines joined by ",", tail;
  # put together by the writer, off the hub (a join's chunk)
  WItems{head: String, items: List<&2, String>, tail: String, ends: Bool}

type Msg is Data:
  Announce{text: String}
  Mcp{thread: String, body: String, reply: Chan(String)}
  # gen: the connection's generation (a socket's id; the window's client 0
  # joins again under a new one); sock: a raw descriptor on its socket (0
  # for none), shut at once when it falls too far behind (core/outbox.bend)
  Join{client: U32, out: Chan(Wire), since: Nat, origin: String, gen: U32, sock: U32}
  # the window in this process: it takes the read model, not the log
  JoinHere{client: U32, out: Chan(Wire), gen: U32}
  # a client's writer has put n frames (bytes bytes) out in all
  Drained{client: U32, gen: U32, n: Nat, bytes: Nat}
  # the next chunk of a joining client's log (OB.Cr: boot)
  JoinMore{client: U32, gen: U32}
  # a client pinged (its reader passes on at most one a second)
  Ping{client: U32, payload: List<&2, U32>}
  Leave{client: U32}
  Rpc{client: U32, text: String}
  AgentLine{thread: String, line: String}
  AgentGone{thread: String, code: U32, pid: U32}
  Tick{}
  # a Codex or Grok turn's KiCad files, read off the hub: the panel opens
  # (Hub.auto) when they arrive
  AutoView{thread: String, fs: K.Files}
  # a Claude process started (its pid) or could not, by generation: the
  # hub registered the agent first, with a placeholder (pid 0)
  ClaudePid{thread: String, pid: U32, gen: String}
  ClaudeFail{thread: String, gen: String, msg: String}
  # every 15 s: a heartbeat for every client (Alive.due)
  Heart{}
  Push{client: U32, text: String}
  # a message for one client, already CBOR
  PushBin{client: U32, cbor: List<&2, U32>}
  TermOut{thread: String, data: List<&2, U32>}
  # a chat terminal's snapshot for a client (TM.Et.all(): every client)
  TermTo{client: U32, key: String, cols: U32, rows: U32, data: List<&2, U32>}
  # a line for a thread's agent built off the hub (a message with images)
  AgentWrite{thread: String, line: String, gen: String}
  # time to look for a release on the update channel
  UpdateCheck{}
  ModelsFound{models: String, text: String}
  MachinesFound{machines: String}
  # the tailnet listener is up: the pairing link clients show in Settings
  LinkFound{link: String}
  # a Codex or Grok turn's process started: the one the hub now hears (and
  # stops) for the thread; its lines come tagged (B.Tag)
  TurnPid{thread: String, pid: U32, input: Chan(String), gen: String}
  # a turn's process exited (tagged)
  TurnDone{tag: String}
  # the hub just started from its log (B.Hub.recover)
  Recover{}
  # changes a job off the hub made (a bot's home folder, a linked machine)
  Commit{changes: List<&2, M.Change>}
  # the minute tick for bots: routines and the linked machines' bots, with
  # this machine's UTC offset as `date +%z` prints it
  BotTick{tz: String}
  # the bots on linked machines (a JSON array)
  BotsFound{peer: String, url: String, result: Maybe<&2, List<&2, J.Json>>}
  # one peer, or every peer when empty; the hub coalesces active fetches
  BotsRefresh{peer: String}
  # a request for bots' routes (a webhook, a linked machine, a bot's
  # screen, Google's sign-in redirect); the reply is the whole response
  # (`ct` its content type; `raw` its bytes, kept only for a form with a
  # recording, which is not text)
  BotHttp{kind: String, arg: String, peer: String, ts: String, sig: String, gh: String, delivery: String, body: String, ct: String, raw: List<&2, U32>, reply: Chan(List<&2, U32>)}
  # the same, its signature checked off the hub: `key` is its replay key
  # ("" when it is not genuine); `me` is this machine's name
  BotVerified{kind: String, arg: String, key: String, body: String, me: String, reply: Chan(List<&2, U32>)}
  # a browser page has a new frame: {"t":"shot",...} for every client
  Shot{text: String}
  # a bot's new project, approved by the person, its folder made and
  # resolved: the hub adds it and answers the tool call (`id` as JSON)
  NewProject{thread: String, root: String, name: String, id: String, reply: Chan(String)}
  # a phone's upload (POST /attach) asks where a thread's attachments go
  AttDir{thread: String, reply: Chan(String)}
  # threads elsewhere (far.bend): this hub's feed made from its log; a
  # push ended; a page pulled (code 0: no answer); a request sent on for
  # a client answered; a mirror read back from disk; the linked machines
  # that answered the minute's directory (one id a line)
  FarFeed{lines: List<&2, FR.Line>, epoch: String}
  FarPushed{link: String, ok: Bool, to: Nat}
  # a failed push's backoff ended
  FarResend{link: String}
  FarPulled{link: String, since: Nat, code: Nat, body: String}
  FarReplied{client: U32, id: String, link: String, code: Nat, body: String}
  FarLoaded{link: String, name: String, text: String}
  FarHere{answered: String}
  # a pull to try again (the other hub was still making its feed)
  FarRetry{link: String}
  # a bot's answer to a person elsewhere, captured at its turn's end
  # (hub.bend's BotReply): sent and logged now
  Replied{thread: String, to: String, text: String}
  # time to start the threads a restart left marked (B.Rec.release): after
  # each turn's end and each minute
  Release{}
  # a Codex or Grok turn's process could not start: its failure line, heard
  # only from the thread's current generation (B.Gen.*)
  SpawnFailed{thread: String, gen: String, line: String}
  # an agent process exited (its watcher saw it; the reader ends within 2 s)
  AgentExited{thread: String, gen: String, code: U32}
  # time to note running turns that went quiet (each minute)
  Silence{}
  # every few seconds: progress lines held back land (Hub.beat)
  Beat{}
  # watched work (core's Watch.*): a work_run launched; what proves the
  # work is the same; its end
  WatchLaunched{thread: String, id: String}
  WatchIdent{thread: String, id: String, ident: String}
  WatchEnded{thread: String, id: String, status: String, detail: String}
  # a message from the hub's own inbox (agents' lines, jobs, its own
  # posts), passed on by Bulk.fwd behind a token (Bulk.*)
  Bulk{m: Msg}

# remote access: also listen on the tailnet, serve HTTPS through
# `tailscale serve`, and the token remote clients must present
type Net is Data:
  Net{tailnet: Bool, https: Bool, token: String, models: String, mtext: String, rt: K.Rt, br: Maybe<&2, Chan(BR.BMsg)>, pk: Maybe<&2, Chan(PK.PMsg)>, tm: Maybe<&2, Chan(TM.TMsg)>, machines: String, pv: Maybe<&2, Chan(PV.PMsg)>, bn: BN.Bn, managed: Bool, link: String, freecad: String}

type Cfg is Data:
  Cfg{home: String, web: String, host: String, port: U32, prompt: String, dirs: List<&2, String>, version: String, net: Net}

type Client is Data:
  # look: what the client last said it shows (desk.look; core/desk.bend);
  # cr: what it was offered and has taken, and whether it still takes its
  # log (core/outbox.bend); sock: a raw descriptor on its socket (0: none)
  Client{id: U32, out: Chan(Wire), look: DK.Look, cr: OB.Cr, sock: U32}

# what the hub keeps about a Claude process's work (a one-element list; a
# Codex or Grok turn's process has none): its command ledger
# (core/cmds.bend) and the messages held behind one whose images are still
# being read; live, heard, gen and quiet are for streamed text, silence
# and spawn generations
type ARun is Data:
  ARun{cmds: CM.Cmds, held: List<&2, CM.Held>, live: List<&2, String>, heard: Nat, gen: String, quiet: Bool, prog_at: Nat, prog_last: List<&2, String>}

type Agent is Data:
  Agent{thread: String, input: Chan(String), pid: U32, key: String, run: List<&2, ARun>}

def ARun.new() -> ARun:
  ARun{CM.Cmds.new(), Nil{}, Nil{}, 0n, "", False{}, 0n, Nil{}}

# a Claude process of generation gen (B.Gen.*)
def ARun.new.g(+gen: String) -> ARun:
  ARun{CM.Cmds.new(), Nil{}, Nil{}, 0n, gen, False{}, 0n, Nil{}}

# the same, started (heard last) at now
def ARun.new.h(+gen: String, +now: Nat) -> ARun:
  ARun{CM.Cmds.new(), Nil{}, Nil{}, now, gen, False{}, 0n, Nil{}}

def Proc.kill.k(ok: Bool, +pid: U32, +sig: U32) -> IO(Unit):
  match ok:
    case True{}:
      H.Proc.kill(pid, sig)
    case False{}:
      IO.pure(Unit, Unit{})

# a signal to a process; never to pid 0 or 1 (B.Proc.kill.ok): an agent
# not started yet is a placeholder with pid 0, and kill(0) would stop the
# hub's own process group
def Proc.kill(+pid: U32, +sig: U32) -> IO(Unit):
  Proc.kill.k(B.Proc.kill.ok(pid), pid, sig)

def Fuel.forever() -> Nat:
  U32.to_nat(4294967295)

def Log.info(+s: String) -> IO(Unit):
  PS.Log.info("hub", s)

def Now.nat() -> IO(Nat):
  do IO<Nat>:
    t : U32 <- H.Clock.epoch()
    return U32.to_nat(t)

# Files
# -----

def Files.read.done(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  do IO<List<&2, U32>>:
    File.close(f)
    return Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{})

def Files.read.sized(r: File & Result<&1, &1, U32 & String, U32>) -> IO(List<&2, U32>):
  (f, res) = r
  IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, List<&2, U32>,
    File.read_bytes(f, U32.max(Result.default(&1, &1, U32 & String, U32, res, 0), 1)), Files.read.done)

def Files.read.opened(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, U32>):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, List<&2, U32>, File.size(f), Files.read.sized)
    case Fail{_}:
      IO.pure(List<&2, U32>, Nil{})

# a whole file's bytes, or [] when it cannot be read
def Files.read(path: String) -> IO(List<&2, U32>):
  IO.bind(Result<&1, &1, U32 & String, File>, List<&2, U32>, File.open(path, "r"), Files.read.opened)

def Files.text(path: String) -> IO(String):
  do IO<String>:
    bs : List<&2, U32> <- Files.read(path)
    return U.Utf8.decode(bs)

# Agent containment (core/contain.bend)
# -------------------------------------
# An agent starts in a scope of its own with a memory limit. /proc files
# report no size, so the machine's memory is read by a tiny `head`.

def Ctn.mem.of(r: P.Ran) -> String:
  match r:
    case P.Ran{_, out}:
      out

def Ctn.limit(+st: M.State) -> IO(String):
  do IO<String>:
    r : P.Ran <- P.Proc.run("head", ["-n", "1", "/proc/meminfo"], "/")
    return CN.Contain.limit(Ctn.mem.of(r), M.Setting.get(st, "agent.memory", ""), M.Setting.get(st, "agent.memory.mb", ""))

# "" unless the scope's Result was an out-of-memory kill
def Ctn.why.text(+res: String, +code: U32, +lim: String) -> String:
  Bool.pick(String, CN.Contain.oom(String.trim(res)), CN.Contain.exit_text(code, String.trim(res), lim), "")

# why an agent that a signal ended ended: its scope says (a scope that
# failed stays until read, then it is reset); "" when it does not say
def Ctn.why.k(ask: Bool, +st: M.State, +thread: String, +gen: String, +code: U32) -> IO(String):
  match ask:
    case True{}:
      do IO<String>:
        r : P.Ran <- P.Proc.run("timeout", CN.Contain.show.args(CN.Contain.unit(thread, gen)), "/")
        x : P.Ran <- P.Proc.run("timeout", CN.Contain.reset.args(CN.Contain.unit(thread, gen)), "/")
        +lim : String <- Ctn.limit(st)
        return Ctn.why.text(Ctn.mem.of(r), code, lim)
    case False{}:
      IO.pure(String, "")

def Ctn.why(ask: Bool, +st: M.State, +thread: String, +gen: String, +code: U32) -> IO(String):
  Ctn.why.k(ask, st, thread, gen, code)

def Ctn.spawn.k(found: Bool, limit: String, thread: String, gen: String, cmd: String, args: List<&2, String>, cwd: String) -> IO(Result<&1, &1, U32 & String, U32 & Socket>):
  match found:
    case True{}:
      H.Proc.spawn("sh", CN.Contain.argv(limit, CN.Contain.unit(thread, gen), cmd, args), cwd, 0)
    case False{}:
      H.Proc.spawn(cmd, args, cwd, 0)

def Ctn.found(r: P.Ran) -> Bool:
  match r:
    case P.Ran{code, _}:
      U32.is_eq(code, 0)

# cmd with args, in its own scope; a program that is not there fails to
# spawn as it always did (its turn says it could not start)
def Ctn.spawn(+limit: String, +thread: String, +gen: String, +cmd: String, +args: List<&2, String>, +cwd: String) -> IO(Result<&1, &1, U32 & String, U32 & Socket>):
  do IO<Result<&1, &1, U32 & String, U32 & Socket>>:
    r : P.Ran <- P.Proc.run("sh", ["-c", "command -v \"$1\" >/dev/null 2>&1", "sh", cmd], "/")
    Ctn.spawn.k(Ctn.found(r), limit, thread, gen, cmd, args, cwd)

# Event log
# ---------

# read in one pass by src/core/store.bend (ST.Store.load)
def Store.lines.k(r: U.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def Store.lines(bs: List<&2, U32>) -> List<&2, String>:
  Store.lines.k(U.Lines.feed(U.Lines.new(), bs))

def Store.path(+home: String) -> String:
  home ++ "/events.jsonl"

# Clients and agents
# ------------------

def Clients.hit(cs: List<&2, Client>, +id: U32) -> Bool:
  match cs:
    case Client{i, _, _, _, _} <> _:
      U32.is_eq(i, id)
    case Nil{}:
      False{}

def Clients.find(cs: List<&2, Client>, hit: Bool, +id: U32) -> Maybe<&2, Client>:
  match cs hit:
    case c <> _ True{}:
      Some{c}
    case _ <> +t False{}:
      Clients.find(t, Clients.hit(t, id), id)
    case _ _:
      None{}

def Clients.get(+cs: List<&2, Client>, +id: U32) -> Maybe<&2, Client>:
  Clients.find(cs, Clients.hit(cs, id), id)

def Clients.drop.k(same: Bool, c: Client, rest: List<&2, Client>) -> List<&2, Client>:
  match same:
    case True{}:
      rest
    case False{}:
      c <> rest

def Clients.drop(cs: List<&2, Client>, +id: U32) -> List<&2, Client>:
  match cs:
    case Nil{}:
      Nil{}
    case Client{+i, o, l, r, k} <> t:
      Clients.drop.k(U32.is_eq(i, id), Client{i, o, l, r, k}, Clients.drop(t, id))

def Clients.look.k(same: Bool, c: Client, +look: DK.Look) -> Client:
  match same c:
    case True{} Client{i, o, _, r, k}:
      Client{i, o, look, r, k}
    case False{} _:
      c

# a client's new look
def Clients.look(cs: List<&2, Client>, +id: U32, +look: DK.Look) -> List<&2, Client>:
  match cs:
    case Nil{}:
      Nil{}
    case Client{+i, o, l, r, k} <> t:
      Clients.look.k(U32.is_eq(i, id), Client{i, o, l, r, k}, look) <> Clients.look(t, id, look)

def Clients.looks(cs: List<&2, Client>) -> List<&2, DK.At>:
  match cs:
    case Nil{}:
      Nil{}
    case Client{i, _, l, _, _} <> t:
      DK.At{i, l} <> Clients.looks(t)

def Clients.cr.k(same: Bool, c: Client, +gen: U32, +n: Nat, +b: Nat) -> Client:
  match same c:
    case True{} Client{i, o, l, r, k}:
      Client{i, o, l, OB.Cr.drained(r, gen, n, b), k}
    case False{} _:
      c

# a writer's report on a client's credit (OB.Cr.drained)
def Clients.cr(cs: List<&2, Client>, +id: U32, +gen: U32, +n: Nat, +b: Nat) -> List<&2, Client>:
  match cs:
    case Nil{}:
      Nil{}
    case Client{+i, o, l, r, k} <> t:
      Clients.cr.k(U32.is_eq(i, id), Client{i, o, l, r, k}, gen, n, b) <> Clients.cr(t, id, gen, n, b)

def Clients.sockets(cs: List<&2, Client>) -> Nat:
  match cs:
    case Nil{}:
      0n
    case Client{_, _, _, r, _} <> t:
      Nat.add(Bool.pick(Nat, OB.Cr.native(r), 0n, 1n), Clients.sockets(t))

# whether a broadcast is worth encoding once on the hub (two or more
# socket clients; a single one's writer encodes it, off the hub)
def Clients.socket(cs: List<&2, Client>) -> Bool:
  Nat.is_ge(Clients.sockets(cs), 2n)

def Clients.add(m: Maybe<&2, Client>, cs: List<&2, Client>) -> List<&2, Client>:
  match m:
    case Some{c}:
      c <> cs
    case None{}:
      cs

def Agents.hit(as: List<&2, Agent>, +th: String) -> Bool:
  match as:
    case Agent{t, _, _, _, _} <> _:
      String.eq(t, th)
    case Nil{}:
      False{}

def Agents.find(as: List<&2, Agent>, hit: Bool, +th: String) -> Maybe<&2, Agent>:
  match as hit:
    case a <> _ True{}:
      Some{a}
    case _ <> +t False{}:
      Agents.find(t, Agents.hit(t, th), th)
    case _ _:
      None{}

def Agents.get(+as: List<&2, Agent>, +th: String) -> Maybe<&2, Agent>:
  Agents.find(as, Agents.hit(as, th), th)

def Agents.drop.k(same: Bool, a: Agent, rest: List<&2, Agent>) -> List<&2, Agent>:
  match same:
    case True{}:
      rest
    case False{}:
      a <> rest

def Agents.drop(as: List<&2, Agent>, +th: String) -> List<&2, Agent>:
  match as:
    case Nil{}:
      Nil{}
    case Agent{+t, i, p, k, r} <> rest:
      Agents.drop.k(String.eq(t, th), Agent{t, i, p, k, r}, Agents.drop(rest, th))

def Agents.run.k(m: Maybe<&2, Agent>) -> Maybe<&2, ARun>:
  match m:
    case Some{Agent{_, _, _, _, r <> _}}:
      Some{r}
    case _:
      None{}

# a Claude process's run (None: none, or a Codex or Grok turn's)
def Agents.run(+as: List<&2, Agent>, +th: String) -> Maybe<&2, ARun>:
  Agents.run.k(Agents.get(as, th))

def Agents.gen.k(m: Maybe<&2, Agent>) -> String:
  match m:
    case Some{Agent{_, _, _, _, ARun{_, _, _, _, g, _, _, _} <> _}}:
      g
    case Some{Agent{_, _, _, +k, Nil{}}}:
      B.Gen.of(k)
    case None{}:
      ""

# the generation of the thread's agent ("" for none)
def Agents.gen(+as: List<&2, Agent>, +th: String) -> String:
  Agents.gen.k(Agents.get(as, th))

def Agents.with.k(same: Bool, a: Agent, +r: ARun) -> Agent:
  match same a:
    case True{} Agent{t, i, p, k, _}:
      Agent{t, i, p, k, [r]}
    case False{} _:
      a

# the thread's agent with its run replaced
def Agents.with(as: List<&2, Agent>, +th: String, +r: ARun) -> List<&2, Agent>:
  match as:
    case Nil{}:
      Nil{}
    case Agent{+t, i, p, k, rs} <> rest:
      Agents.with.k(String.eq(t, th), Agent{t, i, p, k, rs}, r) <> Agents.with(rest, th, r)

# Offering frames
# ---------------
# Every frame for a client goes through Wire.offer: it is counted, and a
# client too far behind (OB.Cr.over) is dropped at once (its socket shut
# through the raw descriptor, so its writer stops; its channel closed), so
# the channel never fills and no send of the hub's waits on a client.
# Socket clients get a message as CBOR (encoded once for all of them),
# the window in this process as text.

def Wire.cut(c: Client) -> IO(Unit):
  match c:
    case Client{i, o, _, _, k}:
      do IO<Unit>:
        PS.Perf.add("hub.client_drop", 1)
        Log.info("client " ++ U32.show(i) ++ " fell too far behind: dropped (it reconnects from its sequence)")
        H.Fd.shut(k)
        Chan.close(Wire, o)

def Wire.kept(over: Bool, c: Client) -> IO(Maybe<&2, Client>):
  match over:
    case True{}:
      IO.bind(Unit, Maybe<&2, Client>, Wire.cut(c), _ => IO.pure(Maybe<&2, Client>, None{}))
    case False{}:
      IO.pure(Maybe<&2, Client>, Some{c})

def Wire.offer.k(c: Client, w: Wire, +n: Nat) -> IO(Maybe<&2, Client>):
  match c:
    case Client{i, +o, l, +r, k}:
      do IO<Maybe<&2, Client>>:
        ok : Bool <- Chan.send(Wire, o, w)
        +r2 : OB.Cr = OB.Cr.offer(r, Bool.pick(Nat, OB.Cr.native(r), 0n, n))
        Wire.kept(OB.Cr.over(r2), Client{i, o, l, r2, k})

# one frame of n bytes for a client: kept, or None when it was dropped
def Wire.offer(c: Client, w: Wire, +n: Nat) -> IO(Maybe<&2, Client>):
  Wire.offer.k(c, w, n)

def Wire.native(c: Client) -> Bool:
  match c:
    case Client{_, _, _, r, _}:
      OB.Cr.native(r)

def Wire.offer.bs(c: Client, +bs: List<&2, U32>) -> IO(Maybe<&2, Client>):
  Wire.offer(c, WBin{bs}, List.length(&2, U32, bs))

# (a message for one client is encoded by its writer, off the hub)
def Wire.text.k(native: Bool, c: Client, +text: String) -> IO(Maybe<&2, Client>):
  match native:
    case True{}:
      Wire.offer(c, WText{text}, 0n)
    case False{}:
      Wire.offer(c, WText{text}, String.length(text))

# a message (JSON text) for one client
def Wire.text(+c: Client, +text: String) -> IO(Maybe<&2, Client>):
  Wire.text.k(Wire.native(c), c, text)

def Wire.text.m(m: Maybe<&2, Client>, +text: String) -> IO(Maybe<&2, Client>):
  match m:
    case Some{c}:
      Wire.text(c, text)
    case None{}:
      IO.pure(Maybe<&2, Client>, None{})

# the same, skipped when empty
def Wire.text.if(empty: Bool, m: Maybe<&2, Client>, +text: String) -> IO(Maybe<&2, Client>):
  match empty:
    case True{}:
      IO.pure(Maybe<&2, Client>, m)
    case False{}:
      Wire.text.m(m, text)

def Client.is(c: Client, +id: U32) -> Bool:
  match c:
    case Client{i, _, _, _, _}:
      U32.is_eq(i, id)

def Wire.to.one(hit: Bool, text: Bool, c: Client, w: Wire, +n: Nat, +t: String) -> IO(Maybe<&2, Client>):
  match hit text:
    case True{} True{}:
      Wire.text(c, t)
    case True{} False{}:
      Wire.offer(c, w, n)
    case False{} _:
      IO.pure(Maybe<&2, Client>, Some{c})

def Wire.to.go(cs: List<&2, Client>, +id: U32, +w: Wire, +n: Nat, +text: Bool, +t: String) -> IO(List<&2, Client>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, Client>, Nil{})
    case +c <> rest:
      do IO<List<&2, Client>>:
        m : Maybe<&2, Client> <- Wire.to.one(Client.is(c, id), text, c, w, n, t)
        r : List<&2, Client> <- Wire.to.go(rest, id, w, n, text, t)
        return Clients.add(m, r)

# a message (JSON text) for the client with this id
def Wire.to(+cs: List<&2, Client>, +id: U32, +text: String) -> IO(List<&2, Client>):
  Wire.to.go(cs, id, WClose{}, 0n, True{}, text)

# a frame as it is (a plot's CBOR, a pong) for the client with this id
def Wire.to.raw(+cs: List<&2, Client>, +id: U32, w: Wire, +n: Nat) -> IO(List<&2, Client>):
  Wire.to.go(cs, id, w, n, False{}, "")

def Wire.all.bin(once: Bool, c: Client, +text: String, +bs: List<&2, U32>, +n: Nat) -> IO(Maybe<&2, Client>):
  match once:
    case True{}:
      Wire.offer(c, WBin{bs}, n)
    case False{}:
      Wire.offer(c, WText{text}, String.length(text))

# (n = 0: the message was not encoded, as for a single socket client: its
# writer encodes it)
def Wire.all.as(native: Bool, c: Client, +text: String, +bs: List<&2, U32>, +n: Nat) -> IO(Maybe<&2, Client>):
  match native:
    case True{}:
      Wire.offer(c, WText{text}, 0n)
    case False{}:
      Wire.all.bin(Nat.is_gt(n, 0n), c, text, bs, n)

def Wire.booting(c: Client) -> Bool:
  match c:
    case Client{_, _, _, r, _}:
      OB.Cr.boot(r)

def Wire.behind(c: Client) -> Bool:
  match c:
    case Client{_, _, _, r, _}:
      OB.Cr.behind(r)

# how a message goes to every client: kind 0 to all; 1 log changes (a
# client taking its log gets them with the rest of it, and one too far
# behind goes back to taking it, from `at`, Cr.catch); 2 streamed text
# (none for a client taking its log: the live text comes with its end)
type All is Data:
  All{kind: Nat, at: Nat, fl: Nat, inbox: List<&2, Chan(Msg)>}

# A message the hub sends itself. The hub fiber is the inbox's only
# reader, so a send into a full inbox (4096 slots) would park it for good:
# the send runs on a fiber of its own and the hub goes on
def Self.post.go(+inbox: Chan(Msg), m: Msg) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, m)
    return Unit{}

def Self.post(+inbox: Chan(Msg), m: Msg) -> IO(Unit):
  IO.spawn(Unit, Self.post.go(inbox, m))

def Self.post.wait(+inbox: Chan(Msg), m: Msg, +ms: U32) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(ms)
    Self.post.go(inbox, m)

# the same a moment later: the next chunk of a join waits a couple of
# milliseconds, so the event loop polls the sockets between chunks and a
# request is read while a long log goes out
def Self.post.later(+inbox: Chan(Msg), m: Msg) -> IO(Unit):
  IO.spawn(Unit, Self.post.wait(inbox, m, 2))

def Wire.post(qs: List<&2, Chan(Msg)>, +m: Msg) -> IO(Unit):
  match qs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case +q <> t:
      do IO<Unit>:
        Self.post(q, m)
        Wire.post(t, m)

def Wire.catch(c: Client, +a: All) -> IO(Maybe<&2, Client>):
  match c a:
    case Client{+i, o, l, +r, k} All{_, +at, +fl, +qs}:
      do IO<Maybe<&2, Client>>:
        Wire.post(qs, JoinMore{i, OB.Cr.gen(r)})
        return Some{Client{i, o, l, OB.Cr.wait.set(OB.Cr.catch(r, at, fl), True{}), k}}

def Wire.all.k3(behind: Bool, +c: Client, +a: All, +text: String, +bs: List<&2, U32>, +n: Nat) -> IO(Maybe<&2, Client>):
  match behind:
    case True{}:
      Wire.catch(c, a)
    case False{}:
      Wire.all.as(Wire.native(c), c, text, bs, n)

def Wire.all.k2(kind: Nat, booting: Bool, +c: Client, +a: All, +text: String, +bs: List<&2, U32>, +n: Nat) -> IO(Maybe<&2, Client>):
  match kind booting:
    case 0n _:
      Wire.all.as(Wire.native(c), c, text, bs, n)
    case _ True{}:
      IO.pure(Maybe<&2, Client>, Some{c})
    case 1n False{}:
      Wire.all.k3(Wire.behind(c), c, a, text, bs, n)
    case _ False{}:
      Wire.all.as(Wire.native(c), c, text, bs, n)

def All.kind(+a: All) -> Nat:
  match a:
    case All{k, _, _, _}:
      k

def Wire.all.go(cs: List<&2, Client>, +text: String, +bs: List<&2, U32>, +n: Nat, +a: All) -> IO(List<&2, Client>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, Client>, Nil{})
    case +c <> t:
      do IO<List<&2, Client>>:
        m : Maybe<&2, Client> <- Wire.all.k2(All.kind(a), Wire.booting(c), c, a, text, bs, n)
        rest : List<&2, Client> <- Wire.all.go(t, text, bs, n, a)
        return Clients.add(m, rest)

def Wire.all.bs(cs: List<&2, Client>, +text: String, +bs: List<&2, U32>, +a: All) -> IO(List<&2, Client>):
  Wire.all.go(cs, text, bs, List.length(&2, U32, bs), a)

def Wire.all.k(sock: Bool, cs: List<&2, Client>, +text: String, +a: All) -> IO(List<&2, Client>):
  match sock:
    case True{}:
      Wire.all.bs(cs, text, W.Ws.cbor.bytes(text), a)
    case False{}:
      Wire.all.go(cs, text, Nil{}, 0n, a)

# a message for every client (encoded once); the clients still there
def Wire.all.of(+cs: List<&2, Client>, +text: String, +a: All) -> IO(List<&2, Client>):
  Wire.all.k(Clients.socket(cs), cs, text, a)

def Wire.all(+cs: List<&2, Client>, +text: String) -> IO(List<&2, Client>):
  Wire.all.of(cs, text, All{0n, 0n, 0n, Nil{}})

# streamed text: none for a client taking its log
def Wire.delta(+cs: List<&2, Client>, +text: String) -> IO(List<&2, Client>):
  Wire.all.of(cs, text, All{2n, 0n, 0n, Nil{}})

# log changes: every client but those taking their log (they get them with
# the rest of it); one too far behind goes back to taking it from item at
# (the log's length before these changes), the far mirrors left out
def Wire.changes(+cs: List<&2, Client>, +text: String, +at: Nat, +fl: Nat, +inbox: Chan(Msg)) -> IO(List<&2, Client>):
  Wire.all.of(cs, text, All{1n, at, fl, [inbox]})

# Agent processes
# ---------------

# lines from the agent's stdout go to the hub; EOF reports the exit
def Agent.lines(ls: List<&2, String>, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, l})
        Agent.lines(t, thread, inbox)

def Agent.end(s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    ok : Bool <- Chan.send(Msg, inbox, AgentGone{thread, code, pid})
    return Unit{}

def Agent.pause(streaming: Bool) -> IO(Unit):
  match streaming:
    case True{}:
      IO.sleep(B.Delta.pace())
    case False{}:
      IO.pure(Unit, Unit{})

# a read's lines, text deltas merged (B.Delta.merge), then a moment's wait
# when it ended mid-stream, so the next read takes what came meanwhile
def Agent.fed.k(+ls: List<&2, String>, s: Socket, carry: U.Lines, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Agent.lines(B.Delta.merge(ls), thread, inbox)
    Agent.pause(B.Delta.streaming(ls))
    k(s, carry)

def Agent.fed(r: U.Lines & List<&2, String>, s: Socket, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> IO(Unit)) -> IO(Unit):
  (carry, ls) = r
  Agent.fed.k(ls, s, carry, thread, inbox, k)

# (lines go out under the tag, B.Tag.of(thread, pid), so a replaced
# process is not heard; the exit names the plain thread and pid)
# the stream ended: a last line with no newline still counts (a result
# written just before the process died), then the exit
def Agent.last(carry: U.Lines, s: Socket, +pid: U32, +thread: String, +tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +rest : String = U.Lines.rest(carry)
    Agent.lines(Bool.pick(List<&2, String>, String.is_empty(String.trim(rest)), Nil{}, [rest]), tag, inbox)
    Agent.end(s, pid, thread, inbox)

def Agent.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, +pid: U32, +thread: String, +tag: String, +inbox: Chan(Msg),
    k: Socket -> U.Lines -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Agent.last(carry, s, pid, thread, tag, inbox)
    case Done{bs}:
      Agent.fed(U.Lines.feed(carry, bs), s, tag, inbox, k)
    case Fail{_}:
      Agent.last(carry, s, pid, thread, tag, inbox)

def Agent.reader(fuel: Nat, s: Socket, carry: U.Lines, +pid: U32, +thread: String, +tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Agent.end(s, pid, thread, inbox)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Agent.got(r, carry, pid, thread, tag, inbox, s2 => c2 => Agent.reader(f, s2, c2, pid, thread, tag, inbox)))

def Agent.wrote(r: Socket & Result<&1, &1, U32 & String, Unit>, k: Socket -> IO(Unit)) -> IO(Unit):
  (s, _) = r
  k(s)

def Agent.write(m: Maybe<&1, String>, s: Socket, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{line}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Unit, H.Sock.send_text(s, line ++ "\n"), r => Agent.wrote(r, k))
    case None{}:
      Socket.close(s)

# lines from the hub go to the agent's stdin until the channel closes
def Agent.writer(fuel: Nat, s: Socket, +input: Chan(String)) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, input),
        m => Agent.write(m, s, s2 => Agent.writer(f, s2, input)))

# Connections
# -----------

def Conn.sent(r: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  (s, _) = r
  IO.pure(Socket, s)

def Conn.send(s: Socket, bs: List<&2, U32>) -> IO(Socket):
  IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Socket, H.Sock.send_bytes(s, bs), Conn.sent)

def Conn.finish(s: Socket, bs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    s2 : Socket <- Conn.send(s, bs)
    Socket.close(s2)

# a message as a frame: always one binary CBOR frame (about 40% fewer
# bytes on the air than JSON text; every client speaks it). A phone's plot
# is CBOR already and goes as WBin, never through here
def Conn.frame.out(t: String) -> List<&2, U32>:
  W.Ws.cbor(t)

# A client's frames go out with a deadline each (Conn.deadline, ms): a
# peer that stops reading (a half-open link, a phone that no longer reads)
# fails the send, and then its channel is closed first, so the hub's sends
# to it end at once instead of waiting on a full queue, and the socket is
# closed (the effect shut it both ways: its reader ends and it leaves)
def Conn.deadline() -> U32:
  10000

# what was queued for a client whose send failed is taken out, so the
# closed channel's row is freed (a closed channel is freed only once it is
# empty) and its frames are not held for good
def Conn.drain.got(m: Maybe<&1, Wire>, k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{_}:
      k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

def Conn.drain(fuel: Nat, +out: Chan(Wire)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, Wire>, Unit, Chan.recv(Wire, out), m => Conn.drain.got(m, u => Conn.drain(f, out)))

def Conn.sent.k(r: Socket & Result<&1, &1, U32 & String, Unit>, +out: Chan(Wire), k: Socket -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{_}:
      k(s)
    case Fail{_}:
      do IO<Unit>:
        Chan.close(Wire, out)
        Conn.drain(Fuel.forever(), out)
        Socket.close(s)

def Conn.out(s: Socket, bs: List<&2, U32>, +out: Chan(Wire), k: Socket -> IO(Unit)) -> IO(Unit):
  IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Unit, H.Sock.send_until(s, bs, Conn.deadline()), r => Conn.sent.k(r, out, k))

# a frame out, then k with its size in bytes
def Conn.put(s: Socket, +bs: List<&2, U32>, +out: Chan(Wire), k: Socket -> Nat -> IO(Unit)) -> IO(Unit):
  Conn.out(s, bs, out, s2 => k(s2, List.length(&2, U32, bs)))

# a join chunk's frames (OB.Items.texts: each within the byte bound), put
# out one by one; to the writer's count they are one frame of no bytes, as
# the hub offered it (it charged none)
def Conn.items(ts: List<&2, String>, s: Socket, +out: Chan(Wire), k: Socket -> Nat -> IO(Unit)) -> IO(Unit):
  match ts:
    case Nil{}:
      k(s, 0n)
    case +t <> rest:
      Conn.out(s, W.Ws.cbor(t), out, s2 => Conn.items(rest, s2, out, k))

def Conn.write(m: Maybe<&1, Wire>, s: Socket, +out: Chan(Wire), k: Socket -> Nat -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{WText{t}}:
      Conn.put(s, Conn.frame.out(t), out, k)
    case Some{WPong{p}}:
      Conn.put(s, W.Ws.encode(10, p), out, k)
    case Some{WBin{bs}}:
      Conn.put(s, W.Ws.encode(2, bs), out, k)
    case Some{WClose{}}:
      Conn.finish(s, W.Ws.encode(8, Nil{}))
    case Some{WState{_, _}}:
      k(s, 0n)
    case Some{WItems{hd, xs, tl, ends}}:
      Conn.items(OB.Items.texts(hd, xs, tl, ends), s, out, k)
    case None{}:
      Socket.close(s)

# what the writer has put out, told to the hub every 32 frames or 256 KB
# (OB.Wr.due), so it knows how far behind the client is
def Conn.told(due: Bool, +w: OB.Wr, +id: U32, +gen: U32, +inbox: Chan(Msg)) -> IO(OB.Wr):
  match due:
    case True{}:
      do IO<OB.Wr>:
        ok : Bool <- Chan.send(Msg, inbox, Drained{id, gen, OB.Wr.n(w), OB.Wr.b(w)})
        return OB.Wr.said(w)
    case False{}:
      IO.pure(OB.Wr, w)

def Conn.wrote(s: Socket, +n: Nat, w: OB.Wr, +id: U32, +gen: U32, +inbox: Chan(Msg), k: Socket -> OB.Wr -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    +w2 : OB.Wr = OB.Wr.put(w, n)
    w3 : OB.Wr <- Conn.told(OB.Wr.due(w2), w2, id, gen, inbox)
    k(s, w3)

# frames from the hub, until it closes our channel
def Conn.writer(fuel: Nat, s: Socket, +out: Chan(Wire), w: OB.Wr, +id: U32, +gen: U32, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(Maybe<&1, Wire>, Unit, Chan.recv(Wire, out),
        m => Conn.write(m, s, out, s2 => n => Conn.wrote(s2, n, w, id, gen, inbox, s3 => w2 => Conn.writer(f, s3, out, w2, id, gen, inbox))))

def Conn.leave(s: Socket, +id: U32, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    ok : Bool <- Chan.send(Msg, inbox, Leave{id})
    return Unit{}

# a request's CBOR as the JSON text the hub reads
def Conn.cbor.json(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{j}:
      J.Json.show(j)
    case None{}:
      ""

# Reading a client
# ----------------
# Frames are scanned without IO (Conn.scan): pings that are not due (at
# most one a second goes to the hub, which answers through the client's
# credit: OB.Pong.due), text frames and pongs are passed over in one
# pure walk, so a flood of them costs a pass over the bytes, not an
# effect each. The clock is read once per read from the socket.

type Scan is Data:
  # fr: the next frame that needs the hub (None: more bytes are needed,
  # rest is then the whole unread buffer); done: the walk stopped
  Scan{fr: Maybe<&2, W.Frame>, rest: List<&2, U32>, done: Bool}

def Conn.quiet.k(+op: U32, +last: Nat, +now: Nat) -> Bool:
  Bool.or(Bool.and(U32.is_eq(op, 9), Bool.not(OB.Pong.due(last, now))), Bool.or(U32.is_eq(op, 1), Bool.or(U32.is_eq(op, 10), U32.is_eq(op, 0))))

def Conn.quiet(fr: W.Frame, +last: Nat, +now: Nat) -> Bool:
  match fr:
    case W.Frame{_, +op, _}:
      Conn.quiet.k(op, last, now)

def Conn.step.q(quiet: Bool, fr: W.Frame, rest: List<&2, U32>) -> Scan:
  match quiet:
    case True{}:
      Scan{None{}, rest, False{}}
    case False{}:
      Scan{Some{fr}, rest, True{}}

def Conn.step(m: Maybe<&2, W.Got>, buf: List<&2, U32>, +last: Nat, +now: Nat) -> Scan:
  match m:
    case Some{W.Got{+fr, rest}}:
      Conn.step.q(Conn.quiet(fr, last, now), fr, rest)
    case None{}:
      Scan{None{}, buf, True{}}

def Conn.scan(fuel: Nat, st: Scan, +last: Nat, +now: Nat) -> Scan:
  match fuel st:
    case 0n Scan{m, r, d}:
      Scan{m, r, d}
    case 1n+f Scan{m, r, True{}}:
      Scan{m, r, True{}}
    case 1n+f Scan{_, +r, False{}}:
      Conn.scan(f, Conn.step(W.Ws.decode(r), r, last, now), last, now)

# a ping passed on to the hub
def Conn.ping(p: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +now: Nat) -> IO(Maybe<&2, Nat>):
  do IO<Maybe<&2, Nat>>:
    ok : Bool <- Chan.send(Msg, inbox, Ping{id, p})
    return Some{now}

# what a frame the hub must hear does: None ends the connection, else the
# last pong's time
def Conn.frame.k(bin: Bool, close: Bool, ping: Bool, p: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +last: Nat, +now: Nat) -> IO(Maybe<&2, Nat>):
  match bin close ping:
    case True{} _ _:
      do IO<Maybe<&2, Nat>>:
        ok : Bool <- Chan.send(Msg, inbox, Rpc{id, Conn.cbor.json(CB.Cbor.decode(p))})
        return Some{last}
    case False{} True{} _:
      IO.pure(Maybe<&2, Nat>, None{})
    case False{} False{} True{}:
      Conn.ping(p, id, inbox, now)
    case False{} False{} False{}:
      IO.pure(Maybe<&2, Nat>, Some{last})

# a frame from a client: a binary frame is a request (CBOR, read here as
# JSON text for the hub); close ends; a due ping pongs
def Conn.frame(fr: W.Frame, +id: U32, +inbox: Chan(Msg), +last: Nat, +now: Nat) -> IO(Maybe<&2, Nat>):
  match fr:
    case W.Frame{_, +op, p}:
      Conn.frame.k(U32.is_eq(op, 2), U32.is_eq(op, 8), U32.is_eq(op, 9), p, id, inbox, last, now)

def Conn.more(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +last: Nat,
    k: Socket -> List<&2, U32> -> Nat -> Nat -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Conn.leave(s, id, inbox)
    case Done{bs}:
      IO.bind(Nat, Unit, IO.now(), now => k(s, List.append(&2, U32, buf, bs), last, now))
    case Fail{_}:
      Conn.leave(s, id, inbox)

def Conn.after(m: Maybe<&2, Nat>, s: Socket, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +now: Nat, k: Socket -> List<&2, U32> -> Nat -> Nat -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{last}:
      k(s, rest, last, now)
    case None{}:
      Conn.leave(s, id, inbox)

def Conn.scanned(sc: Scan, s: Socket, +id: U32, +inbox: Chan(Msg), +last: Nat, +now: Nat,
    k: Socket -> List<&2, U32> -> Nat -> Nat -> IO(Unit)) -> IO(Unit):
  match sc:
    case Scan{Some{fr}, rest, _}:
      IO.bind(Maybe<&2, Nat>, Unit, Conn.frame(fr, id, inbox, last, now), go => Conn.after(go, s, rest, id, inbox, now, k))
    case Scan{None{}, rest, _}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Conn.more(r, rest, id, inbox, last, k))

# the frames in buf; more read when they run out
def Conn.reader(fuel: Nat, s: Socket, buf: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +last: Nat, +now: Nat) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.leave(s, id, inbox)
    case 1n+f:
      Conn.scanned(Conn.scan(65536n, Scan{None{}, buf, False{}}, last, now), s, id, inbox, last, now,
        s2 => b2 => l2 => n2 => Conn.reader(f, s2, b2, id, inbox, l2, n2))

def Conn.raw(r: Socket & U32, rd: Socket, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String) -> IO(Unit):
  (wr, +fd) = r
  do IO<Unit>:
    +out : Chan(Wire) <- Chan.new(Wire, 1024)
    IO.spawn(Unit, Conn.writer(Fuel.forever(), wr, out, OB.Wr.new(), id, id, inbox))
    ok : Bool <- Chan.send(Msg, inbox, Join{id, out, since, origin, id, fd})
    Conn.reader(Fuel.forever(), rd, rest, id, inbox, 0n, 0n)

def Conn.ws.dup(r: Socket & Result<&1, &1, U32 & String, Socket>, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String) -> IO(Unit):
  (rd, res) = r
  match res:
    case Done{wr}:
      IO.bind(Socket & U32, Unit, H.Sock.raw(wr), x => Conn.raw(x, rd, rest, id, inbox, since, origin))
    case Fail{_}:
      Socket.close(rd)

def Conn.ws(s: Socket, key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String) -> IO(Unit):
  do IO<Unit>:
    s2 : Socket <- Conn.send(s, W.Ws.accept(key))
    r : Socket & Result<&1, &1, U32 & String, Socket> <- H.Sock.dup(s2)
    Conn.ws.dup(r, rest, id, inbox, since, origin)

def Conn.safe(+p: String) -> Bool:
  Bool.and(Bool.not(String.contains(p, "..")), String.starts_with(p, "/"))

def Conn.file(+p: String) -> String:
  Bool.pick(String, String.eq(p, "/"), "/index.html", p)

# hashed bundle chunks never change under their name; the page and the
# service worker are checked every time
def Conn.cache(+path: String) -> String:
  Bool.pick(String, String.starts_with(path, "/chunk-"), "public, max-age=31536000, immutable", "no-cache")

# a websocket from plain loopback is trusted; anything else (the tailnet
# listener, or `tailscale serve` proxying with its identity headers) must
# carry ?token=<the pairing token>
def Conn.allowed(+trusted: Bool, +hs: List<&2, W.Header>, +path: String, +token: String) -> Bool:
  Bool.or(Bool.and(trusted, String.is_empty(W.Http.header_of(hs, "tailscale-user-login"))),
    Bool.and(Bool.not(String.is_empty(token)), Bool.or(String.contains(path, "token=" ++ token), String.contains(W.Http.header_of(hs, "cookie"), "bp_token=" ++ token))))

def Conn.gate(ok: Bool, s: Socket, +key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String) -> IO(Unit):
  match ok:
    case True{}:
      Conn.ws(s, key, rest, id, inbox, since, origin)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.is_ws(req: W.Request) -> Bool:
  match req:
    case W.Request{_, p, +hs}:
      Bool.and(String.eq(W.Http.route(p), "/ws"), String.eq(String.to_lower(W.Http.header_of(hs, "upgrade")), "websocket"))

def Conn.is_mcp(req: W.Request) -> Bool:
  match req:
    case W.Request{m, p, _}:
      Bool.and(String.eq(m, "POST"), String.starts_with(W.Http.route(p), "/mcp/"))

def Mcp.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Socket.close(s)
    case Done{bs}:
      k(s, List.append(&2, U32, buf, bs))
    case Fail{_}:
      Socket.close(s)

def Mcp.answer.k(empty: Bool, s: Socket, text: String) -> IO(Unit):
  match empty:
    case True{}:
      Conn.finish(s, W.Http.response("202 Accepted", "application/json", Nil{}, ""))
    case False{}:
      Conn.finish(s, W.Http.response("200 OK", "application/json", U.Utf8.encode(text), ""))

def Mcp.answer(m: Maybe<&1, String>, s: Socket) -> IO(Unit):
  match m:
    case Some{+text}:
      Mcp.answer.k(String.is_empty(text), s, text)
    case None{}:
      Conn.finish(s, W.Http.text("503 Service Unavailable", "the hub is gone"))

def Mcp.ask(s: Socket, +body: String, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +reply : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(Msg, inbox, Mcp{thread, body, reply})
    m : Maybe<&1, String> <- Chan.recv(String, reply)
    Mcp.answer(m, s)

def Mcp.body.k(full: Bool, s: Socket, +buf: List<&2, U32>, +thread: String, +inbox: Chan(Msg), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match full:
    case True{}:
      Mcp.ask(s, U.Utf8.decode(buf), thread, inbox)
    case False{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536), r => Mcp.got(r, buf, k))

# read until the body is complete
def Mcp.body(fuel: Nat, s: Socket, +buf: List<&2, U32>, +len: Nat, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.finish(s, W.Http.text("413 Payload Too Large", "too large"))
    case 1n+f:
      Mcp.body.k(Nat.is_ge(List.length(&2, U32, buf), len), s, buf, thread, inbox, s2 => b2 => Mcp.body(f, s2, b2, len, thread, inbox))

# MCP over HTTP
# -------------
# One POST per JSON-RPC message; the reply is JSON (or 202 for a
# notification). The hub answers on a channel made for this request.

def Mcp.gate(ok: Bool, s: Socket, +thread: String, +len: Nat, rest: List<&2, U32>, +inbox: Chan(Msg)) -> IO(Unit):
  match ok:
    case True{}:
      Mcp.body(64n, s, rest, len, thread, inbox)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.head.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Socket.close(s)
    case Done{bs}:
      k(s, List.append(&2, U32, buf, bs))
    case Fail{_}:
      Socket.close(s)

# The hub
# -------

type Hub is Type:
  Hub{state: M.State, log: File, lines: List<&2, String>, clients: List<&2, Client>, agents: List<&2, Agent>, inbox: Chan(Msg), cfg: Cfg, note: String}

def Hub.changes_msg(ls: List<&2, String>) -> String:
  "{\"t\":\"changes\",\"items\":[" ++ String.join(ls, ",") ++ "]}"

def Info.kicad(rt: K.Rt) -> List<&2, J.KV>:
  match rt:
    case K.Rt{cli, fork, v, c}:
      [J.KV{"kicad.cli", J.Str{cli}}, J.KV{"kicad.fork", J.Str{Bool.pick(String, fork, v, "")}}, J.KV{"kicad.commit", J.Str{c}}]

def Info.net(n: Net) -> List<&2, J.KV>:
  match n:
    case Net{tn, hs, _, ms, _, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}:
      List.append(&2, J.KV, [J.KV{"models", J.Str{ms}}, J.KV{"machines", J.Str{mc}}, J.KV{"bots.remote", J.Str{BN.Bn.dir(bnx)}}, J.KV{"tailnet", J.Str{Bool.pick(String, tn, Bool.pick(String, hs, "https", "on"), "off")}},
        J.KV{"update", J.Str{Bool.pick(String, mgd, "package", "releases")}}, J.KV{"pair", J.Str{lk}}, J.KV{"freecad", J.Str{fc}}], Info.kicad(rt))

# what this machine runs, for the settings screen and the model picker
def Hub.info(c: Cfg) -> J.Json:
  match c:
    case Cfg{+home, _, host, port, _, _, _, net}:
      J.Json.obj(List.append(&2, J.KV, [J.KV{"home", J.Str{home}}, J.KV{"browser.frames", J.Str{home ++ "/browser.rgb"}}, J.KV{"listen", J.Str{host ++ ":" ++ U32.show(port)}}], Info.net(net)))

# A link change is handled after it has been stored, through the inbox,
# so both sides of an invite refresh immediately (revokes prune rows).
def Bot.dir.changed(c: M.Change, +inbox: Chan(Msg)) -> IO(Unit):
  match c:
    case M.PeerSet{peer, _, _, _, _}:
      Self.post(inbox, BotsRefresh{peer})
    case _:
      IO.pure(Unit, Unit{})

# One write per step
# -----------------
# A step's changes go to the log in one write (ST.Store.text), and only once
# it is written are they folded in, announced and their effects run. A
# write that fails folds nothing of the step and runs none of its effects;
# the hub logs it, counts it (hub.write_fail) and tells every client, and
# keeps serving (the window lives in this process).

# what a step's write did: the new lines for clients (newest first), or
# why it failed
type Wrote is Data:
  Wrote{fresh: List<&2, String>, ok: Bool, err: String}

def Hub.lines.disk(cs: List<&2, M.Change>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      J.Json.show(C.Change.encode(c)) <> Hub.lines.disk(t)

# the written changes folded in: the state, the log's lines and the new
# ones (both newest first)
type Folded is Data:
  Folded{st: M.State, ls: List<&2, String>, fresh: List<&2, String>}

def Hub.fold(cs: List<&2, M.Change>, f: Folded) -> Folded:
  match cs f:
    case Nil{} _:
      f
    case +c <> t Folded{st, ls, fr}:
      Hub.fold(t, Folded{M.State.apply(st, c), J.Json.show(C.Change.wire(c)) <> ls, J.Json.show(C.Change.wire(c)) <> fr})

def Bot.dir.changed.all(cs: List<&2, M.Change>, +inbox: Chan(Msg)) -> IO(Unit):
  match cs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case c <> t:
      do IO<Unit>:
        Bot.dir.changed(c, inbox)
        Bot.dir.changed.all(t, inbox)

def Hub.commit.k(fd: Folded, f: File, cl: List<&2, Client>, as: List<&2, Agent>, inbox: Chan(Msg), cfg: Cfg, note: String) -> Hub & Wrote:
  match fd:
    case Folded{st, ls, fr}:
      (Hub{st, f, ls, cl, as, inbox, cfg, note}, Wrote{fr, True{}, ""})

def Hub.err.msg(e: U32 & String) -> String:
  (_, msg) = e
  msg

def Hub.commit.r(r: Hub & Wrote, fresh: List<&2, String>) -> Hub & List<&2, String>:
  (h, w) = r
  match w:
    case Wrote{fr, _, _}:
      (h, List.append(&2, String, fr, fresh))

# a generation's name: when it started and the log's length then
def Hub.gen(+st: M.State, +now: Nat) -> String:
  Nat.show(now) ++ "-" ++ Nat.show(M.State.seq(st))

# An agent's watcher: each second it asks whether the process exited (not
# reaping it: the reader's Agent.end does). When it has, the hub hears so
# and, if the reader has not reached end of stream 2 s later (a child of
# the agent keeps its output open), the reading side is shut so it does;
# its last line is read and the exit handled once. It ends with the
# process, so none outlives its generation.
def Agent.watch.end(+code: U32, s: Socket, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, AgentExited{thread, gen, code})
    IO.sleep(2000)
    s2 : Socket <- H.Sock.shut_read(s)
    Socket.close(s2)

def Agent.watch.k(running: Bool, +code: U32, s: Socket, +thread: String, +gen: String, +inbox: Chan(Msg), k: Socket -> IO(Unit)) -> IO(Unit):
  match running:
    case True{}:
      do IO<Unit>:
        IO.sleep(1000)
        k(s)
    case False{}:
      Agent.watch.end(code, s, thread, gen, inbox)

def Agent.watch.got(+code: U32, s: Socket, +thread: String, +gen: String, +inbox: Chan(Msg), k: Socket -> IO(Unit)) -> IO(Unit):
  Agent.watch.k(U32.is_eq(code, 4294967295), code, s, thread, gen, inbox, k)

def Agent.watch(fuel: Nat, s: Socket, +pid: U32, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(U32, Unit, H.Proc.exited(pid), code => Agent.watch.got(code, s, thread, gen, inbox, s2 => Agent.watch(f, s2, pid, thread, gen, inbox)))

def Agent.watch.start(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Socket):
  (rd, res) = r
  match res:
    case Done{dup}:
      do IO<Socket>:
        IO.spawn(Unit, Agent.watch(Fuel.forever(), dup, pid, thread, gen, inbox))
        return rd
    case Fail{_}:
      IO.pure(Socket, rd)

def Hub.spawned.dup(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, h: Hub, +thread: String, +key: String, +gen: String) -> IO(Hub):
  (rd0, res) = r
  match res h:
    case Done{wr} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        +input : Chan(String) <- Chan.new(String, 256)
        +now : Nat <- Now.nat()
        IO.spawn(Unit, Agent.writer(Fuel.forever(), wr, input))
        rd : Socket <- IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Socket, H.Sock.dup(rd0), d => Agent.watch.start(d, pid, thread, gen, inbox))
        IO.spawn(Unit, Agent.reader(Fuel.forever(), rd, U.Lines.new(), pid, thread, B.Tag.of(thread, pid), inbox))
        return Hub{st, f, ls, cl, Agent{thread, input, pid, key, [ARun.new.h(gen, now)]} <> as, inbox, cfg, note}
    # the process started but its socket could not be shared: it is
    # stopped and goes through the usual exit (Agent.end, AgentGone), so
    # its turn fails, its asks close and its task ends
    case Fail{_} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        +input : Chan(String) <- Chan.new(String, 1)
        Chan.close(String, input)
        Proc.kill(pid, 15)
        IO.spawn(Unit, Agent.end(rd0, pid, thread, inbox))
        return Hub{st, f, ls, cl, Agent{thread, input, pid, key, [ARun.new.g(gen)]} <> as, inbox, cfg, note}

def Hub.spawned.ok(started: U32 & Socket, h: Hub, +thread: String, +key: String, +gen: String) -> IO(Hub):
  (pid, s) = started
  do IO<Hub>:
    r : Socket & Result<&1, &1, U32 & String, Socket> <- H.Sock.dup(s)
    Hub.spawned.dup(r, pid, h, thread, key, gen)

def Hub.agent_send(m: Maybe<&2, Agent>, line: String) -> IO(Unit):
  match m:
    case Some{Agent{_, input, _, _, _}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, input, line)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.agent_stop(m: Maybe<&2, Agent>) -> IO(Unit):
  match m:
    case Some{Agent{_, input, pid, _, _}}:
      do IO<Unit>:
        Chan.close(String, input)
        Proc.kill(pid, 15)
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.state(h: Hub) -> M.State & Hub:
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      (st, Hub{st, f, ls, cl, as, inbox, cfg, note})

# /hello's busy count follows every committed step, not the minute's tick
def Hub.busy.set(h: Hub) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        PS.Perf.set("hub.busy", U32.from_nat(M.Work.threads(st)))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Cfg.version(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, v, nt}:
      v

# which log this is: the time of its first change (a client resumes only
# into the log it came from)
def Hub.origin(+ls: List<&2, String>) -> String:
  Nat.show(J.Json.get_nat(Maybe.default(&2, J.Json, J.Json.parse(Maybe.default(&2, String, List.last(&2, String, ls), "")), J.Null{}), "at", 0n))

def Hub.log_msg.k(+n: Nat, +ls: List<&2, String>, +cfg: Cfg, +since: Nat) -> String:
  "{\"t\":\"log\",\"since\":" ++ Nat.show(since) ++ ",\"origin\":\"" ++ Hub.origin(ls) ++ "\",\"version\":" ++ J.Json.show(J.Str{Cfg.version(cfg)}) ++ ",\"info\":" ++ J.Json.show(Hub.info(cfg))
    ++ ",\"items\":[" ++ String.join(List.reverse(&2, String, List.take(&2, String, ls, Nat.sub(n, since))), ",") ++ "]}"

# the log for a client that has the first `since` changes already (a
# reconnect sends only what it missed; a client ahead of the log, as after
# a server reset, gets everything, since 0)
def Hub.log_msg(+ls: List<&2, String>, +cfg: Cfg, +since: Nat) -> String:
  Hub.log_msg.k(List.length(&2, String, ls), ls, cfg, Bool.pick(Nat, Nat.is_le(since, List.length(&2, String, ls)), since, 0n))

# the first frame of a join: the log message with the first chunk of what
# the client lacks; "more": the rest follows a chunk at a time
# (core/outbox.bend's Join.*), the last one with "boot": false
def Hub.log_msg.c(+origin: String, +cfg: Cfg, +since: Nat, xs: List<&2, String>, more: Bool) -> String:
  "{\"t\":\"log\",\"since\":" ++ Nat.show(since) ++ ",\"origin\":\"" ++ origin ++ "\",\"version\":" ++ J.Json.show(J.Str{Cfg.version(cfg)}) ++ ",\"info\":" ++ J.Json.show(Hub.info(cfg))
    ++ Bool.pick(String, more, ",\"more\":true", "") ++ ",\"items\":[" ++ String.join(xs, ",") ++ "]}"

# a later chunk of a join; the last says "boot": false
def Hub.boot_msg(xs: List<&2, String>, last: Bool) -> String:
  "{\"t\":\"changes\",\"boot\":" ++ Bool.pick(String, last, "false", "true") ++ ",\"items\":[" ++ String.join(xs, ",") ++ "]}"

# the same, put together by the writer
def Hub.boot_items(xs: List<&2, String>) -> Wire:
  WItems{"{\"t\":\"changes\",\"boot\":true,\"items\":[", xs, "]}", False{}}

# a join's first frame, put together by the writer
def Hub.log_items(+origin: String, +cfg: Cfg, +since: Nat, xs: List<&2, String>, +more: Bool) -> Wire:
  WItems{"{\"t\":\"log\",\"since\":" ++ Nat.show(since) ++ ",\"origin\":\"" ++ origin ++ "\",\"version\":" ++ J.Json.show(J.Str{Cfg.version(cfg)}) ++ ",\"info\":" ++ J.Json.show(Hub.info(cfg))
    ++ Bool.pick(String, more, ",\"more\":true", "") ++ ",\"items\":[", xs, "]}", Bool.not(more)}

# Desks
# -----
# which threads a desk watches (core/desk.bend): a client joining hears
# them, and every client hears them again whenever they change

def Desk.join(+text: String) -> String:
  Bool.pick(String, String.is_empty(text), "", DK.Desk.info(text))

def Desk.say.k(same: Bool, +cl: List<&2, Client>, +text: String) -> IO(List<&2, Client>):
  match same:
    case True{}:
      IO.pure(List<&2, Client>, cl)
    case False{}:
      Wire.all(cl, DK.Desk.info(text))

def Desk.say(+before: String, +cl: List<&2, Client>, +now: Nat) -> IO(List<&2, Client>):
  Desk.say.k(String.eq(before, DK.Desk.text(Clients.looks(cl), now)), cl, DK.Desk.text(Clients.looks(cl), now))

# a desk said what it shows
def Hub.desk(h: Hub, +client: U32, +thread: String, +focused: Bool) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        +cl2 : List<&2, Client> = Clients.look(cl, client, DK.Look{True{}, thread, focused, now})
        cl3 : List<&2, Client> <- Desk.say(DK.Desk.text(Clients.looks(cl), now), cl2, now)
        return Hub{st, f, ls, cl3, as, inbox, cfg, note}

def Hub.leave.close(m: Maybe<&2, Client>) -> IO(Unit):
  match m:
    case Some{Client{_, c, _, _, k}}:
      do IO<Unit>:
        Chan.close(Wire, c)
        H.Fd.close(k)
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.push(h: Hub, +client: U32, +text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.to(cl, client, text)
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

def Hub.push.bin(h: Hub, +client: U32, +bs: List<&2, U32>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.to.raw(cl, client, WBin{bs}, List.length(&2, U32, bs))
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

# a ping answered through the client's credit
def Hub.pong(h: Hub, +client: U32, +p: List<&2, U32>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.to.raw(cl, client, WPong{p}, List.length(&2, U32, p))
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

def Hub.note(h: Hub, +text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, _}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.all(cl, text)
        return Hub{st, f, ls, cl2, as, inbox, cfg, text}

def Hub.close(h: Hub) -> IO(Unit):
  match h:
    case Hub{_, f, _, _, _, _, _, _}:
      File.close(f)

# the hub's inbox, handed to k beside the hub
def Hub.inbox(h: Hub, k: Chan(Msg) -> Hub -> IO(Unit)) -> IO(Unit):
  match h:
    case Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      k(inbox, Hub{st, f, ls, cl, as, inbox, cfg, note})

# Codex
# -----

def Codex.sandbox(r: M.RuntimeMode) -> List<&2, String>:
  match r:
    case M.FullAccess{}:
      ["--dangerously-bypass-approvals-and-sandbox"]
    case M.Supervised{}:
      ["-s", "read-only"]
    case _:
      ["-s", "workspace-write"]

def Codex.opt.k(empty: Bool, flag: String, v: String) -> List<&2, String>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      [flag, v]

def Codex.opt(flag: String, +v: String) -> List<&2, String>:
  Codex.opt.k(String.is_empty(v), flag, v)

def Codex.head.k(fresh: Bool, +session: String) -> List<&2, String>:
  match fresh:
    case True{}:
      ["exec", "--json", "--skip-git-repo-check"]
    case False{}:
      ["exec", "resume", session, "--json", "--skip-git-repo-check"]

def Cfg.prompt(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, pr, _, _, _}:
      pr

def Codex.failed(e: U32 & String, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, msg) = e
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, SpawnFailed{thread, gen, "{\"type\":\"turn.failed\",\"message\":" ++ J.Json.show(J.Str{"could not start codex: " ++ msg}) ++ "}"})
    return Unit{}

# whether a Codex event line ends the turn
def Codex.ends(+l: String) -> Bool:
  Bool.or(String.contains(l, "\"type\":\"turn.completed\""), String.contains(l, "\"type\":\"turn.failed\""))

def Codex.lines(ls: List<&2, String>, +ended: Bool, +thread: String, +inbox: Chan(Msg)) -> IO(Bool):
  match ls:
    case Nil{}:
      IO.pure(Bool, ended)
    case +l <> t:
      do IO<Bool>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, l})
        Codex.lines(t, Bool.or(ended, Codex.ends(l)), thread, inbox)

def Codex.fed(r: U.Lines & List<&2, String>, s: Socket, +ended: Bool, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> Bool -> IO(Unit)) -> IO(Unit):
  (carry, ls) = r
  IO.bind(Bool, Unit, Codex.lines(ls, ended, thread, inbox), e2 => k(s, carry, e2))

# Folders for the project picker
# ------------------------------
# The path is always an argument ($1), never part of a script.

# $d from $1: "" and ~ are home, ~/x and relative paths are under home
def FsJob.path.sh() -> String:
  "d=\"$1\"; case \"$d\" in ''|'~') d=\"$HOME\";; '~/'*) d=\"$HOME/${d#??}\";; /*) ;; *) d=\"$HOME/$d\";; esac; "

# a folder that exists and can be opened, printed resolved (symlinks too)
def FsJob.dir.sh() -> String:
  "[ -e \"$d\" ] || { echo \"no such folder: $d\"; exit 2; }; d=$(realpath -e -- \"$d\"); [ -d \"$d\" ] || { echo \"not a folder: $d\"; exit 2; }; [ -r \"$d\" ] && [ -x \"$d\" ] || { echo \"cannot open: $d\"; exit 2; }; "

def FsJob.list.sh() -> String:
  "exec 2>&1; set -e; " ++ FsJob.path.sh() ++ FsJob.dir.sh() ++ "echo \"$d\"; find \"$d\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null | LC_ALL=C sort | head -n 5000"

# a new folder (and any missing parents); an existing one is refused
def FsJob.mkdir.sh() -> String:
  "exec 2>&1; set -e; " ++ FsJob.path.sh() ++ "if [ -e \"$d\" ] || [ -L \"$d\" ]; then echo \"already exists: $d\"; exit 3; fi; mkdir -p -- \"$d\"; " ++ FsJob.dir.sh() ++ "echo \"$d\""

# the folder a project would have
def FsJob.resolve.sh() -> String:
  "exec 2>&1; set -e; " ++ FsJob.path.sh() ++ FsJob.dir.sh() ++ "echo \"$d\""

# folders under home holding .backplane or .backplane.json (Backplane
# projects), five levels down at most; other hidden folders, node_modules
# and other file systems are skipped, and it gives up after five seconds
def FsJob.find.sh() -> String:
  "exec 2>/dev/null; echo \"$HOME\"; timeout 5 find \"$HOME\" -xdev -mindepth 1 -maxdepth 5 \\( -type d \\( -name node_modules -o \\( -name '.*' ! -name .backplane \\) \\) -prune \\) -o \\( -type d -name .backplane -printf '%h\\n' -prune \\) -o \\( -name .backplane.json -printf '%h\\n' \\) | grep -vxF \"$HOME\" | LC_ALL=C sort -u | head -n 500; true"

def FsJob.strs(ls: List<&2, String>) -> List<&2, J.Json>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      J.Str{l} <> FsJob.strs(t)

def FsJob.listed.k(ls: List<&2, String>) -> J.Json:
  match ls:
    case d <> t:
      J.Json.obj([J.KV{"dir", J.Str{d}}, J.KV{"entries", J.Json.arr(FsJob.strs(t))}])
    case Nil{}:
      J.Json.obj([J.KV{"error", J.Str{"not a folder"}}])

def FsJob.listed(r: P.Ran) -> J.Json:
  match r:
    case P.Ran{0, out}:
      FsJob.listed.k(String.lines(String.trim(out)))
    case P.Ran{_, out}:
      J.Json.obj([J.KV{"error", J.Str{String.trim(out)}}])

def FsJob.found.k(ls: List<&2, String>) -> J.Json:
  match ls:
    case h <> t:
      J.Json.obj([J.KV{"home", J.Str{h}}, J.KV{"found", J.Json.arr(FsJob.strs(t))}])
    case Nil{}:
      J.Json.obj([J.KV{"found", J.Json.arr(Nil{})}])

def FsJob.found(r: P.Ran) -> J.Json:
  match r:
    case P.Ran{_, out}:
      FsJob.found.k(String.lines(String.trim(out)))

def FsJob.ok(+r: J.Json) -> Bool:
  String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(r, "error"), J.Null{})), "null")

# Git jobs
# --------
# The hub asks; git runs here off the hub's thread; results go back as a
# reply to the asking client, and as thread notes/events through the hub.

def GitJob.say(+inbox: Chan(Msg), +m: String, p: List<&2, J.KV>) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, Rpc{0, J.Json.show(J.Json.obj([J.KV{"id", J.Num{"0"}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Json.obj(p)}]))})
    return Unit{}

def GitJob.note(+inbox: Chan(Msg), +thread: String, +tone: String, +summary: String) -> IO(Unit):
  GitJob.say(inbox, "thread.note", [J.KV{"thread", J.Str{thread}}, J.KV{"tone", J.Str{tone}}, J.KV{"kind", J.Str{"git"}}, J.KV{"summary", J.Str{summary}}])

def GitJob.reply(+inbox: Chan(Msg), +client: U32, +id: String, +ok: Bool, r: J.Json) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Msg, inbox, Push{client, J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{ok}}, J.KV{"result", r}]))})
    return Unit{}

def FsJob.answer(+inbox: Chan(Msg), +client: U32, +id: String, +r: J.Json) -> IO(Unit):
  GitJob.reply(inbox, client, id, FsJob.ok(r), r)

def FsJob.list(+inbox: Chan(Msg), +client: U32, +id: String, +path: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", FsJob.list.sh(), "sh", path], "/"), r => FsJob.answer(inbox, client, id, FsJob.listed(r)))

def FsJob.last(ls: List<&2, String>) -> String:
  Maybe.default(&2, String, List.last(&2, String, ls), "")

def FsJob.made(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      FsJob.list(inbox, client, id, FsJob.last(String.lines(String.trim(out))))
    case P.Ran{_, out}:
      FsJob.answer(inbox, client, id, J.Json.obj([J.KV{"error", J.Str{String.trim(out)}}]))

# a resolved folder becomes a project: the hub gets project.create as if
# the asking client sent it, so the answer (or "already a project") is its
def FsJob.create(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Rpc{client, J.Json.show(J.Json.obj([J.KV{"id", J.Num{id}}, J.KV{"m", J.Str{"project.create"}},
          J.KV{"p", J.Json.obj([J.KV{"path", J.Str{FsJob.last(String.lines(String.trim(out)))}}])}]))})
        return Unit{}
    case P.Ran{_, out}:
      FsJob.answer(inbox, client, id, J.Json.obj([J.KV{"error", J.Str{String.trim(out)}}]))

def FsJob.sh(+sh: String, +path: String) -> IO(P.Ran):
  P.Proc.run("sh", ["-c", sh, "sh", path], "/")

# list, mkdir (then list it), add (resolve, then create), new (mkdir,
# then create), find
def FsJob.run.k(i: Nat, +inbox: Chan(Msg), +client: U32, +id: String, +path: String) -> IO(Unit):
  match i:
    case 1n:
      IO.bind(P.Ran, Unit, FsJob.sh(FsJob.mkdir.sh(), path), r => FsJob.made(r, inbox, client, id))
    case 2n:
      IO.bind(P.Ran, Unit, FsJob.sh(FsJob.resolve.sh(), path), r => FsJob.create(r, inbox, client, id))
    case 3n:
      IO.bind(P.Ran, Unit, FsJob.sh(FsJob.mkdir.sh(), path), r => FsJob.create(r, inbox, client, id))
    case 4n:
      IO.bind(P.Ran, Unit, FsJob.sh(FsJob.find.sh(), path), r => FsJob.answer(inbox, client, id, FsJob.found(r)))
    case _:
      FsJob.list(inbox, client, id, path)

def FsJob.run(+op: String, +inbox: Chan(Msg), +client: U32, +id: String, +path: String) -> IO(Unit):
  FsJob.run.k(C.Codec.pos(["list", "mkdir", "add", "new", "find"], op), inbox, client, id, path)

def GitJob.nonblank(ls: List<&2, String>, +n: Nat) -> Nat:
  match ls:
    case Nil{}:
      n
    case l <> t:
      GitJob.nonblank(t, Bool.pick(Nat, String.is_empty(String.trim(l)), n, 1n+n))

def GitJob.count.k(r: P.Ran) -> Nat:
  match r:
    case P.Ran{0, out}:
      GitJob.nonblank(String.lines(out), 0n)
    case _:
      0n

# how many checkpoints a thread has (its next turn number)
def GitJob.count(+cwd: String, +thread: String) -> IO(Nat):
  IO.bind(P.Ran, Nat, P.Proc.run("git", ["for-each-ref", "--format=%(refname)", "refs/backplane/checkpoints/" ++ GT.Git.b64url(thread) ++ "/turn/"], cwd),
    r => IO.pure(Nat, GitJob.count.k(r)))

def GitJob.cp0.k(n: Nat, +cwd: String, +thread: String) -> IO(Unit):
  match n:
    case 0n:
      IO.bind(String, Unit, GT.Git.checkpoint.capture(cwd, thread, 0n), r => IO.pure(Unit, Unit{}))
    case _:
      IO.pure(Unit, Unit{})

# A new thread's worktree (Git.thread_wt, in <repo>/.backplane/worktrees).
# When there is no repository to branch, or git fails, the thread works in
# the project folder (thread.local); only a worktree asked for by name
# ("worktree" rather than the default "auto") reports that as an error.

def WtJob.skip(+inbox: Chan(Msg), +thread: String, +tone: String, +why: String) -> IO(Unit):
  do IO<Unit>:
    GitJob.note(inbox, thread, tone, "working in the project folder: " ++ why)
    GitJob.say(inbox, "thread.local", [J.KV{"thread", J.Str{thread}}])

def WtJob.made(+inbox: Chan(Msg), +thread: String, +branch: String, +path: String, carried: Bool) -> IO(Unit):
  do IO<Unit>:
    GitJob.say(inbox, "thread.worktree", [J.KV{"thread", J.Str{thread}}, J.KV{"branch", J.Str{branch}}, J.KV{"path", J.Str{path}}])
    GitJob.note(inbox, thread, "info", "worktree " ++ path ++ Bool.pick(String, carried, " (with the folder's uncommitted work)", ""))

def WtJob.done(+r: String, +inbox: Chan(Msg), +thread: String, +mode: String, +branch: String, +carried: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.skipped(r), WtJob.skip(inbox, thread, Bool.pick(String, String.eq(mode, "worktree"), "error", "info"), String.drop(r, 6n)),
    Bool.pick(IO(Unit), GT.Git.failed(r), WtJob.skip(inbox, thread, "error", String.trim(r)),
      WtJob.made(inbox, thread, branch, r, carried)))

def WtJob.go(+hw: Bool, +inbox: Chan(Msg), +thread: String, +root: String, +mode: String) -> IO(Unit):
  IO.bind(String, Unit, GT.Git.thread_wt(root, hw, GT.Git.branch.temp(B.Wt.seed(thread))),
    r => WtJob.done(r, inbox, thread, mode, GT.Git.branch.sanitize(GT.Git.branch.temp(B.Wt.seed(thread))), hw))

def WtJob.restore.k(n: Nat, +inbox: Chan(Msg), +thread: String, +path: String) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+last:
      IO.bind(String, Unit, GT.Git.checkpoint.revert(path, thread, last), r => IO.pure(Unit, Unit{}))

# a worktree made again gets back what it held when it was removed (the
# checkpoint taken then), before anything that waited for it runs
def WtJob.again.k(+r: String, +inbox: Chan(Msg), +thread: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.or(GT.Git.failed(r), GT.Git.skipped(r)), WtJob.done(r, inbox, thread, "worktree", branch, False{}),
    IO.bind(Nat, Unit, GitJob.count(r, thread), n => IO.bind(Unit, Unit, WtJob.restore.k(n, inbox, thread, r), _ => WtJob.done(r, inbox, thread, "worktree", branch, False{}))))

# a fork's worktree: a new branch like any thread's, then the source
# thread's last checkpoint restored into it, so the fork starts from the
# files as the source left them
def WtJob.fork.k(+r: String, +inbox: Chan(Msg), +thread: String, +src: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.or(GT.Git.failed(r), GT.Git.skipped(r)), WtJob.done(r, inbox, thread, "fork", branch, False{}),
    IO.bind(Nat, Unit, GitJob.count(r, src), n => IO.bind(Unit, Unit, WtJob.restore.k(n, inbox, src, r), _ => WtJob.done(r, inbox, thread, "fork", branch, False{}))))

def WtJob.fork(+inbox: Chan(Msg), +thread: String, +root: String, +src: String) -> IO(Unit):
  IO.bind(String, Unit, GT.Git.thread_wt(root, False{}, GT.Git.branch.temp(B.Wt.seed(thread))),
    r => WtJob.fork.k(r, inbox, thread, src, GT.Git.branch.sanitize(GT.Git.branch.temp(B.Wt.seed(thread)))))

def WtJob.run(+inbox: Chan(Msg), +thread: String, +root: String, +mode: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(mode, "again"),
    IO.bind(String, Unit, GT.Git.thread_wt.again(root, branch), r => WtJob.again.k(r, inbox, thread, branch)),
    Bool.pick(IO(Unit), String.eq(mode, "fork"), WtJob.fork(inbox, thread, root, branch),
      IO.bind(List<&2, String>, Unit, K.Io.names(root), ns => WtJob.go(B.Wt.hardware(ns), inbox, thread, root, mode))))

# Removing a thread's worktree (M.Worktree.drop): its state is kept first as
# a checkpoint (a hidden ref, so nothing is lost; the branch stays too),
# then the worktree goes. Only a directory under .backplane/worktrees is
# ever removed. A worktree already gone is reported gone.

def RmJob.done(+r: String, +inbox: Chan(Msg), +thread: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(r), Log.info("worktree not removed: " ++ r),
    do IO<Unit>:
      GitJob.say(inbox, "thread.unrooted", [J.KV{"thread", J.Str{thread}}])
      GitJob.note(inbox, thread, "info", "worktree removed; branch " ++ branch ++ " and its last state are kept"))

def RmJob.top(+top: String, +inbox: Chan(Msg), +thread: String, +root: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.not(M.Worktree.ours(top ++ "/")), Log.info("worktree not ours, kept: " ++ top),
    IO.bind(String, Unit, GT.Git.worktree.remove_force(root, top), r => RmJob.done(r, inbox, thread, branch)))

def RmJob.saved(+cp: String, +inbox: Chan(Msg), +thread: String, +wt: String, +root: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(cp), Log.info("worktree kept, no checkpoint: " ++ cp),
    IO.bind(String, Unit, GT.Git.root(wt), top => RmJob.top(top, inbox, thread, root, branch)))

def RmJob.there(r: P.Ran, +inbox: Chan(Msg), +thread: String, +wt: String, +root: String, +branch: String) -> IO(Unit):
  match r:
    case P.Ran{0, _}:
      IO.bind(Nat, Unit, GitJob.count(wt, thread), n => IO.bind(String, Unit, GT.Git.checkpoint.capture(wt, thread, n), cp => RmJob.saved(cp, inbox, thread, wt, root, branch)))
    case _:
      GitJob.say(inbox, "thread.unrooted", [J.KV{"thread", J.Str{thread}}])

def RmJob.run(+inbox: Chan(Msg), +thread: String, +wt: String, +root: String, +branch: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("test", ["-d", wt], "/"), r => RmJob.there(r, inbox, thread, wt, root, branch))

# Merges: which of a project's due branches gh reports merged (one call per
# project per tick; nothing happens without gh, auth or a GitHub remote)

def MergeJob.tell(hs: List<&2, J.KV>, +inbox: Chan(Msg)) -> IO(Unit):
  match hs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case J.KV{th, u} <> t:
      IO.bind(Unit, Unit, GitJob.say(inbox, "thread.merged", [J.KV{"thread", J.Str{th}}, J.KV{"url", u}]), _ => MergeJob.tell(t, inbox))

def MergeJob.got(r: P.Ran, +inbox: Chan(Msg), +lines: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      MergeJob.tell(B.Merge.hits(out, lines), inbox)
    case _:
      IO.pure(Unit, Unit{})

def MergeJob.run(+inbox: Chan(Msg), +root: String, +lines: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, GH.GhRun.run(root, "timeout", ["30", "gh", "pr", "list", "--state", "merged", "--limit", "100", "--json", "headRefName,url"], ["30", "gh", "pr", "list", "--state", "merged", "--limit", "100", "--json", "headRefName,url"]),
    r => MergeJob.got(r, inbox, lines))

def GitJob.text.k(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +what: String, +r: String) -> IO(Unit):
  do IO<Unit>:
    GitJob.reply(inbox, client, id, Bool.not(GT.Git.failed(r)), J.Json.obj([J.KV{"text", J.Str{r}}, J.KV{"thread", J.Str{thread}}]))
    GitJob.note(inbox, thread, Bool.pick(String, GT.Git.failed(r), "error", "info"), what ++ Bool.pick(String, String.is_empty(r), "", ": " ++ String.trim(r)))

def GitJob.diff.k(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +r: String) -> IO(Unit):
  GitJob.reply(inbox, client, id, Bool.not(GT.Git.failed(r)), J.Json.obj([J.KV{"diff", J.Str{r}}, J.KV{"thread", J.Str{thread}}]))

def GitJob.diff(+cwd: String, +thread: String, +a: String, +b: String) -> IO(String):
  Bool.pick(IO(String), String.eq(b, "-1"), GT.Git.checkpoint.diff_worktree(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n)),
    GT.Git.checkpoint.diff(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n), Maybe.default(&2, Nat, Nat.read(b), 0n)))

# One-shot writing (thread titles, branch names, commit messages)
# ----------------------------------------------------------------
# The text generation model (AG.Text.of: text.provider, text.model) run by
# AG.OneShot.args under timeout(1); the text goes on stdin
# (AG.OneShot.input). "" when the CLI is missing, fails, or takes longer
# than a minute; callers fall back.

def OneShot.out(r: P.Ran, +provider: String) -> String:
  match r:
    case P.Ran{0, out}:
      AG.OneShot.answer(provider, out)
    case _:
      ""

def OneShot.done(r: Socket & Result<&1, &1, U32 & String, Unit>, +pid: U32, +provider: String) -> IO(String):
  (s, _) = r
  do IO<String>:
    s2 : Socket <- H.Sock.shutdown(s)
    d : Socket & List<&2, U32> <- P.Proc.drain(1000000n, s2, P.Chunks{Nil{}})
    ran : P.Ran <- P.Proc.finish(pid, d)
    return OneShot.out(ran, provider)

def OneShot.started(started: U32 & Socket, +input: String, +provider: String) -> IO(String):
  (+pid, s) = started
  IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, String, H.Sock.send_text(s, input), r => OneShot.done(r, pid, provider))

def OneShot.spawned(r: Result<&1, &1, U32 & String, U32 & Socket>, +input: String, +provider: String) -> IO(String):
  match r:
    case Done{started}:
      OneShot.started(started, input, provider)
    case Fail{_}:
      IO.pure(String, "")

# the writer's answer to one text under a system prompt, in /tmp
def OneShot.run(+tx: AG.Tx, +system: String, +input: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, String, H.Proc.spawn("timeout", AG.OneShot.args(tx, system), "/tmp", 0),
    r => OneShot.spawned(r, AG.OneShot.input(AG.Tx.provider(tx), system, input), AG.Tx.provider(tx)))

# a thread's first message: the writer titles it, and the hub keeps the
# title only while the thread still has the placeholder (thread.titled)
def TitleJob.run(+tx: AG.Tx, +inbox: Chan(Msg), +thread: String, +placeholder: String, +text: String) -> IO(Unit):
  IO.bind(String, Unit, OneShot.run(tx, AG.Title.system(), text), a =>
    GitJob.say(inbox, "thread.titled", [J.KV{"thread", J.Str{thread}}, J.KV{"placeholder", J.Str{placeholder}}, J.KV{"title", J.Str{a}}]))

# a side question (/btw): the writing model reads the thread and the
# question; the answer goes to the asking client only
def BtwJob.run(+tx: AG.Tx, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +q: String, +input: String) -> IO(Unit):
  IO.bind(String, Unit, OneShot.run(tx, AG.Btw.system(), input), a =>
    GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"thread", J.Str{thread}}, J.KV{"q", J.Str{q}}, J.KV{"btw", J.Str{a}}])))

# a summary for the composer's reference menu (refs.bend's Sum.*): of a
# thread (kind "thread") or a project ("project"); the hub keeps it
# (summary.set {id, kind, text})
def SumJob.run(+tx: AG.Tx, +inbox: Chan(Msg), +id: String, +kind: String, +input: String) -> IO(Unit):
  IO.bind(String, Unit, OneShot.run(tx, RF.Sum.system(), input), a =>
    GitJob.say(inbox, "summary.set", [J.KV{"id", J.Str{id}}, J.KV{"kind", J.Str{kind}}, J.KV{"text", J.Str{a}}]))

def AgentJob.named(+r: String, +inbox: Chan(Msg), +thread: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(r), GitJob.note(inbox, thread, "error", "branch name: " ++ r),
    GitJob.say(inbox, "thread.branch", [J.KV{"thread", J.Str{thread}}, J.KV{"branch", J.Str{r}}]))

# a name another branch has already gets the temporary one's hex
def AgentJob.renamed(+r: String, +cwd: String, +old: String, +frag: String, +inbox: Chan(Msg), +thread: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(r),
    IO.bind(String, Unit, GT.Git.branch.rename(cwd, old, AG.Name.branch(frag) ++ "-" ++ String.drop(old, 10n)), r2 => AgentJob.named(r2, inbox, thread)),
    AgentJob.named(r, inbox, thread))

def AgentJob.rename(+frag: String, +cwd: String, +old: String, +inbox: Chan(Msg), +thread: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(frag), IO.pure(Unit, Unit{}),
    IO.bind(String, Unit, GT.Git.branch.rename(cwd, old, AG.Name.branch(frag)), r => AgentJob.renamed(r, cwd, old, frag, inbox, thread)))

# a worktree thread's first message names its branch; without an answer
# the temporary name stays
def AgentJob.name(+tx: AG.Tx, +inbox: Chan(Msg), +thread: String, +cwd: String, +old: String, +text: String) -> IO(Unit):
  IO.bind(String, Unit, OneShot.run(tx, AG.Name.system(), String.take(text, 4000n)), a => AgentJob.rename(AG.Name.fragment(a), cwd, old, inbox, thread))

def AgentJob.write(+tx: AG.Tx, +d: String, +title: String) -> IO(String):
  Bool.pick(IO(String), Bool.or(String.is_empty(String.trim(d)), GT.Git.failed(d)), IO.pure(String, title),
    IO.bind(String, String, OneShot.run(tx, AG.Commit.system(), AG.Commit.input(title, d)), a => IO.pure(String, AG.Commit.message(a, title))))

def AgentJob.commit(+msg: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +action: String) -> IO(Unit):
  IO.bind(String, Unit, GT.Git.act(cwd, action, msg, "", ""), r => GitJob.text.k(inbox, client, id, thread, action, r))

# Commit & push / Open PR with a message written from the thread's diff
# (checkpoint 0 against the work tree); the thread's title when there is
# no diff or no answer
def AgentJob.act(+tx: AG.Tx, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +action: String, +title: String) -> IO(Unit):
  do IO<Unit>:
    d : String <- GT.Git.checkpoint.diff_worktree(cwd, thread, 0n)
    msg : String <- AgentJob.write(tx, d, Bool.pick(String, String.is_empty(title), "Backplane: changes from this thread", title))
    AgentJob.commit(msg, inbox, client, id, thread, cwd, action)

def GitJob.go(i: Nat, +tx: AG.Tx, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +seed: Nat) -> IO(Unit):
  match i:
    case 0n:
      WtJob.run(inbox, thread, cwd, a, b)
    case 1n:
      IO.bind(Nat, Unit, GitJob.count(cwd, thread), n => GitJob.cp0.k(n, cwd, thread))
    case 2n:
      IO.bind(Nat, Unit, GitJob.count(cwd, thread), n => IO.bind(String, Unit, GT.Git.checkpoint.capture(cwd, thread, n), r => IO.pure(Unit, Unit{})))
    case 3n:
      IO.bind(String, Unit, GitJob.diff(cwd, thread, a, b), r => GitJob.diff.k(inbox, client, id, thread, r))
    case 4n:
      IO.bind(String, Unit, GT.Git.checkpoint.revert(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n)), r => GitJob.text.k(inbox, client, id, thread, "reverted to turn " ++ a, r))
    case 5n:
      IO.bind(String, Unit, GT.Git.act(cwd, a, Bool.pick(String, String.is_empty(b), "Backplane: changes from this thread", b), "", ""), r => GitJob.text.k(inbox, client, id, thread, a, r))
    case 6n:
      IO.bind(String, Unit, GT.Git.status(cwd), r => GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"status", J.Str{r}}, J.KV{"thread", J.Str{thread}}])))
    case 7n:
      AgentJob.name(tx, inbox, thread, cwd, a, b)
    case 8n:
      AgentJob.act(tx, inbox, client, id, thread, cwd, a, b)
    case _:
      IO.pure(Unit, Unit{})

def GitJob.repo(ok: Bool, +tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +seed: Nat) -> IO(Unit):
  match ok:
    case True{}:
      GitJob.go(C.Codec.pos(["worktree", "checkpoint0", "checkpoint", "diff", "revert", "act", "status", "name", "act_gen"], job), tx, inbox, client, id, thread, cwd, a, b, home, seed)
    case False{}:
      Bool.pick(IO(Unit), String.is_empty(id), IO.pure(Unit, Unit{}), GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{"not a git repository: " ++ cwd}}])))

# one git job; nothing happens outside a git repository (checkpoints are
# skipped, requests answer why)
def GitJob.run.git(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- GT.Git.is_repo(cwd)
    t : U32 <- H.Clock.epoch()
    GitJob.repo(ok, tx, job, inbox, client, id, thread, cwd, a, b, home, U32.to_nat(t))

# Sidebar jobs
# ------------
# A thread's files for the file picker (git's view of the tree in a
# repository, else a bounded walk; at most 3000), and 9:00 tomorrow in the
# machine's time zone for a snooze.

def Files.limit() -> String:
  "3000"

def Files.cmd(repo: Bool) -> String:
  match repo:
    case True{}:
      "git ls-files --cached --others --exclude-standard | head -n " ++ Files.limit()
    case False{}:
      "find . -maxdepth 8 -type f -not -path '*/.*' -not -path '*/node_modules/*' 2>/dev/null | head -n " ++ Files.limit() ++ " | sed 's|^\\./||'"

def Files.str(blank: Bool, l: String, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match blank:
    case True{}:
      rest
    case False{}:
      J.Str{l} <> rest

def Files.strs(ls: List<&2, String>) -> List<&2, J.Json>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Files.str(String.is_empty(String.trim(l)), l, Files.strs(t))

def Files.sent(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"files", J.Json.arr(Files.strs(String.lines(out)))}, J.KV{"thread", J.Str{thread}}]))
    case P.Ran{_, out}:
      GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{out}}]))

def Files.list(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String) -> IO(Unit):
  do IO<Unit>:
    repo : Bool <- GT.Git.is_repo(cwd)
    r : P.Ran <- P.Proc.run("sh", ["-c", Files.cmd(repo)], cwd)
    Files.sent(r, inbox, client, id, thread)

# a thread's mechanical parts for the Mechanical page: every model and
# render under the project's mech/ folder, sorted, one cksum line each
# (core/mech.bend reads them); none when there is no such folder
def Mech.cmd() -> String:
  "[ -d mech ] || exit 0; find mech -maxdepth 4 -type f \\( -iname '*.step' -o -iname '*.stp' -o -iname '*.glb' -o -iname '*.png' \\) -not -path '*/.*' 2>/dev/null | LC_ALL=C sort | head -n 400 | while IFS= read -r f; do cksum \"$f\"; done"

def Mech.sent(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"mech", J.Str{out}}, J.KV{"root", J.Str{cwd}}, J.KV{"thread", J.Str{thread}}]))
    case P.Ran{_, out}:
      GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{out}}]))

def Mech.list(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", Mech.cmd()], cwd), r => Mech.sent(r, inbox, client, id, thread, cwd))

# a part's renders, drawn on request (mech.render: the Mech page's
# Create renders): `backplane --render` beside this program, in the
# project, then the parts listed again; the answer is a listing that also
# names what was rendered and why it failed ("" when it did not)
def Mech.said(r: P.Ran) -> String:
  match r:
    case P.Ran{0, _}:
      ""
    case P.Ran{_, out}:
      String.take(String.trim(out), 300n)

def Mech.rendered(+err: String, l: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +path: String) -> IO(Unit):
  match l:
    case P.Ran{_, out}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"mech", J.Str{out}}, J.KV{"root", J.Str{cwd}}, J.KV{"thread", J.Str{thread}},
        J.KV{"rendered", J.Str{path}}, J.KV{"error", J.Str{err}}]))

def Mech.render(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    exe : String <- H.Sys.exe_dir()
    r : P.Ran <- P.Proc.run(exe ++ "/backplane", ["--render", path], cwd)
    l : P.Ran <- P.Proc.run("sh", ["-c", Mech.cmd()], cwd)
    Mech.rendered(Mech.said(r), l, inbox, client, id, thread, cwd, path)

def Snooze.tz(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      String.trim(out)
    case _:
      "+0000"

# a tick at start (threads idle past the window settle at once), then
# every minute
def Ticker.loop(fuel: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Tick{})
        tz : P.Ran <- P.Proc.run("date", ["+%z"], "/")
        ok2 : Bool <- Chan.send(Msg, inbox, BotTick{Snooze.tz(tz)})
        IO.sleep(60000)
        Ticker.loop(f, inbox)

# a heartbeat every Alive.every() ms: the clients that hear nothing for
# longer than Alive.limit() take the link for dead and reconnect
def Heart.loop(fuel: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(U32.from_nat(DK.Alive.every()))
        ok : Bool <- Chan.send(Msg, inbox, Heart{})
        Heart.loop(f, inbox)

# every five seconds the hub beats: held progress lines land (Hub.beat)
def Beat.loop(fuel: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(5000)
        ok : Bool <- Chan.send(Msg, inbox, Beat{})
        Beat.loop(f, inbox)

# snooze until 9:00 tomorrow here: the hub hears the time as thread.snooze
def Snooze.tomorrow(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +now: String) -> IO(Unit):
  do IO<Unit>:
    r : P.Ran <- P.Proc.run("date", ["+%z"], "/")
    GitJob.say(inbox, "thread.snooze", [J.KV{"thread", J.Str{thread}}, J.KV{"until", J.Num{Nat.show(M.Snooze.tomorrow(Maybe.default(&2, Nat, Nat.read(now), 0n), Snooze.tz(r)))}}])
    GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"thread", J.Str{thread}}]))

def Env.or(r: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match r:
    case Done{+v}:
      Bool.pick(String, String.is_empty(v), d, v)
    case Fail{_}:
      d

def Env.get(name: String, d: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return Env.or(r, d)

# open the thread's KiCad project in the bundled KiCad
def KiCadJob.run(+inbox: Chan(Msg), +client: U32, +id: String, +cwd: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    explicit : String <- Env.get("BACKPLANE_KICAD_CLI", "")
    exe : String <- H.Sys.exe_dir()
    rt : K.Rt <- K.Rt.resolve(explicit, exe, home)
    fs : K.Files <- K.Files.read(cwd)
    +err : String <- K.KiCad.open(rt, fs)
    GitJob.reply(inbox, client, id, String.is_empty(err), J.Json.obj([J.KV{"text", J.Str{err}}]))

# Design steps (core/hist.bend): after a tool call, the thread's KiCad
# files snapshot (Git.step.capture); a change is logged in the thread as
# an Act of tone "step" whose summary is its record. `entry` is the tool
# call or message it follows ("" at a turn's end).

def StepJob.log(+inbox: Chan(Msg), +thread: String, +id: String, +rec: String) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- Now.nat()
    ok : Bool <- Chan.send(Msg, inbox, Commit{[M.ActivityLogged{thread, id, HI.Step.tone(), "kicad", rec, now}]})
    return Unit{}

def StepJob.done(+inbox: Chan(Msg), +thread: String, +entry: String, +out: String) -> IO(Unit):
  +rec = HI.Hist.record(out, entry)
  Bool.pick(IO(Unit), String.is_empty(rec), IO.pure(Unit, Unit{}),
    StepJob.log(inbox, thread, "step:" ++ String.trim(HI.Hist.at(String.split(out, '\n'), 0n)), rec))

def StepJob.run(+inbox: Chan(Msg), +thread: String, +cwd: String, +entry: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(cwd), IO.pure(Unit, Unit{}),
    IO.bind(String, Unit, GT.Git.step.capture(cwd, thread), out => StepJob.done(inbox, thread, entry, out)))

def RefsJob.files(f: K.Files) -> List<&2, J.KV>:
  match f:
    case K.Files{_, pcb, sch, _}:
      [J.KV{"pcb", J.Str{pcb}}, J.KV{"sch", J.Str{sch}}]

# what the thread's files may be compared with (Git.refs), and its
# canonical board and schematic
def RefsJob.reply(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +ls: List<&2, String>, f: K.Files) -> IO(Unit):
  GitJob.reply(inbox, client, id, True{}, J.Json.obj(List.append(&2, J.KV, [J.KV{"thread", J.Str{thread}}, J.KV{"git", J.Str{HI.Hist.at(ls, 0n)}},
    J.KV{"top", J.Str{HI.Hist.at(ls, 1n)}}, J.KV{"refs", J.Str{String.join(List.drop(&2, String, ls, 2n), "\n")}}], RefsJob.files(f))))

def RefsJob.run(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String) -> IO(Unit):
  do IO<Unit>:
    out : String <- GT.Git.refs(cwd, thread)
    f : K.Files <- K.Files.read(cwd)
    RefsJob.reply(inbox, client, id, thread, String.split(out, '\n'), f)

def FileJob.done(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  match r:
    case P.Ran{0, _}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"text", J.Str{""}}]))
    case P.Ran{_, out}:
      GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{String.trim(out)}}]))

# a file link from a thread, opened here or shown in its folder (core's
# Link.file.cmd: the path goes as an argument, never as shell text)
def FileJob.run(+inbox: Chan(Msg), +client: U32, +id: String, +path: String, +how: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", LK.Link.file.cmd(how), "sh", path], "/"), r => FileJob.done(r, inbox, client, id))

# The viewer's Files tab (core/fm.bend): one folder of a thread's project,
# its folders then its files ("d|f <tab> size <tab> name"), hidden ones and
# symlinked folders left out, 2000 of each at most
def DirJob.sh() -> String:
  "cd \"$1\" 2>/dev/null || { echo 'no such folder'; exit 1; }; [ -z \"$2\" ] || cd \"./$2\" 2>/dev/null || { echo 'no such folder'; exit 1; }; for f in *; do [ -d \"$f\" ] && [ ! -L \"$f\" ] && printf 'd\\t0\\t%s\\n' \"$f\"; done | head -n 2000; for f in *; do [ -f \"$f\" ] && printf 'f\\t%s\\t%s\\n' \"$(wc -c < \"$f\" | tr -d ' ')\" \"$f\"; done | head -n 2000; true"

def DirJob.sent(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +rel: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"fmEntries", J.Str{out}}, J.KV{"fmDir", J.Str{rel}}, J.KV{"fmRoot", J.Str{cwd}}, J.KV{"thread", J.Str{thread}}]))
    case P.Ran{_, out}:
      GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{String.trim(out)}}]))

def DirJob.run(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +rel: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", DirJob.sh(), "sh", cwd, rel], "/"), r => DirJob.sent(r, inbox, client, id, thread, cwd, rel))

# a PDF's page drawn to a PNG for the window (which cannot draw a PDF), by
# poppler's pdftoppm when this machine has it, kept in <home>/pdf per file
# version and page: "<png> <tab> <pages>"
def PdfJob.sh() -> String:
  "command -v pdftoppm >/dev/null 2>&1 || { echo 'nopoppler'; exit 3; }; [ -f \"$1\" ] || { echo 'no such file'; exit 1; }; m=$(stat -c %Y \"$1\" 2>/dev/null || stat -f %m \"$1\"); k=$(printf '%s %s' \"$1\" \"$m\" | cksum | cut -d' ' -f1); mkdir -p \"$3\"; o=\"$3/$k-$2\"; [ -f \"$o.png\" ] || pdftoppm -png -r 110 -f \"$2\" -l \"$2\" -singlefile \"$1\" \"$o\" >/dev/null 2>&1 || { echo \"could not draw page $2\"; exit 1; }; n=$(pdfinfo \"$1\" 2>/dev/null | awk '/^Pages:/{print $2}'); printf '%s\\t%s' \"$o.png\" \"${n:-0}\""

def PdfJob.why(+out: String) -> String:
  Bool.pick(String, String.contains(out, "nopoppler"), "PDFs show here with poppler's pdftoppm (the poppler or poppler-utils package)", String.trim(out))

def PdfJob.sent(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String, +path: String, +page: String) -> IO(Unit):
  match r:
    case P.Ran{0, +out}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"pdfPath", J.Str{path}}, J.KV{"pdfPage", J.Str{page}},
        J.KV{"pdfPng", J.Str{Maybe.default(&2, String, List.head(&2, String, String.split(out, '\t')), "")}},
        J.KV{"pdfPages", J.Str{String.trim(Maybe.default(&2, String, List.get(&2, String, String.split(out, '\t'), 1n), "0"))}}]))
    case P.Ran{_, +out}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"pdfPath", J.Str{path}}, J.KV{"pdfPage", J.Str{page}}, J.KV{"pdfErr", J.Str{PdfJob.why(out)}}]))

def PdfJob.run(+inbox: Chan(Msg), +client: U32, +id: String, +home: String, +path: String, +page: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", PdfJob.sh(), "sh", path, page, home ++ "/pdf"], "/"), r => PdfJob.sent(r, inbox, client, id, path, page))

def GitJob.run.k(i: Nat, +tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  match i:
    case 0n:
      Files.list(inbox, client, id, thread, cwd)
    case 1n:
      Snooze.tomorrow(inbox, client, id, thread, a)
    case 2n:
      WtJob.run(inbox, thread, cwd, a, b)
    case 3n:
      MergeJob.run(inbox, cwd, a)
    case 4n:
      RmJob.run(inbox, thread, cwd, a, b)
    case 5n:
      KiCadJob.run(inbox, client, id, cwd, home)
    case 6n:
      TitleJob.run(tx, inbox, thread, a, b)
    case 7n:
      BtwJob.run(tx, inbox, client, id, thread, a, b)
    case 8n:
      SumJob.run(tx, inbox, thread, a, b)
    case 9n:
      Mech.list(inbox, client, id, thread, cwd)
    case 10n:
      Mech.render(inbox, client, id, thread, cwd, a)
    case 11n:
      StepJob.run(inbox, thread, cwd, a)
    case 12n:
      RefsJob.run(inbox, client, id, thread, cwd)
    case 13n:
      FileJob.run(inbox, client, id, a, b)
    case 14n:
      DirJob.run(inbox, client, id, thread, cwd, a)
    case 15n:
      PdfJob.run(inbox, client, id, home, a, b)
    case _:
      GitJob.run.git(tx, job, inbox, client, id, thread, cwd, a, b, home)

# a job the hub asked for: a git job, or one of the sidebar's
def GitJob.run(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  GitJob.run.k(C.Codec.pos(["files", "snooze", "worktree", "merged", "wt_remove", "kicad", "title", "btw", "summary", "mech", "render", "step", "refs", "open", "dir", "pdf"], job), tx, job, inbox, client, id, thread, cwd, a, b, home)

# Grok (grok agent stdio, ACP)
# ----------------------------
# One process per turn. Acp.line decides what to write back and what to
# report; the reports are Codex-shaped lines for the hub.

def Grok.perm(r: M.RuntimeMode) -> List<&2, String>:
  match r:
    case M.Supervised{}:
      ["--permission-mode", "default", "agent"]
    case M.AcceptEdits{}:
      ["--permission-mode", "acceptEdits", "agent"]
    case M.AutoMode{}:
      ["--permission-mode", "auto", "agent"]
    case M.FullAccess{}:
      ["agent", "--always-approve"]

def Grok.args(r: M.RuntimeMode, +model: String, +effort: String) -> List<&2, String>:
  List.concat(&2, String, [Grok.perm(r), Codex.opt("-m", model), AG.Effort.args("grok", effort), ["stdio"]])

# whether Grok's tool requests go to the user (all modes but full access)
def Grok.asks(r: M.RuntimeMode) -> Bool:
  match r:
    case M.FullAccess{}:
      False{}
    case _:
      True{}

def Grok.report(ls: List<&2, String>, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, l})
        Grok.report(t, thread, inbox)

def Grok.write(ls: List<&2, String>, +input: Chan(String)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, input, l)
        Grok.write(t, input)

def Grok.acp(o: AC.AcpOut) -> AC.Acp:
  match o:
    case AC.AcpOut{a, _, _, _}:
      a

def Grok.done(a: AC.Acp) -> Bool:
  match a:
    case AC.Acp{_, _, d}:
      d

def Grok.answered(m: Maybe<&1, String>, +input: Chan(String)) -> IO(Unit):
  match m:
    case Some{+line}:
      Bool.pick(IO(Unit), String.is_empty(line), IO.pure(Unit, Unit{}), Grok.write([line], input))
    case None{}:
      IO.pure(Unit, Unit{})

# a permission request waits off the reader: the hub allows a tool already
# allowed for the session, or opens an approval and parks the request;
# the ACP answer then goes to grok
def Grok.ask.one(+line: String, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +reply : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(Msg, inbox, Mcp{thread, line, reply})
    m : Maybe<&1, String> <- Chan.recv(String, reply)
    Grok.answered(m, input)

def Grok.ask(ls: List<&2, String>, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        IO.spawn(Unit, Grok.ask.one(l, thread, input, inbox))
        Grok.ask(t, thread, input, inbox)

def Grok.out(o: AC.AcpOut, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(AC.Acp):
  match o:
    case AC.AcpOut{a, send, emit, asks}:
      do IO<AC.Acp>:
        Grok.write(send, input)
        Grok.report(emit, thread, inbox)
        Grok.ask(asks, thread, input, inbox)
        return a

# every line of a chunk, in order, through the ACP state
def Grok.lines(ls: List<&2, String>, a: AC.Acp, +t: AC.AcpTurn, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(AC.Acp):
  match ls:
    case Nil{}:
      IO.pure(AC.Acp, a)
    case l <> rest:
      IO.bind(AC.Acp, AC.Acp, Grok.out(AC.Acp.line(a, t, l), thread, input, inbox), a2 => Grok.lines(rest, a2, t, thread, input, inbox))

# a per-turn process is done: its turn already ended through its own
# events, so its exit tells the hub nothing (a queued turn may be running)
def Turn.end(s: Socket, +pid: U32, +tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    ok : Bool <- Chan.send(Msg, inbox, TurnDone{tag})
    return Unit{}

# output closed: a turn that never ended fails; the exit itself is not news
def Codex.end(s: Socket, +pid: U32, ended: Bool, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ended:
    case True{}:
      Turn.end(s, pid, thread, inbox)
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, AC.Acp.failed("codex exited before the turn ended")})
        Turn.end(s, pid, thread, inbox)

# the stream ended: a last line with no newline still counts (a turn's
# final event written just before the process died), then the usual end
def Codex.last(carry: U.Lines, s: Socket, +ended: Bool, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +rest : String = U.Lines.rest(carry)
    e2 : Bool <- Codex.lines(Bool.pick(List<&2, String>, String.is_empty(String.trim(rest)), Nil{}, [rest]), ended, thread, inbox)
    Codex.end(s, pid, e2, thread, inbox)

def Codex.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, +ended: Bool, +pid: U32, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> Bool -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Codex.last(carry, s, ended, pid, thread, inbox)
    case Done{bs}:
      Codex.fed(U.Lines.feed(carry, bs), s, ended, thread, inbox, k)
    case Fail{_}:
      Codex.last(carry, s, ended, pid, thread, inbox)

def Codex.reader(fuel: Nat, s: Socket, carry: U.Lines, +ended: Bool, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Codex.end(s, pid, ended, thread, inbox)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Codex.got(r, carry, ended, pid, thread, inbox, s2 => c2 => e2 => Codex.reader(f, s2, c2, e2, pid, thread, inbox)))

def Codex.read(started: U32 & Socket, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  (+pid, s) = started
  do IO<Unit>:
    s2 : Socket <- H.Sock.shutdown(s)
    +input : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(Msg, inbox, TurnPid{thread, pid, input, gen})
    s3 : Socket <- IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Socket, H.Sock.dup(s2), d => Agent.watch.start(d, pid, thread, gen, inbox))
    Codex.reader(Fuel.forever(), s3, U.Lines.new(), False{}, pid, B.Tag.of(thread, pid), inbox)

def Codex.started(r: Result<&1, &1, U32 & String, U32 & Socket>, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case Done{started}:
      Codex.read(started, thread, gen, inbox)
    case Fail{e}:
      Codex.failed(e, thread, gen, inbox)

def Codex.run(+limit: String, +args: List<&2, String>, +cwd: String, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Unit, Ctn.spawn(limit, thread, gen, "codex", args, cwd), r => Codex.started(r, thread, gen, inbox))

def Grok.stop(s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Proc.kill(pid, 15)
    Turn.end(s, pid, thread, inbox)

def Grok.next(done: Bool, s: Socket, carry: U.Lines, a: AC.Acp, +pid: U32, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}:
      Grok.stop(s, pid, thread, inbox)
    case False{}:
      k(s, carry, a)

def Grok.after(+a: AC.Acp, s: Socket, carry: U.Lines, +pid: U32, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  Grok.next(Grok.done(a), s, carry, a, pid, thread, inbox, k)

def Grok.fed(r: U.Lines & List<&2, String>, s: Socket, a: AC.Acp, +t: AC.AcpTurn, +pid: U32, +thread: String, +input: Chan(String), +inbox: Chan(Msg),
    k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  (carry, ls) = r
  IO.bind(AC.Acp, Unit, Grok.lines(ls, a, t, thread, input, inbox), a2 => Grok.after(a2, s, carry, pid, thread, inbox, k))

# the agent closed its output before the turn ended
def Grok.gone(s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Grok.report([AC.Acp.failed("grok exited before the turn ended (is it signed in? run `grok login`)")], thread, inbox)
    Turn.end(s, pid, thread, inbox)

def Grok.last.k(done: Bool, s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match done:
    case True{}:
      Turn.end(s, pid, thread, inbox)
    case False{}:
      Grok.gone(s, pid, thread, inbox)

def Grok.last.a(+a: AC.Acp, s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  Grok.last.k(Grok.done(a), s, pid, thread, inbox)

# the stream ended: a last line with no newline still counts (the turn's
# end written just before the process died); only a turn it does not end
# fails as one that exited early
def Grok.last(carry: U.Lines, s: Socket, a: AC.Acp, +t: AC.AcpTurn, +pid: U32, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +rest : String = U.Lines.rest(carry)
    a2 : AC.Acp <- Grok.lines(Bool.pick(List<&2, String>, String.is_empty(String.trim(rest)), Nil{}, [rest]), a, t, thread, input, inbox)
    Grok.last.a(a2, s, pid, thread, inbox)

def Grok.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, a: AC.Acp, +t: AC.AcpTurn, +pid: U32, +thread: String, +input: Chan(String), +inbox: Chan(Msg),
    k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Grok.last(carry, s, a, t, pid, thread, input, inbox)
    case Done{bs}:
      Grok.fed(U.Lines.feed(carry, bs), s, a, t, pid, thread, input, inbox, k)
    case Fail{_}:
      Grok.last(carry, s, a, t, pid, thread, input, inbox)

def Grok.reader(fuel: Nat, s: Socket, carry: U.Lines, a: AC.Acp, +t: AC.AcpTurn, +pid: U32, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Agent.end(s, pid, thread, inbox)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Grok.got(r, carry, a, t, pid, thread, input, inbox, s2 => c2 => a2 => Grok.reader(f, s2, c2, a2, t, pid, thread, input, inbox)))

# a Grok process whose socket could not be shared is stopped and its turn
# fails as one that could not start
def Grok.dup.failed(e: U32 & String, rd: Socket, +pid: U32, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, msg) = e
  do IO<Unit>:
    Socket.close(rd)
    Proc.kill(pid, 15)
    ok : Bool <- Chan.send(Msg, inbox, SpawnFailed{thread, gen, AC.Acp.failed("could not start grok: " ++ msg)})
    return Unit{}

def Grok.duped(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, +t: AC.AcpTurn, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  (rd, res) = r
  match res:
    case Done{wr}:
      do IO<Unit>:
        +input : Chan(String) <- Chan.new(String, 64)
        IO.spawn(Unit, Agent.writer(Fuel.forever(), wr, input))
        ok : Bool <- Chan.send(Msg, inbox, TurnPid{thread, pid, input, gen})
        ok2 : Bool <- Chan.send(String, input, AC.Acp.init())
        rd2 : Socket <- IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Socket, H.Sock.dup(rd), d => Agent.watch.start(d, pid, thread, gen, inbox))
        Grok.reader(Fuel.forever(), rd2, U.Lines.new(), AC.Acp.new(), t, pid, B.Tag.of(thread, pid), input, inbox)
    case Fail{e}:
      Grok.dup.failed(e, rd, pid, thread, gen, inbox)

def Grok.started.ok(started: U32 & Socket, +t: AC.AcpTurn, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  (+pid, s) = started
  IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Unit, H.Sock.dup(s), r => Grok.duped(r, pid, t, thread, gen, inbox))

def Grok.failed(e: U32 & String, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, msg) = e
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, SpawnFailed{thread, gen, AC.Acp.failed("could not start grok: " ++ msg ++ ". Install Grok Build with `curl -fsSL https://x.ai/cli/install.sh | bash`, then `grok login`.")})
    return Unit{}

def Grok.started(r: Result<&1, &1, U32 & String, U32 & Socket>, +t: AC.AcpTurn, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case Done{started}:
      Grok.started.ok(started, t, thread, gen, inbox)
    case Fail{e}:
      Grok.failed(e, thread, gen, inbox)

def Grok.run(+limit: String, +args: List<&2, String>, +t: AC.AcpTurn, +cwd: String, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Unit, Ctn.spawn(limit, thread, gen, "grok", args, cwd), r => Grok.started(r, t, thread, gen, inbox))

# Updates
# -------

def Cfg.home(c: Cfg) -> String:
  match c:
    case Cfg{h, _, _, _, _, _, _, _}:
      h

def Upgrade.note(kvs: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj(J.KV{"t", J.Str{"update"}} <> kvs))

def Upgrade.say(+inbox: Chan(Msg), text: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, Announce{text})
    return Unit{}

def Upgrade.exec.fail(e: U32 & String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, m) = e
  Upgrade.say(inbox, Upgrade.note([J.KV{"error", J.Str{"restart failed: " ++ m}}]))

def Upgrade.exec(r: Result<&1, &1, U32 & String, Unit>, +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case Done{_}:
      IO.pure(Unit, Unit{})
    case Fail{e}:
      Upgrade.exec.fail(e, inbox)

def Upgrade.found.k(none: Bool, +tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Upgrade.say(inbox, Upgrade.note([J.KV{"version", J.Str{tag}}]))

def Upgrade.found(+tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  Upgrade.found.k(String.is_empty(tag), tag, inbox)

# 15 s after start, then hourly: the hub looks for a newer release on the
# update channel (it holds the setting)
def Upgrade.check(fuel: Nat, +wait: U32, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(wait)
        ok : Bool <- Chan.send(Msg, inbox, UpdateCheck{})
        Upgrade.check(f, 3600000, inbox)

def Upgrade.start.go(on: Bool, +inbox: Chan(Msg)) -> IO(Unit):
  match on:
    case True{}:
      IO.spawn(Unit, Upgrade.check(Fuel.forever(), 15000, inbox))
    case False{}:
      IO.pure(Unit, Unit{})

# Remote access (Tailscale)
# ------------------------

def Cfg.net(c: Cfg) -> Net:
  match c:
    case Cfg{_, _, _, _, _, _, _, n}:
      n

def Cfg.port(c: Cfg) -> U32:
  match c:
    case Cfg{_, _, _, p, _, _, _, _}:
      p

def Net.token(n: Net) -> String:
  match n:
    case Net{_, _, t, _, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}:
      t

# updates come from a package (SV.Chan.managed): the updater stays off
def Net.managed(n: Net) -> Bool:
  match n:
    case Net{_, _, _, _, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}:
      mgd

# Effects
# -------

# the MCP endpoint of one thread's agent (token included, so the tailnet
# rules never lock an agent out)
# (gen: the process's generation, B.Gen.mcp: a call from a process that is
# no longer the thread's may only read)
def Hub.mcp_url.g(+cfg: Cfg, +thread: String, +gen: String) -> String:
  "http://127.0.0.1:" ++ U32.show(Cfg.port(cfg)) ++ "/mcp/" ++ B.Gen.mcp(thread, gen) ++ "?token=" ++ Net.token(Cfg.net(cfg))

def Hub.mcp_url(+cfg: Cfg, +thread: String) -> String:
  "http://127.0.0.1:" ++ U32.show(Cfg.port(cfg)) ++ "/mcp/" ++ thread ++ "?token=" ++ Net.token(Cfg.net(cfg))

def Cfg.mtext(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, mt, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      mt

def Cfg.rt(c: Cfg) -> K.Rt:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      rt

def Hub.prompt.kicad(rt: K.Rt, ipc: Bool) -> String:
  match rt:
    case K.Rt{+cli, fork, +v, +c}:
      Q.Prompt.kicad(cli, fork, v, c, ipc)

def Hub.prompt.files(+cwd: String, fs: K.Files) -> String:
  match fs:
    case K.Files{+pro, +pcb, +sch, +all}:
      Q.Prompt.project(cwd, pro, pcb, sch, all)

# one thread's instructions: the shared runtime and skills, then this
# machine's KiCad, the project's canonical files, and what it may delegate
# (keys: the API keys' block, server/apikeys.bend's Ak.prompt, "" for none)
def Hub.prompt(+cfg: Cfg, +st: M.State, +thread: String, +cwd: String, fs: K.Files, +keys: String) -> String:
  String.join([Cfg.prompt(cfg),
    Hub.prompt.kicad(Cfg.rt(cfg), Bool.not(String.eq(M.Setting.get(st, "kicad.ipc", "on"), "off"))),
    Hub.prompt.files(cwd, fs),
    Q.Prompt.orchestration(M.Task.may_delegate(B.Task.depth(st, thread)), Cfg.mtext(cfg)), Q.Prompt.background()], "\n\n") ++ Bool.pick(String, String.is_empty(keys), "", "\n\n" ++ keys) ++ BH.Bots.prompt(st, thread, Cfg.home(cfg))

def Hub.agent_args(+cfg: Cfg, +thread: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, prompt: String, +effort: String, +gen: String) -> List<&2, String>:
  match cfg:
    case Cfg{+home, _, _, _, _, +dirs, _, _}:
      List.append(&2, String, Q.Claude.args(model, session, r, i, prompt, List.append(&2, String, dirs, [home ++ "/attachments"])), List.append(&2, String, AG.Effort.args("claude", effort), List.append(&2, String, Q.Claude.plugins(dirs),
        ["--mcp-config", "{\"mcpServers\":{\"backplane\":{\"type\":\"http\",\"url\":\"" ++ Hub.mcp_url.g(cfg, thread, gen) ++ "\"}}}"])))

# what a Claude process was started with; a turn asking for something else
# (another model, mode or effort) restarts it
def Agent.key(+model: String, r: M.RuntimeMode, i: M.InteractionMode, +effort: String) -> String:
  model ++ "|" ++ C.Runtime.name(r) ++ "|" ++ C.Interaction.name(i) ++ "|" ++ AG.Effort.of("claude", effort)

def Agent.same(m: Maybe<&2, Agent>, +key: String) -> Bool:
  match m:
    case Some{Agent{_, _, _, k, _}}:
      String.eq(k, key)
    case None{}:
      False{}

# an agent starting in a KiCad project opens its thread's panel on the
# board, unless the person has opened or shut it by hand (core's Auto.view,
# client.bend's Viewer.auto)
def Hub.auto.k(empty: Bool, +cl: List<&2, Client>, +text: String) -> IO(List<&2, Client>):
  match empty:
    case True{}:
      IO.pure(List<&2, Client>, cl)
    case False{}:
      Wire.all(cl, text)

def Hub.auto(+cl: List<&2, Client>, +thread: String, fs: K.Files) -> IO(List<&2, Client>):
  match fs:
    case K.Files{_, +pcb, +sch, _}:
      Hub.auto.k(String.is_empty(B.Auto.view(thread, pcb, sch)), cl, B.Auto.view(thread, pcb, sch))

# the process a thread's agent replaces: its background work is told lost
# first, synchronously, so the new process's rows are never touched (law
# replaced_keeps_new_rows); a note to a running turn waits behind it
def Hub.replaced(has: Bool, +st: M.State, +now: Nat, +thread: String) -> List<&2, M.Change>:
  match has:
    case True{}:
      B.Queue.changes(B.Bg.lost(st, now, thread, "replaced"))
    case False{}:
      Nil{}

def Agent.is(m: Maybe<&2, Agent>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# `codex exec` for one turn, with this thread's MCP endpoint and the
# Backplane instructions (the same runtime block Claude gets)
def Codex.args(+cfg: Cfg, +thread: String, +model: String, +session: String, r: M.RuntimeMode, +text: String, prompt: String, +effort: String, +gen: String) -> List<&2, String>:
  List.concat(&2, String, [Codex.head.k(String.is_empty(session), session), Codex.sandbox(r), Codex.opt("-m", model), AG.Effort.args("codex", effort), AT.Att.codex(text),
    ["-c", "mcp_servers.backplane.url=\"" ++ Hub.mcp_url.g(cfg, thread, gen) ++ "\"",
     "-c", "developer_instructions=" ++ J.Json.show(J.Str{prompt}), text]])

# what a tailscale command printed ("" when it failed)
def Tailnet.out(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      out
    case _:
      ""

def Tailnet.first(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      String.trim(Maybe.default(&2, String, List.head(&2, String, String.lines(out)), ""))
    case _:
      ""

def Tailnet.dns.k(+name: String) -> String:
  Bool.pick(String, String.ends_with(name, "."), String.take(name, Nat.sub(String.length(name), 1n)), name)

def Tailnet.dns(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      Tailnet.dns.k(J.Json.get_str(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(out), J.Null{}), "Self"), "DNSName", ""))
    case _:
      ""

def Tailnet.https.k(none: Bool, +name: String, +token: String, +inbox: Chan(Msg)) -> IO(Unit):
  match none:
    case True{}:
      Log.info("tailscale serve did not report a DNS name")
    case False{}:
      do IO<Unit>:
        IO.print("Backplane over HTTPS on your tailnet: " ++ TN.Tailnet.link("https://" ++ name, token))
        ok : Bool <- Chan.send(Msg, inbox, LinkFound{TN.Tailnet.link("https://" ++ name, token)})
        return Unit{}

def Tailnet.https(on: Bool, +port: U32, +token: String, +inbox: Chan(Msg)) -> IO(Unit):
  match on:
    case True{}:
      do IO<Unit>:
        s : P.Ran <- P.Proc.run("tailscale", ["serve", "--bg", "--https=443", "http://127.0.0.1:" ++ U32.show(port)], "")
        st : P.Ran <- P.Proc.run("tailscale", ["status", "--json"], "")
        +name : String = Tailnet.dns(st)
        Tailnet.https.k(String.is_empty(name), name, token, inbox)
    case False{}:
      IO.pure(Unit, Unit{})

def Token.digit(+d: U32) -> Char:
  Chr{U32.add(d, Bool.pick(U32, U32.is_lt(d, 10), 48, 87))}

def Token.hex.go(n: Nat, +x: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+m:
      Token.hex.go(m, U32.shrn(x, 4n), SCon{Token.digit(U32.and(x, 15)), acc})

# the pairing token: made once (128 random bits, hex), kept in the home
def Token.hex(+x: U32) -> String:
  Token.hex.go(8n, x, "")

def Token.fresh() -> IO(String):
  do IO<String>:
    a : U32 <- IO.try(U32, IO.random_u32())
    b : U32 <- IO.try(U32, IO.random_u32())
    c : U32 <- IO.try(U32, IO.random_u32())
    d : U32 <- IO.try(U32, IO.random_u32())
    return Token.hex(a) ++ Token.hex(b) ++ Token.hex(c) ++ Token.hex(d)

def Token.closed(w: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = w
  File.close(f)

def Token.write(r: Result<&1, &1, U32 & String, File>, +t: String) -> IO(Unit):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, t), w => Token.closed(w))
    case Fail{_}:
      IO.pure(Unit, Unit{})

def Token.save(+path: String, +t: String) -> IO(String):
  do IO<String>:
    f : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    Token.write(f, t)
    m : Result<&1, &1, U32 & String, Unit> <- H.FS.chmod(path, 384)
    return t

def Token.load.k(none: Bool, +path: String, +have: String) -> IO(String):
  match none:
    case True{}:
      IO.bind(String, String, Token.fresh(), t => Token.save(path, t))
    case False{}:
      IO.pure(String, have)

def Token.load(+home: String) -> IO(String):
  do IO<String>:
    +have : String <- Files.text(home ++ "/token")
    Token.load.k(String.is_empty(String.trim(have)), home ++ "/token", String.trim(have))

def Cfg.with_token(c: Cfg, +t: String) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, _, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}

def Cfg.with_managed(c: Cfg, m: Bool) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, _, lk, fc}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, m, lk, fc}}

# Startup
# -------

def Upgrade.start(+cfg: Cfg, +inbox: Chan(Msg)) -> IO(Unit):
  Upgrade.start.go(Bool.not(Net.managed(Cfg.net(cfg))), inbox)

def Names.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Names.copy(t)

def Upgrade.done.k(ok: Bool, +err: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"restarting"}}]))
        path : String <- H.Sys.exe_path()
        args : List<String> <- IO.args()
        r : Result<&1, &1, U32 & String, Unit> <- H.Sys.exec(path, Names.copy(args))
        Upgrade.exec(r, inbox)
    case False{}:
      Upgrade.say(inbox, Upgrade.note([J.KV{"error", J.Str{err}}]))

def Upgrade.done(+err: String, +inbox: Chan(Msg)) -> IO(Unit):
  Upgrade.done.k(String.is_empty(err), err, inbox)

# install Backplane KiCad beside our data and restart to pick it up
def Install.go(+home: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"installing Backplane KiCad"}}]))
    err : String <- K.KiCad.install(home)
    Upgrade.done(err, inbox)

# install the channel's newest release and restart into it
def Upgrade.go.k(+home: String, +channel: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"updating"}}]))
    exe : String <- H.Sys.exe_dir()
    err : String <- UP.Update.apply(channel, exe, home)
    Upgrade.done(err, inbox)

def Upgrade.go(managed: Bool, +home: String, +channel: String, +inbox: Chan(Msg)) -> IO(Unit):
  match managed:
    case True{}:
      Upgrade.say(inbox, Upgrade.note([J.KV{"error", J.Str{"this install updates through its package"}}]))
    case False{}:
      Upgrade.go.k(home, channel, inbox)

def Agent.pid_is(m: Maybe<&2, Agent>, +pid: U32) -> Bool:
  match m:
    case Some{Agent{_, _, p, _, _}}:
      U32.is_eq(p, pid)
    case None{}:
      False{}

def Cfg.models(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, ms, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      ms

def Cfg.pk(c: Cfg) -> Maybe<&2, Chan(PK.PMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, pk, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      pk

def Park.put(m: Maybe<&2, Chan(PK.PMsg)>, +msg: PK.PMsg) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        ok : Bool <- Chan.send(PK.PMsg, q, msg)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

# a phone push for an ended turn, off the hub loop; the tokens APNs calls
# dead come back as device.drop requests, as if a client had sent them
def Hub.drop_dead(ts: List<&2, String>, +inbox: Chan(Msg)) -> IO(Unit):
  match ts:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case t <> rest:
      IO.bind(Bool, Unit, Chan.send(Msg, inbox, Rpc{0, PU.Push.drop_request(t)}), _ => Hub.drop_dead(rest, inbox))

def Hub.phone(+home: String, st: M.State, +thread: String, +state: String, seen: Bool, +inbox: Chan(Msg)) -> IO(Unit):
  IO.bind(List<&2, String>, Unit, PU.Push.turn_ended.dead(home, st, thread, state, seen), ds => Hub.drop_dead(ds, inbox))

def Desk.tell.go(quiet: Bool, +n: NO.Notice, +cl: List<&2, Client>, +c: U32, +st: M.State, +thread: String, +state: String) -> IO(List<&2, Client>):
  match quiet:
    case True{}:
      IO.pure(List<&2, Client>, cl)
    case False{}:
      Wire.to(cl, c, DK.Desk.notify(thread, PU.Push.title(B.Hub.thread(st, thread)),
        PU.Push.body(String.eq(state, "failed"), PU.Push.first(B.Task.last(st, thread))), NO.Notice.kind(n), NO.Notice.key(n)))

def Desk.tell.k(+n: NO.Notice, +cl: List<&2, Client>, +c: U32, +st: M.State, +thread: String, +state: String) -> IO(List<&2, Client>):
  Desk.tell.go(String.is_empty(NO.Notice.kind(n)), n, cl, c, st, thread, state)

# a turn's end as a desktop notification, on the desk used last, when it
# is news (core/notice.bend, as for phones) and no desk watches the thread
def Desk.tell(m: Maybe<&2, U32>, +cl: List<&2, Client>, +st: M.State, +thread: String, +state: String) -> IO(List<&2, Client>):
  match m:
    case Some{+c}:
      Desk.tell.k(NO.Notice.of(st, thread, String.eq(state, "failed"), True{}), cl, c, st, thread, state)
    case None{}:
      IO.pure(List<&2, Client>, cl)

# the reply now, or (for a request that waits on the user) parked until
# the ask it opened is answered
def Hub.mcp.send(later: Bool, +park: String, +body: String, +text: String, +reply: Chan(String), +cfg: Cfg) -> IO(Unit):
  match later:
    case True{}:
      Park.put(Cfg.pk(cfg), PK.PPark{park, body, reply})
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, reply, text)
        return Unit{}

def Net.with_br(n: Net, q: Chan(BR.BMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, _, g, i, mc, pvx, bnx, mgd, lk, fc}:
      Net{a, b, c, d, e, f, Some{q}, g, i, mc, pvx, bnx, mgd, lk, fc}

def Net.with_tm(n: Net, q: Chan(TM.TMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, g, h, _, mc, pvx, bnx, mgd, lk, fc}:
      Net{a, b, c, d, e, f, g, h, Some{q}, mc, pvx, bnx, mgd, lk, fc}

def Net.with_pv(n: Net, q: Chan(PV.PMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, g, h, i, mc, _, bnx, mgd, lk, fc}:
      Net{a, b, c, d, e, f, g, h, i, mc, Some{q}, bnx, mgd, lk, fc}

def Cfg.pv(c: Cfg) -> Maybe<&2, Chan(PV.PMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, _, _, _, pv, bnx, mgd, lk, fc}}:
      pv

def Cfg.tm(c: Cfg) -> Maybe<&2, Chan(TM.TMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, _, tm, mc, pvx, bnx, mgd, lk, fc}}:
      tm

# a shell's output, to the hub (which sends it to every client)
def Term.fwd.got(m: Maybe<&1, TM.TOut>, +inbox: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{TM.TOut{th, bs}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, TermOut{th, bs})
        k(Unit{})
    case Some{TM.TTo{c, key, co, ro, bs}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, TermTo{c, key, co, ro, bs})
        k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

def Term.fwd(fuel: Nat, +out: Chan(TM.TOut), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, TM.TOut>, Unit, Chan.recv(TM.TOut, out), m => Term.fwd.got(m, inbox, u => Term.fwd(f, out, inbox)))

def Term.put(m: Maybe<&2, Chan(TM.TMsg)>, +msg: TM.TMsg) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        ok : Bool <- Chan.send(TM.TMsg, q, msg)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

# The phones' viewer
# ------------------

# a plot for a phone, to the hub (which writes it to that phone's socket)
def Plot.fwd.got(m: Maybe<&1, PV.POut>, +inbox: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{PV.POut{client, text}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Push{client, text})
        k(Unit{})
    case Some{PV.PBin{client, bs}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, PushBin{client, bs})
        k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

def Plot.fwd(fuel: Nat, +out: Chan(PV.POut), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, PV.POut>, Unit, Chan.recv(PV.POut, out), m => Plot.fwd.got(m, inbox, u => Plot.fwd(f, out, inbox)))

def Plot.put(m: Maybe<&2, Chan(PV.PMsg)>, +msg: PV.PMsg) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        ok : Bool <- Chan.send(PV.PMsg, q, msg)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.leave(h: Hub, +client: U32, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        Hub.leave.close(Clients.get(cl, client))
        Plot.put(Cfg.pv(cfg), PV.PStop{client})
        +cl2 : List<&2, Client> = Clients.drop(cl, client)
        cl3 : List<&2, Client> <- Desk.say(DK.Desk.text(Clients.looks(cl), now), cl2, now)
        return Hub{st, f, ls, cl3, as, inbox, cfg, note}

# kicad.watch: kind "board", "schematic", "3d", "3d-bare" or "3d-full"
# shows it, anything else stops
def Plot.watch(+client: U32, +kind: String, +root: String, +path: String) -> PV.PMsg:
  Bool.pick(PV.PMsg, String.eq(kind, "board"), PV.PWatch{client, 0, root, path},
    Bool.pick(PV.PMsg, String.eq(kind, "schematic"), PV.PWatch{client, 1, root, path},
      Bool.pick(PV.PMsg, String.eq(kind, "3d"), PV.PWatch{client, 2, root, path},
        Bool.pick(PV.PMsg, String.eq(kind, "3d-bare"), PV.PWatch{client, 3, root, path},
          Bool.pick(PV.PMsg, String.eq(kind, "3d-full"), PV.PWatch{client, 4, root, path}, PV.PStop{client})))))

def Term.msg(+op: String, +thread: String, +cwd: String, data: List<&2, U32>, +cols: U32, +rows: U32) -> TM.TMsg:
  Bool.pick(TM.TMsg, String.eq(op, "open"), TM.TOpen{thread, cwd, cols, rows},
    Bool.pick(TM.TMsg, String.eq(op, "resize"), TM.TSize{thread, cols, rows}, TM.TIn{thread, data}))

# User and project skills
# -----------------------

def Skills.ukeep(empty: Bool, s: AG.USkill, rest: List<&2, AG.USkill>) -> List<&2, AG.USkill>:
  match empty:
    case True{}:
      rest
    case False{}:
      s <> rest

def Skills.uread(ds: List<&2, String>, +root: String) -> IO(List<&2, AG.USkill>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, AG.USkill>, Nil{})
    case +d <> t:
      do IO<List<&2, AG.USkill>>:
        +path : String = root ++ "/" ++ d ++ "/SKILL.md"
        +text : String <- Files.text(path)
        rest : List<&2, AG.USkill> <- Skills.uread(t, root)
        return Skills.ukeep(String.is_empty(text), AG.USkill.parse(text, d, path), rest)

def Skills.names(r: Result<&1, &1, U32 & String, List<String>>) -> List<&2, String>:
  match r:
    case Done{xs}:
      Names.copy(xs)
    case Fail{_}:
      Nil{}

def Skills.dir(+root: String) -> IO(List<&2, AG.USkill>):
  IO.bind(Result<&1, &1, U32 & String, List<String>>, List<&2, AG.USkill>, H.FS.list(root), r => Skills.uread(Skills.names(r), root))

def Skills.scan.k(+home: String, +cwd: String) -> IO(List<&2, AG.USkill>):
  do IO<List<&2, AG.USkill>>:
    us : List<&2, AG.USkill> <- Skills.dir(home ++ "/.claude/skills")
    ps : List<&2, AG.USkill> <- Skills.dir(cwd ++ "/.claude/skills")
    rev : String <- K.KiStack.current(home)
    ks : List<&2, AG.USkill> <- Skills.dir(K.KiStack.base(home) ++ "/" ++ rev ++ "/skills")
    return AG.USkill.merge(AG.USkill.merge(us, ps), ks)

# ~/.claude/skills, then <cwd>/.claude/skills (the user's win a clash),
# then KiStack's
def Skills.scan(+cwd: String) -> IO(List<&2, AG.USkill>):
  IO.bind(String, List<&2, AG.USkill>, Env.get("HOME", "/nonexistent"), home => Skills.scan.k(home, cwd))

def AgentJob.skills(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String) -> IO(Unit):
  IO.bind(List<&2, AG.USkill>, Unit, Skills.scan(cwd), ss =>
    GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"skills", AG.USkill.json(ss)}, J.KV{"thread", J.Str{thread}}])))

# a job for the hub's Git effect: the skills a composer offers (anywhere),
# or a git job (in a repository)
def Jobs.run(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(job, "skills"), AgentJob.skills(inbox, client, id, thread, cwd), GitJob.run(tx, job, inbox, client, id, thread, cwd, a, b, home))

# a thread's reasoning effort setting ("" for the provider's default)
def Hub.effort_of(+st: M.State, +thread: String) -> String:
  M.Setting.get(st, AG.Effort.key(thread), "")

def Mention.user_text(+o: J.Json) -> String:
  J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.elems(J.Json.get_obj(J.Json.get_obj(o, "message"), "content"))), J.Null{}), "text", "")

def Mention.line.k(m: Maybe<&2, J.Json>, +line: String, +ss: List<&2, AG.USkill>) -> String:
  match m:
    case Some{+o}:
      Bool.pick(String, String.eq(J.Json.get_str(o, "type", ""), "user"), B.Claude.user.u(AG.Mention.expand("claude", Mention.user_text(o), ss), J.Json.get_str(o, "uuid", "")), line)
    case None{}:
      line

# a Claude stream-json user line with its `$skill` mentions as `/skill`
def Mention.line(+line: String, +ss: List<&2, AG.USkill>) -> String:
  Mention.line.k(J.Json.parse(line), line, ss)

def Hub.agent_send.k(has: Bool, m: Maybe<&2, Agent>, +line: String, +cwd: String) -> IO(Unit):
  match has:
    case True{}:
      IO.bind(List<&2, AG.USkill>, Unit, Skills.scan(cwd), ss => Hub.agent_send(m, Mention.line(line, ss)))
    case False{}:
      Hub.agent_send(m, line)

# a line for Claude with its `$skill` mentions as `/skill`
def Agent.line.final(has: Bool, +line: String, +cwd: String) -> IO(String):
  match has:
    case True{}:
      IO.bind(List<&2, AG.USkill>, String, Skills.scan(cwd), ss => IO.pure(String, Mention.line(line, ss)))
    case False{}:
      IO.pure(String, line)

# The command ledger (core/cmds.bend)
# -----------------------------------
# Every user line the hub writes to a Claude process carries its uuid; the
# ledger counts it from the moment the hub takes it (a message with images
# waits for them, and the ones after it wait behind it), and Stop makes
# every unanswered one a tomb. Lines from the process are judged against
# it (Hub.line.run).

def ARun.cmds(r: ARun) -> CM.Cmds:
  match r:
    case ARun{c, _, _, _, _, _, _, _}:
      c

def ARun.held(r: ARun) -> List<&2, CM.Held>:
  match r:
    case ARun{_, h, _, _, _, _, _, _}:
      h

def ARun.put(r: ARun, c: CM.Cmds, h: List<&2, CM.Held>) -> ARun:
  match r:
    case ARun{_, _, l, n, g, q, pa, pl}:
      ARun{c, h, l, n, g, q, pa, pl}

def Hub.agent_send.all(+m: Maybe<&2, Agent>, ls: List<&2, String>) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        Hub.agent_send(m, l)
        Hub.agent_send.all(m, t)

# the held lines whose turn has come go out, in order
def Claude.flush.k(fl: CM.Flush, +r: ARun, h: Hub, +thread: String) -> IO(Hub):
  match fl h:
    case CM.Flush{out, +sent, rest} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.agent_send.all(Agents.get(as, thread), out)
        return Hub{st, f, ls, cl, Agents.with(as, thread, ARun.put(r, CM.Cmds.sent.all(sent, ARun.cmds(r)), rest)), inbox, cfg, note}

def Claude.flush(+r: ARun, h: Hub, +thread: String) -> IO(Hub):
  Claude.flush.k(CM.Held.flush(ARun.held(r), ARun.cmds(r)), r, h, thread)

def Claude.raw(h: Hub, +thread: String, line: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.agent_send(Agents.get(as, thread), line)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# 1: a user message (its uuid first, B.Claude.tag); 2: the interrupt
def Claude.put.kind(+line: String) -> Nat:
  Bool.pick(Nat, String.starts_with(line, "{\"uuid\":"), 1n,
    Bool.pick(Nat, Bool.and(String.starts_with(line, "{\"type\":\"control_request\""), String.contains(line, "\"subtype\":\"interrupt\"")), 2n, 0n))

def Claude.put.k(i: Nat, +r: ARun, h: Hub, +thread: String, +line: String) -> IO(Hub):
  match i:
    case 1n:
      Claude.flush(ARun.put(r, CM.Cmds.accept(ARun.cmds(r), B.Claude.uuid.of(line)), CM.Held.push(ARun.held(r), B.Claude.uuid.of(line), line, True{})), h, thread)
    case 2n:
      IO.bind(Hub, Hub, Claude.raw(h, thread, line), h2 => Claude.flush(ARun.put(r, CM.Cmds.stop(ARun.cmds(r), Nil{}), ARun.held(r)), h2, thread))
    case _:
      Claude.raw(h, thread, line)

def Claude.put.r(m: Maybe<&2, ARun>, h: Hub, +thread: String, +line: String) -> IO(Hub):
  match m:
    case Some{+r}:
      Claude.put.k(Claude.put.kind(line), r, h, thread, line)
    case None{}:
      Claude.raw(h, thread, line)

# a line for a thread's agent
def Claude.put(h: Hub, +thread: String, +line: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Claude.put.r(Agents.run(as, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, line)

# a line heard now: the silence note may come again after a new silence
def ARun.heard.set(r: ARun, +now: Nat) -> ARun:
  match r:
    case ARun{c, h, l, _, g, _, pa, pl}:
      ARun{c, h, l, now, g, False{}, pa, pl}

def ARun.prog_at(r: ARun) -> Nat:
  match r:
    case ARun{_, _, _, _, _, _, pa, _}:
      pa

def ARun.prog_last(r: ARun) -> List<&2, String>:
  match r:
    case ARun{_, _, _, _, _, _, _, pl}:
      pl

# the progress lines held back and when the last went through
# (B.Prog.line)
def ARun.prog.set(r: ARun, +at: Nat, pend: List<&2, String>) -> ARun:
  match r:
    case ARun{c, h, l, n, g, q, _, _}:
      ARun{c, h, l, n, g, q, at, pend}

def ARun.gen(r: ARun) -> String:
  match r:
    case ARun{_, _, _, _, g, _, _, _}:
      g

# (a message prepared for an earlier process, or stopped while its images
# were read, is dropped: B.Gen.write)
def Claude.ready.k(ok: Bool, +r: ARun, h: Hub, +thread: String, +u: String, +line: String) -> IO(Hub):
  match ok:
    case True{}:
      Claude.flush(ARun.put(r, ARun.cmds(r), CM.Held.ready(ARun.held(r), u, line)), h, thread)
    case False{}:
      do IO<Hub>:
        Log.info("dropped a prepared message for " ++ thread ++ ": its process is gone or it was stopped")
        Claude.flush(r, h, thread)

def Claude.ready.r(m: Maybe<&2, ARun>, h: Hub, +thread: String, +u: String, +line: String, +gen: String) -> IO(Hub):
  match m:
    case Some{+r}:
      Claude.ready.k(B.Gen.write(gen, ARun.gen(r), CM.Cmds.state(ARun.cmds(r), u)), r, h, thread, u, line)
    case None{}:
      IO.pure(Hub, h)

def Claude.ready.u(empty: Bool, h: Hub, +thread: String, +u: String, +line: String, +gen: String) -> IO(Hub):
  match empty h:
    case True{} _:
      Claude.raw(h, thread, line)
    case False{} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Claude.ready.r(Agents.run(as, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, u, line, gen)

def Claude.ready(h: Hub, +thread: String, +line: String, +gen: String) -> IO(Hub):
  Claude.ready.u(String.is_empty(B.Claude.uuid.of(line)), h, thread, B.Claude.uuid.of(line), line, gen)

def Claude.prep.r(m: Maybe<&2, ARun>, h: Hub, +thread: String, +u: String) -> Hub:
  match m h:
    case Some{+r} Hub{st, f, ls, cl, as, inbox, cfg, note}:
      Hub{st, f, ls, cl, Agents.with(as, thread, ARun.put(r, CM.Cmds.accept(ARun.cmds(r), u), CM.Held.push(ARun.held(r), u, "", False{}))), inbox, cfg, note}
    case None{} _:
      h

# a message whose images are being read is taken now: those after it wait
def Claude.prep(on: Bool, h: Hub, +thread: String, +u: String) -> Hub:
  match on h:
    case True{} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Claude.prep.r(Agents.run(as, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, u)
    case False{} _:
      h

# a Codex or Grok turn's KiCad files, read in its own job (the hub's loop
# never waits on the walk); the hub is told to open the panel
def Files.prepared(+thread: String, +cwd: String, +inbox: Chan(Msg)) -> IO(K.Files):
  do IO<K.Files>:
    +fs : K.Files <- K.Files.read(cwd)
    ok : Bool <- Chan.send(Msg, inbox, AutoView{thread, fs})
    return fs

# one Codex turn: the thread's skills join its instructions and its
# `$skill` mentions become instructions to read them
def Codex.go(+cfg: Cfg, +st: M.State, +thread: String, +cwd: String, +model: String, +session: String, r: M.RuntimeMode, +text: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +fs : K.Files <- Files.prepared(thread, cwd, inbox)
    +ss : List<&2, AG.USkill> <- Skills.scan(cwd)
    +keys : String <- AKS.Ak.prompt(Cfg.home(cfg))
    +lim : String <- Ctn.limit(st)
    Codex.run(lim, Codex.args(cfg, thread, model, session, r, AG.Mention.expand("codex", text, ss), Hub.prompt(cfg, st, thread, cwd, fs, keys) ++ AG.USkill.prompt(ss), Hub.effort_of(st, thread), gen), cwd, thread, gen, inbox)

def Grok.go(+cfg: Cfg, +st: M.State, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +text: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +fs : K.Files <- Files.prepared(thread, cwd, inbox)
    +ss : List<&2, AG.USkill> <- Skills.scan(cwd)
    +keys : String <- AKS.Ak.prompt(Cfg.home(cfg))
    +lim : String <- Ctn.limit(st)
    Grok.run(lim, Grok.args(r, model, Hub.effort_of(st, thread)),
      AC.AcpTurn{cwd, Hub.mcp_url.g(cfg, thread, gen), Hub.prompt(cfg, st, thread, cwd, fs, keys) ++ AG.USkill.prompt(ss), AG.Mention.expand("grok", text, ss), session, Grok.asks(r)}, cwd, thread, gen, inbox)

def Term.nums(bs: List<&2, U32>) -> List<&2, String>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      U32.show(b) <> Term.nums(t)

def Term.json(+thread: String, bs: List<&2, U32>) -> String:
  "{\"t\":\"term\",\"thread\":" ++ J.Json.show(J.Str{thread}) ++ ",\"b\":[" ++ String.join(Term.nums(bs), ",") ++ "]}"

def Net.with_pk(n: Net, q: Chan(PK.PMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, g, _, i, mc, pvx, bnx, mgd, lk, fc}:
      Net{a, b, c, d, e, f, g, Some{q}, i, mc, pvx, bnx, mgd, lk, fc}

def Browser.exe() -> IO(String):
  do IO<String>:
    +d : String <- H.Sys.exe_dir()
    ok : Bool <- K.Io.is_file(d ++ "/backplane-browser")
    return Bool.pick(String, ok, d ++ "/backplane-browser", "backplane-browser")

def Cfg.br(c: Cfg) -> Maybe<&2, Chan(BR.BMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, br, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      br

def Preview.shot(+o: J.Json) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, String.is_empty(J.Json.get_str(o, "data", "")), Nil{},
    [J.Json.obj([J.KV{"type", J.Str{"image"}}, J.KV{"data", J.Str{J.Json.get_str(o, "data", "")}}, J.KV{"mimeType", J.Str{J.Json.get_str(o, "mimeType", "image/png")}}])])

def Preview.drop.fs(fs: J.Json) -> J.Json:
  match fs:
    case J.Field{"screenshot", _, t}:
      Preview.drop.fs(t)
    case J.Field{k, v, t}:
      J.Field{k, v, Preview.drop.fs(t)}
    case _:
      fs

def Preview.drop_shot(o: J.Json) -> J.Json:
  match o:
    case J.Obj{fs}:
      J.Obj{Preview.drop.fs(fs)}
    case _:
      o

def Preview.blocks(+r: J.Json) -> List<&2, J.Json>:
  J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{J.Json.show(Preview.drop_shot(r))}}])
    <> Preview.shot(J.Json.get_obj(r, "screenshot"))

def Preview.content.k(ok: Bool, r: J.Json, +err: String) -> J.Json:
  match ok:
    case True{}:
      J.Json.obj([J.KV{"content", J.Json.arr(Preview.blocks(r))}, J.KV{"isError", J.Flag{False{}}}])
    case False{}:
      J.Json.obj([J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{err}}])])}, J.KV{"isError", J.Flag{True{}}}])

# a browser tool's reply as an MCP result: the helper's result as text,
# a screenshot as an image block, an error flagged
def Preview.content(+o: J.Json) -> J.Json:
  Preview.content.k(J.Json.get_bool(o, "ok", False{}), J.Json.get_obj(o, "result"), J.Json.get_str(o, "error", "browser error"))

def Preview.answer(+id: String, +line: String) -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"result\":" ++ J.Json.show(Preview.content(Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{}))) ++ "}"

def Preview.run.k(m: Maybe<&2, Chan(BR.BMsg)>, +page: String, +id: String, +op: String, args: J.Json, +reply: Chan(String)) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        line : String <- BR.Browser.ask_on(q, page, op, args)
        ok : Bool <- Chan.send(String, reply, Preview.answer(id, line))
        return Unit{}
    case None{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, reply, Preview.answer(id, BR.Browser.fail("no browser in this Backplane")))
        return Unit{}

# a preview_* tool call, answered by the browser off the hub's thread, on
# the page of `page` (a bot's own; "" is the shared page)
def Preview.run(+cfg: Cfg, +page: String, +o: J.Json, +reply: Chan(String)) -> IO(Unit):
  Preview.run.k(Cfg.br(cfg), page, J.Json.as_raw(J.Json.get(o, "id"), "null"), String.drop(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), 8n),
    J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), reply)

def Preview.is(+o: J.Json) -> Bool:
  Bool.and(String.eq(J.Json.get_str(o, "method", ""), "tools/call"), String.starts_with(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_"))

# opening or navigating brings the Browser tab forward in every window
def Preview.shows(+o: J.Json) -> Bool:
  Bool.or(String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_open"), String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_navigate"))

# a shell's output goes to every client (each keeps its own screen)
def Hub.term_out(h: Hub, +thread: String, data: List<&2, U32>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.all(cl, Term.json(thread, data))
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

# a chat terminal from the start: a blank cols x rows screen, then bytes
def Term.json.reset(+key: String, +cols: U32, +rows: U32, bs: List<&2, U32>) -> String:
  "{\"t\":\"term\",\"thread\":" ++ J.Json.show(J.Str{key}) ++ ",\"b\":[" ++ String.join(Term.nums(bs), ",") ++ "],\"reset\":[" ++ U32.show(cols) ++ "," ++ U32.show(rows) ++ "]}"

def Hub.term_to.k(all: Bool, +cl: List<&2, Client>, +client: U32, +text: String) -> IO(List<&2, Client>):
  match all:
    case True{}:
      Wire.all(cl, text)
    case False{}:
      Wire.to(cl, client, text)

def Hub.term_to(h: Hub, +client: U32, +key: String, +cols: U32, +rows: U32, data: List<&2, U32>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Hub.term_to.k(U32.is_eq(client, TM.Et.all()), cl, client, Term.json.reset(key, cols, rows, data))
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

def Cfg.with_models(c: Cfg, +ms: String, +mt: String) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, _, _, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}

def Hub.models.k(h: Hub) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.all(cl, "{\"t\":\"info\",\"info\":" ++ J.Json.show(Hub.info(cfg)) ++ "}")
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

def Cfg.with_machines(c: Cfg, +mc: String) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, _, pvx, bnx, mgd, lk, fc}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}

def Cfg.with_link(c: Cfg, +lk: String) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, _, fc}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}

# the tailnet listener is up: every client hears the pairing link. Each
# one either is the owner's own device or came in with the token already,
# so it tells none of them anything new
def Hub.link(h: Hub, +lk: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      Hub.models.k(Hub{st, f, ls, cl, as, inbox, Cfg.with_link(cfg, lk), note})

# where a thread's attachments go (the upload itself runs off the hub)
def Hub.att_dir(h: Hub, +thread: String, +reply: Chan(String)) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        ok : Bool <- Chan.send(String, reply, AT.Att.dir(Cfg.home(cfg), thread))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# the owner's other machines changed: every client hears
def Hub.machines(h: Hub, +mc: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      Hub.models.k(Hub{st, f, ls, cl, as, inbox, Cfg.with_machines(cfg, mc), note})

# the providers' models changed: new threads' prompts and every client see
# the new list
def Hub.models(h: Hub, +ms: String, +mt: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      Hub.models.k(Hub{st, f, ls, cl, as, inbox, Cfg.with_models(cfg, ms, mt), note})

def Names.list(r: Result<&1, &1, U32 & String, List<String>>) -> List<&2, String>:
  match r:
    case Done{xs}:
      Names.copy(xs)
    case Fail{_}:
      Nil{}

def Names.of(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    r : Result<&1, &1, U32 & String, List<String>> <- H.FS.list(path)
    return List.sort(~String, ~String.is_le, Names.list(r))

def Skills.keep(empty: Bool, s: Q.Skill, rest: List<&2, Q.Skill>) -> List<&2, Q.Skill>:
  match empty:
    case True{}:
      rest
    case False{}:
      s <> rest

# the SKILL.md of every skill dir under root, parsed
def Skills.read(ds: List<&2, String>, +root: String) -> IO(List<&2, Q.Skill>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Q.Skill>, Nil{})
    case +d <> t:
      do IO<List<&2, Q.Skill>>:
        +path : String = root ++ "/" ++ d ++ "/SKILL.md"
        +text : String <- Files.text(path)
        rest : List<&2, Q.Skill> <- Skills.read(t, root)
        return Skills.keep(String.is_empty(text), Q.Skill.parse(text, d, path), rest)

def Skills.kistack.dir(+dir: String) -> IO(String & List<&2, Q.Skill>):
  do IO<String & List<&2, Q.Skill>>:
    ds : List<&2, String> <- Names.of(dir ++ "/skills")
    ss : List<&2, Q.Skill> <- Skills.read(ds, dir ++ "/skills")
    return (dir, ss)

# KiStack lives at <cache>/backplane/kistack/<revision>/skills; the newest
# revision directory wins
def Skills.kistack.k(m: Maybe<&2, String>, +base: String) -> IO(String & List<&2, Q.Skill>):
  match m:
    case Some{+rev}:
      Skills.kistack.dir(base ++ "/" ++ rev)
    case None{}:
      IO.pure(String & List<&2, Q.Skill>, ("", Nil{}))

def Skills.kistack(+home: String) -> IO(String & List<&2, Q.Skill>):
  do IO<String & List<&2, Q.Skill>>:
    +base : String = home ++ "/.cache/backplane/kistack"
    revs : List<&2, String> <- Names.of(base)
    Skills.kistack.k(List.last(&2, String, revs), base)

def Main.args(xs: List<String>, c: Cfg) -> Cfg:
  match xs c:
    case "--port" <> p <> t Cfg{h, w, ho, _, pr, ds, v, nt}:
      Main.args(t, Cfg{h, w, ho, Maybe.default(&2, U32, U32.read(p), 3787), pr, ds, v, nt})
    case "--host" <> x <> t Cfg{h, w, _, po, pr, ds, v, nt}:
      Main.args(t, Cfg{h, w, x, po, pr, ds, v, nt})
    case "--web" <> x <> t Cfg{h, _, ho, po, pr, ds, v, nt}:
      Main.args(t, Cfg{h, x, ho, po, pr, ds, v, nt})
    case "--home" <> x <> t Cfg{_, w, ho, po, pr, ds, v, nt}:
      Main.args(t, Cfg{x, w, ho, po, pr, ds, v, nt})
    case "--no-tailscale" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, _, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{False{}, False{}, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}})
    case "--tailscale" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, https, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, https, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}})
    case "--tailscale-https" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, _, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, True{}, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}})
    case _ <> t _:
      Main.args(t, c)
    case Nil{} _:
      c

# Model refresh
# -------------
# The providers' model lists are read again every Models.every() ms; a
# list that changed goes to the hub, which tells every client.

def Models.every() -> U32:
  900000

# the last model list found (src/core/boot.bend)
def Models.cache(+home: String) -> String:
  home ++ "/models.cache"

def Net.models(n: Net) -> String:
  match n:
    case Net{_, _, _, ms, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}:
      ms

# Machines
# --------
# Every Machines.every() ms: the owner's online tailnet peers (tailscale
# status) and any hubs named in BACKPLANE_PEERS, each asked GET /hello;
# those that answer run Backplane. The list goes to every client.

def Machines.every() -> U32:
  120000

# a hub that may be there: a name and its base URL
type Cand is Data:
  Cand{name: String, url: String}

def Machines.cands(ms: List<&2, TN.Machine>, +port: U32) -> List<&2, Cand>:
  match ms:
    case Nil{}:
      Nil{}
    case TN.Machine{n, ip, _} <> t:
      Cand{n, "http://" ++ ip ++ ":" ++ U32.show(port)} <> Machines.cands(t, port)

def Machines.name(+url: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(Bool.pick(String, String.starts_with(url, "http://"), String.drop(url, 7n), url), ':')), url)

def Machines.static.k(blank: Bool, +u: String, rest: List<&2, Cand>) -> List<&2, Cand>:
  match blank:
    case True{}:
      rest
    case False{}:
      Cand{Machines.name(u), u} <> rest

# hubs named in BACKPLANE_PEERS ("http://host:port,..."), for machines
# that are not on the tailnet
def Machines.static(us: List<&2, String>) -> List<&2, Cand>:
  match us:
    case Nil{}:
      Nil{}
    case +u <> t:
      Machines.static.k(String.is_empty(String.trim(u)), String.trim(u), Machines.static(t))

def Machines.urls(cs: List<&2, Cand>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case Cand{_, u} <> t:
      ("'" ++ u ++ "'") <> Machines.urls(t)

# ask every hub at once; each answer is "<url> <byte> <byte> ...": /hello
# answers CBOR, so od writes its bytes out as decimal numbers
def Machines.probe.sh(+urls: List<&2, String>) -> String:
  "for u in " ++ String.join(urls, " ") ++ "; do (r=$(curl -s -m 3 \"$u/hello\" | od -An -tu1 -v | tr -s ' \\n' '  '); [ -n \"${r# }\" ] && echo \"$u $r\") & done; wait"

def Machines.answer(ls: List<&2, String>, +url: String) -> String:
  match ls:
    case Nil{}:
      ""
    case +l <> t:
      Bool.pick(String, String.starts_with(l, url ++ " "), String.drop(l, Nat.add(String.length(url), 1n)), Machines.answer(t, url))

def Machines.keep(+v: String, +n: String, +url: String, +rest: List<&2, J.Json>) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, String.is_empty(v), rest,
    J.Json.obj([J.KV{"name", J.Str{n}}, J.KV{"url", J.Str{url}}, J.KV{"version", J.Str{v}}]) <> rest)

def Machines.one(+c: Cand, +ls: List<&2, String>, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match c:
    case Cand{+n, +u}:
      Machines.keep(TN.Hello.version(TN.Hello.bytes(Machines.answer(ls, u))), n, u, rest)

def Machines.list(cs: List<&2, Cand>, +ls: List<&2, String>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Machines.one(c, ls, Machines.list(t, ls))

def Machines.found(cs: List<&2, Cand>, r: P.Ran) -> J.Json:
  J.Json.arr(Machines.list(cs, String.lines(Tailnet.out(r))))

# the hubs that answer /hello
def Machines.peers(+cs: List<&2, Cand>) -> IO(J.Json):
  Bool.pick(IO(J.Json), List.is_empty(&2, Cand, cs), IO.pure(J.Json, J.Json.arr(Nil{})),
    IO.bind(P.Ran, J.Json, P.Proc.run("sh", ["-c", Machines.probe.sh(Machines.urls(cs))], "/"), r => IO.pure(J.Json, Machines.found(cs, r))))

def Machines.me(m: TN.Machine, +port: U32, +domain: String) -> J.Json:
  match m:
    case TN.Machine{n, +ip, _}:
      J.Json.obj([J.KV{"name", J.Str{n}}, J.KV{"url", J.Str{Bool.pick(String, String.is_empty(ip), "", "http://" ++ ip ++ ":" ++ U32.show(port))}}, J.KV{"domain", J.Str{domain}}])

# {"self": {"name", "url", "domain"}, "peers": [{"name", "url", "version"}]}
# (domain: the tailnet's MagicDNS domain, how clients know a linked
# machine's address is one of the owner's)
def Machines.ask(+status: String, +port: U32, +extra: String) -> IO(String):
  IO.bind(J.Json, String, Machines.peers(List.append(&2, Cand, Machines.cands(TN.Tailnet.online(TN.Tailnet.peers(status)), port), Machines.static(String.split(extra, ',')))),
    ps => IO.pure(String, J.Json.show(J.Json.obj([J.KV{"self", Machines.me(TN.Tailnet.self(status), port, TN.Tailnet.domain(status))}, J.KV{"peers", ps}]))))

def Machines.tell(+inbox: Chan(Msg), +now: String, +last: String) -> IO(String):
  Bool.pick(IO(String), String.eq(now, last), IO.pure(String, last),
    IO.bind(Bool, String, Chan.send(Msg, inbox, MachinesFound{now}), ok => IO.pure(String, now)))

def Machines.loop(fuel: Nat, +inbox: Chan(Msg), +port: U32, +extra: String, +last: String) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        st : P.Ran <- P.Proc.run("sh", ["-c", "command -v tailscale >/dev/null && timeout 10 tailscale status --json"], "/")
        found : String <- Machines.ask(Tailnet.out(st), port, extra)
        now : String <- Machines.tell(inbox, found, last)
        IO.sleep(Machines.every())
        Machines.loop(f, inbox, port, extra, now)

def Machines.start(+inbox: Chan(Msg), +port: U32) -> IO(Unit):
  do IO<Unit>:
    extra : String <- Env.get("BACKPLANE_PEERS", "")
    IO.spawn(Unit, Machines.loop(Fuel.forever(), inbox, port, extra, ""))

def Main.version() -> String:
  VR.Version.current()

def Main.failed(e: U32 & String, h: Hub, addr: String) -> IO(Unit):
  (_, msg) = e
  do IO<Unit>:
    Hub.close(h)
    IO.die(Unit, 1, "backplane: cannot listen on " ++ addr ++ ": " ++ msg)

def Main.nolog(e: U32 & String) -> IO(Unit):
  (_, msg) = e
  IO.die(Unit, 1, "backplane: cannot open the event log: " ++ msg)

# what the machine offers, found once at start
type Boot is Data:
  Boot{kdir: String, skills: List<&2, Q.Skill>, rt: K.Rt, models: String, mtext: String, freecad: String}

def Models.strs.go(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Str{x} <> Models.strs.go(t)

def Models.strs(xs: List<&2, String>) -> J.Json:
  J.Json.arr(Models.strs.go(xs))

def Models.listed(o: J.Json) -> Bool:
  String.eq(J.Json.get_str(o, "visibility", "list"), "list")

def Models.slugs.k(keep: Bool, +slug: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      slug <> rest
    case False{}:
      rest

def Models.slugs(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      Models.slugs.k(Bool.and(Models.listed(o), Bool.not(String.is_empty(J.Json.get_str(o, "slug", "")))), J.Json.get_str(o, "slug", ""), Models.slugs(t))

# Codex's cached model list ({"models": [{"slug", "visibility"}]})
def Models.codex(+text: String) -> List<&2, String>:
  Models.slugs(J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), "models")))

def Models.claude() -> List<&2, String>:
  ["fable", "opus", "sonnet", "haiku"]

# Claude Code's own model list (what its /model picker offers): asked with
# an `initialize` control request, answered before any model is called
def Claude.probe.sh() -> String:
  "command -v claude >/dev/null || exit 1; printf '%s\\n' '{\"type\":\"control_request\",\"request_id\":\"models\",\"request\":{\"subtype\":\"initialize\"}}' | timeout 30 claude -p --input-format stream-json --output-format stream-json --verbose 2>/dev/null | grep -m1 '\"control_response\"'"

# the models in a probe's answer ([] when it failed or is too old)
def Claude.listed(r: P.Ran) -> List<&2, J.Json>:
  match r:
    case P.Ran{0, out}:
      J.Json.elems(J.Json.get_obj(J.Json.get_obj(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(String.trim(out)), J.Null{}), "response"), "response"), "models"))
    case _:
      Nil{}

def Claude.values.k(keep: Bool, +v: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      v <> rest
    case False{}:
      rest

# what a thread may pick ("default" is the picker's own first row)
def Claude.values(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      Claude.values.k(Bool.not(Bool.or(String.is_empty(J.Json.get_str(o, "value", "")), String.eq(J.Json.get_str(o, "value", ""), "default"))), J.Json.get_str(o, "value", ""), Claude.values(t))

# "Opus 5.5 · claude-opus-5-5"; a full model name gets its description instead
def Claude.label(+o: J.Json) -> String:
  J.Json.get_str(o, "displayName", J.Json.get_str(o, "value", "")) ++ " · "
    ++ Bool.pick(String, String.eq(J.Json.get_str(o, "value", ""), J.Json.get_str(o, "resolvedModel", "")), J.Json.get_str(o, "description", ""), J.Json.get_str(o, "resolvedModel", ""))

def Claude.labels(xs: List<&2, J.Json>) -> List<&2, J.KV>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.KV{J.Json.get_str(o, "value", ""), J.Str{Claude.label(o)}} <> Claude.labels(t)

# the effort levels each model takes (none for a model without effort)
def Claude.efforts(xs: List<&2, J.Json>) -> List<&2, J.KV>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.KV{J.Json.get_str(o, "value", ""), J.Json.get_obj(o, "supportedEffortLevels")} <> Claude.efforts(t)

def Claude.models.k(none: Bool, +xs: List<&2, J.Json>) -> List<&2, String>:
  Bool.pick(List<&2, String>, none, Models.claude(), Claude.values(xs))

def Models.on(has: Bool, +xs: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, has, xs, Nil{})

# the probe's list, or the known aliases when the CLI cannot say
def Claude.models(+has: Bool, +xs: List<&2, J.Json>) -> List<&2, String>:
  Models.on(has, Claude.models.k(List.is_empty(&2, J.Json, xs), xs))

def Models.line(+name: String, +xs: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, xs), "", name ++ " (" ++ String.join(xs, ", ") ++ ")")

def Models.join(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, Bool.pick(String, String.is_empty(b), a, a ++ "; " ++ b))

def Models.text(+cl: List<&2, String>, +cx: List<&2, String>) -> String:
  Models.join(Models.line("claude", cl), Models.line("codex", cx))

def Models.text3(+cl: List<&2, String>, +cx: List<&2, String>, +gk: List<&2, String>) -> String:
  Models.join(Models.text(cl, cx), Models.line("grok", gk))

# what the providers offer: the models JSON clients read, and a line for
# the agents' prompt
type Found is Data:
  Found{models: String, text: String}

def Conn.served(s: Socket, +path: String, +gz: Bool, bs: List<&2, U32>) -> IO(Unit):
  match bs:
    case Nil{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not found"))
    case b <> t:
      Conn.finish(s, W.Http.response.c("200 OK", W.Http.ctype(path), b <> t, Conn.cache(path), Bool.pick(String, gz, "Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n", "Vary: Accept-Encoding\r\n")))

# a precompressed .gz beside the file when the browser takes gzip
def Conn.gz(bs: List<&2, U32>, s: Socket, +web: String, +path: String) -> IO(Unit):
  match bs:
    case Nil{}:
      IO.bind(List<&2, U32>, Unit, Files.read(web ++ path), plain => Conn.served(s, path, False{}, plain))
    case b <> t:
      Conn.served(s, path, True{}, b <> t)

def Conn.static.go(gz: Bool, s: Socket, +web: String, +path: String) -> IO(Unit):
  match gz:
    case True{}:
      IO.bind(List<&2, U32>, Unit, Files.read(web ++ path ++ ".gz"), bs => Conn.gz(bs, s, web, path))
    case False{}:
      IO.bind(List<&2, U32>, Unit, Files.read(web ++ path), bs => Conn.served(s, path, False{}, bs))

def Conn.static.k(ok: Bool, s: Socket, +web: String, +path: String, gz: Bool) -> IO(Unit):
  match ok:
    case True{}:
      Conn.static.go(gz, s, web, path)
    case False{}:
      Conn.finish(s, W.Http.text("400 Bad Request", "bad path"))

def Conn.static(s: Socket, +web: String, +path: String, gz: Bool) -> IO(Unit):
  Conn.static.k(Conn.safe(path), s, web, Conn.file(path), gz)

def Conn.pos(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Conn.pos(t, x, 1n+i))

# Images in threads
# -----------------
# GET /img?path=<an image an agent named>: the file itself, to a client
# the hub already lets in (it could read the file through a terminal as
# well); only image files, at most IM.Img.cap() bytes.

def Img.sent(bs: List<&2, U32>, s: Socket, +path: String) -> IO(Unit):
  match bs:
    case Nil{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not found"))
    case b <> t:
      Conn.finish(s, W.Http.response.c("200 OK", IM.Img.ctype(path), b <> t, "no-cache", ""))

def Img.read(ok: Bool, s: Socket, +path: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.bind(List<&2, U32>, Unit, Files.read(path), bs => Img.sent(bs, s, path))
    case False{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not an image, or too large"))

def Img.stat.k(st: U32 & U32 & U32, s: Socket, +path: String) -> IO(Unit):
  (kind, rest) = st
  (size, _) = rest
  Img.read(Bool.and(U32.is_eq(kind, 0), U32.is_le(size, IM.Img.cap())), s, path)

def Img.stat(r: Result<&1, &1, U32 & String, U32 & U32 & U32>, s: Socket, +path: String) -> IO(Unit):
  match r:
    case Done{st}:
      Img.stat.k(st, s, path)
    case Fail{_}:
      Conn.finish(s, W.Http.text("404 Not Found", "not found"))

def Img.found(+path: String, s: Socket) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & U32 & U32>, Unit, H.FS.stat(path), r => Img.stat(r, s, path))

def Img.serve.k(image: Bool, s: Socket, +path: String) -> IO(Unit):
  match image:
    case True{}:
      IO.bind(String, Unit, Env.get("HOME", ""), home => Img.found(Bool.pick(String, String.starts_with(path, "~/"), home ++ String.drop(path, 1n), path), s))
    case False{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not an image"))

def Img.serve(allowed: Bool, s: Socket, +path: String) -> IO(Unit):
  match allowed:
    case True{}:
      Img.serve.k(IM.Img.viewable(path), s, path)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

# GET /hello says a Backplane hub runs here (and which version), so other
# machines of the owner can find it; it needs no token and tells nothing more
# the hub's last count of threads running or waiting on work (its gauge
# hub.busy, set each minute)
def Hello.busy(ss: List<&2, PF.Stat>) -> Nat:
  match ss:
    case Nil{}:
      0n
    case +x <> t:
      Bool.pick(Nat, String.eq(PF.Stat.name(x), "hub.busy"), PF.Stat.last(x), Hello.busy(t))

def Conn.get(hello: Bool, s: Socket, +web: String, +path: String, gz: Bool) -> IO(Unit):
  match hello:
    case True{}:
      IO.bind(String, Unit, PS.Perf.take(), t => Conn.finish(s, W.Http.response("200 OK", "application/cbor", TN.Hello.answer.b(Main.version(), Hello.busy(PF.Stats.parse(t))), "")))
    case False{}:
      Conn.static(s, web, path, gz)

# GET /debug/perf (a table), /debug/perf.json and /debug/log (the last
# log lines): what this process measured since it started (docs/perf.md),
# for a client the hub lets in
def Debug.answer(+i: Nat, +r: String) -> List<&2, U32>:
  match i:
    case 2n:
      W.Http.text("200 OK", PF.Stats.table(PF.Stats.parse(r)))
    case 3n:
      W.Http.response("200 OK", "application/json", U.Utf8.encode(J.Json.show(PF.Stats.json(PF.Stats.parse(r)))), "")
    case _:
      W.Http.text("200 OK", r)

def Debug.read(+i: Nat) -> IO(String):
  match i:
    case 4n:
      PS.Perf.logs()
    case _:
      PS.Perf.take()

def Debug.serve(allowed: Bool, +i: Nat, s: Socket) -> IO(Unit):
  match allowed:
    case True{}:
      IO.bind(String, Unit, Debug.read(i), r => Conn.finish(s, Debug.answer(i, r)))
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.get.k(i: Nat, s: Socket, +web: String, +p: String, gz: Bool, +allowed: Bool) -> IO(Unit):
  match i:
    case 0n:
      Conn.get(True{}, s, web, W.Http.route(p), gz)
    case 1n:
      Img.serve(allowed, s, ATT.Att.from_uri("file://" ++ W.Http.param(p, "path")))
    case 2n:
      Debug.serve(allowed, 2n, s)
    case 3n:
      Debug.serve(allowed, 3n, s)
    case 4n:
      Debug.serve(allowed, 4n, s)
    case _:
      Conn.get(False{}, s, web, W.Http.route(p), gz)

def Conn.route.k(ws: Bool, s: Socket, req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match ws req:
    case True{} W.Request{_, +p, +hs}:
      Conn.gate(Conn.allowed(trusted, hs, p, token), s, W.Http.header_of(hs, "sec-websocket-key"), rest, id, inbox,
        Maybe.default(&2, Nat, Nat.read(W.Http.param(p, "since")), 0n), W.Http.param(p, "origin"))
    case False{} W.Request{_, +p, +hs}:
      Conn.get.k(Conn.pos(["/hello", "/img", "/debug/perf", "/debug/perf.json", "/debug/log"], W.Http.route(p), 0n), s, web, p, String.contains(W.Http.header_of(hs, "accept-encoding"), "gzip"), Conn.allowed(trusted, hs, p, token))

def Conn.route.mcp(mcp: Bool, s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match mcp req:
    case True{} W.Request{_, +p, +hs}:
      Mcp.gate(Conn.allowed(trusted, hs, p, token), s, String.drop(W.Http.route(p), 5n),
        Maybe.default(&2, Nat, Nat.read(W.Http.header_of(hs, "content-length")), 0n), rest, inbox)
    case False{} _:
      Conn.route.k(Conn.is_ws(req), s, req, rest, web, id, inbox, trusted, token)

def Refresh.news(news: Bool, +ms: String, +mt: String, +inbox: Chan(Msg), +cache: String, +last: String) -> IO(String):
  match news:
    case True{}:
      do IO<String>:
        ok : Bool <- Chan.send(Msg, inbox, ModelsFound{ms, mt})
        w : String <- Token.save(cache, BT.Cache.of(ms, mt))
        return ms
    case False{}:
      IO.pure(String, last)

# a probe's list goes to clients and the cache when it is news
def Refresh.found(fd: Found, +inbox: Chan(Msg), +cache: String, +last: String) -> IO(String):
  match fd:
    case Found{+ms, +mt}:
      Refresh.news(BT.Models.news(ms, last), ms, mt, inbox, cache, last)

def Models.found(+cl: List<&2, String>, +cx: List<&2, String>, +gk: List<&2, String>, about: J.Json) -> Found:
  Found{J.Json.show(J.Json.obj([J.KV{"claude", Models.strs(cl)}, J.KV{"codex", Models.strs(cx)}, J.KV{"grok", Models.strs(gk)}, J.KV{"about", about}])), Models.text3(cl, cx, gk)}

def Models.boot(ks: String & List<&2, Q.Skill>, +rt: K.Rt, fd: Found, +fc: String) -> Boot:
  (kdir, skills) = ks
  match fd:
    case Found{ms, mt}:
      Boot{kdir, skills, rt, ms, mt, fc}

def Models.grok.k(bullet: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match bullet:
    case True{}:
      Maybe.default(&2, String, List.head(&2, String, String.split(String.drop(String.trim(l), 2n), ' ')), "") <> rest
    case False{}:
      rest

def Models.grok.line(+l: String, rest: List<&2, String>) -> List<&2, String>:
  Models.grok.k(Bool.or(String.starts_with(String.trim(l), "* "), String.starts_with(String.trim(l), "- ")), l, rest)

def Models.grok.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Models.grok.line(l, Models.grok.go(t))

# `grok models`: "  * grok-4.6 (default)" / "  - grok-4.5" lines
def Models.grok(r: P.Ran) -> List<&2, String>:
  match r:
    case P.Ran{0, out}:
      Models.grok.go(String.lines(out))
    case _:
      Nil{}

def Main.has(r: P.Ran) -> Bool:
  match r:
    case P.Ran{0, _}:
      True{}
    case _:
      False{}

# KiStack at its pinned revision (fetched when missing), the KiCad CLI,
# and which providers and models are installed
# What each provider is: its CLI's version, and a label per model. This
# table is only for a Claude CLI too old to answer the probe.
def About.claude() -> List<&2, J.KV>:
  [J.KV{"default", J.Str{"Claude Code's own default"}}, J.KV{"fable", J.Str{"Fable 5.1 · claude-fable-5-1"}},
   J.KV{"opus", J.Str{"Opus 5.5 · claude-opus-5-5"}}, J.KV{"sonnet", J.Str{"Sonnet 5 · claude-sonnet-5"}},
   J.KV{"haiku", J.Str{"Haiku 4.5 · claude-haiku-4-5"}}]

def About.codex.go(xs: List<&2, J.Json>) -> List<&2, J.KV>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.KV{J.Json.get_str(o, "slug", ""), J.Str{J.Json.get_str(o, "display_name", "") ++ " · " ++ J.Json.get_str(o, "description", "")}} <> About.codex.go(t)

def About.codex(+text: String) -> List<&2, J.KV>:
  J.KV{"default", J.Str{"Codex's configured default"}} <> About.codex.go(J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), "models")))

def About.grok.k(dflt: Bool, +slug: String, rest: List<&2, J.KV>, bullet: Bool) -> List<&2, J.KV>:
  match bullet:
    case True{}:
      J.KV{slug, J.Str{Bool.pick(String, dflt, "Grok's default model", "Grok")}} <> rest
    case False{}:
      rest

def About.grok.go(ls: List<&2, String>) -> List<&2, J.KV>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      About.grok.k(String.contains(l, "(default)"), Maybe.default(&2, String, List.head(&2, String, String.split(String.drop(String.trim(l), 2n), ' ')), ""), About.grok.go(t), Bool.or(String.starts_with(String.trim(l), "* "), String.starts_with(String.trim(l), "- ")))

def About.grok(r: P.Ran) -> List<&2, J.KV>:
  match r:
    case P.Ran{0, out}:
      J.KV{"default", J.Str{"Grok's own default"}} <> About.grok.go(String.lines(out))
    case _:
      Nil{}

def About.cli(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      String.trim(Maybe.default(&2, String, List.head(&2, String, String.lines(out)), ""))
    case _:
      ""

def About.one(+cli: String, labels: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"cli", J.Str{cli}}, J.KV{"labels", J.Json.obj(labels)}])

def Claude.about(+cli: String, +xs: List<&2, J.Json>) -> J.Json:
  Bool.pick(J.Json, List.is_empty(&2, J.Json, xs), About.one(cli, About.claude()),
    J.Json.obj([J.KV{"cli", J.Str{cli}}, J.KV{"labels", J.Json.obj(Claude.labels(xs))}, J.KV{"efforts", J.Json.obj(Claude.efforts(xs))}]))

# which providers are installed and what models they offer (at start, and
# again every Models.every() ms: new models appear without a restart)
def Models.detect(+user: String) -> IO(Found):
  do IO<Found>:
    cl : P.Ran <- P.Proc.run("sh", ["-c", "command -v claude"], "/")
    cx : P.Ran <- P.Proc.run("sh", ["-c", "command -v codex"], "/")
    +cache : String <- K.Io.text(user ++ "/.codex/models_cache.json")
    +gk : P.Ran <- P.Proc.run("sh", ["-c", "command -v grok >/dev/null && timeout 15 grok models"], "/")
    pc : P.Ran <- P.Proc.run("sh", ["-c", Claude.probe.sh()], "/")
    vc : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 claude --version"], "/")
    vx : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 codex --version"], "/")
    vg : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 grok --version"], "/")
    +xs : List<&2, J.Json> = Claude.listed(pc)
    return Models.found(Claude.models(Main.has(cl), xs), Models.on(Main.has(cx), Models.codex(cache)), Models.grok(gk),
      J.Json.obj([J.KV{"claude", Claude.about(About.cli(vc), xs)}, J.KV{"codex", About.one(About.cli(vx), About.codex(cache))}, J.KV{"grok", About.one(About.cli(vg), About.grok(gk))}]))

# the first probe runs at once (the window is up by then), the next ones
# every Models.every() ms
def Refresh.loop(fuel: Nat, +inbox: Chan(Msg), +user: String, +cache: String, +last: String) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        fd : Found <- Models.detect(user)
        now : String <- Refresh.found(fd, inbox, cache, last)
        IO.sleep(Models.every())
        Refresh.loop(f, inbox, user, cache, now)

def Refresh.start(+inbox: Chan(Msg), +cfg: Cfg) -> IO(Unit):
  do IO<Unit>:
    user : String <- Env.get("HOME", "")
    IO.spawn(Unit, Refresh.loop(Fuel.forever(), inbox, user, Models.cache(Cfg.home(cfg)), Net.models(Cfg.net(cfg))))

def Main.prepare(+user: String, +exe: String) -> IO(Boot):
  do IO<Boot>:
    K.KiStack.ensure(user)
    rev : String <- K.KiStack.current(user)
    ks : String & List<&2, Q.Skill> <- Skills.kistack.dir(K.KiStack.base(user) ++ "/" ++ rev)
    IO.spawn(Unit, K.KiStack.refresh(user))
    explicit : String <- Env.get("BACKPLANE_KICAD_CLI", "")
    rt : K.Rt <- K.Rt.resolve(explicit, exe, user ++ "/.backplane-bend")
    +fc : String <- FC.FreeCAD.find()
    return Models.boot(ks, rt, Found{"", ""}, fc)

def Main.config(+user: String, +exe: String, args: List<String>, b: Boot) -> Cfg:
  Boot{kdir, skills, rt, ms, mt, +fc} = b
  Main.args(args, Cfg{user ++ "/.backplane-bend", exe ++ "/web", "127.0.0.1", 3787,
    Q.Prompt.runtime("Backplane") ++ "\n\n" ++ Q.Prompt.mech(fc, exe ++ "/backplane"), [kdir], Main.version(), Net{True{}, False{}, "", ms, mt, rt, None{}, None{}, None{}, "", None{}, BN.Bn.empty(), False{}, "", fc}})

def Sys.exe_dir.io() -> IO(String):
  H.Sys.exe_dir()

# Media jobs (Hub.media): attachments and update checks
# -----------------------------------------------------

def Media.fail(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +msg: String) -> IO(Unit):
  GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{msg}}, J.KV{"thread", J.Str{thread}}, J.KV{"upload", J.Flag{True{}}}]))

def Media.attached(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"attached", J.Str{path}}, J.KV{"thread", J.Str{thread}}]))

def Media.wrote.k(res: Result<&1, &1, U32 & String, Unit>) -> String:
  match res:
    case Done{_}:
      ""
    case Fail{_}:
      "cannot write the attachment"

def Media.wrote(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(String):
  (f, res) = r
  do IO<String>:
    File.close(f)
    return Media.wrote.k(res)

def Media.opened(r: Result<&1, &1, U32 & String, File>, bs: List<&2, U32>) -> IO(String):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, String, File.write_bytes(f, bs), Media.wrote)
    case Fail{_}:
      IO.pure(String, "cannot open the attachment file")

# write (mode "w") or append ("a") bytes; "" or what went wrong
def Media.put.file(+path: String, +mode: String, bs: List<&2, U32>) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, mode), r => Media.opened(r, bs))

def Media.size(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> Nat:
  match r:
    case Done{(0, (sz, _))}:
      U32.to_nat(sz)
    case _:
      0n

# a regular file's size (None for anything else)
def Media.stat(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> Maybe<&2, Nat>:
  match r:
    case Done{(0, (sz, _))}:
      Some{U32.to_nat(sz)}
    case _:
      None{}

def Media.put.done(+err: String, +last: Bool, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(err),
    Bool.pick(IO(Unit), last, Media.attached(inbox, client, id, thread, path), GitJob.reply(inbox, client, id, True{}, J.Json.obj(Nil{}))),
    Media.fail(inbox, client, id, thread, err))

def Media.put.k(over: Bool, +first: Bool, +last: Bool, bs: List<&2, U32>, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  match over:
    case True{}:
      do IO<Unit>:
        rm : Result<&1, &1, U32 & String, Unit> <- H.FS.remove(path)
        Media.fail(inbox, client, id, thread, "attachments are limited to " ++ Nat.show(Nat.div(AT.Att.cap(), 1048576n)) ++ " MB")
    case False{}:
      IO.bind(String, Unit, Media.put.file(path, Bool.pick(String, first, "w", "a"), bs), e => Media.put.done(e, last, inbox, client, id, thread, path))

def Media.put.go(+have: Nat, +first: Bool, +last: Bool, +bs: List<&2, U32>, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  Media.put.k(Nat.is_gt(Nat.add(have, List.length(&2, U32, bs)), AT.Att.cap()), first, last, bs, inbox, client, id, thread, path)

def Media.put.parts(ps: List<&2, String>, +b: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +home: String) -> IO(Unit):
  match ps:
    case +i <> +l <> +name <> _:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(AT.Att.dir(home, thread))
        st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(AT.Att.dir(home, thread) ++ "/" ++ AT.Att.safe(name))
        Media.put.go(Bool.pick(Nat, String.eq(i, "0"), 0n, Media.size(st)), String.eq(i, "0"), String.eq(l, "1"), AT.Att.b64(b),
          inbox, client, id, thread, AT.Att.dir(home, thread) ++ "/" ++ AT.Att.safe(name))
    case _:
      Media.fail(inbox, client, id, thread, "bad upload")

# one piece of an upload (a = "<index>|<last>|<name>", b = base64); the
# first piece starts the file, the rest append; a file never passes the cap
# and never lands outside <home>/attachments/<thread>/
def Media.put(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +a: String, +b: String, +home: String) -> IO(Unit):
  Media.put.parts(String.split(a, '|'), b, inbox, client, id, thread, home)

def Media.copy.k(ok: Bool, fits: Bool, +src: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +dest: String) -> IO(Unit):
  match ok fits:
    case True{} True{}:
      do IO<Unit>:
        bs : List<&2, U32> <- Files.read(src)
        Media.put.go(0n, True{}, True{}, bs, inbox, client, id, thread, dest)
    case True{} False{}:
      Media.fail(inbox, client, id, thread, "attachments are limited to " ++ Nat.show(Nat.div(AT.Att.cap(), 1048576n)) ++ " MB")
    case False{} _:
      Media.fail(inbox, client, id, thread, "not a file: " ++ src)

def Media.copy.m(m: Maybe<&2, Nat>, +src: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +dest: String) -> IO(Unit):
  match m:
    case Some{+n}:
      Media.copy.k(True{}, Nat.is_le(n, AT.Att.cap()), src, inbox, client, id, thread, dest)
    case None{}:
      Media.copy.k(False{}, True{}, src, inbox, client, id, thread, dest)

# a file on this machine (the native window's paste or path), copied in
def Media.file(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +src: String, +name: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(AT.Att.dir(home, thread))
    st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(src)
    Media.copy.m(Media.stat(st), src, inbox, client, id, thread, AT.Att.dir(home, thread) ++ "/" ++ AT.Att.safe(name))

def Media.img.k(ok: Bool, +path: String) -> IO(Maybe<&2, AT.Img>):
  match ok:
    case True{}:
      IO.bind(List<&2, U32>, Maybe<&2, AT.Img>, Files.read(path), bs => IO.pure(Maybe<&2, AT.Img>, Some{AT.Img{AT.Att.mime(path), SH.B64.encode(bs)}}))
    case False{}:
      IO.pure(Maybe<&2, AT.Img>, None{})

def Media.img.m(m: Maybe<&2, Nat>, +path: String) -> IO(Maybe<&2, AT.Img>):
  match m:
    case Some{+n}:
      Media.img.k(Bool.and(Nat.is_gt(n, 0n), Nat.is_le(n, U32.to_nat(AT.Att.inline_max()))), path)
    case None{}:
      IO.pure(Maybe<&2, AT.Img>, None{})

# an attached image small enough to send inline
def Media.img(+path: String) -> IO(Maybe<&2, AT.Img>):
  do IO<Maybe<&2, AT.Img>>:
    st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(path)
    Media.img.m(Media.stat(st), path)

def Media.imgs.add(m: Maybe<&2, AT.Img>, acc: List<&2, AT.Img>) -> List<&2, AT.Img>:
  match m:
    case Some{i}:
      i <> acc
    case None{}:
      acc

def Media.imgs(ps: List<&2, String>, acc: List<&2, AT.Img>) -> IO(List<&2, AT.Img>):
  match ps:
    case Nil{}:
      IO.pure(List<&2, AT.Img>, List.reverse(&2, AT.Img, acc))
    case +p <> t:
      IO.bind(Maybe<&2, AT.Img>, List<&2, AT.Img>, Media.img(p), m => Media.imgs(t, Media.imgs.add(m, acc)))

# look for a release on a channel now (announced like the hourly check)
def Media.check.go(+channel: String, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    r : Maybe<&2, UP.Release> <- UP.Update.latest(channel)
    +tag : String = UP.Update.newer(r)
    Upgrade.found(tag, inbox)
    Bool.pick(IO(Unit), String.is_empty(id), IO.pure(Unit, Unit{}), GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"version", J.Str{tag}}, J.KV{"channel", J.Str{channel}}])))

# (a packaged install looks for nothing: its updates come from the package)
def Media.check(managed: Bool, +channel: String, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  match managed:
    case True{}:
      Bool.pick(IO(Unit), String.is_empty(id), IO.pure(Unit, Unit{}), GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"version", J.Str{""}}, J.KV{"channel", J.Str{channel}}])))
    case False{}:
      Media.check.go(channel, inbox, client, id)

# a Claude message with images: read them, then hand the stream-json line
# (image blocks, then the text) to the thread's agent
# (uuid: the command's, kept on the line: core/cmds.bend)
def Media.claude(+inbox: Chan(Msg), +thread: String, +cwd: String, +text: String, +uuid: String, +gen: String) -> IO(Unit):
  do IO<Unit>:
    ims : List<&2, AT.Img> <- Media.imgs(AT.Att.images(text), Nil{})
    +ss : List<&2, AG.USkill> <- Skills.scan(cwd)
    ok : Bool <- Chan.send(Msg, inbox, AgentWrite{thread, B.Claude.tag(AT.Att.claude(AG.Mention.expand("claude", text, ss), ims), uuid), gen})
    return Unit{}

# a Git out: the media jobs here (an upload piece runs on the hub, so the
# pieces of a file land in order), git jobs off the hub
def Media.run.k(i: Nat, +tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +managed: Bool, +gen: String) -> IO(Unit):
  match i:
    case 0n:
      Media.put(inbox, client, id, thread, a, b, home)
    case 1n:
      IO.spawn(Unit, Media.file(inbox, client, id, thread, a, b, home))
    case 2n:
      IO.spawn(Unit, Media.claude(inbox, thread, cwd, a, b, gen))
    case 3n:
      IO.spawn(Unit, Media.check(managed, a, inbox, client, id))
    case _:
      IO.spawn(Unit, Jobs.run(tx, job, inbox, client, id, thread, cwd, a, b, home))

def Media.run(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +managed: Bool, +gen: String) -> IO(Unit):
  Media.run.k(C.Codec.pos(["attach.put", "attach.file", "attach.claude", "update.check"], job), tx, job, inbox, client, id, thread, cwd, a, b, home, managed, gen)

# thread_wait: the check (MC.Wait.now) goes through the hub each second,
# off the hub, until the thread is done or the time is up; its last answer
# is the reply
def Wait.next(stop: Bool, text: String, +reply: Chan(String), k: Unit -> IO(Unit)) -> IO(Unit):
  match stop:
    case True{}:
      IO.bind(Bool, Unit, Chan.send(String, reply, text), ok => IO.pure(Unit, Unit{}))
    case False{}:
      IO.bind(Unit, Unit, IO.sleep(1000), k)

def Wait.got(m: Maybe<&1, String>, +left: Nat, +reply: Chan(String), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{+text}:
      Wait.next(Bool.or(MC.Wait.done(text), Nat.is_eq(left, 0n)), text, reply, k)
    case None{}:
      IO.pure(Unit, Unit{})

def Wait.loop(+fuel: Nat, +thread: String, +check: String, +reply: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        +r2 : Chan(String) <- Chan.new(String, 1)
        ok : Bool <- Chan.send(Msg, inbox, Mcp{thread, check, r2})
        m : Maybe<&1, String> <- Chan.recv(String, r2)
        Wait.got(m, f, reply, _ => Wait.loop(f, thread, check, reply, inbox))

# a message's line, its images read: it goes once every message the hub
# took before it has gone (Claude.ready)
def Hub.agent_write(h: Hub, +thread: String, +line: String, +gen: String) -> IO(Hub):
  Claude.ready(h, thread, line, gen)

def Hub.update_check(h: Hub) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Media.check(Net.managed(Cfg.net(cfg)), M.Setting.get(st, "update.channel", "stable"), inbox, 0, ""))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Agent.pid_of(m: Maybe<&2, Agent>) -> Maybe<&2, U32>:
  match m:
    case Some{Agent{_, _, p, _, _}}:
      Some{p}
    case None{}:
      None{}

def Agent.key.of(m: Maybe<&2, Agent>) -> String:
  match m:
    case Some{Agent{_, _, _, k, _}}:
      k
    case None{}:
      ""

# the thread's agent until its process reports: a placeholder of the
# generation being started (pid 0, never signalled: Proc.kill)
def Hub.placeholder(h: Hub, +thread: String, +gen: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.agent_stop(Agents.get(as, thread))
        c : Chan(String) <- Chan.new(String, 1)
        return Hub{st, f, ls, cl, Agent{thread, c, 0, B.Gen.key(gen), Nil{}} <> Agents.drop(as, thread), inbox, cfg, note}

def Hub.turn_pid.k(ok: Bool, h: Hub, +thread: String, +pid: U32, input: Chan(String), +gen: String) -> IO(Hub):
  match ok h:
    case True{} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.agent_stop(Agents.get(as, thread))
        return Hub{st, f, ls, cl, Agent{thread, input, pid, B.Gen.turn(gen), Nil{}} <> Agents.drop(as, thread), inbox, cfg, note}
    case False{} _:
      do IO<Hub>:
        Chan.close(String, input)
        Proc.kill(pid, 15)
        return h

# a turn process started: it is the thread's only if the thread's agent is
# the placeholder of its generation (B.Gen.accepts); any other (its turn
# stopped, or a later one started) is stopped at once
def Hub.turn_pid(h: Hub, +thread: String, +pid: U32, input: Chan(String), +gen: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.turn_pid.k(B.Gen.accepts(Agent.key.of(Agents.get(as, thread)), gen), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, pid, input, gen)

def Hub.turn_done.k(same: Bool, h: Hub, +thread: String) -> Hub:
  match same h:
    case True{} Hub{st, f, ls, cl, as, inbox, cfg, note}:
      Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}
    case False{} _:
      h

# a turn process exited: forgotten, unless another replaced it already
def Hub.turn_done(h: Hub, +tag: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      IO.pure(Hub, Hub.turn_done.k(B.Tag.heard(B.Tag.pid(tag), Agent.pid_of(Agents.get(as, B.Tag.thread(tag)))), Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Tag.thread(tag)))

# Bots
# ----
# The IO of docs/bots.md around the pure decider (core/bothub.bend):
# effects (B.BotFx), signed requests from webhooks and linked machines,
# Google's tools, a bot's own browser page. Secrets are handled by
# botnet.bend and never reach the log, the event log or a broadcast.

def Cfg.machines(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, _, _, mc, _, _, _, _, _}}:
      mc

def Cfg.bn(c: Cfg) -> BN.Bn:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      bnx

def Live.of(+cfg: Cfg) -> List<&2, LV.Buf>:
  BN.Bn.live(Cfg.bn(cfg))

def Cfg.with_bn(c: Cfg, b: BN.Bn) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, _, mgd, lk, fc}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, b, mgd, lk, fc}}

def Live.with(+cfg: Cfg, lv: List<&2, LV.Buf>) -> Cfg:
  Cfg.with_bn(cfg, BN.Bn.with_live(Cfg.bn(cfg), lv))

# a write failed and may have left a cut line: it was closed off with a
# newline (the next line starts on its own), and a repair that failed is
# reported too
def Hub.commit.failed(r: File & Result<&1, &1, U32 & String, Unit>, err: String, st: M.State, ls: List<&2, String>, cl: List<&2, Client>,
    as: List<&2, Agent>, inbox: Chan(Msg), cfg: Cfg, note: String) -> IO(Hub & Wrote):
  (f, res) = r
  match res:
    case Done{_}:
      IO.pure(Hub & Wrote, (Hub{st, f, ls, cl, as, inbox, cfg, note}, Wrote{Nil{}, False{}, ST.Store.fail.msg(err, True{})}))
    case Fail{_}:
      IO.pure(Hub & Wrote, (Hub{st, f, ls, cl, as, inbox, cfg, note}, Wrote{Nil{}, False{}, ST.Store.fail.msg(err, False{})}))

def Hub.commit.done(r: File & Result<&1, &1, U32 & String, Unit>, +cs: List<&2, M.Change>, st: M.State, ls: List<&2, String>, cl: List<&2, Client>,
    as: List<&2, Agent>, +inbox: Chan(Msg), +cfg: Cfg, note: String) -> IO(Hub & Wrote):
  (f, res) = r
  match res:
    case Done{_}:
      do IO<Hub & Wrote>:
        Bot.dir.changed.all(cs, inbox)
        return Hub.commit.k(Hub.fold(cs, Folded{st, ls, Nil{}}), f, cl, as, inbox, Live.with(cfg, LV.Live.ends(cs, Live.of(cfg))), note)
    case Fail{e}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Hub & Wrote, File.write(f, "\n"),
        r2 => Hub.commit.failed(r2, Hub.err.msg(e), st, ls, cl, as, inbox, cfg, note))

# persist a step's changes in one write, then fold them in
def Hub.commit.w(+cs: List<&2, M.Change>, h: Hub) -> IO(Hub & Wrote):
  match cs h:
    case Nil{} _:
      IO.pure(Hub & Wrote, (h, Wrote{Nil{}, True{}, ""}))
    case _ Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Hub & Wrote, File.write(f, ST.Store.text(Hub.lines.disk(cs))),
        r => Hub.commit.done(r, cs, st, ls, cl, as, inbox, cfg, note))

def Hub.commit.b(r: Hub & List<&2, String>) -> IO(Hub & List<&2, String>):
  (h, fr) = r
  IO.bind(Hub, Hub & List<&2, String>, Hub.busy.set(h), h2 => IO.pure(Hub & List<&2, String>, (h2, fr)))

# persist changes, fold them in; answers the hub and the new lines (newest first)
def Hub.commit(+cs: List<&2, M.Change>, h: Hub, fresh: List<&2, String>) -> IO(Hub & List<&2, String>):
  IO.bind(Hub & Wrote, Hub & List<&2, String>, Hub.commit.w(cs, h), r => Hub.commit.b(Hub.commit.r(r, fresh)))

def Cfg.host(c: Cfg) -> String:
  match c:
    case Cfg{_, _, ho, _, _, _, _, _}:
      ho

def Cfg.tailnet(c: Cfg) -> Bool:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{tn, _, _, _, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}}:
      tn

def Hub.broadcast(h: Hub, +text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.all(cl, text)
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

# a thread's browser page: a bot's is named by the bot, any other
# thread's by the thread (BO.World.page)
def Bot.page(+st: M.State, +thread: String) -> String:
  BO.World.page(M.State.bots(st), thread)

def Bot.is_bot(m: Maybe<&2, BO.Bot>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# opening or navigating brings the Browser tab forward in the viewer of
# the thread that asked (a bot shows its page in its own Browser tab)
def Preview.view(+thread: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"view"}}, J.KV{"thread", J.Str{thread}}, J.KV{"kind", J.Str{"browser"}}, J.KV{"path", J.Str{""}}]))

def Hub.preview(h: Hub, +thread: String, +o: J.Json, +reply: Chan(String)) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Preview.run(cfg, Bot.page(st, thread), o, reply))
        cl2 : List<&2, Client> <- Hub.auto.k(Bool.not(Bool.and(Bool.not(Bot.is_bot(BO.World.of_thread(M.State.bots(st), thread))), Preview.shows(o))), cl, Preview.view(thread))
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

# requests: "bots.*" to the bots' decider, the rest to the hub's
def Bot.request.k(bots: Bool, +o: J.Json, +st: M.State, +now: Nat, +client: U32) -> B.Step:
  match bots:
    case True{}:
      BH.Bots.request(st, now, client, o)
    case False{}:
      BH.Bots.hub(st, now, client, o)

def Bot.request(m: Maybe<&2, J.Json>, +st: M.State, +now: Nat, +client: U32, +text: String) -> B.Step:
  match m:
    case Some{+o}:
      Bot.request.k(BH.Bots.is(J.Json.get_str(o, "m", "")), o, st, now, client)
    case None{}:
      B.Hub.request_text(st, now, client, text)

# Memory reaches only the agent: a bot's turn text gets its <memory>
# block here, after the timeline kept the text as it was sent

def Bot.line.k(m: Maybe<&2, J.Json>, +st: M.State, +now: Nat, +thread: String, +line: String) -> String:
  match m:
    case Some{+o}:
      Bool.pick(String, String.eq(J.Json.get_str(o, "type", ""), "user"), B.Claude.user.u(BH.Bots.turn(st, now, thread, Mention.user_text(o)), J.Json.get_str(o, "uuid", "")), line)
    case None{}:
      line

# a Claude stream-json line for a bot's thread: a user message gets the memory
def Bot.line(bot: Bool, +st: M.State, +now: Nat, +thread: String, +line: String) -> String:
  match bot:
    case True{}:
      Bot.line.k(J.Json.parse(line), st, now, thread, line)
    case False{}:
      line

# a Claude message with images carries its text in the job's `a`
def Bot.attach(claude: Bool, +st: M.State, +now: Nat, +thread: String, +a: String) -> String:
  match claude:
    case True{}:
      BH.Bots.turn(st, now, thread, a)
    case False{}:
      a

# Effects
# -------

def BotJob.reply(+inbox: Chan(Msg), +client: U32, +id: String, +ok: Bool, kvs: List<&2, J.KV>) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Msg, inbox, Push{client, J.Json.show(J.Json.obj(List.append(&2, J.KV, [J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{ok}}], kvs)))})
    return Unit{}

def BotJob.fail(+inbox: Chan(Msg), +client: U32, +id: String, msg: String) -> IO(Unit):
  BotJob.reply(inbox, client, id, False{}, [J.KV{"error", J.Str{msg}}])

def BotJob.client(+b: String) -> U32:
  Maybe.default(&2, U32, U32.read(b), 0)

def BotJob.id(+c: String) -> String:
  Bool.pick(String, String.is_empty(c), "0", c)

# a bot's home folder (dir <home>/bots/), or a scratch thread's
# (<home>/scratch/, M.Scratch), a git repository (so its turns get
# checkpoints), becomes its thread's folder
def BotJob.home.k(safe: Bool, +inbox: Chan(Msg), +dir: String, +bot: String, +thread: String) -> IO(Unit):
  match safe:
    case True{}:
      do IO<Unit>:
        +path : String = dir ++ bot
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(path)
        r : P.Ran <- P.Proc.run("git", ["init", "-q"], path)
        +now : Nat <- Now.nat()
        ok : Bool <- Chan.send(Msg, inbox, Commit{[M.WorktreeSet{thread, "", path, now}]})
        return Unit{}
    case False{}:
      Log.info("bots: not a folder name: " ++ bot)

# a scratch thread's folder is made at once, before the effects after it
# (its first turn may start in the same step); git init follows
def BotJob.scratch(safe: Bool, +inbox: Chan(Msg), +dir: String, +thread: String) -> IO(Unit):
  match safe:
    case True{}:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(dir ++ thread)
        IO.spawn(Unit, BotJob.home.k(True{}, inbox, dir, thread, thread))
    case False{}:
      IO.pure(Unit, Unit{})

# an expired scratch thread's folder goes with it
def BotJob.scratch.gone(safe: Bool, +home: String, +thread: String) -> IO(Unit):
  match safe:
    case True{}:
      do IO<Unit>:
        r : P.Ran <- P.Proc.run("rm", ["-rf", "--", home ++ "/scratch/" ++ thread], home)
        return Unit{}
    case False{}:
      IO.pure(Unit, Unit{})

def BotJob.hooked(+secret: String, +inbox: Chan(Msg), +client: U32, +id: String, +hook: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(secret), BotJob.fail(inbox, client, id, "could not keep the webhook's secret"),
    BotJob.reply(inbox, client, id, True{}, [J.KV{"hook", J.Str{hook}}, J.KV{"secret", J.Str{secret}}, J.KV{"path", J.Str{"/hook/" ++ hook}}]))

# a webhook's secret: made and kept here, shown once to the client that asked
def BotJob.hook(+inbox: Chan(Msg), +home: String, +hook: String, +client: U32, +id: String) -> IO(Unit):
  IO.bind(String, Unit, BN.Bn.hook.make(home, hook), s => BotJob.hooked(s, inbox, client, id, hook))

def BotJob.sent(r: BN.Resp, +peer: String, +path: String) -> IO(Unit):
  match r:
    case BN.Resp{+code, _}:
      Bool.pick(IO(Unit), Bool.and(Nat.is_ge(code, 200n), Nat.is_lt(code, 300n)), IO.pure(Unit, Unit{}),
        Log.info("bots: " ++ path ++ " to " ++ peer ++ " failed (" ++ Nat.show(code) ++ ")"))

# a signed POST to a linked machine
def BotJob.send(+home: String, +url: String, +peer: String, +path: String, +body: String) -> IO(Unit):
  do IO<Unit>:
    +now : Nat <- Now.nat()
    r : BN.Resp <- BN.Bn.to_peer(home, url, peer, now, path, True{}, body)
    BotJob.sent(r, peer, path)

def BotJob.invited(ok: Bool, +inbox: Chan(Msg), +client: U32, +id: String, +url: String, +peer: String, +secret: String) -> IO(Unit):
  match ok:
    case True{}:
      BotJob.reply(inbox, client, id, True{}, [J.KV{"invite", J.Str{SG.Invite.make(url, peer, secret)}}, J.KV{"peer", J.Str{peer}}])
    case False{}:
      BotJob.fail(inbox, client, id, "could not keep the invite's secret")

# an invite: a new peer id and secret, kept here; the other machine links
# with it (POST /bots/link) and both keep the secret
def BotJob.invite(+inbox: Chan(Msg), +home: String, +tailnet: Bool, +host: String, +port: U32, +given: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    +here : String <- BN.Bn.url.here(tailnet, host, port)
    +r : String <- BN.Bn.random(2n)
    +peer : String = "p" ++ r
    +secret : String <- BN.Bn.secret.fresh()
    ok : Bool <- BN.Bn.peer.save(home, peer, secret)
    BotJob.invited(ok, inbox, client, id, Bool.pick(String, String.is_empty(String.trim(given)), here, String.trim(given)), peer, secret)

def BotJob.linked.k(ok: Bool, +name: String, +code: Nat, +body: String, +inbox: Chan(Msg), +home: String, +url: String, +peer: String, +client: U32, +id: String, +now: Nat) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        +shown : String = Bool.pick(String, String.is_empty(name), peer, name)
        sent : Bool <- Chan.send(Msg, inbox, Commit{[M.PeerSet{peer, shown, url, False{}, now}]})
        BotJob.reply(inbox, client, id, True{}, [J.KV{"peer", J.Str{peer}}, J.KV{"name", J.Str{shown}}])
    case False{}:
      do IO<Unit>:
        BN.Bn.peer.forget(home, peer)
        BotJob.fail(inbox, client, id, "the other machine did not link (" ++ Nat.show(code) ++ ") " ++ String.take(String.trim(body), 200n))

def BotJob.linked(r: BN.Resp, +inbox: Chan(Msg), +home: String, +url: String, +peer: String, +client: U32, +id: String, +now: Nat) -> IO(Unit):
  match r:
    case BN.Resp{+code, +body}:
      BotJob.linked.k(Nat.is_eq(code, 200n), BN.Bn.clean(J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), "name", "")), code, body,
        inbox, home, url, peer, client, id, now)

# joining with an invite: keep its secret, tell the inviter where we are
# (signed POST /bots/link), and link once it answers with its name
def BotJob.join(+inbox: Chan(Msg), +home: String, +tailnet: Bool, +host: String, +port: U32, +url: String, +peer: String, +secret: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- BN.Bn.peer.save(home, peer, secret)
    +here : String <- BN.Bn.url.here(tailnet, host, port)
    +me : String <- BN.Bn.name()
    +now : Nat <- Now.nat()
    r : BN.Resp <- BN.Bn.signed(home, url, peer, secret, now, "/bots/link", True{}, J.Json.show(J.Json.obj([J.KV{"url", J.Str{here}}, J.KV{"name", J.Str{me}}])))
    BotJob.linked(r, inbox, home, url, peer, client, id, now)

def BotJob.join.go(ok: Bool, linked: Bool, +inbox: Chan(Msg), +cfg: Cfg, +url: String, +peer: String, +secret: String, +client: U32, +id: String) -> IO(Unit):
  match ok linked:
    case True{} False{}:
      IO.spawn(Unit, BotJob.join(inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), url, peer, secret, client, id))
    case True{} True{}:
      BotJob.fail(inbox, client, id, "already linked to that machine")
    case False{} _:
      BotJob.fail(inbox, client, id, "not a usable invite")

def Bot.peer.live.k(p: BO.Peer) -> Bool:
  match p:
    case BO.Peer{_, _, _, _, revoked}:
      Bool.not(revoked)

def Bot.peer.live(+st: M.State, +id: String) -> Bool:
  Bot.peer.live.k(BO.World.peer(M.State.bots(st), id))

def Bot.peer.url.k(p: BO.Peer) -> String:
  match p:
    case BO.Peer{_, _, u, _, revoked}:
      Bool.pick(String, revoked, "", u)

# a live peer's address ("" for none)
def Bot.peer.url(+st: M.State, +id: String) -> String:
  Bot.peer.url.k(BO.World.peer(M.State.bots(st), id))

def Bot.peer.name.k(p: BO.Peer, +id: String) -> String:
  match p:
    case BO.Peer{_, +n, _, _, _}:
      Bool.pick(String, String.is_empty(n), id, n)

# what bots here call a peer ("name@<this>")
def Bot.peer.name(+st: M.State, +id: String) -> String:
  Bot.peer.name.k(BO.World.peer(M.State.bots(st), id), id)

def BotJob.join.k(m: Maybe<&2, SG.Inv>, +st: M.State, +inbox: Chan(Msg), +cfg: Cfg, +client: U32, +id: String) -> IO(Unit):
  match m:
    case Some{SG.Inv{+url, +peer, +secret}}:
      BotJob.join.go(Bool.and(BN.Bn.url.ok(url), BN.Bn.safe(peer)), Bot.peer.live(st, peer), inbox, cfg, url, peer, secret, client, id)
    case None{}:
      BotJob.fail(inbox, client, id, "not an invite")

def BotJob.send.k(+url: String, +cfg: Cfg, +peer: String, +path: String, +body: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(url), Log.info("bots: no linked machine " ++ peer),
    IO.spawn(Unit, BotJob.send(Cfg.home(cfg), url, peer, path, body)))

def BotJob.close(m: Maybe<&2, Chan(BR.BMsg)>, +bot: String) -> IO(Unit):
  match m:
    case Some{q}:
      IO.bind(String, Unit, BR.Browser.ask_on(q, bot, "close", J.Json.obj(Nil{})), r => IO.pure(Unit, Unit{}))
    case None{}:
      IO.pure(Unit, Unit{})

def Bot.redirect(+port: U32) -> String:
  "http://127.0.0.1:" ++ U32.show(port) ++ "/oauth/google"

# "configure" (phones) and "config" are the same op, and so are "paste"
# (the window) and "finish"; "connect" saves the client when one was typed,
# then begins
def BotJob.google.pos(+op: String) -> Nat:
  Bool.pick(Nat, String.eq(op, "configure"), 0n,
    Bool.pick(Nat, String.eq(op, "paste"), 2n, C.Codec.pos(["config", "begin", "finish", "status", "disconnect", "connect"], op)))

def BotJob.google.then(+text: String, +home: String, +redirect: String, +here: String) -> IO(String):
  Bool.pick(IO(String), String.starts_with(text, "error"), IO.pure(String, text), GS.Google.begin(home, redirect, here))

def BotJob.google.connect(typed: Bool, +home: String, +p: J.Json, +redirect: String, +here: String) -> IO(String):
  match typed:
    case False{}:
      GS.Google.begin(home, redirect, here)
    case True{}:
      IO.bind(String, String, GS.Google.configure(home, J.Json.get_str(p, "clientId", ""), J.Json.get_str(p, "clientSecret", "")),
        t => BotJob.google.then(t, home, redirect, here))

def BotJob.google.op(i: Nat, +home: String, +p: J.Json, +redirect: String, +here: String) -> IO(String):
  match i:
    case 0n:
      GS.Google.configure(home, J.Json.get_str(p, "clientId", ""), J.Json.get_str(p, "clientSecret", ""))
    case 1n:
      GS.Google.begin(home, redirect, here)
    case 2n:
      GS.Google.finish(home, J.Json.get_str(p, "pasted", ""), redirect)
    case 3n:
      GS.Google.status(home)
    case 4n:
      GS.Google.disconnect(home, String.trim(J.Json.get_str(p, "account", "")))
    case 5n:
      BotJob.google.connect(Bool.not(String.is_empty(String.trim(J.Json.get_str(p, "clientId", "")))), home, p, redirect, here)
    case _:
      IO.pure(String, "error: unknown Google request")

# a status answer carries the signed-in addresses too, one a line
def BotJob.google.kvs(status: Bool, +key: String, +text: String, +raw: String) -> List<&2, J.KV>:
  match status:
    case True{}:
      [J.KV{key, J.Str{text}}, J.KV{"googleAccounts", J.Str{GG.Accts.line(raw)}}]
    case False{}:
      [J.KV{key, J.Str{text}}]

def BotJob.google.done(+text: String, +raw: String, +begin: Bool, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.starts_with(text, "error"), BotJob.fail(inbox, client, id, Bool.pick(String, String.starts_with(text, "error: "), String.drop(text, 7n), text)),
    BotJob.reply(inbox, client, id, True{}, BotJob.google.kvs(String.starts_with(raw, "{"), Bool.pick(String, begin, "googleUrl", "google"), text, raw)))

# where other machines reach this hub, for a sign-in to name (begin and
# connect only: it asks tailscale)
def BotJob.google.here(begin: Bool, +tailnet: Bool, +host: String, +port: U32) -> IO(String):
  match begin:
    case True{}:
      BN.Bn.url.here(tailnet, host, port)
    case False{}:
      IO.pure(String, "")

# Google's setup and sign-in (src/server/google.bend), off the hub
def BotJob.google(+inbox: Chan(Msg), +home: String, +tailnet: Bool, +host: String, +port: U32, +params: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    +p : J.Json = Maybe.default(&2, J.Json, J.Json.parse(params), J.Null{})
    +i : Nat = BotJob.google.pos(J.Json.get_str(p, "op", ""))
    +here : String <- BotJob.google.here(Bool.or(Nat.is_eq(i, 1n), Nat.is_eq(i, 5n)), tailnet, host, port)
    +raw : String <- BotJob.google.op(i, home, p, Bot.redirect(port), here)
    +text : String <- GS.Google.say(raw)
    BotJob.google.done(text, raw, Bool.or(Nat.is_eq(i, 1n), Nat.is_eq(i, 5n)), inbox, client, id)

def Bot.ran(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      out
    case _:
      ""

def Bot.serve(on: Bool) -> IO(P.Ran):
  match on:
    case True{}:
      P.Proc.run("sh", ["-c", "command -v tailscale >/dev/null && timeout 5 tailscale serve status --json"], "/")
    case False{}:
      IO.pure(P.Ran, P.Ran{1, ""})

def Bot.hook.base.k(+env: String, +serve: String, +here: String) -> String:
  Bool.pick(String, String.is_empty(env), Bool.pick(String, String.is_empty(serve), here, serve),
    Bool.pick(String, String.ends_with(env, "/"), String.take(env, Nat.sub(String.length(env), 1n)), env))

# where a phone reaches this hub's webhooks: BACKPLANE_HOOK_URL (a
# funnel, a relay), else the HTTPS address `tailscale serve` gives the
# hub's port, else its tailnet address (plain HTTP)
def Bot.hook.base(+tailnet: Bool, +host: String, +port: U32) -> IO(String):
  do IO<String>:
    +env : String <- BN.Bf.env("BACKPLANE_HOOK_URL")
    r : P.Ran <- Bot.serve(tailnet)
    +here : String <- BN.Bn.url.here(tailnet, host, port)
    return Bot.hook.base.k(String.trim(env), TN.Tailnet.serve(Bot.ran(r), U32.show(port)), here)

def BotJob.token.or(none: Bool, +t: String, +home: String, +hook: String) -> IO(String):
  match none:
    case True{}:
      BN.Bn.token.make(home, hook)
    case False{}:
      IO.pure(String, t)

def BotJob.token.got(+t: String, +home: String, +hook: String) -> IO(String):
  BotJob.token.or(String.is_empty(t), t, home, hook)

# 0: the hook's token (made the first time), 1: a new one, 2: none
def BotJob.token.tok(op: Nat, +home: String, +hook: String) -> IO(String):
  match op:
    case 0n:
      IO.bind(String, String, BN.Bn.token.of(home, hook), t => BotJob.token.got(t, home, hook))
    case 1n:
      BN.Bn.token.make(home, hook)
    case _:
      IO.bind(Unit, String, BN.Bn.token.forget(home, hook), u => IO.pure(String, ""))

def BotJob.token.done(bad: Bool, +tok: String, +url: String, +inbox: Chan(Msg), +client: U32, +id: String, +hook: String) -> IO(Unit):
  match bad:
    case True{}:
      BotJob.fail(inbox, client, id, "could not keep the webhook's token")
    case False{}:
      BotJob.reply(inbox, client, id, True{}, [J.KV{"tokenHook", J.Str{hook}}, J.KV{"token", J.Str{tok}}, J.KV{"tokenUrl", J.Str{url ++ "/hook/" ++ hook}}])

# a webhook's bearer token, shown to the client that asked (only clients
# the server lets in reach this), with the URL a phone posts to
def BotJob.token(+op: Nat, +inbox: Chan(Msg), +home: String, +tailnet: Bool, +host: String, +port: U32, +hook: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    +tok : String <- BotJob.token.tok(op, home, hook)
    +url : String <- Bot.hook.base(tailnet, host, port)
    BotJob.token.done(Bool.and(String.is_empty(tok), Nat.is_lt(op, 2n)), tok, url, inbox, client, id, hook)

# Dictation (server/voice.bend): the key, the dictionary, and live sessions
# of this machine's microphone, whose messages go to the client that
# started them. "add" also comes from a bot's voice_dictionary_add (client
# 0: no one hears the answer).

# the key (masked), the dictionary and the microphones, and the API keys'
# names (server/apikeys.bend; never a secret)
def VoiceJob.status(+inbox: Chan(Msg), +home: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    kvs : List<&2, J.KV> <- VO.Vo.status(home)
    +d : String <- VO.Vo.devices()
    +ks : String <- AKS.Ak.names(home)
    BotJob.reply(inbox, client, id, True{}, List.append(&2, J.KV, kvs, [J.KV{"voiceDevices", J.Str{d}}, J.KV{"apiKeys", J.Str{ks}}]))

# "" when done (then the status goes back), else "error: why"
def VoiceJob.done(+err: String, +inbox: Chan(Msg), +home: String, +client: U32, +id: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(err), VoiceJob.status(inbox, home, client, id), BotJob.fail(inbox, client, id, String.drop(err, 7n)))

def VoiceJob.fwd.k(end: Bool, k: Unit -> IO(Unit)) -> IO(Unit):
  match end:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      k(Unit{})

def VoiceJob.fwd(m: Maybe<&1, String>, +inbox: Chan(Msg), +client: U32, k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{+text}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Msg, inbox, Push{client, text})
        VoiceJob.fwd.k(String.contains(text, "\"ev\":\"idle\""), k)
    case None{}:
      IO.pure(Unit, Unit{})

# a session's messages to its client, until idle
def VoiceJob.forward(fuel: Nat, +out: Chan(String), +inbox: Chan(Msg), +client: U32) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, out), m => VoiceJob.fwd(m, inbox, client, u => VoiceJob.forward(f, out, inbox, client)))

def VoiceJob.live(+inbox: Chan(Msg), +home: String, +client: U32, +id: String, +thread: String, +device: String) -> IO(Unit):
  do IO<Unit>:
    BotJob.reply(inbox, client, id, True{}, Nil{})
    +out : Chan(String) <- Chan.new(String, 256)
    IO.spawn(Unit, VO.Vo.live(home, thread, device, out))
    VoiceJob.forward(Fuel.forever(), out, inbox, client)

def VoiceJob.stopped(on: Bool, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String) -> IO(Unit):
  match on:
    case True{}:
      BotJob.reply(inbox, client, id, True{}, Nil{})
    case False{}:
      do IO<Unit>:
        BotJob.reply(inbox, client, id, True{}, Nil{})
        sent : Bool <- Chan.send(Msg, inbox, Push{client, VO.Vo.msg(thread, "idle", Nil{})})
        return Unit{}

def VoiceJob.op(i: Nat, +inbox: Chan(Msg), +home: String, +p: J.Json, +client: U32, +id: String) -> IO(Unit):
  match i:
    case 0n:
      VoiceJob.status(inbox, home, client, id)
    case 1n:
      IO.bind(String, Unit, VO.Vo.set_key(home, J.Json.get_str(p, "key", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case 2n:
      IO.bind(String, Unit, VO.Vo.unkey(home), e => VoiceJob.done(e, inbox, home, client, id))
    case 3n:
      IO.bind(String, Unit, VO.Vo.set_dict(home, J.Json.get_str(p, "dict", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case 4n:
      IO.bind(String, Unit, VO.Vo.add(home, J.Json.get_str(p, "term", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case 5n:
      VoiceJob.live(inbox, home, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "device", ""))
    case 6n:
      IO.bind(Bool, Unit, VO.Vo.stop(home), on => VoiceJob.stopped(on, inbox, client, id, J.Json.get_str(p, "thread", "")))
    case 7n:
      IO.bind(String, Unit, VO.Vo.devices(), d => BotJob.reply(inbox, client, id, True{}, [J.KV{"voiceDevices", J.Str{d}}]))
    # Settings' API keys: keep one, forget one (the status, names only, goes back)
    case 8n:
      IO.bind(String, Unit, AKS.Ak.add(home, J.Json.get_str(p, "name", ""), J.Json.get_str(p, "value", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case 9n:
      IO.bind(String, Unit, AKS.Ak.del(home, J.Json.get_str(p, "name", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case _:
      BotJob.fail(inbox, client, id, "unknown voice request")

def VoiceJob.go(+p: J.Json, +inbox: Chan(Msg), +home: String, +client: U32, +id: String) -> IO(Unit):
  VoiceJob.op(C.Codec.pos(["status", "key", "unkey", "dict", "add", "start", "stop", "devices", "api-add", "api-del"], J.Json.get_str(p, "op", "")), inbox, home, p, client, id)

def VoiceJob.run(+inbox: Chan(Msg), +home: String, +params: String, +client: U32, +id: String) -> IO(Unit):
  VoiceJob.go(Maybe.default(&2, J.Json, J.Json.parse(params), J.Null{}), inbox, home, client, id)

# one B.BotFx: home, gone, hook, unhook, send, invite, join, unpeer, google,
# token, retoken, untoken, voice
def Bot.fx(i: Nat, +st: M.State, +inbox: Chan(Msg), +cfg: Cfg, +a: String, +b: String, +c: String) -> IO(Unit):
  match i:
    case 0n:
      IO.spawn(Unit, BotJob.home.k(BN.Bn.safe(a), inbox, Cfg.home(cfg) ++ "/bots/", a, b))
    case 1n:
      IO.spawn(Unit, BotJob.close(Cfg.br(cfg), a))
    case 2n:
      IO.spawn(Unit, BotJob.hook(inbox, Cfg.home(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 3n:
      IO.spawn(Unit, BN.Bn.hook.forget(Cfg.home(cfg), a))
    case 4n:
      BotJob.send.k(Bot.peer.url(st, a), cfg, a, b, c)
    case 5n:
      IO.spawn(Unit, BotJob.invite(inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 6n:
      BotJob.join.k(SG.Invite.parse(a), st, inbox, cfg, BotJob.client(b), BotJob.id(c))
    case 7n:
      IO.spawn(Unit, BN.Bn.peer.forget(Cfg.home(cfg), a))
    case 8n:
      IO.spawn(Unit, BotJob.google(inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 9n:
      IO.spawn(Unit, BotJob.token(0n, inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 10n:
      IO.spawn(Unit, BotJob.token(1n, inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 11n:
      IO.spawn(Unit, BotJob.token(2n, inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 12n:
      IO.spawn(Unit, VoiceJob.run(inbox, Cfg.home(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 13n:
      BotJob.scratch(BN.Bn.safe(a), inbox, Cfg.home(cfg) ++ "/scratch/", a)
    case 14n:
      IO.spawn(Unit, BotJob.scratch.gone(BN.Bn.safe(a), Cfg.home(cfg), a))
    case _:
      IO.pure(Unit, Unit{})

# Terminals in the chat at the person's next message
# --------------------------------------------------
# What the thread's terminals show (those the agent has not seen as they
# are) goes after the message, and the ones not pinned stop: they grey
# out in the chat until a click starts them again (core/emb.bend).

def EmbNote.ask(m: Maybe<&2, Chan(TM.TMsg)>, +thread: String) -> IO(String):
  match m:
    case Some{q}:
      do IO<String>:
        +r : Chan(String) <- Chan.new(String, 1)
        ok : Bool <- Chan.send(TM.TMsg, q, TM.TNote{thread, r})
        a : Maybe<&1, String> <- Chan.recv(String, r)
        return Maybe.default(&1, String, a, "")
    case None{}:
      IO.pure(String, "")

def EmbNote.kill(ks: List<&2, String>, +m: Maybe<&2, Chan(TM.TMsg)>) -> IO(Unit):
  match ks:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case k <> t:
      IO.bind(Unit, Unit, Term.put(m, TM.TKill{k}), u => EmbNote.kill(t, m))

def EmbNote.take.k(has: Bool, +cfg: Cfg, +st: M.State, +thread: String) -> IO(String):
  match has:
    case True{}:
      do IO<String>:
        +n : String <- EmbNote.ask(Cfg.tm(cfg), thread)
        EmbNote.kill(EM.Emb.loose(M.State.mine(st, thread), st), Cfg.tm(cfg))
        return n
    case False{}:
      IO.pure(String, "")

def EmbNote.take(+cfg: Cfg, +st: M.State, +thread: String) -> IO(String):
  EmbNote.take.k(EM.Emb.any(M.State.mine(st, thread)), cfg, st, thread)

def EmbNote.user.k(m: Maybe<&2, J.Json>) -> Bool:
  match m:
    case Some{+o}:
      String.eq(J.Json.get_str(o, "type", ""), "user")
    case None{}:
      False{}

def EmbNote.user(+line: String) -> Bool:
  EmbNote.user.k(J.Json.parse(line))

def EmbNote.put.k(m: Maybe<&2, J.Json>, +line: String, +n: String) -> String:
  match m:
    case Some{+o}:
      B.Claude.user(Mention.user_text(o) ++ n)
    case None{}:
      line

def EmbNote.put(+line: String, +n: String) -> String:
  Bool.pick(String, String.is_empty(n), line, EmbNote.put.k(J.Json.parse(line), line, n))

# a Claude user line, with the note after its text
def EmbNote.claude(user: Bool, +cfg: Cfg, +st: M.State, +thread: String, +line: String) -> IO(String):
  match user:
    case True{}:
      IO.bind(String, String, EmbNote.take(cfg, st, thread), n => IO.pure(String, EmbNote.put(line, n)))
    case False{}:
      IO.pure(String, line)

# terminal_read: the actor's answer, again every 250 ms while the program
# runs and waitMs lasts
def TermRead.ask(+q: Chan(TM.TMsg), +key: String) -> IO(String):
  do IO<String>:
    +r : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(TM.TMsg, q, TM.TRead{key, r})
    a : Maybe<&1, String> <- Chan.recv(String, r)
    return Maybe.default(&1, String, a, "gone\n")

def TermRead.answer(+rid: String, +text: String) -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":" ++ rid ++ ",\"result\":" ++ J.Json.show(J.Json.obj([
    J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{Bool.pick(String, String.starts_with(text, "gone"), "There is no such terminal in this thread.", String.join(List.drop(&2, String, String.split(text, '\n'), 1n), "\n"))}}])])},
    J.KV{"isError", J.Flag{String.starts_with(text, "gone")}}])) ++ "}"

def TermRead.got(last: Bool, +text: String, +rid: String, +reply: Chan(String), k: Unit -> IO(Unit)) -> IO(Unit):
  match last:
    case False{}:
      Bool.pick(IO(Unit), String.starts_with(text, "running\n"), IO.bind(Unit, Unit, IO.sleep(250), k),
        IO.bind(Bool, Unit, Chan.send(String, reply, TermRead.answer(rid, text)), ok => IO.pure(Unit, Unit{})))
    case True{}:
      IO.bind(Bool, Unit, Chan.send(String, reply, TermRead.answer(rid, text)), ok => IO.pure(Unit, Unit{}))

def TermRead.loop(fuel: Nat, +q: Chan(TM.TMsg), +key: String, +rid: String, +reply: Chan(String)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.bind(String, Unit, TermRead.ask(q, key), t => TermRead.got(True{}, t, rid, reply, u => IO.pure(Unit, Unit{})))
    case 1n+f:
      IO.bind(String, Unit, TermRead.ask(q, key), t => TermRead.got(False{}, t, rid, reply, u => TermRead.loop(f, q, key, rid, reply)))

def TermRead.run(m: Maybe<&2, Chan(TM.TMsg)>, +key: String, +wait: Nat, +rid: String, +reply: Chan(String)) -> IO(Unit):
  match m:
    case Some{q}:
      TermRead.loop(Nat.div(Nat.min(wait, 120000n), 250n), q, key, rid, reply)
    case None{}:
      IO.bind(Bool, Unit, Chan.send(String, reply, TermRead.answer(rid, "gone\n")), ok => IO.pure(Unit, Unit{}))

def TermRead.is(+o: J.Json) -> Bool:
  Bool.and(String.eq(J.Json.get_str(o, "method", ""), "tools/call"), String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "terminal_read"))

def Hub.term_read(h: Hub, +thread: String, +o: J.Json, +reply: Chan(String)) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        +a : J.Json = J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments")
        IO.spawn(Unit, TermRead.run(Cfg.tm(cfg), EM.Emb.key(thread, J.Json.get_str(a, "id", "")), U32.to_nat(J.Json.get_u32(a, "waitMs", 0)), J.Json.as_raw(J.Json.get(o, "id"), "null"), reply))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# Watched work (core's Watch.*)
# -----------------------------
# Each piece of watched work has a folder, <home>/work/<id>. A work_run's
# command runs from there through a small script that writes its output
# to out and, when it ends, its exit code to code (written to code.tmp and
# renamed, so code appears whole); started marks that it was launched, so
# a launch asked again (after a restart) never starts it twice; it runs as
# the transient unit bp-<id> (systemd-run --user, so it outlives a restart
# of Backplane's own service) or, without user systemd, set apart with
# setsid. The code file is the outcome: a run gone without one, a pid
# reused or gone, a unit restarted as another invocation, all read as
# "gone", outcome unknown, never success. A watcher checks every 2 s.

def Watch.dir(+home: String, +id: String) -> String:
  home ++ "/work/" ++ id

def Watch.unit(+id: String) -> String:
  "bp-" ++ id

def Watch.launch.sh() -> String:
  "d=$1; c=$2; cmd=$3; u=$4; l=$5\npid_id() { q=$1; if [ -r \"/proc/$q/stat\" ]; then b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null); st=$(sed 's/^.*) //' \"/proc/$q/stat\" | cut -d' ' -f20); echo \"$b:$st\"; elif ps -p \"$q\" >/dev/null 2>&1; then ps -o lstart= -p \"$q\" | tr -s ' ' '_'; fi; }\nmkdir -p \"$d\" || { echo gone; exit 0; }\n[ -e \"$d/code\" ] && { echo running; exit 0; }\nif [ -e \"$d/started\" ]; then { [ -e \"$d/out\" ] || [ -e \"$d/how\" ] || systemctl --user is-active --quiet \"$u\" 2>/dev/null; } && { echo running; exit 0; }; fi\nprintf '%s\\n' \"$cmd\" > \"$d/cmd\"\n{ printf ': > \"%s/out\"\\n' \"$d\"; printf 'cd \"%s\" || exit 127\\n' \"$c\"; printf 'sh \"%s/cmd\" > \"%s/out\" 2>&1\\n' \"$d\" \"$d\"; printf 'echo $? > \"%s/code.tmp\" && mv \"%s/code.tmp\" \"%s/code\"\\n' \"$d\" \"$d\" \"$d\"; } > \"$d/run.sh\"\n: > \"$d/started\"\nif command -v systemd-run >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then\n  if systemd-run --user --quiet --collect --unit=\"$u\" ${l:+\"--property=MemoryMax=$l\" --property=MemorySwapMax=0} sh \"$d/run.sh\" >/dev/null 2>&1; then systemctl --user show -p InvocationID --value \"$u\" > \"$d/inv\" 2>/dev/null; echo unit > \"$d/how\"; echo running; exit 0; fi\nfi\nsetsid nohup sh \"$d/run.sh\" >/dev/null 2>&1 < /dev/null &\necho $! > \"$d/pid\"\npid_id $! > \"$d/pidid\"\necho pid > \"$d/how\"\necho running\n"

def Watch.check.sh() -> String:
  "k=$1; t=$2; id=$3; d=$4; u=$5\ncase $k in\nrun)\n  [ -e \"$d/stop\" ] && { echo stop; exit 0; }\n  [ -e \"$d/code\" ] && { echo \"done $(cat \"$d/code\")\"; exit 0; }\n  how=$(cat \"$d/how\" 2>/dev/null)\n  if [ \"$how\" != pid ]; then systemctl --user is-active --quiet \"$u\" && { echo running; exit 0; }\n  else p=$(cat \"$d/pid\" 2>/dev/null); [ -n \"$p\" ] && kill -0 \"$p\" 2>/dev/null && { echo running; exit 0; }; fi\n  [ -e \"$d/code\" ] && { echo \"done $(cat \"$d/code\")\"; exit 0; }\n  echo gone ;;\nunit)\n  [ -e \"$d/stop\" ] && { echo stop; exit 0; }\n  s=$(systemctl --user show -p ActiveState --value \"$t\" 2>/dev/null); r=$(systemctl --user show -p ExecMainStatus --value \"$t\" 2>/dev/null); n=$(systemctl --user show -p InvocationID --value \"$t\" 2>/dev/null)\n  [ \"$id\" = - ] && [ -n \"$n\" ] && echo \"ident $n\"\n  [ \"$id\" != - ] && [ -n \"$n\" ] && [ \"$n\" != \"$id\" ] && { echo gone; exit 0; }\n  case $s in active|activating|deactivating|reloading) echo running ;; inactive|failed) [ -n \"$n\" ] && echo \"done ${r:-0}\" || echo gone ;; *) echo gone ;; esac ;;\npid)\n  [ -e \"$d/stop\" ] && { echo stop; exit 0; }\n  if [ -r \"/proc/$t/stat\" ]; then b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null); st=$(sed 's/^.*) //' \"/proc/$t/stat\" | cut -d' ' -f20); n=\"$b:$st\"\n  elif ps -p \"$t\" >/dev/null 2>&1; then n=$(ps -o lstart= -p \"$t\" | tr -s ' ' '_')\n  else echo gone; exit 0; fi\n  [ \"$id\" = - ] && { echo \"ident $n\"; echo running; exit 0; }\n  [ \"$n\" = \"$id\" ] && echo running || echo gone ;;\nfile)\n  [ -e \"$d/stop\" ] && { echo stop; exit 0; }\n  [ -f \"$t\" ] && grep -qF \"$id\" \"$t\" 2>/dev/null && { echo found; exit 0; }\n  echo running ;;\n*) echo gone ;;\nesac\n"

def Watch.stop.sh() -> String:
  "pid_id() { q=$1; if [ -r \"/proc/$q/stat\" ]; then b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null); st=$(sed 's/^.*) //' \"/proc/$q/stat\" | cut -d' ' -f20); echo \"$b:$st\"; elif ps -p \"$q\" >/dev/null 2>&1; then ps -o lstart= -p \"$q\" | tr -s ' ' '_'; fi; }\nk=$1; t=$2; id=$3; d=$4; u=$5\nmkdir -p \"$d\"\ncase $k in\nunwatch) : > \"$d/stop\" ;;\nrun) if [ \"$(cat \"$d/how\" 2>/dev/null)\" = unit ]; then n=$(systemctl --user show -p InvocationID --value \"$u\" 2>/dev/null); [ -n \"$n\" ] && [ \"$n\" = \"$(cat \"$d/inv\" 2>/dev/null)\" ] && systemctl --user stop \"$u\" >/dev/null 2>&1; else p=$(cat \"$d/pid\" 2>/dev/null); n=$(pid_id \"$p\"); [ -n \"$p\" ] && [ \"$p\" -gt 1 ] && [ -n \"$n\" ] && [ \"$n\" = \"$(cat \"$d/pidid\" 2>/dev/null)\" ] && { kill -TERM \"-$p\" 2>/dev/null; kill -TERM \"$p\" 2>/dev/null; }; fi ;;\nunit) n=$(systemctl --user show -p InvocationID --value \"$t\" 2>/dev/null); [ \"$id\" != - ] && [ -n \"$n\" ] && [ \"$n\" = \"$id\" ] && systemctl --user stop \"$t\" >/dev/null 2>&1 ;;\npid) [ \"$t\" -gt 1 ] 2>/dev/null && [ \"$id\" != - ] && [ \"$(pid_id \"$t\")\" = \"$id\" ] && kill -TERM \"$t\" 2>/dev/null ;;\nesac\ntrue\n"

def Watch.tail.sh() -> String:
  "d=$1; [ -e \"$d/out\" ] && tail -c 2048 \"$d/out\"; true\n"

def Watch.lines(+out: String) -> List<&2, String>:
  M.Bg.lines(out)

def Watch.last(ls: List<&2, String>, +acc: String) -> String:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Watch.last(t, Bool.pick(String, String.starts_with(l, "ident "), acc, String.trim(l)))

def Watch.ident.of(ls: List<&2, String>, +acc: String) -> String:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Watch.ident.of(t, Bool.pick(String, String.starts_with(l, "ident "), String.trim(String.drop(l, 6n)), acc))

def Watch.ran(r: P.Ran) -> String:
  match r:
    case P.Ran{_, out}:
      out

def Watch.tail.text(r: P.Ran) -> String:
  match r:
    case P.Ran{_, out}:
      out

# the outcome's words for the thread: the code, where the output is, its end
def Watch.detail(+kind: String, +status: String, +dir: String, +tail: String) -> String:
  Bool.pick(String, String.eq(kind, "run"),
    Bool.pick(String, String.starts_with(status, "exit "), "exit code " ++ String.drop(status, 5n) ++ "\noutput: " ++ dir ++ "/out" ++ Bool.pick(String, String.is_empty(tail), "", "\nits end:\n" ++ tail), "output so far: " ++ dir ++ "/out"),
    "")

def Watch.report(+inbox: Chan(Msg), +thread: String, +id: String, +kind: String, +status: String, +dir: String) -> IO(Unit):
  do IO<Unit>:
    tr : P.Ran <- P.Proc.run("sh", ["-c", Watch.tail.sh(), "sh", dir], "/")
    ok : Bool <- Chan.send(Msg, inbox, WatchEnded{thread, id, status, Watch.detail(kind, status, dir, Watch.tail.text(tr))})
    return Unit{}

# a check's verdict: "running" carries on, "stop" (unwatched) ends quietly,
# anything else is reported
def Watch.verdict(+last: String) -> String:
  Bool.pick(String, String.starts_with(last, "done "), "exit " ++ String.drop(last, 5n), Bool.pick(String, String.eq(last, "found"), "done", last))

def Watch.step(i: Nat, +status: String, +ident: String, +thread: String, +id: String, +kind: String, +dir: String, +inbox: Chan(Msg), k: String -> IO(Unit)) -> IO(Unit):
  match i:
    case 0n:
      do IO<Unit>:
        IO.sleep(2000)
        k(ident)
    case 1n:
      IO.pure(Unit, Unit{})
    case _:
      Watch.report(inbox, thread, id, kind, Watch.verdict(status), dir)

def Watch.ident.post(same: Bool, +inbox: Chan(Msg), +thread: String, +id: String, +ident: String) -> IO(Unit):
  match same:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, WatchIdent{thread, id, ident})
        return Unit{}

def Watch.got.k(+ls: List<&2, String>, +ident: String, +thread: String, +id: String, +kind: String, +dir: String, +inbox: Chan(Msg), k: String -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Watch.ident.post(String.eq(Watch.ident.of(ls, ident), ident), inbox, thread, id, Watch.ident.of(ls, ident))
    Watch.step(C.Codec.pos(["running", "stop"], Watch.last(ls, "gone")), Watch.last(ls, "gone"), Watch.ident.of(ls, ident), thread, id, kind, dir, inbox, k)

def Watch.got(r: P.Ran, +ident: String, +thread: String, +id: String, +kind: String, +dir: String, +inbox: Chan(Msg), k: String -> IO(Unit)) -> IO(Unit):
  Watch.got.k(Watch.lines(Watch.ran(r)), ident, thread, id, kind, dir, inbox, k)

def Watch.tick(late: Bool, +ident: String, +home: String, +thread: String, +id: String, +kind: String, +target: String, +inbox: Chan(Msg), k: String -> IO(Unit)) -> IO(Unit):
  match late:
    case True{}:
      Watch.report(inbox, thread, id, kind, "timeout", Watch.dir(home, id))
    case False{}:
      IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", Watch.check.sh(), "sh", kind, target, ident, Watch.dir(home, id), Watch.unit(id)], "/"),
        r => Watch.got(r, ident, thread, id, kind, Watch.dir(home, id), inbox, k))

# the watcher: a check every 2 s until the work ends, its deadline passes,
# or it is no longer watched
def Watch.loop(fuel: Nat, +ident: String, +home: String, +thread: String, +id: String, +kind: String, +target: String, +deadline: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Nat, Unit, Now.nat(), now => Watch.tick(Bool.and(Nat.is_gt(deadline, 0n), Nat.is_ge(now, deadline)), ident, home, thread, id, kind, target, inbox,
        i2 => Watch.loop(f, i2, home, thread, id, kind, target, deadline, inbox)))

def Watch.launched(r: P.Ran, +thread: String, +id: String, +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case P.Ran{_, out}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, WatchLaunched{thread, id})
        return Unit{}

def Watch.start(run: Bool, +limit: String, +home: String, +thread: String, +id: String, +target: String, +cwd: String, +inbox: Chan(Msg)) -> IO(Unit):
  match run:
    case True{}:
      IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", Watch.launch.sh(), "sh", Watch.dir(home, id), cwd, target, Watch.unit(id), limit], "/"), r => Watch.launched(r, thread, id, inbox))
    case False{}:
      IO.pure(Unit, Unit{})

# an Await: a work_run's command launched (unless it ran already), then
# watched
def Watch.job(+limit: String, +home: String, +thread: String, +id: String, +kind: String, +target: String, +ident: String, +deadline: Nat, +cwd: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Watch.start(String.eq(kind, "run"), limit, home, thread, id, target, cwd, inbox)
    Watch.loop(Fuel.forever(), ident, home, thread, id, kind, target, deadline, inbox)

def Watch.stop.job(+home: String, +id: String, +kind: String, +target: String, +ident: String) -> IO(Unit):
  do IO<Unit>:
    r : P.Ran <- P.Proc.run("sh", ["-c", Watch.stop.sh(), "sh", kind, target, ident, Watch.dir(home, id), Watch.unit(id)], "/")
    return Unit{}

# Threads elsewhere (far.bend, docs/bots.md)
# ------------------------------------------
# This hub shares its bots and their threads with the owner's other
# machines it is linked to: each commit's shared changes are pushed to
# each (POST /far/push, one push out per link at a time), and a machine
# that missed some pulls them (POST /far/log, paged). What the others
# share with this one is kept as a mirror per link (in memory and in
# <home>/far/<link>.jsonl) and handed to every client ({"t":"far"}); a
# client's request about something elsewhere goes to its hub (POST
# /far/rpc). Every request between hubs is signed like /bots/deliver. The
# network is only ever used off the hub, in jobs that answer by message.

def Far.fh(h: Hub) -> FR.Fh & Hub:
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      (BN.Bn.far(Cfg.bn(cfg)), Hub{st, f, ls, cl, as, inbox, cfg, note})

def Far.with(h: Hub, fh: FR.Fh) -> Hub:
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub{st, f, ls, cl, as, inbox, Cfg.with_bn(cfg, BN.Bn.with_far(Cfg.bn(cfg), fh)), note}

# the machines' list (self and peers, as the switcher shows it)
def Far.machines(+cfg: Cfg) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(Cfg.machines(cfg)), J.Null{})

# whether a linked machine is one of the owner's own (only those get this
# hub's threads, or may act on them)
def Far.some(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

def Far.own(+cfg: Cfg, p: BO.Peer) -> Bool:
  match p:
    case BO.Peer{_, +n, +u, _, r}:
      Bool.and(Bool.not(r), Far.some(UC.Far.machine(Far.machines(cfg), n, u)))

def Far.keep(ok: Bool, p: BO.Peer, rest: List<&2, BO.Peer>) -> List<&2, BO.Peer>:
  match ok:
    case True{}:
      p <> rest
    case False{}:
      rest

def Far.own.go(ps: List<&2, BO.Peer>, +cfg: Cfg) -> List<&2, BO.Peer>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Far.keep(Far.own(cfg, p), p, Far.own.go(t, cfg))

def Far.own.id(+st: M.State, +cfg: Cfg, +id: String) -> Bool:
  Bool.and(Bot.peer.live(st, id), Far.own(cfg, BO.World.peer(M.State.bots(st), id)))

def Far.dir(+home: String) -> String:
  home ++ "/far"

def Far.file(+home: String, +link: String) -> String:
  Far.dir(home) ++ "/" ++ link ++ ".jsonl"

# Jobs (off the hub)
# ------------------

def Far.send(+inbox: Chan(Msg), m: Msg) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, m)
    return Unit{}

def Far.code(r: BN.Resp) -> Nat:
  match r:
    case BN.Resp{c, _}:
      c

def Far.body(r: BN.Resp) -> String:
  match r:
    case BN.Resp{_, b}:
      b

# a push too big for a request says only where it ends, past a gap, so
# the other end pulls it in pages
# The first durable change identifies the history. Cache its hash at
# startup or the first (small) commit, before accepting new pushes.
def Far.history(+ls: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, ls), "", SG.Sign.header("00", 0n, Maybe.default(&2, String, List.last(&2, String, ls), "")))

# at start: lines the log holds that this build cannot decode give the
# history a new identity (Fr.history.body)
def Far.history.at(+ls: List<&2, String>, +seq: Nat) -> String:
  Bool.pick(String, List.is_empty(&2, String, ls), "", SG.Sign.header("00", 0n, FR.Fr.history.body(Maybe.default(&2, String, List.last(&2, String, ls), ""), List.length(&2, String, ls), seq)))

def Far.push.body(+s: FR.Send, +name: String) -> String:
  Bool.pick(String, Nat.is_gt(String.length(FR.Send.body(s, name)), 200000n), FR.Send.body(FR.Send.gap(s), name), FR.Send.body(s, name))

def Far.push.job(s: FR.Send, +epoch: String, +home: String, +url: String, +inbox: Chan(Msg)) -> IO(Unit):
  match s:
    case FR.Send{+link, +since, +to, xs}:
      do IO<Unit>:
        now : Nat <- Now.nat()
        +name : String <- BN.Bn.name()
        +r : BN.Resp <- BN.Bn.to_peer(home, url, link, now, "/far/push", True{}, FR.Fr.with.epoch(Far.push.body(FR.Send{link, since, to, xs}, name), epoch))
        Far.send(inbox, FarPushed{link, Nat.is_eq(Far.code(r), 200n), to})

def Far.pull.job(+link: String, +since: Nat, +epoch: String, +home: String, +url: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- Now.nat()
    +r : BN.Resp <- BN.Bn.to_peer(home, url, link, now, "/far/log", True{}, J.Json.show(J.Json.obj([J.KV{"since", J.Json.nat(since)}, J.KV{"epoch", J.Str{epoch}}])))
    Far.send(inbox, FarPulled{link, since, Far.code(r), Far.body(r)})

def Far.rpc.job(+client: U32, +id: String, +link: String, +body: String, +home: String, +url: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- Now.nat()
    +r : BN.Resp <- BN.Bn.to_peer(home, url, link, now, "/far/rpc", True{}, body)
    Far.send(inbox, FarReplied{client, id, link, Far.code(r), Far.body(r)})

# this hub's shared lines, made from its log (newest first)
def Far.feed.job(+ls: List<&2, String>, +st: M.State, +inbox: Chan(Msg)) -> IO(Unit):
  Far.send(inbox, FarFeed{FR.Fr.feed(ls, st), ""})

# a mirror kept on disk, read back
def Far.load.job(+link: String, +name: String, +home: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +text : String <- Files.text(Far.file(home, link))
    Far.send(inbox, FarLoaded{link, name, text})

def Far.keep.job(+path: String, +text: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- BN.Bf.append(path, text)
    return Unit{}

def Far.out.put.k(p: FR.Fh & Hub, o: FR.Out) -> IO(Hub):
  (fh, h) = p
  IO.pure(Hub, Far.with(h, FR.Fh.out.set(fh, o)))

def Far.out.put(h: Hub, o: FR.Out) -> IO(Hub):
  Far.out.put.k(Far.fh(h), o)

def Far.push.next.k(m: Maybe<&2, FR.Send>, o: FR.Out, h: Hub, +url: String) -> IO(Hub):
  match m h:
    case Some{s} Hub{st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Far.push.job(s, FR.Fh.epoch(BN.Bn.far(Cfg.bn(cfg))), Cfg.home(cfg), url, inbox))
        Far.out.put(Hub{st, f, ls, cl, as, inbox, cfg, note}, o)
    case None{} _:
      Far.out.put(h, o)

# Pushing
# -------

def Far.push.next(r: Maybe<&2, FR.Send> & FR.Out, h: Hub, +url: String) -> IO(Hub):
  (m, o) = r
  Far.push.next.k(m, o, h, url)

def Far.out.of(p: FR.Fh & Hub, +link: String) -> FR.Out & Hub:
  (fh, h) = p
  (FR.Fh.out(fh, link), h)

def Far.push.one.k(r: FR.Out & Hub, +url: String, +from: Nat, +to: Nat, +xs: List<&2, FR.Item>) -> IO(Hub):
  (o, h) = r
  Far.push.next(FR.Out.next(FR.Out.add(o, from, to, xs)), h, url)

def Far.push.go(ps: List<&2, BO.Peer>, h: Hub, +from: Nat, +to: Nat, +xs: List<&2, FR.Item>) -> IO(Hub):
  match ps:
    case Nil{}:
      IO.pure(Hub, h)
    case BO.Peer{+i, _, +u, _, _} <> t:
      IO.bind(Hub, Hub, Far.push.one.k(Far.out.of(Far.fh(h), i), u, from, to, xs), h2 => Far.push.go(t, h2, from, to, xs))

# When discovery first recognizes a linked machine as the owner's, offer
# our current head. Its mirror can pull even if our commits happened
# before discovery, or our hub restarted without an observed away tick.
# Only discovery's newly returned peers are offered; no extra timer.
def Far.offer.job(+link: String, +head: Nat, +epoch: String, +home: String, +url: String) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- Now.nat()
    +name : String <- BN.Bn.name()
    r : BN.Resp <- BN.Bn.to_peer(home, url, link, now, "/far/push", True{},
      FR.Fr.with.epoch(FR.Send.body(FR.Send{link, head, head, Nil{}}, name), epoch))
    return Unit{}

# An empty head hint is deliberately outside the item queue: Out.next
# sends only batches with items. It carries no acknowledgement for that
# queue, and cannot reset a mirror without an authoritative pull.
def Far.offer.go(ps: List<&2, BO.Peer>, +head: Nat, +epoch: String, +home: String) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case BO.Peer{+link, _, +url, _, _} <> t:
      do IO<Unit>:
        IO.spawn(Unit, Far.offer.job(link, head, epoch, home, url))
        Far.offer.go(t, head, epoch, home)

def Far.offer(h: Hub, +ps: List<&2, BO.Peer>) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        Far.offer.go(Far.own.go(ps, cfg), M.State.seq(st), FR.Fh.epoch(BN.Bn.far(Cfg.bn(cfg))), Cfg.home(cfg))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Far.feed.put(p: FR.Fh & Hub, ls: List<&2, FR.Line>) -> Hub:
  (fh, h) = p
  Far.with(h, FR.Fh.feed.add(fh, ls))

def Far.push.k(empty: Bool, h: Hub, +lines: List<&2, FR.Line>, +from: Nat, +to: Nat) -> IO(Hub):
  match empty h:
    case True{} _:
      IO.pure(Hub, h)
    case False{} Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Far.push.go(Far.own.go(BO.World.peers(M.State.bots(st)), cfg), Far.feed.put(Far.fh(Hub{st, f, ls, cl, as, inbox, cfg, note}), lines), from, to,
        FR.Fr.lines.items(lines, Nil{}))

def Far.push.lines(+lines: List<&2, FR.Line>, h: Hub, +from: Nat, +to: Nat) -> IO(Hub):
  Far.push.k(List.is_empty(&2, FR.Line, lines), h, lines, from, to)

# a commit took the log from `from`: its shared changes join the feed and
# go to each of the owner's linked machines
def Far.history.first.k(first: Bool, fh: FR.Fh, h: Hub, +fresh: List<&2, String>) -> Hub:
  match first:
    case True{}:
      Far.with(h, FR.Fh.epoch.set(fh, Far.history(fresh)))
    case False{}:
      Far.with(h, fh)

def Far.history.first(first: Bool, p: FR.Fh & Hub, +fresh: List<&2, String>) -> Hub:
  (fh, h) = p
  Far.history.first.k(first, fh, h, fresh)

def Far.push(h: Hub, cs: List<&2, M.Change>, +fresh: List<&2, String>, +from: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Far.push.lines(FR.Fr.feed.add(cs, List.reverse(&2, String, fresh), from, st, Nil{}), Far.history.first(Nat.is_eq(from, 0n), Far.fh(Hub{st, f, ls, cl, as, inbox, cfg, note}), fresh), from, M.State.seq(st))

# a failed push holds its link for a backoff on a timer of its own; the
# timer's message lets the retained batch go again
def Far.retry.arm(holding: Bool, +link: String, +secs: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match holding:
    case True{}:
      IO.spawn(Unit, Self.post.wait(inbox, FarResend{link}, U32.from_nat(Nat.mul(secs, 1000n))))
    case False{}:
      IO.pure(Unit, Unit{})

def Far.pushed.go(+o: FR.Out, h: Hub, +ok: Bool, +to: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        Far.retry.arm(Bool.not(ok), FR.Out.link(o), FR.Out.delay(Nat.add(FR.Out.fails(o), 1n)), inbox)
        Far.push.next(FR.Out.next(FR.Out.done(o, ok, to)), Hub{st, f, ls, cl, as, inbox, cfg, note}, Bot.peer.url(st, FR.Out.link(o)))

def Far.pushed.k(r: FR.Out & Hub, ok: Bool, +to: Nat) -> IO(Hub):
  (o, h) = r
  Far.pushed.go(o, h, ok, to)

# a push ended: the next waiting one goes
def Hub.far.pushed(h: Hub, +link: String, ok: Bool, +to: Nat) -> IO(Hub):
  Far.pushed.k(Far.out.of(Far.fh(h), link), ok, to)

def Far.retry.go(+o: FR.Out, h: Hub) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Far.push.next(FR.Out.next(FR.Out.release(o)), Hub{st, f, ls, cl, as, inbox, cfg, note}, Bot.peer.url(st, FR.Out.link(o)))

def Far.retry.k(r: FR.Out & Hub) -> IO(Hub):
  (o, h) = r
  Far.retry.go(o, h)

# the backoff ended: the retained batch goes again
def Hub.far.resend(h: Hub, +link: String) -> IO(Hub):
  Far.retry.k(Far.out.of(Far.fh(h), link))

# Mirrors
# -------

def Far.in.of(p: FR.Fh & Hub, +link: String, +name: String) -> FR.In & Hub:
  (fh, h) = p
  (FR.Fh.in(fh, link, name), h)

def Far.in.put.k(p: FR.Fh & Hub, i: FR.In) -> Hub:
  (fh, h) = p
  Far.with(h, FR.Fh.in.set(fh, i))

def Far.in.put(h: Hub, i: FR.In) -> Hub:
  Far.in.put.k(Far.fh(h), i)

# every client hears a mirror's news
def Far.tell(h: Hub, +text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.broadcast(Hub{st, f, ls, cl, as, inbox, cfg, note}, FR.Fr.with.epoch(text,
        FR.In.epoch(FR.Fh.in(BN.Bn.far(Cfg.bn(cfg)), J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), "link", ""), ""))))

def Far.pull.go(busy: Bool, +fh: FR.Fh, h: Hub, +link: String, +since: Nat) -> IO(Hub):
  match busy h:
    case True{} _:
      IO.pure(Hub, Far.with(h, fh))
    case False{} Hub{+st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Far.pull.job(link, since, FR.In.epoch(FR.Fh.in(fh, link, link)), Cfg.home(cfg), Bot.peer.url(st, link), inbox))
        return Far.with(Hub{st, f, ls, cl, as, inbox, cfg, note}, FR.Fh.pull.on(fh, link))

def Far.pull.f(+fh: FR.Fh, h: Hub, +link: String, +since: Nat) -> IO(Hub):
  Far.pull.go(FR.Fh.pulling(fh, link), fh, h, link, since)

# a pull, unless one is out for the link
def Far.pull.p(p: FR.Fh & Hub, +link: String, +since: Nat) -> IO(Hub):
  (fh, h) = p
  Far.pull.f(fh, h, link, since)

def Far.pull(h: Hub, +link: String, +since: Nat) -> IO(Hub):
  Far.pull.p(Far.fh(h), link, since)

def Far.mirror.head.k(p: FR.Fh & Hub, +link: String) -> Nat & Hub:
  (+fh, h) = p
  (FR.In.head(FR.Fh.in(fh, link, link)), Far.with(h, fh))

def Far.mirror.head(h: Hub, +link: String) -> Nat & Hub:
  Far.mirror.head.k(Far.fh(h), link)

def Far.pull.here.k(r: Nat & Hub, +link: String) -> IO(Hub):
  (hd, h) = r
  Far.pull(h, link, hd)

# a pull from where the mirror is
def Far.pull.here(h: Hub, +link: String) -> IO(Hub):
  Far.pull.here.k(Far.mirror.head(h, link), link)

# Recognition must pull too: the other side's earlier hint may have
# arrived before this side recognized ownership and been refused. Pull
# even a healthy cached mirror, so a quick history replacement is found.
def Far.returned.go(ps: List<&2, BO.Peer>, h: Hub) -> IO(Hub):
  match ps:
    case Nil{}:
      IO.pure(Hub, h)
    case BO.Peer{+link, _, _, _, _} <> t:
      IO.bind(Hub, Hub, Far.pull.here(h, link), h2 => Far.returned.go(t, h2))

def Far.returned(h: Hub, +ps: List<&2, BO.Peer>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      IO.bind(Hub, Hub, Far.offer(Hub{st, f, ls, cl, as, inbox, cfg, note}, ps),
        h2 => Far.returned.go(Far.own.go(ps, cfg), h2))

def Far.store(h: Hub, +link: String, +text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        BN.Bf.dir(Far.dir(Cfg.home(cfg)))
        Far.keep.job(Far.file(Cfg.home(cfg), link), text)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Far.took.go(none: Bool, moved: Bool, h: Hub, +link: String, +from: Nat, +hd: Nat, +ys: List<&2, FR.Item>, +name: String) -> IO(Hub):
  match none moved:
    case True{} False{}:
      IO.pure(Hub, h)
    case True{} True{}:
      Far.tell(h, FR.Fr.msg(link, name, False{}, from, hd, Nil{}))
    case False{} _:
      IO.bind(Hub, Hub, Far.store(h, link, FR.Fr.file.batch(ys, hd)), h2 => Far.tell(h2, FR.Fr.msg(link, name, False{}, from, hd, ys)))

# a batch taken into the mirror: kept, told, and on a gap the rest pulled
def Far.took.k(g: FR.Got, +i: FR.In, h: Hub, +since: Nat, +to: Nat, +xs: List<&2, FR.Item>, +name: String, moved: Bool) -> IO(Hub):
  match g:
    case FR.Got{+_, +_, True{}}:
      Far.pull(Far.in.put(h, FR.In.name.set(i, name)), FR.In.link(i), FR.In.head(i))
    case FR.Got{+hd, ys, False{}}:
      Far.took.go(List.is_empty(&2, FR.Item, ys), moved, Far.in.put(h, FR.In.name.set(FR.In.put(i, since, to, xs), name)), FR.In.link(i), FR.In.head(i), hd, ys, name)

def Far.take.i(+i: FR.In, h: Hub, +since: Nat, +to: Nat, +xs: List<&2, FR.Item>, +name: String) -> IO(Hub):
  Far.took.k(FR.In.got(i, since, to, xs), i, h, since, to, xs, Bool.pick(String, String.is_empty(name), FR.In.name.of(i), name), FR.In.away(i))

def Far.take.p(r: FR.In & Hub, +since: Nat, +to: Nat, +xs: List<&2, FR.Item>, +name: String) -> IO(Hub):
  (i, h) = r
  Far.take.i(i, h, since, to, xs, name)

# a batch from a link (a push, or a page pulled)
def Far.take(h: Hub, +link: String, +since: Nat, +to: Nat, +xs: List<&2, FR.Item>, +name: String) -> IO(Hub):
  Far.take.p(Far.in.of(Far.fh(h), link, name), since, to, xs, name)

def Far.reset.put(+i: FR.In, h: Hub) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        BN.Bf.dir(Far.dir(Cfg.home(cfg)))
        ok : Bool <- BN.Bf.secret(Far.file(Cfg.home(cfg), FR.In.link(i)), J.Json.show(J.Json.obj([J.KV{"epoch", J.Str{FR.In.epoch(i)}}])) ++ "\n")
        Far.tell(Far.in.put(Hub{st, f, ls, cl, as, inbox, cfg, note}, i), FR.In.msg(i))

def Far.reset.k(reset: Bool, +i: FR.In, h: Hub, +epoch: String) -> IO(Hub):
  match reset:
    case True{}:
      Far.reset.put(FR.In.epoch.set(FR.In.new(FR.In.link(i), FR.In.name.of(i)), epoch), h)
    case False{}:
      IO.pure(Hub, h)

def Far.reset.in(r: FR.In & Hub, +epoch: String) -> IO(Hub):
  (+i, h) = r
  Far.reset.k(FR.Fr.epoch.changed(FR.In.epoch(i), epoch), i, h, epoch)

def Far.take.epoch(h: Hub, +link: String, +epoch: String, +since: Nat, +to: Nat, +xs: List<&2, FR.Item>, +name: String) -> IO(Hub):
  IO.bind(Hub, Hub, Far.reset.in(Far.in.of(Far.fh(h), link, name), epoch),
    h2 => Far.take(h2, link, since, to, xs, name))

def Far.away.go(was: Bool, +i: FR.In, h: Hub) -> IO(Hub):
  match was:
    case True{}:
      IO.pure(Hub, Far.in.put(h, i))
    case False{}:
      Far.tell(Far.in.put(h, FR.In.away.set(i, True{})), FR.Fr.msg(FR.In.link(i), FR.In.name.of(i), True{}, FR.In.head(i), FR.In.head(i), Nil{}))

def Far.away.i(+i: FR.In, h: Hub) -> IO(Hub):
  Far.away.go(FR.In.away(i), i, h)

# a link that does not answer: its mirror shows, away
def Far.away.p(r: FR.In & Hub) -> IO(Hub):
  (i, h) = r
  Far.away.i(i, h)

def Far.away(h: Hub, +link: String) -> IO(Hub):
  Far.away.p(Far.in.of(Far.fh(h), link, link))

def Far.feed.of(p: FR.Fh & Hub) -> Maybe<&2, List<&2, FR.Line>> & Hub:
  (+fh, h) = p
  (FR.Fh.feed(fh), Far.with(h, fh))

# the client a linked machine's request acts as: none (its answer goes
# back over HTTP, not to a client)
def Far.client() -> U32:
  4000000000

def Far.more(more: Bool, h: Hub, +link: String) -> IO(Hub):
  match more:
    case True{}:
      Far.pull.here(h, link)
    case False{}:
      IO.pure(Hub, h)

# Messages back from the jobs
# ---------------------------

def Far.page.k(ok: Bool, m: Maybe<&2, J.Json>, h: Hub, +link: String, +since: Nat) -> IO(Hub):
  match ok m:
    case True{} Some{+o}:
      IO.bind(Hub, Hub, Far.take.epoch(h, link, J.Json.get_str(o, "epoch", ""), J.Json.get_nat(o, "since", since), J.Json.get_nat(o, "head", since), FR.Fr.items.of(J.Json.elems(J.Json.get_obj(o, "items"))), ""),
        h2 => Far.more(J.Json.get_bool(o, "more", False{}), h2, link))
    case _ _:
      Far.away(h, link)

def Far.pull.done(p: FR.Fh & Hub, +link: String) -> Hub:
  (fh, h) = p
  Far.with(h, FR.Fh.pull.off(fh, link))

# a page came back (or the pull failed: the link is away until it answers)
def Far.retry.job(+link: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(2000)
    Far.send(inbox, FarRetry{link})

def Far.pulled.k(busy: Bool, h: Hub, +link: String, +since: Nat, +code: Nat, +body: String) -> IO(Hub):
  match busy h:
    case True{} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Far.retry.job(link, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case False{} _:
      Far.page.k(Nat.is_eq(code, 200n), J.Json.parse(body), h, link, since)

# a page came back (or the pull failed: the link is away until it answers;
# a hub still making its feed is asked again in a moment)
def Hub.far.pulled(h: Hub, +link: String, +since: Nat, +code: Nat, +body: String) -> IO(Hub):
  Far.pulled.k(Nat.is_eq(code, 503n), Far.pull.done(Far.fh(h), link), link, since, code, body)

# a request sent on for a client came back: its answer goes to the client
def Hub.far.replied(h: Hub, +client: U32, +id: String, +link: String, +code: Nat, +body: String) -> IO(Hub):
  Hub.push(h, client, Bool.pick(String, Nat.is_eq(code, 200n), FR.Fr.reply(Maybe.default(&2, J.Json, J.Json.parse(body), J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"ok", J.Flag{False{}}}, J.KV{"error", J.Str{"invalid reply from that machine"}}, J.KV{"id", J.Num{"0"}}])), id),
    J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{False{}}},
      J.KV{"error", J.Str{Bool.pick(String, Nat.is_eq(code, 0n), "that machine is away", "that machine did not take it: " ++ String.take(body, 120n))}}]))))

# (the feed leaves the history epoch alone: Far.start installed it, and
# the startup feed's "" would reset it)
def Far.fed.k(p: FR.Fh & Hub, ls: List<&2, FR.Line>, epoch: String) -> Hub:
  (fh, h) = p
  Far.with(h, FR.Fh.feed.ready(fh, ls))

def Hub.far.fed(h: Hub, ls: List<&2, FR.Line>, +epoch: String) -> IO(Hub):
  IO.pure(Hub, Far.fed.k(Far.fh(h), ls, epoch))

# a mirror read back from disk: shown (away) until its machine answers,
# then pulled from where it ends
def Far.loaded.put(+i: FR.In, h: Hub) -> IO(Hub):
  do IO<Hub>:
    h2 : Hub <- Far.tell(Far.in.put(h, i), FR.In.msg(i))
    Far.pull(h2, FR.In.link(i), FR.In.head(i))

def Far.loaded.choose(r: FR.In & Hub, disk: FR.In) -> IO(Hub):
  (live, h) = r
  Far.loaded.put(FR.In.loaded(live, disk), h)

def Hub.far.loaded(h: Hub, +link: String, +name: String, +text: String) -> IO(Hub):
  Far.loaded.choose(Far.in.of(Far.fh(h), link, name), FR.Fr.file.read(text, link, name))

# (one already online is pulled too, through the same coalesced pull: a
# lost last push is so repaired within the minute)
def Far.here.was.k(away: Bool, h: Hub, +link: String) -> IO(Hub):
  match away:
    case True{}:
      Far.pull.here(h, link)
    case False{}:
      Far.pull.here(h, link)

def Far.here.was(r: FR.In & Hub, +link: String) -> IO(Hub):
  (i, h) = r
  Far.here.was.k(FR.In.away(i), h, link)

# The minute: linked machines that answered pull what they lack (a mirror
# that was away, or none yet); those that did not are away
def Far.here.one(ok: Bool, h: Hub, +link: String) -> IO(Hub):
  match ok:
    case True{}:
      Far.here.was(Far.in.of(Far.fh(h), link, link), link)
    case False{}:
      Far.away(h, link)

def Far.here.go(ps: List<&2, BO.Peer>, h: Hub, +ok: List<&2, String>) -> IO(Hub):
  match ps:
    case Nil{}:
      IO.pure(Hub, h)
    case BO.Peer{+i, _, _, _, _} <> t:
      IO.bind(Hub, Hub, Far.here.one(FR.Fr.may.go(ok, i), h, i), h2 => Far.here.go(t, h2, ok))

def Far.live(ps: List<&2, BO.Peer>) -> List<&2, BO.Peer>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Far.keep(Bot.peer.live.k(p), p, Far.live(t))

def Hub.far.here(h: Hub, +answered: String) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Far.here.go(Far.live(BO.World.peers(M.State.bots(st))), Hub{st, f, ls, cl, as, inbox, cfg, note}, String.lines(answered))

# At start: this hub's feed is made off the hub; each link's mirror is
# read back from disk (then pulled)
def Far.start.go(ps: List<&2, BO.Peer>, +home: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case BO.Peer{+i, +n, _, _, _} <> t:
      do IO<Unit>:
        IO.spawn(Unit, Far.load.job(i, n, home, inbox))
        Far.start.go(t, home, inbox)

def Far.start.epoch(p: FR.Fh & Hub, +ls: List<&2, String>, +seq: Nat) -> Hub:
  (fh, h) = p
  Far.with(h, FR.Fh.epoch.set(fh, Far.history.at(ls, seq)))

def Far.start(h: Hub) -> IO(Hub):
  match h:
    case Hub{+st, f, +ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Far.feed.job(ls, st, inbox))
        Far.start.go(Far.live(BO.World.peers(M.State.bots(st))), Cfg.home(cfg), inbox)
        return Far.start.epoch(Far.fh(Hub{st, f, ls, cl, as, inbox, cfg, note}), ls, M.State.seq(st))

def Far.mirrors(+cfg: Cfg) -> List<&2, FR.In>:
  FR.Fh.ins(BN.Bn.far(Cfg.bn(cfg)))

def Hub.announce(r: Hub & List<&2, String>) -> IO(Hub):
  (h, fresh) = r
  match h fresh:
    case _ Nil{}:
      IO.pure(Hub, h)
    case Hub{st, f, +ls, cl, as, +inbox, +cfg, note} +l <> +t:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.changes(cl, Hub.changes_msg(List.reverse(&2, String, l <> t)), Nat.sub(List.length(&2, String, ls), List.length(&2, String, l <> t)),
          List.length(&2, FR.In, Far.mirrors(cfg)), inbox)
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

def Hub.spawned.fail(e: U32 & String, h: Hub, +thread: String) -> IO(Hub):
  (_, +msg) = e
  do IO<Hub>:
    +now : Nat <- Now.nat()
    Log.info("could not start agent: " ++ msg)
    r : Hub & List<&2, String> <- Hub.commit([M.ActivityLogged{thread, "spawn-" ++ Nat.show(now), "error", "spawn", "could not start claude: " ++ msg, now}, M.TurnChanged{thread, M.Failed{}, now}], h, Nil{})
    Hub.announce(r)

def Hub.spawned(r: Result<&1, &1, U32 & String, U32 & Socket>, h: Hub, +thread: String, +key: String, +gen: String) -> IO(Hub):
  match r h:
    case Done{started} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      Hub.spawned.ok(started, Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, key, gen)
    case Fail{e} _:
      Hub.spawned.fail(e, h, thread)

# A Claude process is started by a job of its own (its files and keys are
# read there, never on the hub's loop). The agent is registered first, with
# a placeholder: pid 0 (never signalled), the generation's run and the
# input channel the process's writer will read, so a line for the thread
# meanwhile waits in it. ClaudePid gives the pid (a stale generation's
# process is stopped), ClaudeFail ends the turn as a process that could
# not start does.
def Claude.fail(+thread: String, +gen: String, +msg: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, ClaudeFail{thread, gen, msg})
    return Unit{}

def Claude.duped(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, +thread: String, +gen: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  (rd0, res) = r
  match res:
    case Done{wr}:
      do IO<Unit>:
        IO.spawn(Unit, Agent.writer(Fuel.forever(), wr, input))
        ok : Bool <- Chan.send(Msg, inbox, ClaudePid{thread, pid, gen})
        rd : Socket <- IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Socket, H.Sock.dup(rd0), d => Agent.watch.start(d, pid, thread, gen, inbox))
        Agent.reader(Fuel.forever(), rd, U.Lines.new(), pid, thread, B.Tag.of(thread, pid), inbox)
    case Fail{_}:
      do IO<Unit>:
        Proc.kill(pid, 15)
        IO.spawn(Unit, Agent.end(rd0, pid, thread, inbox))
        Claude.fail(thread, gen, "its output could not be shared", inbox)

def Claude.started.ok(started: U32 & Socket, +thread: String, +gen: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  (+pid, s) = started
  IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Unit, H.Sock.dup(s), r => Claude.duped(r, pid, thread, gen, input, inbox))

def Claude.started.fail(e: U32 & String, +thread: String, +gen: String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, msg) = e
  Claude.fail(thread, gen, msg, inbox)

def Claude.started(r: Result<&1, &1, U32 & String, U32 & Socket>, +thread: String, +gen: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case Done{started}:
      Claude.started.ok(started, thread, gen, input, inbox)
    case Fail{e}:
      Claude.started.fail(e, thread, gen, inbox)

def Claude.job(+cfg: Cfg, +st: M.State, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, +effort: String, +gen: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +fs : K.Files <- K.Files.read(cwd)
    ok : Bool <- Chan.send(Msg, inbox, AutoView{thread, fs})
    +keys : String <- AKS.Ak.prompt(Cfg.home(cfg))
    +lim : String <- Ctn.limit(st)
    res : Result<&1, &1, U32 & String, U32 & Socket> <- Ctn.spawn(lim, thread, gen, "env", "MCP_TOOL_TIMEOUT=86400000" <> "CLAUDE_CODE_ENABLE_TODO_TOOLS=1" <> "claude" <> Hub.agent_args(cfg, thread, model, session, r, i, Hub.prompt(cfg, st, thread, cwd, fs, keys), effort, gen), cwd)
    Claude.started(res, thread, gen, input, inbox)

def Agents.pid.k(same: Bool, a: Agent, +pid: U32) -> Agent:
  match same a:
    case True{} Agent{t, i, _, k, rs}:
      Agent{t, i, pid, k, rs}
    case False{} _:
      a

# the thread's agent with its pid set
def Agents.pid(as: List<&2, Agent>, +th: String, +pid: U32) -> List<&2, Agent>:
  match as:
    case Nil{}:
      Nil{}
    case Agent{+t, i, p, k, rs} <> rest:
      Agents.pid.k(String.eq(t, th), Agent{t, i, p, k, rs}, pid) <> Agents.pid(rest, th, pid)

def Hub.claude_pid.k(cur: Bool, h: Hub, +thread: String, +pid: U32) -> IO(Hub):
  match cur h:
    case True{} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      IO.pure(Hub, Hub{st, f, ls, cl, Agents.pid(as, thread, pid), inbox, cfg, note})
    case False{} _:
      do IO<Hub>:
        Proc.kill(pid, 15)
        return h

# a Claude process started: the thread's only if its agent is still of
# its generation (B.Exit.current); any other is stopped at once
def Hub.claude_pid(h: Hub, +thread: String, +pid: U32, +gen: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.claude_pid.k(B.Exit.current(gen, Agents.gen(as, thread)), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, pid)

def Hub.claude_fail.k(cur: Bool, h: Hub, +thread: String, +msg: String) -> IO(Hub):
  match cur h:
    case True{} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.agent_stop(Agents.get(as, thread))
        Hub.spawned.fail((0, msg), Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}, thread)
    case False{} _:
      IO.pure(Hub, h)

def Hub.claude_fail(h: Hub, +thread: String, +gen: String, +msg: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.claude_fail.k(B.Exit.current(gen, Agents.gen(as, thread)), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, msg)

def Hub.start.spawn(m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, +effort: String, +gen: String) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, +as, +inbox, +cfg, note}:
      do IO<Hub>:
        Hub.agent_stop(m)
        +now : Nat <- Now.nat()
        +input : Chan(String) <- Chan.new(String, 256)
        IO.spawn(Unit, Claude.job(cfg, st, thread, cwd, model, session, r, i, effort, gen, input, inbox))
        return Hub{st, f, ls, cl, Agent{thread, input, 0, Agent.key(model, r, i, effort), [ARun.new.h(gen, now)]} <> Agents.drop(as, thread), inbox, cfg, note}

def Hub.start.r(r: Hub & List<&2, String>, m: Maybe<&2, Agent>, +thread: String, +cwd: String, +model: String, +session: String, +rt: M.RuntimeMode, +i: M.InteractionMode, +effort: String, +gen: String) -> IO(Hub):
  IO.bind(Hub, Hub, Hub.announce(r), h => Hub.start.spawn(m, h, thread, cwd, model, session, rt, i, effort, gen))

def Hub.start.go(same: Bool, +m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, +effort: String) -> IO(Hub):
  match same h:
    case True{} _:
      IO.pure(Hub, h)
    case False{} Hub{+st, f, ls, +cl, +as, inbox, +cfg, note}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        cr : Hub & List<&2, String> <- Hub.commit(Hub.replaced(Agent.is(m), st, now, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, Nil{})
        Hub.start.r(cr, m, thread, cwd, model, session, r, i, effort, Hub.gen(st, now))

def Hub.start.k(+m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, +effort: String) -> IO(Hub):
  Hub.start.go(Agent.same(m, Agent.key(model, r, i, effort)), m, h, thread, cwd, model, session, r, i, effort)

def Hub.autoview(h: Hub, +thread: String, fs: K.Files) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Hub.auto(cl, thread, fs)
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

# A user line naming `$skills` goes to the thread's agent through the same
# job as one with images (Media.claude, which scans the skills off the hub
# and answers AgentWrite): the command is taken now (Claude.prep), the ones
# after it wait behind it
def Line.skills.u(go: Bool, +o: J.Json, h: Hub, +thread: String, +line: String, +cwd: String) -> IO(Hub):
  match go h:
    case True{} Hub{st, f, ls, cl, +as, +inbox, cfg, note}:
      do IO<Hub>:
        +u : String = J.Json.get_str(o, "uuid", "")
        IO.spawn(Unit, Media.claude(inbox, thread, cwd, Mention.user_text(o), u, Agents.gen(as, thread)))
        return Claude.prep(True{}, Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, u)
    case False{} _:
      Claude.put(h, thread, line)

def Line.skills.k(m: Maybe<&2, J.Json>, h: Hub, +thread: String, +line: String, +cwd: String) -> IO(Hub):
  match m:
    case Some{+o}:
      Line.skills.u(Bool.and(String.eq(J.Json.get_str(o, "type", ""), "user"), Bool.not(String.is_empty(J.Json.get_str(o, "uuid", "")))), o, h, thread, line, cwd)
    case None{}:
      Claude.put(h, thread, line)

def Line.skills(has: Bool, h: Hub, +thread: String, +line: String, +cwd: String) -> IO(Hub):
  match has:
    case True{}:
      Line.skills.k(J.Json.parse(line), h, thread, line, cwd)
    case False{}:
      Claude.put(h, thread, line)

def Hub.out(h: Hub, o: B.Out) -> IO(Hub):
  match h o:
    case Hub{st, f, ls, cl, as, inbox, cfg, note} B.Send{+client, +text}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.to(cl, client, text)
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.Live{+thread, +text}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        cl2 : List<&2, Client> <- Wire.delta(cl, B.Delta.msg(thread, text))
        return Hub{st, f, ls, cl2, as, inbox, Live.with(cfg, LV.Live.add.at(Live.of(cfg), thread, text, Nat.mul(now, 1000n))), note}
    case Hub{st, f, ls, cl, as, inbox, cfg, note} B.Broadcast{+text}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Wire.all.of(cl, text, All{Bool.pick(Nat, String.starts_with(text, "{\"t\":\"delta"), 2n, 0n), 0n, 0n, Nil{}})
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, +as, inbox, cfg, note} B.AgentStart{+thread, +cwd, _, +model, +session, r, i}:
      Hub.start.k(Agents.get(as, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, cwd, model, session, r, i, Hub.effort_of(st, thread))
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note} B.AgentSend{+thread, +line}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        +l1 : String = Bot.line(Bool.or(BO.World.is_bot_thread(M.State.bots(st), thread), RF.Refs.maybe(line)), st, now, thread, line)
        +l2 : String <- EmbNote.claude(EmbNote.user(l1), cfg, st, thread, l1)
        Line.skills(String.contains(l2, "$"), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, l2, B.Hub.cwd(st, B.Hub.thread(st, thread)))
    case Hub{st, f, ls, cl, +as, inbox, cfg, note} B.AgentStop{+thread}:
      do IO<Hub>:
        Hub.agent_stop(Agents.get(as, thread))
        return Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.PlotInfo{+client, +id, +key, +at, +idx}:
      do IO<Hub>:
        Plot.put(Cfg.pv(cfg), PV.PInfo{client, id, key, at, idx})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.Watch{+client, +kind, +root, +path}:
      do IO<Hub>:
        Plot.put(Cfg.pv(cfg), Plot.watch(client, kind, root, path))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.CodexTurn{+thread, +cwd, +model, +session, r, text}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        +t2 : String = BH.Bots.turn(st, now, thread, text)
        +g : String = Hub.gen(st, now)
        IO.spawn(Unit, IO.bind(String, Unit, EmbNote.take(cfg, st, thread), n => Codex.go(cfg, st, thread, cwd, model, session, r, t2 ++ n, g, inbox)))
        Hub.placeholder(Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, g)
    case Hub{st, f, ls, cl, as, +inbox, +cfg, note} B.KiCadInstall{}:
      do IO<Hub>:
        IO.spawn(Unit, Install.go(Cfg.home(cfg), inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.GrokTurn{+thread, +cwd, +model, +session, r, +text}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        +t2 : String = BH.Bots.turn(st, now, thread, text)
        +g : String = Hub.gen(st, now)
        IO.spawn(Unit, IO.bind(String, Unit, EmbNote.take(cfg, st, thread), n => Grok.go(cfg, st, thread, cwd, model, session, r, t2 ++ n, g, inbox)))
        Hub.placeholder(Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, g)
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.Await{+thread, +id, +kind, +target, +ident, +deadline, +cwd}:
      do IO<Hub>:
        +lim : String <- Ctn.limit(st)
        IO.spawn(Unit, Watch.job(lim, Cfg.home(cfg), thread, id, kind, target, ident, deadline, cwd, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.WatchStop{_, +id, +kind, +target, +ident}:
      do IO<Hub>:
        IO.spawn(Unit, Watch.stop.job(Cfg.home(cfg), id, kind, target, ident))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, cfg, note} B.DeskLook{+client, +thread, +focused}:
      Hub.desk(Hub{st, f, ls, cl, as, inbox, cfg, note}, client, thread, focused)
    case Hub{+st, f, ls, +cl, as, +inbox, +cfg, note} B.TurnEnded{+thread, +state}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        +seen : Bool = DK.Desk.seen(Clients.looks(cl), thread, now)
        cl2 : List<&2, Client> <- Desk.tell(DK.Desk.to(Clients.looks(cl), thread, now), cl, st, thread, state)
        IO.spawn(Unit, Hub.phone(Cfg.home(cfg), st, thread, state, seen, inbox))
        Self.post(inbox, Release{})
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}
    # a bot's answer to a person elsewhere, captured by the step that left
    # its thread ready (hub.bend's Answer.out)
    case Hub{st, f, ls, cl, as, +inbox, cfg, note} B.BotReply{+thread, +to, +text, _}:
      do IO<Hub>:
        Self.post(inbox, Replied{thread, to, text})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, +inbox, cfg, note} B.Fs{+client, +id, +op, +path}:
      do IO<Hub>:
        IO.spawn(Unit, FsJob.run(op, inbox, client, id, path))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.TermOp{+op, +thread, +cwd, data, +cols, +rows}:
      do IO<Hub>:
        Term.put(Cfg.tm(cfg), Term.msg(op, thread, cwd, data, cols, rows))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.TermRun{key, ti, cwd, cmd, c, r, again}:
      do IO<Hub>:
        Term.put(Cfg.tm(cfg), TM.TRun{key, ti, cwd, cmd, c, r, again})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.TermSnap{c, key}:
      do IO<Hub>:
        Term.put(Cfg.tm(cfg), TM.TSnap{c, key})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.TermKill{key}:
      do IO<Hub>:
        Term.put(Cfg.tm(cfg), TM.TKill{key})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, +as, +inbox, +cfg, note} B.Git{+client, +id, +job, +thread, +cwd, +a, +b}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        Media.run(AG.Text.of(st), job, inbox, client, id, thread, cwd, Bot.attach(String.eq(job, "attach.claude"), st, now, thread, a), b, Cfg.home(cfg), Net.managed(Cfg.net(cfg)), Agents.gen(as, thread))
        return Claude.prep(Bool.and(String.eq(job, "attach.claude"), Bool.not(String.is_empty(b))), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, b)
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.AskAnswered{+ask, +answer}:
      do IO<Hub>:
        Park.put(Cfg.pk(cfg), PK.PAnswer{ask, answer})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.Upgrade{}:
      do IO<Hub>:
        IO.spawn(Unit, Upgrade.go(Net.managed(Cfg.net(cfg)), Cfg.home(cfg), M.Setting.get(st, "update.channel", "stable"), inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.BotFx{+kind, +a, +b, +c}:
      do IO<Hub>:
        Bot.fx(C.Codec.pos(["home", "gone", "hook", "unhook", "send", "invite", "join", "unpeer", "google", "token", "retoken", "untoken", "voice", "scratch", "scratch-gone"], kind), st, inbox, cfg, a, b, c)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.outs(os: List<&2, B.Out>, h: Hub) -> IO(Hub):
  match os:
    case Nil{}:
      IO.pure(Hub, h)
    case o <> t:
      IO.bind(Hub, Hub, Hub.out(h, o), h2 => Hub.outs(t, h2))

# the window in this process: every mirror, whole
def Far.join.here(ms: List<&2, FR.In>, m: Maybe<&2, Client>) -> IO(Maybe<&2, Client>):
  match ms:
    case Nil{}:
      IO.pure(Maybe<&2, Client>, m)
    case +i <> t:
      IO.bind(Maybe<&2, Client>, Maybe<&2, Client>, Wire.text.m(m, FR.In.msg(i)), m2 => Far.join.here(t, m2))

def Hub.join.notes(m: Maybe<&2, Client>, +note: String, +desk: String) -> IO(Maybe<&2, Client>):
  IO.bind(Maybe<&2, Client>, Maybe<&2, Client>, Wire.text.if(String.is_empty(note), m, note), m2 => Wire.text.if(String.is_empty(desk), m2, desk))

def Hub.join.state(c: Client, w: Wire) -> IO(Maybe<&2, Client>):
  Wire.offer(c, w, 0n)

# the window in this process: the read model (devices left out, as the
# wire leaves them) and the log message with no items
def Hub.join.here(h: Hub, +client: U32, +out: Chan(Wire), +gen: U32, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, +ls, +cl, as, inbox, +cfg, +note}:
      do IO<Hub>:
        m : Maybe<&2, Client> <- Hub.join.state(Client{client, out, DK.Look.none(), OB.Cr.new(gen, True{}, False{}, 0n), 0}, WState{M.State.private(st), Hub.log_msg.k(0n, ls, cfg, 0n)})
        m1 : Maybe<&2, Client> <- Far.join.here(Far.mirrors(cfg), m)
        m2 : Maybe<&2, Client> <- Wire.text.m(m1, LV.Live.msg(Live.of(cfg)))
        m3 : Maybe<&2, Client> <- Hub.join.notes(m2, note, Desk.join(DK.Desk.text(Clients.looks(cl), now)))
        return Hub{st, f, ls, Clients.add(m3, cl), as, inbox, cfg, note}

# a join in one frame is live at once: the streamed text follows it
def Hub.join.live(more: Bool, m: Maybe<&2, Client>, +cfg: Cfg) -> IO(Maybe<&2, Client>):
  match more:
    case True{}:
      IO.pure(Maybe<&2, Client>, m)
    case False{}:
      Wire.text.m(m, LV.Live.msg(Live.of(cfg)))

def Hub.join.more(more: Bool, +inbox: Chan(Msg), +client: U32, +gen: U32) -> IO(Unit):
  match more:
    case True{}:
      Self.post.later(inbox, JoinMore{client, gen})
    case False{}:
      IO.pure(Unit, Unit{})

def Hub.join.k(+n: Nat, +s0: Nat, +xs: List<&2, String>, h: Hub, +client: U32, +out: Chan(Wire), +origin: String, +gen: U32, +sock: U32, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, +ls, +cl, as, +inbox, +cfg, +note}:
      +k = List.length(&2, String, OB.Join.next(xs))
      +more = Bool.or(Nat.is_lt(Nat.add(s0, k), n), Bool.not(List.is_empty(&2, FR.In, Far.mirrors(cfg))))
      do IO<Hub>:
        m : Maybe<&2, Client> <- Wire.offer(Client{client, out, DK.Look.none(), OB.Cr.rest.set(OB.Cr.wait.set(OB.Cr.new(gen, U32.is_eq(client, 0), more, Nat.add(s0, k)), more), OB.Join.from(ls, n, Nat.add(s0, k))), sock},
          Hub.log_items(origin, cfg, s0, List.take(&2, String, xs, k), more), 0n)
        m1 : Maybe<&2, Client> <- Hub.join.live(more, m, cfg)
        m2 : Maybe<&2, Client> <- Hub.join.notes(m1, note, Desk.join(DK.Desk.text(Clients.looks(cl), now)))
        Hub.join.more(more, inbox, client, gen)
        return Hub{st, f, ls, Clients.add(m2, cl), as, inbox, cfg, note}

# a client joined: the log from what it has (`since`, if it came from this
# log), its first chunk now and the rest a chunk at a time (Hub.boot); the
# origin and the log's length are found once
def Hub.join(h: Hub, +client: U32, +out: Chan(Wire), +since: Nat, +origin: String, +gen: U32, +sock: U32, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, +ls, cl, as, inbox, cfg, note}:
      +n = List.length(&2, String, ls)
      +o = Hub.origin(ls)
      +s0 = Bool.pick(Nat, Bool.and(String.eq(origin, o), Nat.is_le(since, n)), since, 0n)
      Hub.join.k(n, s0, OB.Join.window(ls, n, s0), Hub{st, f, ls, cl, as, inbox, cfg, note}, client, out, o, gen, sock, now)

# Joining, a chunk at a time
# --------------------------
# While a client takes its log it gets no live changes (Wire.changes);
# each JoinMore (and each report from its writer) sends the next chunk if
# it has room (OB.Cr.room): the rest of the log, then each far mirror in
# chunks (FR.In.chunk), then a last frame with "boot": false that makes it
# live. Changes made meanwhile are part of the log by then, so nothing is
# missed or sent twice, and the hub's inbox is read between chunks.

def Clients.swap.k(same: Bool, c: Client, +m: Maybe<&2, Client>) -> Maybe<&2, Client>:
  match same:
    case True{}:
      m
    case False{}:
      Some{c}

# the client with this id replaced by m (dropped for None)
def Clients.swap(cs: List<&2, Client>, +id: U32, +m: Maybe<&2, Client>) -> List<&2, Client>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Clients.add(Clients.swap.k(Client.is(c, id), c, m), Clients.swap(t, id, m))

def Boot.due(c: Client, +gen: U32) -> Bool:
  match c:
    case Client{_, _, _, +r, _}:
      Bool.and(Bool.and(OB.Cr.boot(r), U32.is_eq(OB.Cr.gen(r), gen)), OB.Cr.room(r))

def Boot.cr(c: Client, +r: OB.Cr) -> Client:
  match c:
    case Client{i, o, l, _, k}:
      Client{i, o, l, r, k}

def Boot.r(c: Client) -> OB.Cr:
  match c:
    case Client{_, _, _, r, _}:
      r

def Boot.next(more: Bool, h: Hub, k: Hub -> IO(Hub)) -> IO(Hub):
  match more:
    case True{}:
      k(h)
    case False{}:
      IO.pure(Hub, h)

# the next JoinMore for a joining client, when it has room and none is
# on its way already: one at a time, so the hub sends one chunk per
# message it reads and anything else waits behind at most a few
def Kick.k(go: Bool, c: Client, +inbox: Chan(Msg)) -> IO(Client):
  match go c:
    case True{} Client{+i, o, l, +r, k}:
      do IO<Client>:
        Self.post.later(inbox, JoinMore{i, OB.Cr.gen(r)})
        return Client{i, o, l, OB.Cr.wait.set(r, True{}), k}
    case False{} _:
      IO.pure(Client, c)

def Kick.due(+r: OB.Cr) -> Bool:
  Bool.and(Bool.and(OB.Cr.boot(r), Bool.not(OB.Cr.wait(r))), OB.Cr.room(r))

def Kick.one(+c: Client, +id: U32, +inbox: Chan(Msg)) -> IO(Client):
  Kick.k(Bool.and(Client.is(c, id), Kick.due(Boot.r(c))), c, inbox)

def Kick.go(cs: List<&2, Client>, +id: U32, +inbox: Chan(Msg)) -> IO(List<&2, Client>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, Client>, Nil{})
    case +c <> t:
      do IO<List<&2, Client>>:
        c2 : Client <- Kick.one(c, id, inbox)
        t2 : List<&2, Client> <- Kick.go(t, id, inbox)
        return c2 <> t2

def Hub.kick(h: Hub, +id: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        cl2 : List<&2, Client> <- Kick.go(cl, id, inbox)
        return Hub{st, f, ls, cl2, as, inbox, cfg, note}

# a chunk out, then the next one asked for (Hub.kick)
def Boot.send(h: Hub, c: Client, w: Wire, +n: Nat, +id: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        m : Maybe<&2, Client> <- Wire.offer(c, w, n)
        Hub.kick(Hub{st, f, ls, Clients.swap(cl, id, m), as, inbox, cfg, note}, id)

def Boot.text(+text: String) -> Wire:
  WText{text}

# the last frame of a join (or a catch-up), then every thread's streamed
# text so far, which replaces the client's (core/live.bend)
def Boot.last(h: Hub, c: Client, +id: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        m : Maybe<&2, Client> <- Wire.offer(c, Boot.text(Hub.boot_msg(Nil{}, True{})), 0n)
        m2 : Maybe<&2, Client> <- Wire.text.m(m, LV.Live.msg(Live.of(cfg)))
        return Hub{st, f, ls, Clients.swap(cl, id, m2), as, inbox, cfg, note}

def Boot.far.c(fc: FR.FC, h: Hub, +c: Client, +id: U32) -> IO(Hub):
  match fc:
    case FR.FC{+text, +next, True{}}:
      Boot.send(h, Boot.cr(c, OB.Cr.far.set(Boot.r(c), 1n+OB.Cr.fl(Boot.r(c)), 0n)), Boot.text(text), String.length(text), id)
    case FR.FC{+text, +next, False{}}:
      Boot.send(h, Boot.cr(c, OB.Cr.far.set(Boot.r(c), OB.Cr.fl(Boot.r(c)), next)), Boot.text(text), String.length(text), id)

# the log is all out, then the far mirrors; the last frame makes it live
def Boot.far.k(m: Maybe<&2, FR.In>, h: Hub, +c: Client, +id: U32) -> IO(Hub):
  match m:
    case Some{+i}:
      Boot.far.c(FR.In.chunk(i, OB.Cr.fseq(Boot.r(c))), h, c, id)
    case None{}:
      Boot.last(h, Boot.cr(c, OB.Cr.live(Boot.r(c))), id)

# what the next chunk comes from: what was left when the client joined
# (or caught up), else the changes made since
def Boot.src(rs: List<&2, String>, +ls: List<&2, String>, +n: Nat, +at: Nat) -> List<&2, String>:
  match rs:
    case Nil{}:
      OB.Join.window(ls, n, at)
    case +x <> t:
      x <> t

def Boot.go(log: Bool, +c: Client, h: Hub, +n: Nat, +id: U32) -> IO(Hub):
  match log h:
    case True{} Hub{st, f, +ls, cl, as, inbox, cfg, note}:
      +xs = Boot.src(OB.Cr.rest(Boot.r(c)), ls, n, OB.Cr.at(Boot.r(c)))
      +ch = OB.Join.next(xs)
      Boot.send(Hub{st, f, ls, cl, as, inbox, cfg, note},
        Boot.cr(c, OB.Cr.rest.set(OB.Cr.at.set(Boot.r(c), Nat.add(OB.Cr.at(Boot.r(c)), List.length(&2, String, ch))), List.drop(&2, String, xs, List.length(&2, String, ch)))),
        Hub.boot_items(ch), 0n, id)
    case False{} Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Boot.far.k(List.get(&2, FR.In, Far.mirrors(cfg), OB.Cr.fl(Boot.r(c))), Hub{st, f, ls, cl, as, inbox, cfg, note}, c, id)

def Boot.k(due: Bool, +c: Client, h: Hub, +id: U32) -> IO(Hub):
  match due h:
    case True{} Hub{st, f, +ls, cl, as, inbox, cfg, note}:
      Boot.go(Nat.is_lt(OB.Cr.at(Boot.r(c)), List.length(&2, String, ls)), c, Hub{st, f, ls, cl, as, inbox, cfg, note}, List.length(&2, String, ls), id)
    case False{} _:
      IO.pure(Hub, h)

def Boot.m(m: Maybe<&2, Client>, h: Hub, +id: U32, +gen: U32) -> IO(Hub):
  match m:
    case Some{+c}:
      Boot.k(Boot.due(c, gen), c, h, id)
    case None{}:
      IO.pure(Hub, h)

def Boot.unwait.k(same: Bool, c: Client) -> Client:
  match same c:
    case True{} Client{i, o, l, r, k}:
      Client{i, o, l, OB.Cr.wait.set(r, False{}), k}
    case False{} _:
      c

def Boot.unwait(cs: List<&2, Client>, +id: U32, +gen: U32) -> List<&2, Client>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Boot.unwait.k(Bool.and(Client.is(c, id), U32.is_eq(OB.Cr.gen(Boot.r(c)), gen)), c) <> Boot.unwait(t, id, gen)

def Hub.boot.c(h: Hub, +client: U32, +gen: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      Boot.m(Clients.get(cl, client), Hub{st, f, ls, cl, as, inbox, cfg, note}, client, gen)

# a JoinMore: the next chunk of a joining client's log, if it still joins
# under this generation and has room; then the one after is asked for
def Hub.boot(h: Hub, +client: U32, +gen: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      Hub.boot.c(Hub{st, f, ls, Boot.unwait(cl, client, gen), as, inbox, cfg, note}, client, gen)

# a writer's report: the client's credit, then its next chunk asked for
# if it joins (Hub.kick)
def Hub.drained(h: Hub, +client: U32, +gen: U32, +n: Nat, +b: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, cfg, note}:
      Hub.kick(Hub{st, f, ls, Clients.cr(cl, client, gen, n, b), as, inbox, cfg, note}, client)

def Far.rpc.may(ok: Bool, h: Hub, +client: U32, +id: String, +link: String, +body: String, +now: Nat) -> IO(Hub):
  match ok h:
    case True{} Hub{+st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Far.rpc.job(client, id, link, body, Cfg.home(cfg), Bot.peer.url(st, link), inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case False{} _:
      Hub.far.replied(h, client, id, link, 403n, "that is done on its own machine")

def Hub.announce.far(r: Hub & List<&2, String>, cs: List<&2, M.Change>, +from: Nat) -> IO(Hub):
  (h, +fresh) = r
  IO.bind(Hub, Hub, Hub.announce((h, fresh)), h2 => Far.push(h2, cs, fresh, from))

def Hub.write_fail.note(+err: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"update"}}, J.KV{"error", J.Str{"log write failed: " ++ err}}]))

def Hub.step.wrote(r: Hub & Wrote, +cs: List<&2, M.Change>, os: List<&2, B.Out>, +from: Nat) -> IO(Hub & Bool):
  (h, w) = r
  match w:
    case Wrote{+fresh, True{}, _}:
      do IO<Hub & Bool>:
        h1 : Hub <- Hub.busy.set(h)
        h2 : Hub <- Hub.announce.far((h1, fresh), cs, from)
        h3 : Hub <- Hub.outs(os, h2)
        return (h3, True{})
    case Wrote{_, False{}, +err}:
      do IO<Hub & Bool>:
        PS.Log.error("hub", "log write failed: " ++ err)
        PS.Perf.add("hub.write_fail", 1)
        h2 : Hub <- Hub.note(h, Hub.write_fail.note(err))
        return (h2, False{})

def Hub.step.go(+st: M.State, h: Hub, cs: List<&2, M.Change>, os: List<&2, B.Out>) -> IO(Hub & Bool):
  do IO<Hub & Bool>:
    +cs2 : List<&2, M.Change> = B.Pend.fix(st, cs)
    r : Hub & Wrote <- Hub.commit.w(cs2, h)
    Hub.step.wrote(r, cs2, os, M.State.seq(st))

def Hub.step.k(p: M.State & Hub, cs: List<&2, M.Change>, os: List<&2, B.Out>) -> IO(Hub & Bool):
  (st, h) = p
  Hub.step.go(st, h, cs, os)

# a step's changes are stored (with the pending counts they move), then
# its effects run; answers whether it was stored
def Hub.step.ok(h: Hub, s: B.Step) -> IO(Hub & Bool):
  match s:
    case B.Step{cs, os}:
      Hub.step.k(Hub.state(h), cs, os)

def Hub.step.drop(r: Hub & Bool) -> Hub:
  (h, _) = r
  h

def Hub.step(h: Hub, s: B.Step) -> IO(Hub):
  IO.bind(Hub & Bool, Hub, Hub.step.ok(h, s), r => IO.pure(Hub, Hub.step.drop(r)))

def Hub.rpc.k(p: M.State & Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  (st, h) = p
  Hub.step(h, Bot.request(J.Json.parse(text), st, now, client, text))

def Hub.rpc.here(h: Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  Hub.rpc.k(Hub.state(h), client, text, now)

# A client's request about something elsewhere goes to its machine; any
# other stays here
def Far.rpc.go(m: Maybe<&2, FR.Route>, h: Hub, +client: U32, +o: J.Json, +text: String, +now: Nat) -> IO(Hub):
  match m h:
    case Some{FR.Route{+link, +meth, +body}} Hub{+st, f, ls, cl, as, +inbox, +cfg, note}:
      Far.rpc.may(FR.Fr.may(meth), Hub{st, f, ls, cl, as, inbox, cfg, note}, client, J.Json.as_raw(J.Json.get(o, "id"), "0"), link, body, now)
    case None{} _:
      Hub.rpc.here(h, client, text, now)

def Hub.rpc.o(m: Maybe<&2, J.Json>, h: Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  match m:
    case Some{+o}:
      Far.rpc.go(FR.Fr.route(o), h, client, o, text, now)
    case None{}:
      Hub.rpc.here(h, client, text, now)

# a request about something on a linked machine goes there (Far.rpc.go)
def Hub.rpc.far(maybe: Bool, h: Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  match maybe:
    case True{}:
      Hub.rpc.o(J.Json.parse(text), h, client, text, now)
    case False{}:
      Hub.rpc.here(h, client, text, now)

def Hub.rpc(h: Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  Hub.rpc.far(String.contains(text, "~"), h, client, text, now)

def Hub.line.k(p: M.State & Hub, +thread: String, +line: String, +now: Nat) -> IO(Hub):
  (st, h) = p
  Hub.step(h, B.Hub.agent_line(st, now, thread, line))

# a progress line: the ledger sees it, and it is written only once in
# B.Prog.gap() seconds with the held ones (B.Prog.line); a line held lands
# on the beat (Hub.beat)
def Hub.line.prog.k(p: B.PStep, +r: ARun, h: Hub, +thread: String, +o: J.Json, +now: Nat) -> IO(Hub):
  match p h:
    case B.PStep{+at, +pend, +flush} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, Agents.with(as, thread, ARun.prog.set(ARun.heard.set(ARun.put(r, CM.Cmds.see(ARun.cmds(r), o), ARun.held(r)), now), at, pend)), inbox, cfg, note},
        B.Prog.flush(st, thread, now, flush))

def Hub.line.prog(+r: ARun, h: Hub, +thread: String, +line: String, +o: J.Json, +now: Nat) -> IO(Hub):
  Hub.line.prog.k(B.Prog.line(ARun.prog_at(r), ARun.prog_last(r), now, line, o), r, h, thread, o, now)

# a Claude line judged by its process's ledger, which sees it before the
# step runs (the step may send the next command)
def Hub.line.run.k(prog: Bool, +r: ARun, h: Hub, +thread: String, +line: String, +o: J.Json, +now: Nat) -> IO(Hub):
  match prog h:
    case True{} _:
      Hub.line.prog(r, h, thread, line, o, now)
    case False{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, Agents.with(as, thread, ARun.heard.set(ARun.put(r, CM.Cmds.see(ARun.cmds(r), o), ARun.held(r)), now)), inbox, cfg, note},
        B.Hub.agent_line.vo(CM.Cmds.verdict(ARun.cmds(r), B.Hub.running(B.Hub.thread(st, thread)), o), st, now, thread, line, o, CM.Cmds.text(ARun.cmds(r), o)))

def Hub.line.run(+r: ARun, h: Hub, +thread: String, +line: String, +o: J.Json, +now: Nat) -> IO(Hub):
  Hub.line.run.k(B.Prog.is(o), r, h, thread, line, o, now)

def Hub.line.m(m: Maybe<&2, ARun>, h: Hub, +thread: String, +line: String, +now: Nat) -> IO(Hub):
  match m:
    case Some{+r}:
      Hub.line.run(r, h, thread, line, Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{}), now)
    case None{}:
      Hub.line.k(Hub.state(h), thread, line, now)

def Hub.line(h: Hub, +thread: String, +line: String, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.line.m(Agents.run(as, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, line, now)

def Hub.gone.k(current: Bool, h: Hub, +thread: String, +code: U32, +now: Nat) -> IO(Hub):
  match current h:
    case True{} Hub{+st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        +why : String <- Ctn.why(CN.Contain.ask(code), st, thread, Agents.gen(as, thread), code)
        Hub.step(Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}, B.Hub.agent_gone.why(st, now, thread, code, why))
    case False{} _:
      IO.pure(Hub, h)

# a process exited; one already replaced (a restart for a new model or
# mode) is old news
def Hub.gone(h: Hub, +thread: String, +code: U32, +pid: U32, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.gone.k(Agent.pid_is(Agents.get(as, thread), pid), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, code, now)

# each minute the hub's size goes into the gauges
def Hub.tick(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, +ls, +cl0, +as, +inbox, cfg, note}:
      do IO<Hub>:
        +cl : List<&2, Client> <- Desk.say(DK.Desk.text(Clients.looks(cl0), Nat.sub(now, 60n)), cl0, now)
        PS.Perf.set("hub.clients", U32.from_nat(List.length(&2, Client, cl)))
        PS.Perf.set("hub.agents", U32.from_nat(List.length(&2, Agent, as)))
        PS.Perf.set("hub.changes", U32.from_nat(List.length(&2, String, ls)))
        PS.Perf.set("hub.busy", U32.from_nat(M.Work.threads(st)))
        Self.post(inbox, Release{})
        Self.post(inbox, Silence{})
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Hub.tick(st, now))

# a tool call's answer goes once its step is stored: a call whose changes
# could not be written is told so, never that it worked
def Hub.mcp.fail(+body: String) -> String:
  MC.Mcp.error(Maybe.default(&2, J.Json, J.Json.get(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), "id"), J.Null{}), "-32000", "Backplane could not record this (the log write failed); nothing was done")

def Hub.mcp.after(r: Hub & Bool, +park: String, +body: String, +text: String, +reply: Chan(String)) -> IO(Hub):
  (h, ok) = r
  match h ok:
    case Hub{hs, f, ls, cl, as, inbox, +cfg, note} True{}:
      do IO<Hub>:
        Hub.mcp.send(Bool.not(String.is_empty(park)), park, body, text, reply, cfg)
        return Hub{hs, f, ls, cl, as, inbox, cfg, note}
    case Hub{hs, f, ls, cl, as, inbox, +cfg, note} False{}:
      do IO<Hub>:
        Hub.mcp.send(False{}, "", body, Hub.mcp.fail(body), reply, cfg)
        return Hub{hs, f, ls, cl, as, inbox, cfg, note}

def Hub.mcp.k(o: MC.McpOut, h: Hub, +reply: Chan(String), +body: String) -> IO(Hub):
  match o:
    case MC.McpOut{+text, st, +park}:
      IO.bind(Hub & Bool, Hub, Hub.step.ok(h, st), r => Hub.mcp.after(r, park, body, text, reply))

def Hub.mcp.hub(h: Hub, +thread: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.mcp.k(BH.Bots.mcp(st, now, thread, Maybe.default(&2, J.Json, J.Json.parse(Cfg.models(cfg)), J.Null{}), Cfg.version(cfg),
          Maybe.default(&2, J.Json, J.Json.parse(BN.Bn.dir(Cfg.bn(cfg))), J.Json.arr(Nil{})), GG.Google.tool_defs(), body),
        Hub{st, f, ls, cl, as, inbox, cfg, note}, reply, body)

# the approved folder, resolved: added (or found) and the tool answered
def Hub.newproj.made(h: Hub, +root: String, +name: String, +id: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.mcp.k(MC.Mcp.reply(Maybe.default(&2, J.Json, J.Json.parse(id), J.Null{}), BH.Bots.newproj.made(st, now, root, name)),
        Hub{st, f, ls, cl, as, inbox, cfg, note}, reply, "")

def Hub.mcp.w(secs: Nat, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match secs h:
    case 0n _:
      Hub.mcp.hub(h, thread, body, reply, now)
    case 1n+k Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Wait.loop(1n+k, thread, MC.Wait.now(o), reply, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# a line from an agent: a turn process's only while it is the one the hub
# runs for its thread (B.Tag.heard)
def Hub.tagged.k(heard: Bool, h: Hub, +thread: String, line: String, +now: Nat) -> IO(Hub):
  match heard:
    case True{}:
      Hub.line(h, thread, line, now)
    case False{}:
      IO.pure(Hub, h)

def Hub.tagged(h: Hub, +tag: String, line: String, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.tagged.k(B.Tag.heard(B.Tag.pid(tag), Agent.pid_of(Agents.get(as, B.Tag.thread(tag)))), Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Tag.thread(tag), line, now)

# then turns the restart cut short carry on (B.Hub.carry)
def Hub.recover.carry(h: Hub, +before: M.State, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Hub.carry(before, st, now))

def Hub.recover.go(h: Hub, st: B.Step, before: M.State, +now: Nat) -> IO(Hub):
  IO.bind(Hub, Hub, Hub.step(h, st), h2 => Hub.recover.carry(h2, before, now))

# (and the Scratch project is made the first time, M.Scratch.ensure)
def Hub.recover.k(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.recover.go(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Step.before(M.Scratch.ensure(st, Cfg.home(cfg) ++ "/scratch", now), Nil{}, B.Hub.recover(st, now)), st, now)

# (and threads elsewhere start: Far.start)
def Hub.recover(h: Hub, +now: Nat) -> IO(Hub):
  IO.bind(Hub, Hub, Far.start(h), h2 => Hub.recover.k(h2, now))

# The minute
# ----------

# Each worker publishes as soon as its peer answers. The hub owns slots;
# no worker reads or replaces a snapshot of another worker's result.
def Bot.dir.job(+peer: String, +url: String, +pname: String, +home: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +now : Nat <- Now.nat()
    r : BN.Resp <- BN.Bn.dir.fetch(home, url, peer, now)
    seen : Nat <- Now.nat()
    ok : Bool <- Chan.send(Msg, inbox, BotsFound{peer, url, BN.Bn.fetched(r, peer, pname, seen)})
    return Unit{}

def Bot.dir.launch(ids: List<&2, String>, +st: M.State, +cfg: Cfg, +inbox: Chan(Msg)) -> IO(Unit):
  match ids:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case +i <> t:
      do IO<Unit>:
        IO.spawn(Unit, Bot.dir.job(i, Bot.peer.url(st, i), Bot.peer.name(st, i), Cfg.home(cfg), inbox))
        Bot.dir.launch(t, st, cfg, inbox)

def Hub.dir.plan(h: Hub, +plan: BH.DirPlan) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        Bot.dir.launch(BH.DirPlan.launch(plan), st, cfg, inbox)
        return Hub{st, f, ls, cl, as, inbox, Cfg.with_bn(cfg, BN.Bn.with_work(Cfg.bn(cfg), BH.DirPlan.work(plan))), note}

def Hub.dir.queue(h: Hub, ps: List<&2, BO.Peer>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.dir.plan(Hub{st, f, ls, cl, as, inbox, cfg, note}, BH.DirWork.plan(BH.DirWork.queue(ps, BN.Bn.work(Cfg.bn(cfg)))))

def Hub.bots_found.k(same: Bool, h: Hub, +d: String) -> IO(Hub):
  match same h:
    case True{} _:
      IO.pure(Hub, h)
    case False{} Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        BN.Bn.cache.save(Cfg.home(cfg), d)
        Hub.models.k(Hub{st, f, ls, cl, as, inbox, Cfg.with_bn(cfg, BN.Bn.with_dir(Cfg.bn(cfg), d)), note})

# Compare with the current directory, never the worker's starting copy.
def Hub.dir.publish(h: Hub, +d: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.bots_found.k(String.eq(BN.Bn.dir(Cfg.bn(cfg)), d), Hub{st, f, ls, cl, as, inbox, cfg, note}, d)

# Only the result of a still-linked peer at the same URL is accepted.
# Always release its slot, including for failures and revoked links.
def Hub.bots_found(h: Hub, +peer: String, +url: String, +result: Maybe<&2, List<&2, J.Json>>) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        +prev : List<&2, J.Json> = J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(BN.Bn.dir(Cfg.bn(cfg))), J.Null{}))
        +rows : List<&2, J.Json> = BH.Dir.accept(Bool.and(Bot.peer.live(st, peer), String.eq(Bot.peer.url(st, peer), url)), result, prev, peer)
        h2 : Hub <- Hub.dir.publish(Hub{st, f, ls, cl, as, inbox,
          Cfg.with_bn(cfg, BN.Bn.with_work(Cfg.bn(cfg), BH.DirWork.finish(BN.Bn.work(Cfg.bn(cfg)), peer))), note},
          J.Json.show(J.Json.arr(BH.Dir.linked(rows, BO.World.peers(M.State.bots(st))))))
        h3 : Hub <- Far.here.one(Bool.and(Bool.and(Bot.peer.live(st, peer), String.eq(Bot.peer.url(st, peer), url)), Maybe.is_some(&2, List<&2, J.Json>, result)), h2, peer)
        Hub.dir.queue(h3, Nil{})

# Link changes prune the cache too, so revoked peers stay gone on restart.
def Hub.dir.refresh(h: Hub, +peer: String) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        +ps : List<&2, BO.Peer> = BO.World.peers(M.State.bots(st))
        h2 : Hub <- Hub.dir.publish(Hub{st, f, ls, cl, as, inbox, cfg, note}, J.Json.show(J.Json.arr(BH.Dir.linked(
          J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(BN.Bn.dir(Cfg.bn(cfg))), J.Null{})), ps))))
        Hub.dir.queue(h2, BH.Dir.request(ps, peer))

# Routines keep their minute cadence; the ticker's first message also
# refreshes directories immediately after the hub/window has opened.
def Hub.bot_tick(h: Hub, +tz: String, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        h2 : Hub <- Hub.dir.refresh(Hub{st, f, ls, cl, as, inbox, cfg, note}, "")
        Hub.step(h2, BH.Bots.tick(st, now, BH.Tz{M.Snooze.tz.secs(tz), M.Snooze.tz.east(tz)}))

# Discovery and signed inbound traffic are return signals. Fetch just the
# returning peer, and never bounce every successful directory request.
def Bot.dir.machines(n: Net) -> String:
  match n:
    case Net{_, _, _, _, _, _, _, _, _, mc, _, _, _, _, _}:
      mc

def Hub.dir.returned(h: Hub, +mc: String) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        h2 : Hub <- Hub.machines(Hub{st, f, ls, cl, as, inbox, cfg, note}, mc)
        +returned : List<&2, BO.Peer> = BH.Dir.returned(BO.World.peers(M.State.bots(st)),
          J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(Bot.dir.machines(Cfg.net(cfg))), J.Null{}), "peers")),
          J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(mc), J.Null{}), "peers")))
        h3 : Hub <- Hub.dir.queue(h2, returned)
        Far.returned(h3, returned)

def Bot.dir.awake(refresh: Bool, +inbox: Chan(Msg), +peer: String) -> IO(Unit):
  match refresh:
    case True{}:
      Self.post(inbox, BotsRefresh{peer})
    case False{}:
      IO.pure(Unit, Unit{})

# Requests from outside
# ---------------------
# A webhook (POST /hook/<id>) or a linked machine (POST /bots/deliver,
# POST /bots/link, GET /bots/dir) is checked off the hub: its secret read,
# its signature compared (Sign.check: fresh, constant time). Back on the
# hub the replay cache accepts its key once, and only then does anything
# change. A bot's screen (GET /bots/<id>/screen.jpg) and Google's redirect
# (GET /oauth/google) come from clients the server already lets in.

def Bot.cap() -> Nat:
  262144n

# a form may carry a recording (a Pebble ring's voice note, M4A): 2 MB,
# a few minutes of it
def Bot.cap.form() -> Nat:
  2097152n

def Bot.cap.of(+ct: String) -> Nat:
  Bool.pick(Nat, RG.Ring.is_form(ct), Bot.cap.form(), Bot.cap())

def Bot.answer(+reply: Chan(List<&2, U32>), bs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(List<&2, U32>, reply, bs)
    return Unit{}

def Hub.answer(h: Hub, +reply: Chan(List<&2, U32>), bs: List<&2, U32>) -> IO(Hub):
  do IO<Hub>:
    Bot.answer(reply, bs)
    return h

def Bot.json(+status: String, +text: String) -> List<&2, U32>:
  W.Http.response(status, "application/json", U.Utf8.encode(text), "")

# The requests between hubs
# -------------------------

# POST /far/push: a batch from a linked machine (the owner's own)
# A push from another history is only a resync hint. Ask the owner for
# its current epoch instead of trusting a potentially late old push.
def Far.push.receive.k(changed: Bool, h: Hub, +link: String, +since: Nat, +head: Nat, +xs: List<&2, FR.Item>, +name: String) -> IO(Hub):
  match changed:
    case True{}:
      Far.pull.here(h, link)
    case False{}:
      Far.take(h, link, since, head, xs, name)

def Far.push.receive(r: FR.In & Hub, +epoch: String, +since: Nat, +head: Nat, +xs: List<&2, FR.Item>, +name: String) -> IO(Hub):
  (+i, h) = r
  Far.push.receive.k(FR.Fr.epoch.changed(FR.In.epoch(i), epoch), h, FR.In.link(i), since, head, xs, name)

def Hub.far.push.in(ok: Bool, m: Maybe<&2, J.Json>, h: Hub, +peer: String, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  match ok m:
    case True{} Some{+o}:
      do IO<Hub>:
        Bot.answer(reply, Bot.json("200 OK", "{\"ok\":true}"))
        Far.push.receive(Far.in.of(Far.fh(h), peer, BN.Bn.clean(J.Json.get_str(o, "name", ""))), J.Json.get_str(o, "epoch", ""), J.Json.get_nat(o, "since", 0n), J.Json.get_nat(o, "head", 0n), FR.Fr.items.of(J.Json.elems(J.Json.get_obj(o, "items"))),
          BN.Bn.clean(J.Json.get_str(o, "name", "")))
    case True{} None{}:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "not JSON"))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("403 Forbidden", "threads are shared with the owner's own machines"))

def Far.log.go(m: Maybe<&2, List<&2, FR.Line>>, h: Hub, +since: Nat, +epoch: String, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  match m h:
    case Some{+fs} Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      +own = FR.Fh.epoch(BN.Bn.far(Cfg.bn(cfg)))
      +from = Bool.pick(Nat, FR.Fr.epoch.changed(epoch, own), 0n, since)
      Hub.answer(Hub{st, f, ls, cl, as, inbox, cfg, note}, reply, Bot.json("200 OK", J.Json.show(J.Obj{J.Field{"since", J.Json.nat(from),
        FR.Fr.epoch.fields(Maybe.default(&2, J.Json, J.Json.parse(FR.Fr.with.epoch(FR.Page.json(FR.Fr.page(fs, from, M.State.seq(st), 400000n)), own)), J.Null{}))}})))
    case None{} _:
      Hub.answer(h, reply, W.Http.text("503 Service Unavailable", "not ready"))

def Far.log.k(r: Maybe<&2, List<&2, FR.Line>> & Hub, +since: Nat, +epoch: String, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  (m, h) = r
  Far.log.go(m, h, since, epoch, reply)

# POST /far/log: a page of what this hub shares after `since`
def Hub.far.log(ok: Bool, m: Maybe<&2, J.Json>, h: Hub, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  match ok m:
    case True{} Some{+o}:
      Far.log.k(Far.feed.of(Far.fh(h)), J.Json.get_nat(o, "since", 0n), J.Json.get_str(o, "epoch", ""), reply)
    case True{} None{}:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "not JSON"))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("403 Forbidden", "threads are shared with the owner's own machines"))

# Extract the actual decider reply before sending the step's effects.
def Far.rpc.reply(os: List<&2, B.Out>) -> String:
  match os:
    case Nil{}:
      "{\"t\":\"reply\",\"id\":0,\"ok\":false,\"error\":\"no reply from owning hub\"}"
    case B.Send{_, text} <> _:
      text
    case _ <> t:
      Far.rpc.reply(t)

def Hub.far.rpc.step(step: B.Step, h: Hub, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  match step:
    case B.Step{cs, +os}:
      do IO<Hub>:
        h2 : Hub <- Hub.step(h, B.Step{cs, os})
        Hub.answer(h2, reply, Bot.json("200 OK", Far.rpc.reply(os)))

def Hub.far.rpc.k(may: Bool, h: Hub, +o: J.Json, +text: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match may h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.far.rpc.step(Bot.request(Some{o}, st, now, Far.client(), text), Hub{st, f, ls, cl, as, inbox, cfg, note}, reply)
    case False{} _:
      Hub.answer(h, reply, W.Http.text("403 Forbidden", "not something this machine shares"))

# POST /far/rpc: a request about one of this hub's shared threads (Fr.allowed)
def Hub.far.rpc(ok: Bool, m: Maybe<&2, J.Json>, h: Hub, +text: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match ok m h:
    case True{} Some{+o} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.far.rpc.k(FR.Fr.allowed(st, o), Hub{st, f, ls, cl, as, inbox, cfg, note}, o, text, reply, now)
    case True{} None{} _:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "not JSON"))
    case False{} _ _:
      Hub.answer(h, reply, W.Http.text("403 Forbidden", "threads are shared with the owner's own machines"))

def Bot.shot.sent(bs: List<&2, U32>, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  match bs:
    case Nil{}:
      Bot.answer(reply, W.Http.text("404 Not Found", "no screen yet"))
    case b <> t:
      Bot.answer(reply, W.Http.response.c("200 OK", "image/jpeg", b <> t, "no-store", ""))

# a bot's newest browser frame, as the helper wrote it
def Bot.shot(+home: String, +bot: String, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(bot), Bot.answer(reply, W.Http.text("404 Not Found", "no such bot")),
    IO.bind(List<&2, U32>, Unit, Files.read(BR.Br.shot_file(home, bot)), bs => Bot.shot.sent(bs, reply)))

def Bot.oauth.page(+text: String) -> String:
  GG.Google.page(Bool.pick(String, String.starts_with(text, "error"), text, "Google is connected to Backplane. You can close this tab."))

def Bot.oauth.here(+home: String, +port: U32, +path: String, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  IO.bind(String, Unit, GS.Google.finish(home, path, Bot.redirect(port)),
    t => Bot.answer(reply, W.Http.response("200 OK", "text/html; charset=utf-8", U.Utf8.encode(Bot.oauth.page(t)), "")))

def Bot.oauth.to(+to: String, +home: String, +port: U32, +path: String, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(to), Bot.oauth.here(home, port, path, reply),
    Bot.answer(reply, W.Http.response("302 Found", "text/plain; charset=utf-8", U.Utf8.encode("Signing in on " ++ to), "Location: " ++ to ++ "\r\n")))

# Google sent the browser back with a code: finish signing in, or, when
# the sign-in was started on another of the owner's hubs (the browser runs
# here, that hub elsewhere), send the browser on to it (GG.Google.hop)
def Bot.oauth(+home: String, +port: U32, +path: String, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  IO.bind(String, Unit, GS.Google.pending(home),
    mine => Bot.oauth.to(GG.Google.hop(GG.Url.query(path), mine), home, port, path, reply))

def Bot.me(+link: Bool) -> IO(String):
  Bool.pick(IO(String), link, BN.Bn.name(), IO.pure(String, ""))

# the secret of the hook or the peer, the signature against it, and the
# replay key (or "") back to the hub
def Bot.refuse(+id: String, +key: String, body: String, +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, BotVerified{"hook", id, key, body, "", reply})
    return Unit{}

# a form (the Pebble Index ring's) becomes a JSON object; any other body
# goes as it came. Only a call let in is read.
def Bot.bearer.body(form: Bool, +body: String, +size: String) -> String:
  match form:
    case True{}:
      RG.Ring.form(body, size)
    case False{}:
      body

# A ring's recording, let in, is heard here before the bot gets the form
# (VO.Vo.ring: GPT-Live-Transcribe with the dictionary): the phone gets its
# 202 at once, and the form, with the words heard, goes on when they are
# (the hub's own answer then goes nowhere). A form under a bearer token
# becomes JSON as usual.
def Bot.heard(+home: String, +kind: String, +id: String, +key: String, +ct: String, +body: String, raw: List<&2, U32>, +me: String, form: Bool, +size: String,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Bot.answer(reply, W.Http.text("202 Accepted", "accepted"))
    +nonce : String <- BN.Bn.random(6n)
    +heard : String <- VO.Vo.ring(home, nonce, ct, body, raw)
    +none : Chan(List<&2, U32>) <- Chan.new(List<&2, U32>, 1)
    ok : Bool <- Chan.send(Msg, inbox, BotVerified{kind, id, key, Bot.bearer.body(form, heard, size), me, none})
    return Unit{}

def Bot.verify.go(heard: Bool, +home: String, +kind: String, +id: String, +key: String, +ct: String, +body: String, raw: List<&2, U32>, +me: String,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  match heard:
    case True{}:
      Bot.heard(home, kind, id, key, ct, body, raw, me, False{}, "", reply, inbox)
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, BotVerified{kind, id, key, body, me, reply})
        return Unit{}

# the replay key: a form with a recording is checked over its bytes (the
# ring signs those; the recording is not text)
def Bot.verify.key(text: Bool, +hook: Bool, +secret: String, +now: Nat, +key: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    raw: List<&2, U32>) -> String:
  match text:
    case True{}:
      BN.Bn.check(hook, secret, now, key, ts, sig, gh, dl, body)
    case False{}:
      BN.Bn.check.raw(secret, now, key, gh, raw)

# the secret of the hook or the peer, the signature against it, and the
# replay key (or "") back to the hub
def Bot.verify(+hook: Bool, +home: String, +kind: String, +id: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    +ct: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +secret : String <- BN.Bn.secret.of(hook, home, id)
    +me : String <- Bot.me(String.eq(kind, "link"))
    +key : String = Bot.verify.key(List.is_empty(&2, U32, raw), hook, secret, now, kind ++ ":" ++ id, ts, sig, gh, dl, body, raw)
    Bot.verify.go(Bool.and(Bool.not(List.is_empty(&2, U32, raw)), Bool.not(String.is_empty(key))), home, kind, id, key, ct, body, raw,
      Bool.pick(String, String.contains(key, ":i:"), "ring", me), reply, inbox)

def Bot.bearer.go(heard: Bool, form: Bool, +home: String, +key: String, +ct: String, +size: String, +id: String, +body: String, raw: List<&2, U32>,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  match heard:
    case True{}:
      Bot.heard(home, "hook", id, key, ct, body, raw, "", True{}, size, reply, inbox)
    case False{}:
      Bot.refuse(id, key, Bot.bearer.body(form, body, size), reply, inbox)

def Bot.bearer.k(+home: String, +key: String, +ct: String, +size: String, +id: String, +body: String, +raw: List<&2, U32>,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  Bot.bearer.go(Bool.and(Bool.and(Bool.not(BN.Bn.refused(key)), RG.Ring.is_form(ct)), Bool.not(List.is_empty(&2, U32, raw))),
    Bool.and(Bool.not(BN.Bn.refused(key)), RG.Ring.is_form(ct)), home, key, ct, size, id, body, raw, reply, inbox)

# a webhook called with a bearer token (packed by Bot.gh as
# "bearer\n<token>\n<content type>\n<X-Audio-Size>"): the token compared
# with the hook's own off the hub
def Bot.bearer(fs: List<&2, String>, +home: String, +id: String, +body: String, +full: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fs:
    case _ <> +tok <> +ct <> +size <> _:
      do IO<Unit>:
        +kept : String <- BN.Bn.token.of(home, id)
        +nonce : String <- BN.Bn.random(2n)
        Bot.bearer.k(home, BN.Bn.bearer(kept, tok, "hook:" ++ id, Nat.show(now) ++ "." ++ nonce), Bool.pick(String, String.is_empty(full), ct, full), size, id, body, raw, reply, inbox)
    case _:
      Bot.refuse(id, "!bearer", body, reply, inbox)

# how a webhook call proves itself: 0 not at all, 1 a bearer token, 2 a
# signature (ours, GitHub's, the ring's). A signature wins over a token.
def Bot.hook.how(+sig: String, +gh: String) -> Nat:
  Bool.pick(Nat, Bool.not(String.is_empty(sig)), 2n,
    Bool.pick(Nat, String.starts_with(gh, "bearer\n"), 1n, Bool.pick(Nat, String.is_empty(gh), 0n, 2n)))

def Bot.hook.in(i: Nat, +home: String, +id: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String, +ct: String, +raw: List<&2, U32>,
    +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match i:
    case 0n:
      Bot.refuse(id, "!none", body, reply, inbox)
    case 1n:
      Bot.bearer(String.split(gh, '\n'), home, id, body, ct, raw, reply, now, inbox)
    case _:
      Bot.verify(True{}, home, "hook", id, ts, sig, gh, dl, body, ct, raw, reply, now, inbox)

def Bot.http.job(i: Nat, +home: String, +port: U32, +kind: String, +arg: String, +peer: String, +ts: String, +sig: String, +gh: String, +dl: String,
    +body: String, +ct: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match i:
    case 0n:
      Bot.shot(home, arg, reply)
    case 1n:
      Bot.oauth(home, port, arg, reply)
    case 2n:
      Bot.hook.in(Bot.hook.how(sig, gh), home, arg, ts, sig, gh, dl, body, ct, raw, reply, now, inbox)
    case _:
      Bot.verify(False{}, home, kind, peer, ts, sig, gh, dl, body, "", Nil{}, reply, now, inbox)

def Bot.page.sent(none: Bool, +html: String, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  match none:
    case True{}:
      Bot.answer(reply, W.Http.text("404 Not Found", "no page"))
    case False{}:
      Bot.answer(reply, W.Http.response.c("200 OK", "text/html; charset=utf-8", U.Utf8.encode(SPC.Space.page(html)), "no-store",
        "Content-Security-Policy: " ++ SPC.Space.page.csp() ++ "\r\nX-Content-Type-Options: nosniff\r\n"))

# a bot's space page (Space.page: no scripts, nothing from the network)
# a bot's page: one here from the read model, one mirrored from a linked
# machine ("<link>~<id>") from its mirror
def Hub.bot.page.html(+st: M.State, +cfg: Cfg, +bot: String) -> String:
  Bool.pick(String, FR.Fr.is(bot), FR.In.page(FR.Fh.in(BN.Bn.far(Cfg.bn(cfg)), FR.Fr.link(bot), ""), FR.Fr.local(bot)),
    BO.Page.html(BO.World.spage(M.State.bots(st), bot)))

def Hub.bot.page(h: Hub, +bot: String, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        +html : String = Hub.bot.page.html(st, cfg, bot)
        IO.spawn(Unit, Bot.page.sent(Bool.or(String.is_empty(bot), String.is_empty(html)), html, reply))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.bot_http.job(h: Hub, +kind: String, +arg: String, +peer: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    +ct: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Bot.http.job(C.Codec.pos(["shot", "oauth", "hook"], kind), Cfg.home(cfg), Cfg.port(cfg), kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply, now, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.bot_http.k(page: Bool, h: Hub, +kind: String, +arg: String, +peer: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    +ct: String, +raw: List<&2, U32>,
    +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match page:
    case True{}:
      Hub.bot.page(h, arg, reply)
    case False{}:
      Hub.bot_http.job(h, kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply, now)

def Hub.bot_http(h: Hub, +kind: String, +arg: String, +peer: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    +ct: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  Hub.bot_http.k(String.eq(kind, "page"), h, kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply, now)

def Bot.hook.live.k(hk: BO.Hook, +st: M.State) -> Bool:
  match hk:
    case BO.Hook{_, +bot, _, _, revoked, _, _}:
      Bool.and(Bool.not(revoked), BH.Bots.live(st, bot))

def Bot.hook.live(+st: M.State, +id: String) -> Bool:
  Bot.hook.live.k(BO.World.hook(M.State.bots(st), id), st)

# a ring's voice note reaches the bot as the person's words (Bots.ring);
# any other webhook's body as untrusted data (Bots.hooked)
def Bot.hook.step(ring: Bool, +st: M.State, +now: Nat, +hook: String, +body: String) -> B.Step:
  match ring:
    case True{}:
      BH.Bots.ring(st, now, hook, body)
    case False{}:
      BH.Bots.hooked(st, now, hook, body)

def Hub.bot.hook(live: Bool, h: Hub, +hook: String, +body: String, ring: Bool, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match live h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Bot.answer(reply, W.Http.text("202 Accepted", "accepted"))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, Bot.hook.step(ring, st, now, hook, body))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "no such webhook"))

def Hub.bot.deliver(live: Bool, m: Maybe<&2, J.Json>, h: Hub, +peer: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match live m h:
    case True{} Some{+o} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Bot.answer(reply, Bot.json("200 OK", "{\"ok\":true}"))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, BH.Bots.incoming(st, now, Bot.peer.name(st, peer), o))
    case True{} None{} _:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "not JSON"))
    case False{} _ _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "not a linked machine"))

def Hub.bot.link.k(ok: Bool, h: Hub, +url: String, +name: String, +peer: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match ok:
    case True{}:
      do IO<Hub>:
        Bot.answer(reply, Bot.json("200 OK", J.Json.show(J.Json.obj([J.KV{"name", J.Str{me}}]))))
        Hub.step(h, B.Step{[M.PeerSet{peer, Bool.pick(String, String.is_empty(name), peer, name), url, False{}, now}], Nil{}})
    case False{}:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "no http address"))

# an invite used: the machine that holds it says where it is; once only
def Hub.bot.link(fresh: Bool, m: Maybe<&2, J.Json>, h: Hub, +peer: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match fresh m:
    case True{} Some{+o}:
      Hub.bot.link.k(BN.Bn.url.ok(J.Json.get_str(o, "url", "")), h, J.Json.get_str(o, "url", ""), BN.Bn.clean(J.Json.get_str(o, "name", "")), peer, me, reply, now)
    case True{} None{}:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "not JSON"))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("409 Conflict", "already linked"))

def Hub.bot.dir(live: Bool, h: Hub, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  match live h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.answer(Hub{st, f, ls, cl, as, inbox, cfg, note}, reply, Bot.json("200 OK", BN.Bn.mine(st)))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "not a linked machine"))

def Hub.bot.act(i: Nat, h: Hub, +arg: String, +body: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match i h:
    case 0n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.hook(Bot.hook.live(st, arg), Hub{st, f, ls, cl, as, inbox, cfg, note}, arg, body, String.eq(me, "ring"), reply, now)
    case 1n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.deliver(Bot.peer.live(st, arg), J.Json.parse(body), Hub{st, f, ls, cl, as, inbox, cfg, note}, arg, reply, now)
    case 2n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.link(Bool.not(Bot.peer.live(st, arg)), J.Json.parse(body), Hub{st, f, ls, cl, as, inbox, cfg, note}, arg, me, reply, now)
    case 3n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.dir(Bot.peer.live(st, arg), Hub{st, f, ls, cl, as, inbox, cfg, note}, reply)
    case 4n Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.far.push.in(Far.own.id(st, cfg, arg), J.Json.parse(body), Hub{st, f, ls, cl, as, inbox, cfg, note}, arg, reply)
    case 5n Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.far.log(Far.own.id(st, cfg, arg), J.Json.parse(body), Hub{st, f, ls, cl, as, inbox, cfg, note}, reply)
    case 6n Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.far.rpc(Far.own.id(st, cfg, arg), J.Json.parse(body), Hub{st, f, ls, cl, as, inbox, cfg, note}, body, reply, now)
    case _ _:
      Hub.answer(h, reply, W.Http.text("404 Not Found", "not found"))

def Hub.bot.seen(bad: Bool, m: Maybe<&2, SG.Seen>, h: Hub, +why: String, +kind: String, +arg: String, body: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match bad m h:
    case True{} _ _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", why))
    case False{} None{} _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "already seen"))
    case False{} Some{s} Hub{st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        Bot.dir.awake(Bool.and(Bool.or(String.eq(kind, "dir"), String.eq(kind, "deliver")), BH.Dir.stale(
          J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(BN.Bn.dir(Cfg.bn(cfg))), J.Null{})), arg)), inbox, arg)
        Hub.bot.act(C.Codec.pos(["hook", "deliver", "link", "dir", "far-push", "far-log", "far-rpc"], kind), Hub{st, f, ls, cl, as, inbox, Cfg.with_bn(cfg, BN.Bn.with_seen(Cfg.bn(cfg), s)), note},
        arg, body, me, reply, now)

# a signed request (or a webhook's bearer token), checked: genuine (key),
# not seen before, then acted on; a refusal says why
def Hub.bot_verified(h: Hub, +kind: String, +arg: String, +key: String, body: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.bot.seen(BN.Bn.refused(key), BN.Bn.accept(Cfg.bn(cfg), key, now), Hub{st, f, ls, cl, as, inbox, cfg, note}, BN.Bn.denied(key), kind, arg, body, me, reply, now)

# Connections for bots' routes
# ----------------------------

type BotReq is Data:
  BotReq{kind: String, arg: String, peer: String, ts: String, sig: String, gh: String, delivery: String}

def Conn.bot.kind.k(+post: Bool, +get: Bool, +r: String) -> Nat:
  Bool.pick(Nat, Bool.and(post, String.starts_with(r, "/hook/")), 1n,
    Bool.pick(Nat, Bool.and(post, String.eq(r, "/bots/deliver")), 2n,
      Bool.pick(Nat, Bool.and(post, String.eq(r, "/bots/link")), 3n,
        Bool.pick(Nat, Bool.and(get, String.eq(r, "/bots/dir")), 4n,
          Bool.pick(Nat, Bool.and(get, Bool.and(String.starts_with(r, "/bots/"), String.ends_with(r, "/screen.jpg"))), 5n,
            Bool.pick(Nat, Bool.and(get, String.eq(r, "/oauth/google")), 6n,
              Bool.pick(Nat, Bool.and(get, Bool.and(String.starts_with(r, "/bots/"), String.ends_with(r, "/space.html"))), 7n,
                Bool.pick(Nat, Bool.and(post, String.eq(r, "/far/push")), 8n,
                  Bool.pick(Nat, Bool.and(post, String.eq(r, "/far/log")), 9n,
                    Bool.pick(Nat, Bool.and(post, String.eq(r, "/far/rpc")), 10n, 0n))))))))))

# which bots' route a request is (0: none)
def Conn.bot.kind(req: W.Request) -> Nat:
  match req:
    case W.Request{+m, +p, _}:
      Conn.bot.kind.k(String.eq(m, "POST"), String.eq(m, "GET"), W.Http.route(p))

# /bots/<id>/screen.jpg: the id ("" when it is not a plain id)
def Conn.bot.shot_id(+r: String) -> String:
  Bool.pick(String, BN.Bn.safe(String.take(String.drop(r, 6n), Nat.sub(String.length(r), 17n))), String.take(String.drop(r, 6n), Nat.sub(String.length(r), 17n)), "")

# /bots/<id>/space.html: the id ("" when it is not a plain id)
# (a plain id, or a mirrored bot's "<link>~<id>" of two plain ids)
def Conn.bot.page_ok(+id: String) -> Bool:
  Bool.or(BN.Bn.safe(id), Bool.and(FR.Fr.is(id), Bool.and(BN.Bn.safe(FR.Fr.link(id)), BN.Bn.safe(FR.Fr.local(id)))))

def Conn.bot.page_id(+r: String) -> String:
  Bool.pick(String, Conn.bot.page_ok(String.take(String.drop(r, 6n), Nat.sub(String.length(r), 17n))), String.take(String.drop(r, 6n), Nat.sub(String.length(r), 17n)), "")

def Conn.bot.answer(m: Maybe<&1, List<&2, U32>>, s: Socket) -> IO(Unit):
  match m:
    case Some{bs}:
      Conn.finish(s, bs)
    case None{}:
      Conn.finish(s, W.Http.text("503 Service Unavailable", "the hub is gone"))

# the hub answers the whole response on a channel made for this request
def Conn.bot.ask(s: Socket, rq: BotReq, body: String, +ct: String, raw: List<&2, U32>, +inbox: Chan(Msg)) -> IO(Unit):
  match rq:
    case BotReq{k, a, p, t, sg, g, d}:
      do IO<Unit>:
        +reply : Chan(List<&2, U32>) <- Chan.new(List<&2, U32>, 1)
        ok : Bool <- Chan.send(Msg, inbox, BotHttp{k, a, p, t, sg, g, d, body, ct, raw, reply})
        m : Maybe<&1, List<&2, U32>> <- Chan.recv(List<&2, U32>, reply)
        Conn.bot.answer(m, s)

# the body as text, and its bytes too when it is a form with a recording
def Conn.bot.bytes(s: Socket, +rq: BotReq, +bs: List<&2, U32>, +text: String, +ct: String, +inbox: Chan(Msg)) -> IO(Unit):
  Conn.bot.ask(s, rq, text, ct, Bool.pick(List<&2, U32>, Bool.and(RG.Ring.is_form(ct), String.contains(text, "name=\"audio\"")), bs, Nil{}), inbox)

def Conn.bot.body.k(full: Bool, s: Socket, +buf: List<&2, U32>, +len: Nat, +rq: BotReq, +ct: String, +inbox: Chan(Msg), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match full:
    case True{}:
      Conn.bot.bytes(s, rq, List.take(&2, U32, buf, len), U.Utf8.decode(List.take(&2, U32, buf, len)), ct, inbox)
    case False{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536), r => Mcp.got(r, buf, k))

# read the body (Content-Length bytes, capped before reading)
def Conn.bot.body(fuel: Nat, s: Socket, +buf: List<&2, U32>, +len: Nat, +rq: BotReq, +ct: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.finish(s, W.Http.text("408 Request Timeout", "the body did not arrive"))
    case 1n+f:
      Conn.bot.body.k(Nat.is_ge(List.length(&2, U32, buf), len), s, buf, len, rq, ct, inbox, s2 => b2 => Conn.bot.body(f, s2, b2, len, rq, ct, inbox))

def Conn.bot.signed.k(ok: Bool, big: Bool, s: Socket, rest: List<&2, U32>, +len: Nat, +rq: BotReq, +ct: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ok big:
    case False{} _:
      Conn.finish(s, W.Http.text("401 Unauthorized", "unknown sender"))
    case True{} True{}:
      Conn.finish(s, W.Http.text("413 Payload Too Large", "at most 256 KB, or 2 MB for a form"))
    case True{} False{}:
      Conn.bot.body(4096n, s, rest, len, rq, ct, inbox)

def Conn.bot.len(+hs: List<&2, W.Header>) -> Nat:
  Maybe.default(&2, Nat, Nat.read(W.Http.header_of(hs, "content-length")), 0n)

def Bot.bearer.of(+auth: String) -> String:
  Bool.pick(String, Bool.or(String.starts_with(auth, "Bearer "), String.starts_with(auth, "bearer ")), String.trim(String.drop(auth, 7n)), "")

# Authorization: Bearer <token>, with what reading the body needs, packed
# after "bearer\n" ("" when there is no token)
def Bot.gh.bearer(+tok: String, +hs: List<&2, W.Header>) -> String:
  Bool.pick(String, String.is_empty(tok), "",
    "bearer\n" ++ tok ++ "\n" ++ W.Http.header_of(hs, "content-type") ++ "\n" ++ W.Http.header_of(hs, "x-audio-size"))

def Bot.gh.hub(+g: String, +hs: List<&2, W.Header>) -> String:
  Bool.pick(String, String.is_empty(g), Bot.gh.bearer(Bot.bearer.of(W.Http.header_of(hs, "authorization")), hs), g)

# a third party's signature: the Pebble Index ring's (its X-Index-*
# headers, packed after "index\n" for BN.Bn.check), else GitHub's, else a
# bearer token
def Bot.gh.k(ring: Bool, +hs: List<&2, W.Header>) -> String:
  match ring:
    case True{}:
      "index\n" ++ String.join([W.Http.header_of(hs, "x-index-webhook-version"), W.Http.header_of(hs, "x-index-timestamp"),
        W.Http.header_of(hs, "x-index-delivery"), W.Http.header_of(hs, "x-index-trigger"), W.Http.header_of(hs, "x-index-test"),
        W.Http.header_of(hs, "x-index-signature")], "\n")
    case False{}:
      Bot.gh.hub(W.Http.header_of(hs, "x-hub-signature-256"), hs)

def Bot.gh(+hs: List<&2, W.Header>) -> String:
  Bot.gh.k(Bool.not(String.is_empty(W.Http.header_of(hs, "x-index-signature"))), hs)

# a signed request (no token: webhooks come from outside; peers sign)
def Conn.bot.signed(+kind: String, +arg: String, s: Socket, +hs: List<&2, W.Header>, rest: List<&2, U32>, +inbox: Chan(Msg)) -> IO(Unit):
  Conn.bot.signed.k(BN.Bn.safe(arg), Nat.is_gt(Conn.bot.len(hs), Bot.cap.of(W.Http.header_of(hs, "content-type"))), s, rest, Conn.bot.len(hs),
    BotReq{kind, arg, W.Http.header_of(hs, "x-backplane-peer"), W.Http.header_of(hs, "x-backplane-timestamp"), W.Http.header_of(hs, "x-backplane-signature"),
      Bot.gh(hs), W.Http.header_of(hs, "x-github-delivery")}, W.Http.header_of(hs, "content-type"), inbox)

# a client's own route (a bot's screen, Google's redirect): the same
# authorisation as the websocket's
def Conn.bot.own(ok: Bool, s: Socket, rq: BotReq, +inbox: Chan(Msg)) -> IO(Unit):
  match ok:
    case True{}:
      Conn.bot.ask(s, rq, "", "", Nil{}, inbox)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

# Uploads over HTTP
# -----------------
# POST /attach?thread=<id>&key=<key>&name=<name> with the file as the body: the
# phones' way to attach (no base64, no pieces through the hub). The hub
# only names the folder; the bytes after the head go straight from the
# socket to the file (H.Sock.save) off the hub. The answer is what an
# attach.put answers: {"attached", "thread"}, or {"text", "thread",
# "upload"} when it failed.

def Conn.is_att(req: W.Request) -> Bool:
  match req:
    case W.Request{m, p, _}:
      Bool.and(String.eq(m, "POST"), String.eq(W.Http.route(p), "/attach"))

def Upload.json(+status: String, +ok: Bool, +thread: String, +v: String) -> List<&2, U32>:
  W.Http.response(status, "application/json", U.Utf8.encode(J.Json.show(J.Json.obj(Bool.pick(List<&2, J.KV>, ok,
    [J.KV{"attached", J.Str{v}}, J.KV{"thread", J.Str{thread}}],
    [J.KV{"text", J.Str{v}}, J.KV{"thread", J.Str{thread}}, J.KV{"upload", J.Flag{True{}}}])))), "")

def Upload.saved(r: Socket & Result<&1, &1, U32 & String, Unit>, +thread: String, +path: String) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{_}:
      Conn.finish(s, Upload.json("200 OK", True{}, thread, path))
    case Fail{_}:
      do IO<Unit>:
        rm : Result<&1, &1, U32 & String, Unit> <- H.FS.remove(path)
        Conn.finish(s, Upload.json("400 Bad Request", False{}, thread, "the upload did not arrive whole"))

# the head's leftover (the body's start) is written; the rest is copied
# (a body that came whole with the head has nothing left to copy: the copy
# would wait for bytes that never come)
def Upload.rest(none: Bool, s: Socket, +left: Nat, +thread: String, +path: String) -> IO(Unit):
  match none:
    case True{}:
      Conn.finish(s, Upload.json("200 OK", True{}, thread, path))
    case False{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Unit, H.Sock.save(s, path, U32.from_nat(left)), r => Upload.saved(r, thread, path))

def Upload.wrote.k(ok: Bool, s: Socket, +err: String, +left: Nat, +thread: String, +path: String) -> IO(Unit):
  match ok:
    case True{}:
      Upload.rest(Nat.is_eq(left, 0n), s, left, thread, path)
    case False{}:
      Conn.finish(s, Upload.json("500 Internal Server Error", False{}, thread, err))

def Upload.wrote(+err: String, s: Socket, +left: Nat, +thread: String, +path: String) -> IO(Unit):
  Upload.wrote.k(String.is_empty(err), s, err, left, thread, path)

def Upload.into(m: Maybe<&1, String>, s: Socket, +thread: String, +name: String, +len: Nat, rest: List<&2, U32>) -> IO(Unit):
  match m:
    case Some{+dir}:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(dir)
        +head : List<&2, U32> = List.take(&2, U32, rest, len)
        +path : String = dir ++ "/" ++ name
        e : String <- Media.put.file(path, "w", head)
        Upload.wrote(e, s, Nat.sub(len, List.length(&2, U32, head)), thread, path)
    case None{}:
      Conn.finish(s, W.Http.text("503 Service Unavailable", "the hub is gone"))

# a client that waits for leave to send the body (Expect: 100-continue) is
# told to go on
def Upload.go(cont: Bool, s: Socket) -> IO(Socket):
  match cont:
    case True{}:
      Conn.send(s, U.Utf8.encode("HTTP/1.1 100 Continue\r\n\r\n"))
    case False{}:
      IO.pure(Socket, s)

def Upload.gate(ok: Bool, big: Bool, s: Socket, +cont: Bool, +thread: String, +name: String, +len: Nat, +rest: List<&2, U32>, +inbox: Chan(Msg)) -> IO(Unit):
  match ok big:
    case False{} _:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))
    case True{} True{}:
      Conn.finish(s, Upload.json("413 Payload Too Large", False{}, thread, "attachments are limited to " ++ Nat.show(Nat.div(AT.Att.cap(), 1048576n)) ++ " MB"))
    case True{} False{}:
      do IO<Unit>:
        +reply : Chan(String) <- Chan.new(String, 1)
        sent : Bool <- Chan.send(Msg, inbox, AttDir{thread, reply})
        m : Maybe<&1, String> <- Chan.recv(String, reply)
        s2 : Socket <- Upload.go(Bool.and(cont, List.is_empty(&2, U32, rest)), s)
        Upload.into(m, s2, thread, name, len, rest)

def Conn.route.att(att: Bool, s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match att req:
    case True{} W.Request{_, +p, +hs}:
      Upload.gate(Conn.allowed(trusted, hs, p, token), Nat.is_gt(Conn.bot.len(hs), AT.Att.cap()), s,
        String.contains(String.to_lower(W.Http.header_of(hs, "expect")), "100-continue"),
        AT.Att.unpct(W.Http.param(p, "thread")), AT.Att.stored(AT.Att.unpct(W.Http.param(p, "key")), AT.Att.unpct(W.Http.param(p, "name"))), Conn.bot.len(hs), rest, inbox)
    case False{} _:
      Conn.route.mcp(Conn.is_mcp(req), s, req, rest, web, id, inbox, trusted, token)

def Conn.route.bot(k: Nat, s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match k req:
    case 1n W.Request{_, +p, +hs}:
      Conn.bot.signed("hook", String.drop(W.Http.route(p), 6n), s, hs, rest, inbox)
    case 2n W.Request{_, _, +hs}:
      Conn.bot.signed("deliver", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 3n W.Request{_, _, +hs}:
      Conn.bot.signed("link", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 4n W.Request{_, _, +hs}:
      Conn.bot.signed("dir", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 5n W.Request{_, +p, +hs}:
      Conn.bot.own(Conn.allowed(trusted, hs, p, token), s, BotReq{"shot", Conn.bot.shot_id(W.Http.route(p)), "", "", "", "", ""}, inbox)
    case 6n W.Request{_, +p, +hs}:
      Conn.bot.own(Conn.allowed(trusted, hs, p, token), s, BotReq{"oauth", p, "", "", "", "", ""}, inbox)
    case 7n W.Request{_, +p, +hs}:
      Conn.bot.own(Conn.allowed(trusted, hs, p, token), s, BotReq{"page", Conn.bot.page_id(W.Http.route(p)), "", "", "", "", ""}, inbox)
    case 8n W.Request{_, _, +hs}:
      Conn.bot.signed("far-push", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 9n W.Request{_, _, +hs}:
      Conn.bot.signed("far-log", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 10n W.Request{_, _, +hs}:
      Conn.bot.signed("far-rpc", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case _ _:
      Conn.route.att(Conn.is_att(req), s, req, rest, web, id, inbox, trusted, token)

def Conn.route(s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  Conn.route.bot(Conn.bot.kind(req), s, req, rest, web, id, inbox, trusted, token)

def Conn.head.k(m: Maybe<&2, W.Split>, s: Socket, buf: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg),
    +trusted: Bool, +token: String, k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{W.Split{head, rest}}:
      Conn.route(s, W.Http.request(head), rest, web, id, inbox, trusted, token)
    case None{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536), r => Conn.head.got(r, buf, k))

# read until the request head is complete (at most 64 reads)
def Conn.head(fuel: Nat, s: Socket, +buf: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.finish(s, W.Http.text("431 Request Header Fields Too Large", "too large"))
    case 1n+f:
      Conn.head.k(W.Http.split(buf), s, buf, web, id, inbox, trusted, token, s2 => b2 => Conn.head(f, s2, b2, web, id, inbox, trusted, token))

# Accepting
# ---------

# a tailnet connection from a device its owner also owns is trusted like
# loopback (Tailscale vouches for it); others still need the token
def Accept.whois(r: Socket & String, +owner: String, +id: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  (s, ip) = r
  do IO<Unit>:
    w : P.Ran <- P.Proc.run("timeout", ["--kill-after=1", "5", "tailscale", "whois", "--json", ip], "/")
    Conn.head(64n, s, Nil{}, web, id, inbox, TN.Tailnet.trusts(owner, TN.Tailnet.login(Tailnet.out(w))), token)

def Accept.trust(ask: Bool, s: Socket, +owner: String, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match ask:
    case True{}:
      IO.bind(Socket & String, Unit, H.Sock.peer(s), r => Accept.whois(r, owner, id, web, inbox, token))
    case False{}:
      Conn.head(64n, s, Nil{}, web, id, inbox, trusted, token)

def Accept.got(r: Listener & Result<&1, &1, U32 & String, Socket>, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String, +owner: String, k: Listener -> IO(Unit)) -> IO(Unit):
  (l, res) = r
  match res:
    case Done{s}:
      do IO<Unit>:
        IO.spawn(Unit, Accept.trust(Bool.and(Bool.not(trusted), Bool.not(String.is_empty(owner))), s, owner, id, web, inbox, trusted, token))
        k(l)
    case Fail{_}:
      k(l)

# connections from one listener; ids count up from `id` (loopback from 1,
# the tailnet from 2^31, so they never meet)
def Accept.loop(fuel: Nat, l: Listener, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String, +owner: String) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(l)
    case 1n+f:
      IO.bind(Listener & Result<&1, &1, U32 & String, Socket>, Unit, TCP.accept(l),
        r => Accept.got(r, id, web, inbox, trusted, token, owner, l2 => Accept.loop(f, l2, (id + 1 : U32), web, inbox, trusted, token, owner)))

def Tailnet.listened(r: Result<&1, &1, U32 & String, Listener>, +ip: String, +port: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  match r:
    case Done{l}:
      do IO<Unit>:
        w : P.Ran <- P.Proc.run("tailscale", ["whois", "--json", ip], "/")
        +owner : String = TN.Tailnet.login(Tailnet.out(w))
        IO.print("Backplane on your tailnet: http://" ++ ip ++ ":" ++ U32.show(port) ++ "/ (" ++ Bool.pick(String, String.is_empty(owner), "pairing token " ++ token, owner ++ "'s devices, or pairing token " ++ token) ++ ")")
        ok : Bool <- Chan.send(Msg, inbox, LinkFound{TN.Tailnet.link("http://" ++ ip ++ ":" ++ U32.show(port), token)})
        IO.spawn(Unit, Accept.loop(Fuel.forever(), l, 2147483648, web, inbox, False{}, token, owner))
    case Fail{_}:
      Log.info("could not listen on the tailnet address " ++ ip)

def Tailnet.listen.k(none: Bool, +ip: String, +port: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  match none:
    case True{}:
      Log.info("tailscale is not up (tailscale ip -4 gave nothing)")
    case False{}:
      IO.bind(Result<&1, &1, U32 & String, Listener>, Unit, H.Net.listen(ip, port), r => Tailnet.listened(r, ip, port, web, inbox, token))

# listen on the tailnet address too (clients there need the token), and
# serve HTTPS through `tailscale serve` when asked
def Tailnet.start(n: Net, +port: U32, +web: String, +inbox: Chan(Msg)) -> IO(Unit):
  match n:
    case Net{True{}, https, +token, _, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}:
      do IO<Unit>:
        r : P.Ran <- P.Proc.run("tailscale", ["ip", "-4"], "")
        +ip : String = Tailnet.first(r)
        Tailnet.listen.k(String.is_empty(ip), ip, port, web, inbox, token)
        Tailnet.https(https, port, token, inbox)
    case Net{False{}, _, _, _, _, _, brx, pkx, tmx, mc, pvx, bnx, mgd, lk, fc}:
      IO.pure(Unit, Unit{})

# Google's tools for bots
# -----------------------
# gmail_search, gmail_read, calendar_events, google_accounts run at once, off the hub;
# gmail_send and calendar_create first open an approval ask (the reply
# waits in the park until the user answers).

def Gg.is(+o: J.Json) -> Bool:
  Bool.and(String.eq(J.Json.get_str(o, "method", ""), "tools/call"),
    Nat.is_lt(C.Codec.pos(GG.Google.tool_names(), J.Json.get_str(J.Json.get_obj(o, "params"), "name", "")), List.length(&2, String, GG.Google.tool_names())))

def Gg.tool(+o: J.Json) -> String:
  J.Json.get_str(J.Json.get_obj(o, "params"), "name", "")

def Gg.args(+o: J.Json) -> J.Json:
  J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments")

def Gg.say(+reply: Chan(String), +id: J.Json, +ok: Bool, text: String) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(String, reply, MC.Mcp.result(id, J.Json.obj([J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{text}}])])},
      J.KV{"isError", J.Flag{Bool.not(ok)}}])))
    return Unit{}

def Gg.said(+t: String, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  Gg.say(reply, id, Bool.not(String.starts_with(t, "error")), t)

def Gg.call(+home: String, +tool: String, +args: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  IO.bind(String, Unit, GS.Google.call(home, tool, args), t => Gg.said(t, id, reply))

def Gg.wait.k(m: Maybe<&1, String>, +home: String, +tool: String, +args: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  match m:
    case Some{+answer}:
      Bool.pick(IO(Unit), Bool.or(String.eq(answer, "accept"), String.eq(answer, "session")), Gg.call(home, tool, args, id, reply),
        Gg.say(reply, id, False{}, "The user declined this."))
    case None{}:
      IO.pure(Unit, Unit{})

# the user's answer (raw from the park), then the call or a refusal
def Gg.wait(+r2: Chan(String), +home: String, +tool: String, +args: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, r2), m => Gg.wait.k(m, home, tool, args, id, reply))

def Gg.detail.k(send: Bool, +a: J.Json) -> String:
  match send:
    case True{}:
      "To: " ++ J.Json.get_str(a, "to", "") ++ Bool.pick(String, String.is_empty(J.Json.get_str(a, "cc", "")), "", "\nCc: " ++ J.Json.get_str(a, "cc", "")) ++
        "\nSubject: " ++ J.Json.get_str(a, "subject", "") ++ "\n\n" ++ String.take(J.Json.get_str(a, "body", ""), 1500n)
    case False{}:
      J.Json.get_str(a, "summary", "") ++ "\n" ++ J.Json.get_str(a, "start", "") ++ " to " ++ J.Json.get_str(a, "end", "") ++
        Bool.pick(String, List.is_empty(&2, J.Json, J.Json.elems(J.Json.get_obj(a, "attendees"))), "", "\nInvites: " ++ J.Json.show(J.Json.get_obj(a, "attendees")))

# what the user approves: the mail's recipients, subject and text, or the event
def Gg.detail(+o: J.Json) -> String:
  Bool.pick(String, String.is_empty(J.Json.get_str(Gg.args(o), "account", "")), "", "Account: " ++ J.Json.get_str(Gg.args(o), "account", "") ++ "\n")
    ++ Gg.detail.k(String.eq(Gg.tool(o), "gmail_send"), Gg.args(o))

def Hub.google.k(ask: Bool, h: Hub, +thread: String, +o: J.Json, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match ask h:
    case False{} Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Gg.call(Cfg.home(cfg), Gg.tool(o), Gg.args(o), J.Json.get_obj(o, "id"), reply))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case True{} Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        +ask : String = B.Hub.id("q", now, B.Hub.seq(st))
        +r2 : Chan(String) <- Chan.new(String, 1)
        Park.put(Cfg.pk(cfg), PK.PPark{ask, "", r2})
        IO.spawn(Unit, Gg.wait(r2, Cfg.home(cfg), Gg.tool(o), Gg.args(o), J.Json.get_obj(o, "id"), reply))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Step{[M.AskOpened{ask, thread, "approval", Gg.tool(o), Gg.detail(o), "", now}], Nil{}})

def Hub.google(bot: Bool, h: Hub, +thread: String, +o: J.Json, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match bot h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.google.k(Bool.and(GG.Google.asks(Gg.tool(o)), Bool.not(MC.Perm.session_ok(M.Asks.all(st), thread, Gg.tool(o)))), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, o, reply, now)
    case False{} _:
      do IO<Hub>:
        Gg.say(reply, J.Json.get_obj(o, "id"), False{}, "only bots have this tool")
        return h

# A bot's new project (project_create)
# ------------------------------------
# The hub asks the person first (BH.Bots.newproj.asks); once they accept,
# the folder is made when missing and resolved off the hub, and comes back
# as NewProject, where BH.Bots.newproj.made adds it.

# the folder from $1 (never empty), made when missing, printed resolved
def Np.sh() -> String:
  "exec 2>&1; set -e; [ -n \"$1\" ] || { echo \"name a folder\"; exit 2; }; " ++ FsJob.path.sh() ++
    "[ -e \"$d\" ] || [ -L \"$d\" ] || mkdir -p -- \"$d\"; " ++ FsJob.dir.sh() ++ "echo \"$d\""

def Np.ran(r: P.Ran, +inbox: Chan(Msg), +thread: String, +name: String, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, NewProject{thread, FsJob.last(String.lines(String.trim(out))), name, J.Json.show(id), reply})
        return Unit{}
    case P.Ran{_, out}:
      Gg.say(reply, id, False{}, "error: " ++ String.trim(out))

def Np.run(+inbox: Chan(Msg), +thread: String, +a: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  IO.bind(P.Ran, Unit, FsJob.sh(Np.sh(), String.trim(J.Json.get_str(a, "path", ""))), r => Np.ran(r, inbox, thread, J.Json.get_str(a, "name", ""), id, reply))

def Np.wait.k(m: Maybe<&1, String>, +inbox: Chan(Msg), +thread: String, +a: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  match m:
    case Some{+answer}:
      Bool.pick(IO(Unit), BH.Bots.newproj.yes(answer), Np.run(inbox, thread, a, id, reply),
        Gg.say(reply, id, False{}, "The person declined this."))
    case None{}:
      IO.pure(Unit, Unit{})

def Np.wait(+r2: Chan(String), +inbox: Chan(Msg), +thread: String, +a: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, r2), m => Np.wait.k(m, inbox, thread, a, id, reply))

def Hub.newproj.k(ask: Bool, h: Hub, +thread: String, +o: J.Json, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match ask h:
    case False{} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Np.run(inbox, thread, Gg.args(o), J.Json.get_obj(o, "id"), reply))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case True{} Hub{+st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        +ask : String = B.Hub.id("q", now, B.Hub.seq(st))
        +r2 : Chan(String) <- Chan.new(String, 1)
        Park.put(Cfg.pk(cfg), PK.PPark{ask, "", r2})
        IO.spawn(Unit, Np.wait(r2, inbox, thread, Gg.args(o), J.Json.get_obj(o, "id"), reply))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Step{[M.AskOpened{ask, thread, "approval", "project_create", BH.Bots.newproj.detail(Gg.args(o)), "", now}], Nil{}})

def Hub.newproj(bot: Bool, h: Hub, +thread: String, +o: J.Json, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match bot h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.newproj.k(BH.Bots.newproj.asks(M.Asks.all(st), thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, o, reply, now)
    case False{} _:
      do IO<Hub>:
        Gg.say(reply, J.Json.get_obj(o, "id"), False{}, "only bots have this tool")
        return h

def Hub.mcp.np(np: Bool, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match np h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.newproj(BO.World.is_bot_thread(M.State.bots(st), thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, o, reply, now)
    case False{} _:
      Hub.mcp.w(MC.Wait.secs(o), h, thread, o, body, reply, now)

def Hub.mcp.gg(g: Bool, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match g h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.google(BO.World.is_bot_thread(M.State.bots(st), thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, o, reply, now)
    case False{} _:
      Hub.mcp.np(BH.Bots.newproj.is(o), h, thread, o, body, reply, now)

def Hub.mcp.route(pv: Bool, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match pv:
    case True{}:
      Hub.preview(h, thread, o, reply)
    case False{}:
      Hub.mcp.gg(Gg.is(o), h, thread, o, body, reply, now)

def Hub.mcp.tr(tr: Bool, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match tr:
    case True{}:
      Hub.term_read(h, thread, o, reply)
    case False{}:
      Hub.mcp.route(Preview.is(o), h, thread, o, body, reply, now)

def Hub.mcp(h: Hub, +thread: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  Hub.mcp.tr(TermRead.is(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{})), h, thread, Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), body, reply, now)

def Msg.kind(m: Msg) -> String:
  match m:
    case AgentWrite{_, _, _}:
      "agent_write"
    case UpdateCheck{}:
      "update_check"
    case Mcp{_, _, _}:
      "mcp"
    case Announce{_}:
      "announce"
    case Join{_, _, _, _, _, _}:
      "join"
    case JoinHere{_, _, _}:
      "join_here"
    case Drained{_, _, _, _}:
      "drained"
    case JoinMore{_, _}:
      "join_more"
    case Ping{_, _}:
      "ping"
    case Leave{_}:
      "leave"
    case Rpc{_, _}:
      "rpc"
    case AgentLine{_, _}:
      "agent_line"
    case AgentGone{_, _, _}:
      "agent_gone"
    case Tick{}:
      "tick"
    case Heart{}:
      "heart"
    case AutoView{_, _}:
      "auto_view"
    case ClaudePid{_, _, _}:
      "claude_pid"
    case ClaudeFail{_, _, _}:
      "claude_fail"
    case Push{_, _}:
      "push"
    case PushBin{_, _}:
      "push_bin"
    case TermOut{_, _}:
      "term_out"
    case TermTo{_, _, _, _, _}:
      "term_to"
    case ModelsFound{_, _}:
      "models"
    case MachinesFound{_}:
      "machines"
    case LinkFound{_}:
      "link"
    case TurnPid{_, _, _, _}:
      "turn_pid"
    case TurnDone{_}:
      "turn_done"
    case Recover{}:
      "recover"
    case Commit{_}:
      "commit"
    case BotTick{_}:
      "bot_tick"
    case BotsFound{_, _, _}:
      "bots_found"
    case BotsRefresh{_}:
      "bots_refresh"
    case BotHttp{_, _, _, _, _, _, _, _, _, _, _}:
      "bot_http"
    case BotVerified{_, _, _, _, _, _}:
      "bot_verified"
    case Shot{_}:
      "shot"
    case NewProject{_, _, _, _, _}:
      "new_project"
    case AttDir{_, _}:
      "att_dir"
    case FarFeed{_, _}:
      "far_feed"
    case FarPushed{_, _, _}:
      "far_pushed"
    case FarResend{_}:
      "far_resend"
    case FarPulled{_, _, _, _}:
      "far_pulled"
    case FarReplied{_, _, _, _, _}:
      "far_replied"
    case FarLoaded{_, _, _}:
      "far_loaded"
    case FarHere{_}:
      "far_here"
    case FarRetry{_}:
      "far_retry"
    case Replied{_, _, _}:
      "replied"
    case Release{}:
      "release"
    case SpawnFailed{_, _, _}:
      "spawn_failed"
    case AgentExited{_, _, _}:
      "agent_exited"
    case Silence{}:
      "silence"
    case Beat{}:
      "beat"
    case WatchLaunched{_, _}:
      "watch_launched"
    case WatchIdent{_, _, _}:
      "watch_ident"
    case WatchEnded{_, _, _, _}:
      "watch_ended"
    case Bulk{_}:
      "bulk"

def Hub.spawn_failed.k(ok: Bool, h: Hub, +thread: String, +line: String, +now: Nat) -> IO(Hub):
  match ok h:
    case True{} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.line(Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}, thread, line, now)
    case False{} _:
      IO.pure(Hub, h)

# a turn process that could not start: heard from the current generation
# only (law stale_spawn_fail_quiet)
def Hub.spawn_failed(h: Hub, +thread: String, +gen: String, +line: String, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.spawn_failed.k(B.Gen.accepts(Agent.key.of(Agents.get(as, thread)), gen), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, line, now)

def Hub.mcp.stale(+body: String) -> String:
  MC.McpOut.reply(MC.Mcp.reply(Maybe.default(&2, J.Json, J.Json.get(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), "id"), J.Null{}),
    MC.Res.fail("stale process: this agent process is no longer the thread's, so it may read but not change anything")))

def Hub.mcp.gate(refused: Bool, h: Hub, +thread: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match refused:
    case True{}:
      do IO<Hub>:
        ok : Bool <- Chan.send(String, reply, Hub.mcp.stale(body))
        return h
    case False{}:
      Hub.mcp(h, thread, body, reply, now)

# an MCP call names its thread and the process's generation
# ("<thread>.<gen>", B.Gen.*): one from a process the thread no longer
# runs may read, never change anything (law mcp_stale_gen_refused)
def Hub.mcp.g(h: Hub, +tag: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.mcp.gate(B.Gen.refused(B.Gen.tag(tag), Agents.gen(as, B.Gen.thread(tag)), Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{})),
        Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Gen.thread(tag), body, reply, now)

def Hub.exited.k(cur: Bool, h: Hub, +thread: String, +code: U32) -> IO(Hub):
  match cur:
    case True{}:
      do IO<Hub>:
        Log.info("agent for " ++ thread ++ " exited with code " ++ U32.show(code) ++ "; its reader ends at most 2 s later")
        return h
    case False{}:
      IO.pure(Hub, h)

# an agent's watcher saw its process exit: the reader ends (its last line
# read) and the exit is handled there, once; a stale generation's report
# changes nothing (B.Exit.current)
def Hub.exited(h: Hub, +thread: String, +gen: String, +code: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.exited.k(B.Exit.current(gen, Agents.gen(as, thread)), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, code)

# Silence: a running Claude turn with no line for 10 minutes and no work
# out is noted once (B.Quiet.due); the note comes again only after a line
# and a new silence
type Quieted is Data:
  Quieted{as: List<&2, Agent>, cs: List<&2, M.Change>}

def Quiet.mark.r(rs: List<&2, ARun>) -> List<&2, ARun>:
  match rs:
    case ARun{c, hd, l, n, g, _, pa, pl} <> t:
      ARun{c, hd, l, n, g, True{}, pa, pl} <> t
    case Nil{}:
      Nil{}

def Quiet.mark(a: Agent) -> Agent:
  match a:
    case Agent{t, i, p, k, rs}:
      Agent{t, i, p, k, Quiet.mark.r(rs)}

def Quiet.one.k(due: Bool, a: Agent, +t: String, +st: M.State, +now: Nat, q: Quieted) -> Quieted:
  match due q:
    case True{} Quieted{as, +cs}:
      Quieted{Quiet.mark(a) <> as, B.Quiet.act(t, now, Nat.add(M.State.seq(st), List.length(&2, M.Change, cs))) <> cs}
    case False{} Quieted{as, cs}:
      Quieted{a <> as, cs}

def Quiet.heard(rs: List<&2, ARun>) -> Nat:
  match rs:
    case ARun{_, _, _, n, _, _, _, _} <> _:
      n
    case Nil{}:
      0n

def Quiet.said(rs: List<&2, ARun>) -> Bool:
  match rs:
    case ARun{_, _, _, _, _, q, _, _} <> _:
      q
    case Nil{}:
      True{}

def Quiet.one(a: Agent, +st: M.State, +now: Nat, q: Quieted) -> Quieted:
  match a:
    case Agent{+t, i, p, k, +rs}:
      Quiet.one.k(B.Quiet.due(B.Hub.running(B.Hub.thread(st, t)), Quiet.heard(rs), now, Quiet.said(rs), M.Work.busy(st, t)), Agent{t, i, p, k, rs}, t, st, now, q)

def Quiet.all(as: List<&2, Agent>, +st: M.State, +now: Nat, q: Quieted) -> Quieted:
  match as:
    case Nil{}:
      q
    case a <> t:
      Quiet.all(t, st, now, Quiet.one(a, st, now, q))

def Hub.quiet.k(q: Quieted, h: Hub) -> IO(Hub):
  match q h:
    case Quieted{as, cs} Hub{st, f, ls, cl, _, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, List.reverse(&2, Agent, as), inbox, cfg, note}, B.Step{cs, Nil{}})

def Hub.quiet(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.quiet.k(Quiet.all(as, st, now, Quieted{Nil{}, Nil{}}), Hub{st, f, ls, cl, Nil{}, inbox, cfg, note})

# Beat: a thread's held progress lines land once B.Prog.gap() seconds have
# passed since its last write (B.Prog.beat), so the newest always shows
type Beated is Data:
  Beated{as: List<&2, Agent>, cs: List<&2, M.Change>}

def Beat.run.k(+p: B.PStep, +st: M.State, a: Agent, +t: String, +r: ARun, +now: Nat, q: Beated) -> Beated:
  match a q:
    case Agent{t0, i, pid, k, _} Beated{as, cs}:
      Beated{Agent{t0, i, pid, k, [ARun.prog.set(r, B.PStep.at(p), B.PStep.pend(p))]} <> as, List.append(&2, M.Change, B.Queue.changes(B.Prog.flush(st, t, now, B.PStep.flush(p))), cs)}

def Beat.none(a: Agent, q: Beated) -> Beated:
  match q:
    case Beated{as, cs}:
      Beated{a <> as, cs}

def Beat.one.k(m: Maybe<&2, ARun>, a: Agent, +st: M.State, +t: String, +now: Nat, q: Beated) -> Beated:
  match m:
    case Some{+r}:
      Beat.run.k(B.Prog.beat(ARun.prog_at(r), ARun.prog_last(r), now), st, a, t, r, now, q)
    case None{}:
      Beat.none(a, q)

def Beat.head(+rs: List<&2, ARun>) -> Maybe<&2, ARun>:
  List.head(&2, ARun, rs)

def Beat.one(a: Agent, +st: M.State, +now: Nat, q: Beated) -> Beated:
  match a:
    case Agent{+t, i, p, k, +rs}:
      Beat.one.k(Beat.head(rs), Agent{t, i, p, k, rs}, st, t, now, q)

def Beat.all(as: List<&2, Agent>, +st: M.State, +now: Nat, q: Beated) -> Beated:
  match as:
    case Nil{}:
      q
    case a <> t:
      Beat.all(t, st, now, Beat.one(a, st, now, q))

def Hub.beat.k(q: Beated, h: Hub) -> IO(Hub):
  match q h:
    case Beated{as, cs} Hub{st, f, ls, cl, _, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, List.reverse(&2, Agent, as), inbox, cfg, note}, B.Step{cs, Nil{}})

def Hub.beat(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.beat.k(Beat.all(as, st, now, Beated{Nil{}, Nil{}}), Hub{st, f, ls, cl, Nil{}, inbox, cfg, note})

def Hub.watched.k(i: Nat, +st: M.State, +thread: String, +id: String, +a: String, +b: String, +now: Nat) -> B.Step:
  match i:
    case 0n:
      B.Watch.launched(st, now, thread, id)
    case 1n:
      B.Watch.identified(st, now, thread, id, a)
    case _:
      B.Watch.end(st, now, thread, id, a, b)

# what a watcher reported, folded in (core's Watch.*)
def Hub.watched(p: M.State & Hub, +i: Nat, +thread: String, +id: String, +a: String, +b: String, +now: Nat) -> IO(Hub):
  (+st, h) = p
  Hub.step(h, Hub.watched.k(i, st, thread, id, a, b, now))

def Hub.release(p: M.State & Hub, +now: Nat) -> IO(Hub):
  (+st, h) = p
  do IO<Hub>:
    PS.Perf.set("hub.busy", U32.from_nat(M.Work.threads(st)))
    Hub.step(h, B.Rec.release(st, now))

def Hub.replied(p: M.State & Hub, +thread: String, +to: String, +text: String, +now: Nat) -> IO(Hub):
  (st, h) = p
  Hub.step(h, BH.Reply.send(st, now, thread, to, text))

def Hub.handle(h: Hub, m: Msg, +now: Nat) -> IO(Hub):
  match m:
    case AgentWrite{thread, line, gen}:
      Hub.agent_write(h, thread, line, gen)
    case UpdateCheck{}:
      Hub.update_check(h)
    case Mcp{thread, body, reply}:
      Hub.mcp.g(h, B.Tag.thread(thread), body, reply, now)
    case Announce{text}:
      Hub.note(h, text)
    case Join{client, out, since, origin, gen, sock}:
      Hub.join(h, client, out, since, origin, gen, sock, now)
    case JoinHere{client, out, gen}:
      Hub.join.here(h, client, out, gen, now)
    case Drained{client, gen, n, b}:
      Hub.drained(h, client, gen, n, b)
    case JoinMore{client, gen}:
      Hub.boot(h, client, gen)
    case Ping{client, p}:
      Hub.pong(h, client, p)
    case Leave{client}:
      Hub.leave(h, client, now)
    case Rpc{client, text}:
      Hub.rpc(h, client, text, now)
    case AgentLine{tag, line}:
      Hub.tagged(h, tag, line, now)
    case TurnPid{thread, pid, input, gen}:
      Hub.turn_pid(h, thread, pid, input, gen)
    case TurnDone{tag}:
      Hub.turn_done(h, tag)
    case Recover{}:
      Hub.recover(h, now)
    case AgentGone{thread, code, pid}:
      Hub.gone(h, thread, code, pid, now)
    case Tick{}:
      Hub.tick(h, now)
    case Heart{}:
      Hub.broadcast(h, DK.Alive.frame())
    case AutoView{thread, fs}:
      Hub.autoview(h, thread, fs)
    case ClaudePid{thread, pid, gen}:
      Hub.claude_pid(h, thread, pid, gen)
    case ClaudeFail{thread, gen, msg}:
      Hub.claude_fail(h, thread, gen, msg)
    case Push{client, text}:
      Hub.push(h, client, text)
    case PushBin{client, bs}:
      Hub.push.bin(h, client, bs)
    case TermOut{thread, data}:
      Hub.term_out(h, thread, data)
    case TermTo{c, key, co, ro, data}:
      Hub.term_to(h, c, key, co, ro, data)
    case ModelsFound{ms, mt}:
      Hub.models(h, ms, mt)
    case MachinesFound{mc}:
      Hub.dir.returned(h, mc)
    case LinkFound{lk}:
      Hub.link(h, lk)
    case Commit{cs}:
      Hub.step(h, B.Step{cs, Nil{}})
    case BotTick{tz}:
      Hub.bot_tick(h, tz, now)
    case BotsFound{peer, url, result}:
      Hub.bots_found(h, peer, url, result)
    case BotsRefresh{peer}:
      Hub.dir.refresh(h, peer)
    case BotHttp{kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply}:
      Hub.bot_http(h, kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply, now)
    case BotVerified{kind, arg, key, body, me, reply}:
      Hub.bot_verified(h, kind, arg, key, body, me, reply, now)
    case NewProject{_, root, name, id, reply}:
      Hub.newproj.made(h, root, name, id, reply, now)
    case Shot{text}:
      Hub.broadcast(h, text)
    case AttDir{thread, reply}:
      Hub.att_dir(h, thread, reply)
    case FarFeed{ls2, epoch}:
      Hub.far.fed(h, ls2, epoch)
    case FarPushed{link, ok, to}:
      Hub.far.pushed(h, link, ok, to)
    case FarResend{link}:
      Hub.far.resend(h, link)
    case FarPulled{link, since, code, body}:
      Hub.far.pulled(h, link, since, code, body)
    case FarReplied{client, id, link, code, body}:
      Hub.far.replied(h, client, id, link, code, body)
    case FarLoaded{link, name, text}:
      Hub.far.loaded(h, link, name, text)
    case FarHere{ans}:
      Hub.far.here(h, ans)
    case FarRetry{link}:
      Far.pull.here(h, link)
    case Replied{+thread, +to, +text}:
      Hub.replied(Hub.state(h), thread, to, text, now)
    case Release{}:
      Hub.release(Hub.state(h), now)
    case SpawnFailed{thread, gen, line}:
      Hub.spawn_failed(h, thread, gen, line, now)
    case AgentExited{thread, gen, code}:
      Hub.exited(h, thread, gen, code)
    case Silence{}:
      Hub.quiet(h, now)
    case Beat{}:
      Hub.beat(h, now)
    case WatchLaunched{thread, id}:
      Hub.watched(Hub.state(h), 0n, thread, id, "", "", now)
    case WatchIdent{thread, id, ident}:
      Hub.watched(Hub.state(h), 1n, thread, id, ident, "", now)
    case WatchEnded{thread, id, status, detail}:
      Hub.watched(Hub.state(h), 2n, thread, id, status, detail, now)
    # unwrapped by Hub.got, never nested
    case Bulk{_}:
      IO.pure(Hub, h)

# Two inboxes
# ------------
# The hub reads one channel (pri): clients' requests, joins and writers'
# reports, MCP calls and ticks come straight in. Everything else (agents'
# lines, jobs, the hub's own posts) goes to the hub's inbox, and Bulk.fwd
# passes it on only while it holds one of Bulk.room() tokens, one given
# back as each is handled: however fast an agent floods, a request (Stop)
# waits behind at most that many of its lines.

def Bulk.room() -> Nat:
  16n

def Bulk.fill(n: Nat, +tok: Chan(Unit)) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        ok : Bool <- Chan.send(Unit, tok, Unit{})
        Bulk.fill(k, tok)

def Bulk.moved(m: Maybe<&1, Msg>, +pri: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{msg}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, pri, Bulk{msg})
        k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

def Bulk.took(t: Maybe<&1, Unit>, +inbox: Chan(Msg), +pri: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match t:
    case Some{_}:
      IO.bind(Maybe<&1, Msg>, Unit, Chan.recv(Msg, inbox), m => Bulk.moved(m, pri, k))
    case None{}:
      IO.pure(Unit, Unit{})

def Bulk.fwd(fuel: Nat, +inbox: Chan(Msg), +pri: Chan(Msg), +tok: Chan(Unit)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, Unit>, Unit, Chan.recv(Unit, tok), t => Bulk.took(t, inbox, pri, u => Bulk.fwd(f, inbox, pri, tok)))

def Bulk.back(+tok: Chan(Unit), h: Hub, k: Hub -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Unit, tok, Unit{})
    k(h)

# each message's handling is timed as hub.<kind> (docs/perf.md)
def Hub.got.one(+msg: Msg, h: Hub, k: Hub -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- Now.nat()
    t0 : U32 <- PS.Perf.us()
    h2 : Hub <- Hub.handle(h, msg, now)
    t1 : U32 <- PS.Perf.lap("hub." ++ Msg.kind(msg), t0)
    k(h2)

def Hub.got(m: Maybe<&1, Msg>, h: Hub, +tok: Chan(Unit), k: Hub -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{Bulk{+msg}}:
      Hub.got.one(msg, h, h2 => Bulk.back(tok, h2, k))
    case Some{+msg}:
      Hub.got.one(msg, h, k)
    case None{}:
      Hub.close(h)

def Hub.loop(fuel: Nat, h: Hub, +pri: Chan(Msg), +tok: Chan(Unit)) -> IO(Unit):
  match fuel:
    case 0n:
      Hub.close(h)
    case 1n+f:
      IO.bind(Maybe<&1, Msg>, Unit, Chan.recv(Msg, pri), m => Hub.got(m, h, tok, h3 => Hub.loop(f, h3, pri, tok)))

# The web port was taken at start (often only for a moment, by the process
# this one replaces): try it again every few seconds, and once it is ours,
# start what Main.serve starts beside the hub, so a restart never leaves the
# hub unreachable from other machines and phones
def Listen.up(l: Listener, +web: String, +inbox: Chan(Msg), +cfg: Cfg, +addr: String) -> IO(Unit):
  do IO<Unit>:
    Log.info("web server on: " ++ addr)
    IO.spawn(Unit, Accept.loop(Fuel.forever(), l, 1, web, inbox, True{}, Net.token(Cfg.net(cfg)), ""))
    Tailnet.start(Cfg.net(cfg), Cfg.port(cfg), web, inbox)
    Machines.start(inbox, Cfg.port(cfg))

def Listen.got(r: Result<&1, &1, U32 & String, Listener>, +web: String, +inbox: Chan(Msg), +cfg: Cfg, +addr: String, k: Unit -> IO(Unit)) -> IO(Unit):
  match r:
    case Done{l}:
      Listen.up(l, web, inbox, cfg, addr)
    case Fail{_}:
      k(Unit{})

def Listen.retry(fuel: Nat, +web: String, +inbox: Chan(Msg), +cfg: Cfg, +addr: String) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(2000)
        l : Result<&1, &1, U32 & String, Listener> <- H.Net.listen(Cfg.host(cfg), Cfg.port(cfg))
        Listen.got(l, web, inbox, cfg, addr, _ => Listen.retry(f, web, inbox, cfg, addr))

# without the web server (its port was taken): hub and ticker only
def Main.headless(h: Hub, +inbox: Chan(Msg), +cfg: Cfg, +tok: Chan(Unit), front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, Ticker.loop(Fuel.forever(), inbox))
    IO.spawn(Unit, Beat.loop(Fuel.forever(), inbox))
    IO.spawn(Unit, Heart.loop(Fuel.forever(), inbox))
    Refresh.start(inbox, cfg)
    IO.spawn(Unit, Hub.loop(Fuel.forever(), h, inbox, tok))
    Upgrade.start(cfg, inbox)
    front(inbox)

def Main.serve(l: Listener, h: Hub, +web: String, +inbox: Chan(Msg), +cfg: Cfg, +tok: Chan(Unit), front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, Accept.loop(Fuel.forever(), l, 1, web, inbox, True{}, Net.token(Cfg.net(cfg)), ""))
    Tailnet.start(Cfg.net(cfg), Cfg.port(cfg), web, inbox)
    IO.spawn(Unit, Ticker.loop(Fuel.forever(), inbox))
    IO.spawn(Unit, Beat.loop(Fuel.forever(), inbox))
    IO.spawn(Unit, Heart.loop(Fuel.forever(), inbox))
    Refresh.start(inbox, cfg)
    Machines.start(inbox, Cfg.port(cfg))
    IO.spawn(Unit, Hub.loop(Fuel.forever(), h, inbox, tok))
    Upgrade.start(cfg, inbox)
    front(inbox)

def Main.listened(r: Result<&1, &1, U32 & String, Listener>, h: Hub, +web: String, +inbox: Chan(Msg), +addr: String, need: Bool, +cfg: Cfg, +tok: Chan(Unit), front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  match r need:
    case Done{l} _:
      do IO<Unit>:
        IO.print("Backplane listening on http://" ++ addr)
        Main.serve(l, h, web, inbox, cfg, tok, front)
    case Fail{e} True{}:
      Main.failed(e, h, addr)
    case Fail{_} False{}:
      do IO<Unit>:
        Log.info("web server off: " ++ addr ++ " is taken; trying again every 2 s")
        IO.spawn(Unit, Listen.retry(Fuel.forever(), web, inbox, cfg, addr))
        Main.headless(h, inbox, cfg, tok, front)

# One hub per home
# ----------------
# Two hubs on one home (a window opened while `--headless` ran for the same
# folder) each kept a state of their own over the same log: a message sent
# in the window never reached the web or the phones, and theirs never the
# window. A hub notes its pid and port in <home>/hub.lock as it starts; a
# later start that finds that hub alive joins it (the window) or leaves it
# be (`--headless`): src/app/main.bend's Start.run.

def Lock.path(+home: String) -> String:
  home ++ "/hub.lock"

# the shell's parent is this process, so $PPID is the hub's pid
def Lock.write(+home: String, +port: U32) -> IO(Unit):
  do IO<Unit>:
    r : P.Ran <- P.Proc.run("sh", ["-c", "echo \"$PPID $1\" > \"$2\"", "sh", U32.show(port), Lock.path(home)], "/")
    return Unit{}

# "<pid> <port>" of another live Backplane holding the lock (the same
# program as this one, by its process name), else ""
def Lock.find.sh() -> String:
  "f=$1/hub.lock; [ -f \"$f\" ] || exit 0; read pid port < \"$f\"; [ -n \"$pid\" ] && [ \"$pid\" != \"$PPID\" ] || exit 0; kill -0 \"$pid\" 2>/dev/null || exit 0; [ \"$(ps -p \"$pid\" -o comm= 2>/dev/null)\" = \"$(ps -p \"$PPID\" -o comm= 2>/dev/null)\" ] && echo \"$pid $port\""

def Lock.out(r: P.Ran) -> String:
  match r:
    case P.Ran{0, +out}:
      String.trim(out)
    case _:
      ""

def Lock.find(+home: String) -> IO(String):
  IO.bind(P.Ran, String, P.Proc.run("sh", ["-c", Lock.find.sh(), "sh", home], "/"), r => IO.pure(String, Lock.out(r)))

def Lock.word(+held: String, +i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(held, ' '), i), "")

# Browser frames
# --------------

def Shot.fwd.got(m: Maybe<&1, String>, +inbox: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{+line}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Shot{BR.Browser.shot(line)})
        k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

# page-frame events from the browser, to the hub
def Shot.fwd(fuel: Nat, +ev: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, ev), m => Shot.fwd.got(m, inbox, u => Shot.fwd(f, ev, inbox)))

def Main.opened(r: Result<&1, &1, U32 & String, File>, st: M.State, ls: List<&2, String>, cfg: Cfg, need: Bool, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  match r cfg:
    case Done{f} Cfg{+home, +web, +host, +port, +pr, +ds, +v, nt0}:
      do IO<Unit>:
        Lock.write(home, port)
        +inbox : Chan(Msg) <- Chan.new(Msg, 4096)
        +pri : Chan(Msg) <- Chan.new(Msg, 4096)
        +tok : Chan(Unit) <- Chan.new(Unit, 32)
        Bulk.fill(Bulk.room(), tok)
        IO.spawn(Unit, Bulk.fwd(Fuel.forever(), inbox, pri, tok))
        rc : Bool <- Chan.send(Msg, inbox, Recover{})
        +bq : Chan(BR.BMsg) <- Chan.new(BR.BMsg, 256)
        bexe : String <- Browser.exe()
        # page-frame events from the browser, broadcast by the hub as {"t":"shot",...}
        +bev : Chan(String) <- Chan.new(String, 256)
        IO.spawn(Unit, Shot.fwd(Fuel.forever(), bev, inbox))
        IO.spawn(Unit, BR.Browser.loop(Fuel.forever(), bq, bev, BR.Br.at(bexe, home)))
        +pq : Chan(PK.PMsg) <- Chan.new(PK.PMsg, 256)
        IO.spawn(Unit, PK.Park.loop(Fuel.forever(), pq, Nil{}))
        +tq : Chan(TM.TMsg) <- Chan.new(TM.TMsg, 1024)
        +to : Chan(TM.TOut) <- Chan.new(TM.TOut, 4096)
        shell : String <- Env.get("SHELL", "/bin/bash")
        IO.spawn(Unit, TM.Term.start(tq, shell, home, to))
        IO.spawn(Unit, Term.fwd(Fuel.forever(), to, inbox))
        +vq : Chan(PV.PMsg) <- Chan.new(PV.PMsg, 1024)
        +vo : Chan(PV.POut) <- Chan.new(PV.POut, 1024)
        IO.spawn(Unit, PV.Pv.loop(Fuel.forever(), vq, PV.Pv.empty(), vo, home ++ "/plot"))
        IO.spawn(Unit, Plot.fwd(Fuel.forever(), vo, inbox))
        +nt : Net = Net.with_pv(Net.with_tm(Net.with_pk(Net.with_br(nt0, bq), pq), tq), vq)
        l : Result<&1, &1, U32 & String, Listener> <- H.Net.listen(host, port)
        Main.listened(l, Hub{st, f, ls, Nil{}, Nil{}, inbox, Cfg{home, web, host, port, pr, ds, v, nt}, ""}, web, pri, host ++ ":" ++ U32.show(port), need, Cfg{home, web, host, port, pr, ds, v, nt}, tok, front)
    case Fail{e} _:
      Main.nolog(e)

def Main.torn.k(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, U32 & String, File>):
  (f, res) = r
  match res:
    case Done{_}:
      IO.pure(Result<&1, &1, U32 & String, File>, Done{f})
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, File>, Fail{e})

# a log whose last line was torn by a crash ends without a newline: the
# next line starts on its own (ST.Store.tail_fix)
def Main.torn.w(none: Bool, f: File, +fix: String) -> IO(Result<&1, &1, U32 & String, File>):
  match none:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, File>, Done{f})
    case False{}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Result<&1, &1, U32 & String, File>, File.write(f, fix), Main.torn.k)

def Main.torn(r: Result<&1, &1, U32 & String, File>, +fix: String) -> IO(Result<&1, &1, U32 & String, File>):
  match r:
    case Done{f}:
      Main.torn.w(String.is_empty(fix), f, fix)
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, File>, Fail{e})

# replay the log, start the hub (and the web server), then run front
# with the hub's inbox; `need` makes a taken web port fatal
def Main.boot(cfg: Cfg, need: Bool, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  match cfg:
    case Cfg{+home, w, h, p, pr, ds, v, nt}:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(home)
        t0 : U32 <- PS.Perf.us()
        +bs : List<&2, U32> <- Files.read(Store.path(home))
        t1 : U32 <- PS.Perf.span("boot.read", t0)
        +ld : ST.Loaded = ST.Store.load(Store.lines(bs), ST.Loaded{M.State.empty(), Nil{}})
        +st : M.State = ST.Loaded.st(ld)
        +ls : List<&2, String> = ST.Loaded.wire(ld)
        t2 : U32 <- PS.Perf.span("boot.replay", t1)
        Log.info("replayed " ++ Nat.show(List.length(&2, String, ls)) ++ " changes from " ++ Store.path(home))
        f0 : Result<&1, &1, U32 & String, File> <- File.open(Store.path(home), "a")
        f : Result<&1, &1, U32 & String, File> <- Main.torn(f0, ST.Store.tail_fix(bs))
        tok : String <- Token.load(home)
        +mc : String <- Files.text(Models.cache(home))
        +bc : String <- BN.Bf.text(BN.Bn.cache(home))
        +off : String <- Env.get("BACKPLANE_NO_UPDATE", "")
        +ai : String <- Env.get("APPIMAGE", "")
        Main.opened(f, st, ls, Cfg.with_managed(Cfg.with_models(Cfg.with_bn(Cfg.with_token(Cfg{home, w, h, p, pr, ds, v, nt}, tok), BN.Bn.with_dir(BN.Bn.empty(), BN.Bn.cache.load(bc, BO.World.peers(M.State.bots(st))))), BT.Cache.json(mc), BT.Cache.text(mc)), SV.Chan.managed(off, ai)), need, front)
