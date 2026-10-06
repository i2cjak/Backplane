import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./hub.bend as B
import ./far.bend as FR
import ./refs.bend as RF
import ./mcp.bend as MC
import ./xref.bend as XR
import ./handoff.bend as HD
import ./bothub.bend as BH

# Agents across machines: the thread tools reaching another machine
# ------------------------------------------------------------------
# An agent's thread_send, thread_wait, thread_interrupt, thread_update,
# thread_list, thread_launch and project_list may name a machine of the
# owner's (a thread or project id elsewhere, "<link>~<id>", or a `machine`
# argument). The hub that hears the call does not run it: it sends it to
# the owning hub as the signed request `mcp.call` (POST /far/rpc, the path
# clients use for threads elsewhere) and answers the agent with what comes
# back, its ids made `<link>~<id>` so the agent can use them in its next
# call. The owner runs the same defs as for its own agents (mcp.bend), but
# only on what it shares with the owner's machines (Fr.thread.shared) and
# only the tools in Fm.names: a request from a machine that is not the
# owner's never gets this far (the route checks Far.own), and one for a
# thread this machine does not share is answered with an error and no
# change. thread_read is the mirror's (xref.bend), thread_wait polls its
# owner through thread_wait_now.

# the tools a remote agent may call here (thread_wait is its poll)
def Fm.names() -> List<&2, String>:
  ["thread_send", "thread_wait_now", "thread_interrupt", "thread_update", "thread_list", "thread_launch", "project_list", "machine_list"]

# a request from another machine: `mcp.call` of one of the tools the owner's
# machines may call here (machine_list is each hub's own answer)
def Fm.is(+o: J.Json) -> Bool:
  String.eq(J.Json.get_str(o, "m", ""), "mcp.call")

def Fm.remote(+tool: String) -> Bool:
  Nat.is_lt(C.Codec.pos(Fm.names(), tool), 7n)

def Fm.allowed(+o: J.Json) -> Bool:
  Bool.and(Fm.is(o), Fm.remote(J.Json.get_str(J.Json.get_obj(o, "p"), "tool", "")))

# what a hub takes at /far/rpc: a client's request about a shared thing, or
# a remote agent's tool call
def Fm.permit(+s: M.State, +o: J.Json) -> Bool:
  Bool.or(FR.Fr.allowed(s, o), Fm.allowed(o))

# On the owning hub
# -----------------

def Fm.say(ok: Bool, r: MC.Res) -> MC.Res:
  match ok:
    case True{}:
      r
    case False{}:
      MC.Res.fail("that thread is not shared with you (it is not on this machine)")

def Fm.keep(ok: Bool, j: J.Json, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match ok:
    case True{}:
      j <> rest
    case False{}:
      rest

def Fm.projects(ps: List<&2, M.Project>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case M.Project{+i, +t, +r, _, rm} <> rest:
      Fm.keep(Bool.not(rm), J.Json.obj([J.KV{"id", J.Str{i}}, J.KV{"name", J.Str{t}}, J.KV{"folder", J.Str{r}}]), Fm.projects(rest))

def Fm.proj.rows(+s: M.State) -> List<&2, J.Json>:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _, _, _}:
      Fm.projects(Map.values(&2, M.Project, ps))

def Fm.list.k(all: Bool, +s: M.State, +pid: String, ts: List<&2, M.Thread>) -> MC.Res:
  match all:
    case True{}:
      MC.Res.ok(J.Json.obj([J.KV{"threads", J.Json.arr(List.take(&2, J.Json, MC.Mcp.threads(ts, "*"), 200n))}]))
    case False{}:
      Bool.pick(MC.Res, String.is_empty(pid), MC.Res.fail("no such project here (project_list shows them)"),
        MC.Res.ok(J.Json.obj([J.KV{"threads", J.Json.arr(List.take(&2, J.Json, MC.Mcp.threads(ts, pid), 200n))}])))

# its threads, optionally those of the project the name or id picks
def Fm.list(+s: M.State, +project: String) -> MC.Res:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _, _}:
      Fm.list.k(String.is_empty(String.trim(project)), s, MC.Mcp.project.find(s, project), Map.values(&2, M.Thread, ts))

