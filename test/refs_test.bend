import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/codec.bend as CD
import ../src/core/hub.bend as B
import ../src/core/bot.bend as BT
import ../src/core/bothub.bend as BH
import ../src/core/refs.bend as RF
import ../src/core/client.bend as U
import ../src/core/far.bend as FR
import ../src/core/xref.bend as XR

# References in a message (refs.bend): slugs, what the composer offers for
# `@bot`, `>thread`, `%project` and `#room`, what a sent message names, the
# agent's block, the bots and rooms a mention reaches, and summaries.

def yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def tags(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case c <> t:
      J.Json.get_str(CD.Change.encode(c), "$", "") ++ " " ++ tags(t)

def outs(os: List<&2, B.Out>) -> String:
  match os:
    case Nil{}:
      ""
    case B.Git{_, _, job, id, _, kind, _} <> t:
      "git:" ++ job ++ ":" ++ id ++ ":" ++ kind ++ " " ++ outs(t)
    case _ <> t:
      outs(t)

def st.tags(st: B.Step) -> String:
  match st:
    case B.Step{cs, os}:
      tags(cs) ++ "| " ++ outs(os)

def ch.tags(st: B.Step) -> String:
  match st:
    case B.Step{cs, _}:
      tags(cs) ++ "| "

def run(s: M.State, st: B.Step) -> M.State:
  match st:
    case B.Step{cs, _}:
      M.State.replay(cs, s)

def req(+m: String, +p: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse("{\"id\":1,\"m\":\"" ++ m ++ "\",\"p\":" ++ p ++ "}"), J.Null{})

def made(+s: M.State, +now: Nat, +m: String, +p: String) -> M.State:
  run(s, BH.Bots.request(s, now, 1, req(m, p)))

def miso(+s: M.State) -> String:
  BT.Bot.id(Maybe.default(&2, BT.Bot, List.head(&2, BT.Bot, BT.World.bots(M.State.bots(s))), BT.Bot.blank("")))

def changes(st: B.Step) -> List<&2, M.Change>:
  match st:
    case B.Step{cs, _}:
      cs

def extra(+bot: String) -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "Backplane Bend", "/src/bend", 900n},
   M.ProjectCreated{"p2", "Board rev B", "/src/board", 901n},
   M.ThreadCreated{"t100-7", "p1", "Fix perf lag", M.Local{}, "", "", "claude", "", 1002n},
   M.ThreadCreated{"t100-8", "p1", "Refs popup", M.Local{}, "", "", "claude", "", 1003n},
   M.ThreadCreated{"t100-9", "p2", "Fix perf lag", M.Local{}, "", "", "claude", "", 1004n},
   M.SettingSet{"summary.t100-7", "Tiles redraw only what changed", 1005n},
   M.RoomSet{"r1", "Hardware talk", bot, 1006n}]

def log.k(+c1: List<&2, M.Change>, +s1: M.State) -> List<&2, M.Change>:
  List.append(&2, M.Change, c1, List.append(&2, M.Change, changes(BH.Bots.request(s1, 1001n, 1, req("bots.create", "{\"name\":\"Tofu\",\"provider\":\"codex\"}"))), extra(miso(s1))))

# the whole log: two bots, two projects, three threads, a summary, a room
def log() -> List<&2, M.Change>:
  +c1 = changes(BH.Bots.request(M.State.empty(), 1000n, 1, req("bots.create", "{\"name\":\"Miso\",\"provider\":\"claude\",\"persona\":\"Keeps the parts library tidy\"}")))
  log.k(c1, M.State.replay(c1, M.State.empty()))