def Fm.call.k(i: Nat, +s: M.State, +now: Nat, +from: String, +a: J.Json, +id: String, +ok: Bool) -> MC.Res:
  match i:
    case 0n:
      Fm.say(ok, MC.Mcp.send.k(ok, s, now, from, id, J.Json.get_str(a, "text", ""), J.Json.get_str(a, "mode", "")))
    case 1n:
      Fm.say(ok, MC.Mcp.wait.k(ok, s, id))
    case 2n:
      Fm.say(ok, MC.Mcp.interrupt.k(ok, B.Hub.running(B.Hub.thread(s, id)), s, now, id))
    case 3n:
      Fm.say(ok, MC.Mcp.update.k(ok, String.is_empty(String.trim(J.Json.get_str(a, "title", ""))), s, now, id, String.trim(J.Json.get_str(a, "title", ""))))
    case 4n:
      Fm.list(s, J.Json.get_str(a, "project", ""))
    case 5n:
      MC.Mcp.launch(s, now, "", a)
    case 6n:
      MC.Res.ok(J.Json.obj([J.KV{"projects", J.Json.arr(Fm.proj.rows(s))}]))
    case _:
      MC.Res.fail("unknown tool")

def Fm.call(+s: M.State, +now: Nat, +tool: String, +from: String, +a: J.Json) -> MC.Res:
  Fm.call.k(C.Codec.pos(Fm.names(), tool), s, now, from, a, J.Json.get_str(a, "threadId", ""), FR.Fr.thread.shared(s, J.Json.get_str(a, "threadId", "")))

def Fm.serve.k(r: MC.Res, +client: U32) -> B.Step:
  match r:
    case MC.Res{ok, body, B.Step{cs, os}}:
      B.Step{cs, B.Send{client, J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{"0"}}, J.KV{"ok", J.Flag{True{}}},
        J.KV{"mcp", J.Json.obj([J.KV{"ok", J.Flag{ok}}, J.KV{"body", body}])}]))} <> os}

# the step answering a remote agent's call (its reply first, which is the
# one the route sends back)
def Fm.serve(+s: M.State, +now: Nat, +client: U32, +o: J.Json) -> B.Step:
  Fm.serve.k(Fm.call(s, now, J.Json.get_str(J.Json.get_obj(o, "p"), "tool", ""), J.Json.get_str(J.Json.get_obj(o, "p"), "from", ""),
    J.Json.get_obj(J.Json.get_obj(o, "p"), "args")), client)

# On the calling hub
# ------------------

# ids that come back from a machine, named as here
def Fm.id.key(+k: String) -> Bool:
  Bool.or(String.eq(k, "id"), Bool.or(String.eq(k, "threadId"), String.eq(k, "project")))

def Fm.far.json(j: J.Json, +link: String) -> J.Json:
  match j:
    case J.Obj{fs}:
      J.Obj{Fm.far.json(fs, link)}
    case J.Arr{xs}:
      J.Arr{Fm.far.json(xs, link)}
    case J.Item{h, t}:
      J.Item{Fm.far.json(h, link), Fm.far.json(t, link)}
    case J.Field{+k, J.Str{+v}, t}:
      J.Field{k, J.Str{Bool.pick(String, Fm.id.key(k), FR.Fr.opt(link, v), v)}, Fm.far.json(t, link)}
    case J.Field{k, v, t}:
      J.Field{k, Fm.far.json(v, link), Fm.far.json(t, link)}
    case x:
      x

# the call's arguments with the ids of that machine made its own
def Fm.args.local(fs: J.Json, +link: String) -> J.Json:
  match fs:
    case J.Field{+k, J.Str{+v}, t}:
      J.Field{k, J.Str{Bool.pick(String, Bool.and(Bool.or(String.eq(k, "threadId"), String.eq(k, "project")), String.eq(FR.Fr.link(v), link)), FR.Fr.local(v), v)}, Fm.args.local(t, link)}
    case J.Field{k, v, t}:
      J.Field{k, v, Fm.args.local(t, link)}
    case x:
      x

def Fm.request(+link: String, +tool: String, +from: String, a: J.Json) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Num{"0"}}, J.KV{"m", J.Str{"mcp.call"}},
    J.KV{"p", J.Json.obj([J.KV{"tool", J.Str{tool}}, J.KV{"from", J.Str{from}}, J.KV{"args", J.Obj{Fm.args.local(FR.Fr.obj.fields(a), link)}}])}]))

# what the hub does with a tool call
type Plan is Data:
  PHere{}
  PAnswer{r: MC.Res}
  PFar{link: String, body: String}

# one machine as the agent sees it
def Fm.machine(+i: FR.In) -> J.Json:
  J.Json.obj([J.KV{"machine", J.Str{FR.In.name.of(i)}}, J.KV{"link", J.Str{FR.In.link(i)}},
    J.KV{"state", J.Str{Bool.pick(String, FR.In.away(i), "away", "here")}},
    J.KV{"projects", J.Json.arr(Fm.proj.rows(XR.Xref.state(i)))}])

def Fm.machines.go(ins: List<&2, FR.In>) -> List<&2, J.Json>:
  match ins:
    case Nil{}:
      Nil{}
    case +i <> t:
      Fm.machine(i) <> Fm.machines.go(t)

# this machine and the owner's others, each with its projects (ids a
# thread_launch `project` takes, threads in each by thread_list `machine`)
def Fm.machines(+s: M.State, ins: List<&2, FR.In>) -> MC.Res:
  MC.Res.ok(J.Json.obj([J.KV{"machines", J.Json.arr(J.Json.obj([J.KV{"machine", J.Str{"this"}}, J.KV{"state", J.Str{"here"}}, J.KV{"projects", J.Json.arr(Fm.proj.rows(s))}]) <> Fm.machines.go(ins))},
    J.KV{"note", J.Str{"Name a machine in thread_list and thread_launch (`machine`), or use the ids shown here (<link>~<id>) with thread_send, thread_read, thread_wait and thread_interrupt."}}]))

# the machine word a call names ("" for none: it is this hub's)
def Fm.word(i: Nat, +a: J.Json) -> String:
  Bool.pick(String, Nat.is_lt(i, 4n),
    Bool.pick(String, FR.Fr.is(J.Json.get_str(a, "threadId", "")), FR.Fr.link(J.Json.get_str(a, "threadId", "")), ""),
    Bool.pick(String, FR.Fr.is(J.Json.get_str(a, "project", "")), FR.Fr.link(J.Json.get_str(a, "project", "")), J.Json.get_str(a, "machine", "")))

def Fm.plan.i(m: Maybe<&2, FR.In>, +word: String, +tool: String, +thread: String, a: J.Json) -> Plan:
  match m:
    case Some{+i}:
      Bool.pick(Plan, FR.In.away(i), PAnswer{MC.Res.fail("the machine " ++ FR.In.name.of(i) ++ " is away; try again when it is back")},
        PFar{FR.In.link(i), Fm.request(FR.In.link(i), tool, FR.Fr.id(FR.In.link(i), thread), a)})
    case None{}:
      PAnswer{MC.Res.fail("no machine of yours called " ++ word ++ " is linked here (machine_list shows them)")}

def Fm.plan.w(+word: String, +ins: List<&2, FR.In>, +tool: String, +thread: String, a: J.Json) -> Plan:
  Bool.pick(Plan, String.is_empty(word), PHere{}, Fm.plan.i(XR.Xref.pick(ins, RF.Slug.of(word)), word, tool, thread, a))

def Fm.plan.k(i: Nat, +s: M.State, +ins: List<&2, FR.In>, +tool: String, +thread: String, +a: J.Json) -> Plan:
  match i:
    case 8n:
      PHere{}
    case 7n:
      PAnswer{Fm.machines(s, ins)}
    case _:
      Fm.plan.w(Fm.word(i, a), ins, tool, thread, a)