def base() -> M.State:
  M.State.replay(log(), M.State.empty())

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def rows(rs: List<&2, U.SkillRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case U.SkillRow{n, _, _} <> t:
      n ++ "," ++ rows(t)

def descs(rs: List<&2, U.SkillRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case U.SkillRow{_, a, _} <> t:
      a ++ "|" ++ descs(t)

def lit(rs: List<&2, U.SkillRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case U.SkillRow{n, _, True{}} <> t:
      "[" ++ n ++ "]," ++ lit(t)
    case U.SkillRow{n, _, False{}} <> t:
      n ++ "," ++ lit(t)

def names(cs: List<&2, RF.Cand>) -> String:
  match cs:
    case Nil{}:
      ""
    case RF.Cand{w, _, _, _} <> t:
      w ++ "," ++ names(t)

def abouts(cs: List<&2, RF.Cand>) -> String:
  match cs:
    case Nil{}:
      ""
    case RF.Cand{_, a, _, _} <> t:
      a ++ "|" ++ abouts(t)

def hits(hs: List<&2, RF.Hit>) -> String:
  match hs:
    case Nil{}:
      ""
    case RF.Hit{k, i, _, w} <> t:
      k ++ ":" ++ i ++ ":" ++ w ++ " " ++ hits(t)

# a linked machine, "laptop", and the bots it reports
def dir() -> String:
  "[{\"name\":\"Kit\",\"peer\":\"pk\",\"peerName\":\"laptop\",\"state\":\"idle\",\"seen\":1009},{\"name\":\"Old Bot\",\"peer\":\"pk\",\"peerName\":\"laptop\"}]"

def linked(+s: M.State) -> M.State:
  M.State.replay([M.PeerSet{"pk", "laptop", "http://laptop:3787", False{}, 1000n}], s)

def fars(+s: M.State) -> List<&2, RF.Far>:
  RF.Refs.fars(dir(), BT.World.peers(M.State.bots(s)))

def far.offer(+s: M.State, +w: String) -> List<&2, RF.Cand>:
  RF.Refs.offer.with(s, "t100-8", 1010n, w, fars(s))

def fx(os: List<&2, B.Out>) -> String:
  match os:
    case Nil{}:
      ""
    case B.BotFx{k, a, b, c} <> t:
      k ++ ":" ++ a ++ ":" ++ b ++ ":" ++ J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(c), J.Null{}), "to", "") ++ " " ++ fx(t)
    case _ <> t:
      fx(t)

def st.fx(st: B.Step) -> String:
  match st:
    case B.Step{_, os}:
      fx(os)

def info(+k: String, +v: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("info")}, J.KV{"info", J.Json.obj([J.KV{k, J.Json.str(v)}])}])

def offer(+s: M.State, +w: String) -> List<&2, RF.Cand>:
  RF.Refs.offer(s, "t100-8", 1010n, w)

# desk's mirror (link "pk"): a project and a thread with a message
def desk.items() -> List<&2, FR.Item>:
  [FR.Item{1n, CD.Change.wire(M.ProjectCreated{"pq", "Board", "/b", 5n})},
   FR.Item{2n, CD.Change.wire(M.ThreadCreated{"t9", "pq", "Fix the perf lag", M.Local{}, "", "", "claude", "", 6n})},
   FR.Item{3n, CD.Change.wire(M.MessagePosted{"t9", "m9", M.User{}, "the frame takes 70 ms", 7n})}]

def desk.far() -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(FR.Fr.msg("pk", "desk", False{}, 0n, 3n, desk.items())), J.Null{})

def desk.in() -> FR.In:
  FR.In.put(FR.In.new("pk", "desk"), 0n, 3n, desk.items())