# where a tools/call goes: here (the usual run), answered by the hub, or
# to the machine it names
def Fm.plan.o(+o: J.Json, +s: M.State, +ins: List<&2, FR.In>, +thread: String) -> Plan:
  Bool.pick(Plan, String.eq(J.Json.get_str(o, "method", ""), "tools/call"),
    Fm.plan.k(C.Codec.pos(Fm.names(), J.Json.get_str(J.Json.get_obj(o, "params"), "name", "")), s, ins, J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), thread, J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments")),
    PHere{})

def Fm.answer.r(m: Maybe<&2, J.Json>, +ok: Bool, +err: String, +link: String) -> MC.Res:
  match m:
    case Some{+b}:
      MC.Res{ok, Fm.far.json(b, link), B.Step.none()}
    case None{}:
      MC.Res.fail(err)

# the JSON-RPC answer from a machine's reply (code 0: no answer at all)
def Fm.answer.b(m: Maybe<&2, J.Json>, +id: J.Json, +link: String) -> String:
  match m:
    case Some{+r}:
      XR.Xref.out(MC.Mcp.reply(id, Fm.answer.r(J.Json.get(J.Json.get_obj(r, "mcp"), "body"), J.Json.get_bool(J.Json.get_obj(r, "mcp"), "ok", False{}), J.Json.get_str(r, "error", "that machine gave no answer"), link)))
    case None{}:
      XR.Xref.out(MC.Mcp.reply(id, MC.Res.fail("that machine's answer was not understood")))

def Fm.answer(+id: J.Json, +link: String, +code: Nat, +body: String) -> String:
  Bool.pick(String, Nat.is_eq(code, 200n), Fm.answer.b(J.Json.parse(body), id, link),
    XR.Xref.out(MC.Mcp.reply(id, MC.Res.fail(Bool.pick(String, Nat.is_eq(code, 0n), "that machine is away or did not answer", "that machine did not take it: " ++ String.take(body, 160n))))))

# The agent's prompt
# ------------------
# which machines are linked as the agent starts ("" for none; how to use
# them is in the orchestration paragraph)

def Fm.nm(+i: FR.In) -> String:
  Bool.pick(String, String.is_empty(FR.In.name.of(i)), FR.In.link(i), FR.In.name.of(i)) ++ Bool.pick(String, FR.In.away(i), " (away)", "")

def Fm.nms(ins: List<&2, FR.In>) -> List<&2, String>:
  match ins:
    case Nil{}:
      Nil{}
    case +i <> t:
      Fm.nm(i) <> Fm.nms(t)

def Fm.prompt.k(ns: List<&2, String>) -> String:
  match ns:
    case Nil{}:
      ""
    case +x <> +t:
      "<machines>The person's other machines linked to this one: " ++ String.join(x <> t, ", ") ++ ". machine_list shows their projects and ids.</machines>"

def Fm.prompt(ins: List<&2, FR.In>) -> String:
  Fm.prompt.k(Fm.nms(ins))

# /give elsewhere
# ---------------
# `/give >machine:slug` hands the conversation to a thread on another
# machine (thread_send, queued there), and `/give %machine:project` makes a
# new thread in that machine's project with it (thread_launch): the same
# signed request an agent's call becomes (PFar). Words naming something
# here are the hub's own (bothub.bend's Give.*).

# a project on another machine: `%machine:name`
def Fm.pword(+w: String) -> Bool:
  Bool.and(String.eq(RF.Refs.kind(w), "project"), Bool.and(String.contains(w, ":"), Bool.not(String.is_empty(RF.Slug.of(RF.Refs.x.m(String.drop(w, 1n)))))))

def Fm.give.thread(m: Maybe<&2, RF.Cand>, +link: String, +src: String, +hand: String) -> List<&2, Plan>:
  match m:
    case Some{RF.Cand{+id, _, _, _}}:
      [PFar{link, Fm.request(link, "thread_send", FR.Fr.id(link, src), J.Json.obj([J.KV{"threadId", J.Str{id}}, J.KV{"text", J.Str{hand}}, J.KV{"mode", J.Str{"queue"}}]))}]
    case None{}:
      Nil{}

def Fm.give.t(m: Maybe<&2, FR.In>, +slug: String, +src: String, +hand: String) -> List<&2, Plan>:
  match m:
    case Some{+i}:
      Fm.give.thread(List.head(&2, RF.Cand, List.sort(~RF.Cand, ~RF.Cand.before, RF.Refs.t.hits(XR.Xref.threads(XR.Xref.state(i)), slug, ""))), FR.In.link(i), src, hand)
    case None{}:
      Nil{}

def Fm.give.p(m: Maybe<&2, FR.In>, +name: String, +src: String, +hand: String, +title: String) -> List<&2, Plan>:
  match m:
    case Some{+i}:
      [PFar{FR.In.link(i), Fm.request(FR.In.link(i), "thread_launch", FR.Fr.id(FR.In.link(i), src), J.Json.obj([J.KV{"project", J.Str{name}}, J.KV{"prompt", J.Str{hand}}, J.KV{"title", J.Str{title}}]))}]
    case None{}:
      Nil{}

def Fm.give.word(+w: String, +ins: List<&2, FR.In>, +src: String, +hand: String, +title: String) -> List<&2, Plan>:
  Bool.pick(List<&2, Plan>, XR.Xref.named(w),
    Fm.give.t(XR.Xref.pick(ins, RF.Slug.of(RF.Refs.x.m(String.drop(w, 1n)))), RF.Slug.of(RF.Slug.take(RF.Refs.x.q(String.drop(w, 1n)))), src, hand),
    Bool.pick(List<&2, Plan>, Fm.pword(w),
      Fm.give.p(XR.Xref.pick(ins, RF.Slug.of(RF.Refs.x.m(String.drop(w, 1n)))), RF.Refs.x.q(String.drop(w, 1n)), src, hand, title),
      Nil{}))

def Fm.give.words(ws: List<&2, String>, +ins: List<&2, FR.In>, +src: String, +hand: String, +title: String) -> List<&2, Plan>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      List.append(&2, Plan, Fm.give.word(w, ins, src, hand, title), Fm.give.words(t, ins, src, hand, title))

def Fm.give.go(+s: M.State, +ins: List<&2, FR.In>, +src: String, +text: String) -> List<&2, Plan>:
  Fm.give.words(RF.Refs.sigil.words(text), ins, src, String.take(HD.Hand.give(B.Hub.entries(s), src, HD.Hand.title(B.Hub.thread(s, src)), BH.Give.note(text)), 100000n), HD.Hand.title(B.Hub.thread(s, src)))

# the requests a `bots.give` makes of other machines (none for any other
# request, or a text that names nothing elsewhere: a cheap test first)
def Fm.give(+s: M.State, +ins: List<&2, FR.In>, +o: J.Json) -> List<&2, Plan>:
  Bool.pick(List<&2, Plan>, Bool.and(String.eq(J.Json.get_str(o, "m", ""), "bots.give"), String.contains(J.Json.get_str(J.Json.get_obj(o, "p"), "text", ""), ":")),
    Fm.give.go(s, ins, J.Json.get_str(J.Json.get_obj(o, "p"), "thread", ""), J.Json.get_str(J.Json.get_obj(o, "p"), "text", "")), Nil{})

# whether the text also names something here (bothub.bend's Give.*)
def Fm.give.here(+s: M.State, +o: J.Json) -> Bool:
  Bool.not(List.is_empty(&2, RF.Hit, RF.Refs.found(s, J.Json.get_str(J.Json.get_obj(o, "p"), "thread", ""), J.Json.get_str(J.Json.get_obj(o, "p"), "text", ""))))

# a plan's name (laws and logs)
def Fm.plan.name(p: Plan) -> String:
  match p:
    case PHere{}:
      "here"
    case PAnswer{_}:
      "answer"
    case PFar{_, _}:
      "far"