def main() -> IO(Unit):
  +s = base()
  +said = BH.Bots.hub(s, 1020n, 1, req("turn.start", "{\"thread\":\"t100-8\",\"text\":\"@Miso look at >fix-perf-lag-7 with #hardware-talk\",\"msg\":\"m1\"}"))
  +u0 = U.Ui.fold(log(), ui(U.Ui.select(U.Ui.init(1010n), "t100-8")))
  +u1 = ui(U.Ui.act(u0, "draft", "ask @"))
  +u2 = ui(U.Ui.act(u1, "draft", "ask @mi"))
  +u3 = ui(U.Ui.act(u2, "skill", ""))
  do IO<Unit>:
    C.Check.str("slug", RF.Slug.of("  Fix the perf lag! (v2)"), "fix-the-perf-lag-v2")
    C.Check.str("slug of _", RF.Slug.of("my_bot"), "my-bot")
    C.Check.str("slug cut", RF.Slug.of("aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddd eeee"), "aaaaaaaaaa-bbbbbbbbbb-cccccccccc-ddddddd")
    C.Check.str("typing @", yes(RF.Refs.typing("@")), "yes")
    C.Check.str("typing @mi", yes(RF.Refs.typing("@mi")), "yes")
    C.Check.str("typing mid-word", yes(RF.Refs.typing("a@b")), "no")
    C.Check.str("typing path", yes(RF.Refs.typing("@src/app")), "no")
    C.Check.str("typing money", yes(RF.Refs.typing("$5")), "no")
    C.Check.str("bots, newest first", names(offer(s, "@")), "@Tofu,@Miso,")
    C.Check.str("bot by prefix", names(offer(s, "@to")), "@Tofu,")
    C.Check.str("bot about", abouts(offer(s, "@mi")), "Keeps the parts library tidy|")
    C.Check.str("threads, same project first, shared slugs numbered", names(offer(s, ">fix")), ">fix-perf-lag-7,>fix-perf-lag-9,")
    C.Check.str("thread abouts", abouts(offer(s, ">fix")), "Fix perf lag — Tiles redraw only what changed|Board rev B: Fix perf lag|")
    C.Check.str("not this thread", names(offer(s, ">refs")), "")
    C.Check.str("summary matches", names(offer(s, ">tiles")), ">fix-perf-lag-7,")
    C.Check.str("projects, this one first", names(offer(s, "%b")), "%backplane-bend,%board-rev-b,")
    C.Check.str("projects narrow", names(offer(s, "%bo")), "%board-rev-b,")
    C.Check.str("rooms", names(offer(s, "#h")), "#hardware-talk,")
    C.Check.str("plain word offers none", names(offer(s, "hello")), "")
    C.Check.str("found", hits(RF.Refs.found(s, "t100-8", "hey @miso, see >fix-perf-lag and %board-rev-b in #hardware-talk. @Miso again @nobody")),
      "bot:" ++ miso(s) ++ ":@Miso thread:t100-7:>fix-perf-lag project:p2:%board-rev-b room:r1:#hardware-talk ")
    C.Check.str("found numbered", hits(RF.Refs.found(s, "t100-8", ">fix-perf-lag-9")), "thread:t100-9:>fix-perf-lag-9 ")
    C.Check.str("agent block", yes(String.contains(RF.Refs.agent(s, "t100-8", "ask @Tofu"), "<references>\n@Tofu is the bot \"Tofu\"")), "yes")
    C.Check.str("agent plain", RF.Refs.agent(s, "t100-8", "no refs here"), "no refs here")
    C.Check.str("mention wakes and posts", ch.tags(said), "MessagePosted TurnChanged BotWoke MessagePosted TurnChanged RoomPosted BotWoke MessagePosted TurnChanged | ")
    C.Check.str("mention sent again sets off nothing", st.tags(BH.Bots.hub(run(s, said), 1021n, 1, req("turn.start", "{\"thread\":\"t100-8\",\"text\":\"@Miso look\",\"msg\":\"m1\"}"))), "| ")
    C.Check.str("summary clean", RF.Sum.clean("  Tiles  redraw.\nMore"), "Tiles redraw.")
    C.Check.str("summary due", yes(RF.Sum.due(s, "t100-8", 1010n)), "yes")
    C.Check.str("summary kept, project next", st.tags(B.Hub.request(s, 1030n, 1, req("summary.set", "{\"id\":\"t100-8\",\"kind\":\"thread\",\"text\":\"Adds a popup\"}"))),
      "SettingSet SettingSet | git:summary:p1:project ")
    C.Check.str("summary not due again", yes(RF.Sum.due(M.State.replay([M.SettingSet{"summary.at.t100-8", "1030", 1030n}], s), "t100-8", 1100n)), "no")
    C.Check.str("composer offers bots", rows(U.Ui.skills(u1)), "@Tofu,@Miso,")
    C.Check.str("composer narrows", rows(U.Ui.skills(u2)), "@Miso,")
    C.Check.str("tab completes", U.Ui.draft_text(u3), "ask @Miso ")
    C.Check.str("completed offers none", rows(U.Ui.skills(u3)), "")
    C.Check.str("composer threads", rows(U.Ui.skills(ui(U.Ui.act(u0, "draft", "see >")))), ">fix-perf-lag-7,>fix-perf-lag-9,")
    C.Check.str("complete ref", U.Skills.complete("ask @mi", "@Miso"), "ask @Miso ")
    # the arrow keys move the highlight; Enter or Tab takes it
    C.Check.str("first lit", lit(U.Ui.skills(u1)), "[@Tofu],@Miso,")
    C.Check.str("down", lit(U.Ui.skills(ui(U.Ui.act(u1, "skill-move", "down")))), "@Tofu,[@Miso],")
    C.Check.str("down wraps", lit(U.Ui.skills(ui(U.Ui.act(ui(U.Ui.act(u1, "skill-move", "down")), "skill-move", "down")))), "[@Tofu],@Miso,")
    C.Check.str("up wraps", lit(U.Ui.skills(ui(U.Ui.act(u1, "skill-move", "up")))), "@Tofu,[@Miso],")
    C.Check.str("takes the lit one", U.Ui.draft_text(ui(U.Ui.act(ui(U.Ui.act(u1, "skill-move", "down")), "skill", ""))), "ask @Miso ")
    C.Check.str("a click still wins", U.Ui.draft_text(ui(U.Ui.act(ui(U.Ui.act(u1, "skill-move", "down")), "skill", "@Tofu"))), "ask @Tofu ")
    C.Check.str("typing starts over", lit(U.Ui.skills(ui(U.Ui.act(ui(U.Ui.act(u1, "skill-move", "down")), "draft", "ask @t")))), "[@Tofu],")
    # bots on linked machines: `@name@machine`
    C.Check.str("typing far", yes(RF.Refs.typing("@kit@la")), "yes")
    C.Check.str("typing far, machine to come", yes(RF.Refs.typing("@kit@")), "yes")
    C.Check.str("typing far, not a path", yes(RF.Refs.typing("@kit@la/x")), "no")
    C.Check.str("typing two @", yes(RF.Refs.typing("@kit@la@b")), "no")
    C.Check.str("far bots offered with ours", names(far.offer(linked(s), "@")), "@Kit@laptop,@Tofu,@Miso,")
    C.Check.str("far bot by prefix", names(far.offer(linked(s), "@ki")), "@Kit@laptop,")
    C.Check.str("far bot by machine", names(far.offer(linked(s), "@kit@la")), "@Kit@laptop,")
    C.Check.str("far bot about", abouts(far.offer(linked(s), "@ki")), "bot on laptop|")
    C.Check.str("far bots only after @", names(far.offer(linked(s), ">ki")), "")
    C.Check.str("far found", hits(RF.Refs.found(linked(s), "t100-8", "ask @Kit@laptop, and @kit@nowhere")), "bot:Kit@laptop:@Kit@laptop ")
    C.Check.str("far by link id", hits(RF.Refs.found(linked(s), "t100-8", "@Kit@pk")), "bot:Kit@pk:@Kit@pk ")
    C.Check.str("far agent block", yes(String.contains(RF.Refs.agent(linked(s), "t100-8", "ask @Kit@laptop"), "@Kit@laptop is the bot \"Kit\" on the linked machine laptop")), "yes")
    C.Check.str("far mention logged", ch.tags(BH.Bots.hub(linked(s), 1020n, 1, req("turn.start", "{\"thread\":\"t100-8\",\"text\":\"@Kit@laptop look\",\"msg\":\"m2\"}"))),
      "MessagePosted TurnChanged RoomPosted | ")
    C.Check.str("far mention delivered", st.fx(BH.Bots.hub(linked(s), 1020n, 1, req("turn.start", "{\"thread\":\"t100-8\",\"text\":\"@Kit@laptop look\",\"msg\":\"m2\"}"))),
      "send:pk:/bots/deliver:Kit ")
    C.Check.str("composer offers far bots",
      rows(U.Ui.skills(ui(U.Ui.act(U.Ui.recv(U.Ui.fold([M.PeerSet{"pk", "laptop", "http://laptop:3787", False{}, 1000n}], u0), info("bots.remote", dir())), "draft", "ask @k")))),
      "@Kit@laptop,")
    C.Check.str("complete far", U.Skills.complete("ask @k", "@Kit@laptop"), "ask @Kit@laptop ")
    # threads on another of the owner's machines: `>machine:slug`
    +ux : U.Ui = U.Ui.recv(u0, desk.far())
    C.Check.str("composer offers a thread elsewhere with its machine", rows(U.Ui.skills(ui(U.Ui.act(ux, "draft", "see >perf")))), ">fix-perf-lag-7,>fix-perf-lag-9,>desk:fix-the-perf-lag,")
    C.Check.str("its row names the machine", descs(U.Ui.skills(ui(U.Ui.act(ux, "draft", "see >desk:")))), "desk · Board: Fix the perf lag|")
    C.Check.str(">desk: narrows to that machine", rows(U.Ui.skills(ui(U.Ui.act(ux, "draft", "see >desk:")))), ">desk:fix-the-perf-lag,")
    C.Check.str(">desk:fix", rows(U.Ui.skills(ui(U.Ui.act(ux, "draft", "see >desk:fix")))), ">desk:fix-the-perf-lag,")
    C.Check.str("another machine's name narrows to none", rows(U.Ui.skills(ui(U.Ui.act(ux, "draft", "see >lab:")))), "")
    C.Check.str("a machine word names nothing here; `>fix:` still a word here", yes(RF.Refs.x.word("desk:fix")) ++ " " ++ yes(RF.Refs.x.word("fix:")) ++ " " ++ Nat.show(List.length(&2, RF.Hit, RF.Refs.find(U.Ui.state(ux), "t100-8", ">desk:fix-the-perf-lag"))), "yes no 0")
    # the hub: the agent's block names it from the mirror; thread_read reads it
    C.Check.str("the agent is told what >desk:slug is", XR.Xref.block("look at >desk:fix-the-perf-lag please", [desk.in()]),
      "\n\n<references>\n>desk:fix-the-perf-lag is the thread \"Fix the perf lag\" (id pk~t9, project \"Board\"). Read it with thread_read. It is on the machine desk; thread_read reads it from here, thread_send writes to it there.\n</references>")
    C.Check.str("no machine word, no block", XR.Xref.block("look at >fix and a: colon", [desk.in()]), "")
    +rd : J.Json = Maybe.default(&2, J.Json, J.Json.parse("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"thread_read\",\"arguments\":{\"threadId\":\"pk~t9\"}}}"), J.Null{})
    C.Check.str("thread_read on it is answered from the mirror", yes(XR.Xref.read.is(rd)) ++ " " ++ yes(String.contains(XR.Xref.read(rd, [desk.in()]), "the frame takes 70 ms")), "yes yes")
