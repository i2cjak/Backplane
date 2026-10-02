import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/core/client.bend as U
import ../src/core/subs.bend as SB

# Claude's subagents and background shells: a background one started, said what it does, and
# ended (lines as Claude Code 2.1 writes them); the thread waits on it
# after its own turn ends, and an agent that exits leaves none at work.

def base() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "P", "/r/board", 50n}]

def state(es: List<&2, M.Change>) -> M.State:
  M.State.replay(es, M.State.empty())

def after.req(+es: List<&2, M.Change>, +now: Nat, +text: String) -> List<&2, M.Change>:
  List.append(&2, M.Change, es, H.Queue.changes(H.Hub.request_text(state(es), now, 1, text)))

# the log after one line of the agent's output
def after(+es: List<&2, M.Change>, +now: Nat, +line: String) -> List<&2, M.Change>:
  List.append(&2, M.Change, es, H.Queue.changes(H.Hub.agent_line(state(es), now, "t100-1", line)))

def made() -> List<&2, M.Change>:
  List.append(&2, M.Change, after.req(base(), 100n, "{\"id\":1,\"m\":\"thread.create\",\"p\":{\"project\":\"p1\",\"env\":\"local\"}}"),
    [M.TurnChanged{"t100-1", M.Running{}, 101n}])

def started() -> List<&2, M.Change>:
  after(made(), 102n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"description\":\"Run bash command and report output\",\"subagent_type\":\"general-purpose\",\"is_backgrounded\":true,\"task_type\":\"local_agent\",\"session_id\":\"s\"}")

# the agent's own turn ends while the subagent works on
def done() -> List<&2, M.Change>:
  List.append(&2, M.Change, started(), [M.TurnChanged{"t100-1", M.Completed{}, 103n}])

def progressed() -> List<&2, M.Change>:
  after(done(), 104n, "{\"type\":\"system\",\"subtype\":\"task_progress\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"description\":\"Running Sleep for 20 seconds\",\"last_tool_name\":\"Bash\",\"session_id\":\"s\"}")

def ended() -> List<&2, M.Change>:
  after(progressed(), 105n, "{\"type\":\"system\",\"subtype\":\"task_notification\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"status\":\"completed\",\"session_id\":\"s\"}")

# a shell the agent put in the background (or Claude moved there when it
# ran past its timeout)
def shell() -> List<&2, M.Change>:
  after(made(), 102n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"b3\",\"description\":\"scripts/check.sh\",\"task_type\":\"local_bash\",\"is_backgrounded\":true}")

def shell.done() -> List<&2, M.Change>:
  List.append(&2, M.Change, shell(), [M.TurnChanged{"t100-1", M.Completed{}, 103n}])

# a foreground shell (Claude names it once it has run 30 s) that ran past
# its timeout and was moved to the background (lines as Claude Code 2.1.285
# writes them)
def moved() -> List<&2, M.Change>:
  after(after(made(), 102n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"b5\",\"task_type\":\"local_bash\",\"is_backgrounded\":false,\"description\":\"Run checks\"}"),
    103n, "{\"type\":\"system\",\"subtype\":\"task_updated\",\"task_id\":\"b5\",\"patch\":{\"is_backgrounded\":true}}")

# the subagent's own lines: a tool call, then what it wrote
def stepped() -> List<&2, M.Change>:
  after(after(started(), 102n, "{\"type\":\"assistant\",\"parent_tool_use_id\":\"toolu_1\",\"message\":{\"id\":\"m9\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_2\",\"name\":\"Bash\",\"input\":{\"command\":\"ls /etc/ssh\"}}]}}"),
    103n, "{\"type\":\"assistant\",\"parent_tool_use_id\":\"toolu_1\",\"message\":{\"id\":\"m10\",\"content\":[{\"type\":\"text\",\"text\":\"10 files\\nmore\"}]}}")

def entries(+es: List<&2, M.Change>, +th: String) -> String:
  Nat.show(List.length(&2, M.Entry, M.State.mine(state(es), th)))

def row.show(r: SB.SubRow) -> String:
  match r:
    case SB.SubRow{k, _, ti, _, w, d, _, o, n, ss}:
      k ++ "|" ++ ti ++ "|" ++ w ++ "|" ++ d ++ "|" ++ Bool.pick(String, o, "open", "shut") ++ "|" ++ Nat.show(n) ++ "|" ++ Nat.show(List.length(&2, SB.SubStep, ss))

def rows.show(rs: List<&2, SB.SubRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case r <> t:
      row.show(r) ++ ";" ++ rows.show(t)

def rows(+es: List<&2, M.Change>) -> String:
  rows.show(SB.Subs.rows(state(es), Map.new(&2, String), "t100-1"))

# the panel as a whole: open (1) or shut (0), its word, and its rows shown
def panel.k(+info: Map<&2, String>, +rs: List<&2, SB.SubRow>) -> String:
  +open = SB.Subs.panel.open(info, "t100-1", rs)
  Bool.pick(String, open, "1", "0") ++ "|" ++ SB.Subs.panel.word(rs) ++ "|" ++ Nat.show(List.length(&2, SB.SubRow, SB.Subs.panel.rows(open, rs)))

def panel.with(+es: List<&2, M.Change>, +info: Map<&2, String>) -> String:
  panel.k(info, SB.Subs.rows(state(es), info, "t100-1"))

def panel(+es: List<&2, M.Change>) -> String:
  panel.with(es, Map.new(&2, String))

# the info after a click on the panel's head (the "fold" action's value)
def clicked(+v: String) -> Map<&2, String>:
  Map.set(&2, String, Map.new(&2, String), "fold:" ++ String.drop(v, 1n), String.take(v, 1n))

def stepped.ended() -> List<&2, M.Change>:
  after(stepped(), 105n, "{\"type\":\"system\",\"subtype\":\"task_notification\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"status\":\"completed\",\"session_id\":\"s\"}")

def status(+es: List<&2, M.Change>) -> String:
  M.Status.name(U.Side.status(state(es), H.Hub.thread(state(es), "t100-1")))

def phase(+es: List<&2, M.Change>) -> String:
  M.Phase.label(U.Side.phase(state(es), H.Hub.thread(state(es), "t100-1")))

def doings(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      M.Bg.doing(l) <> doings(t)

def doing(+es: List<&2, M.Change>) -> String:
  String.join(doings(M.Bg.of(state(es), "t100-1")), "|")

def updated() -> List<&2, M.Change>:
  after(progressed(), 105n, "{\"type\":\"system\",\"subtype\":\"task_updated\",\"task_id\":\"a847\",\"patch\":{\"status\":\"completed\"}}")

def head(ls: List<&2, String>) -> String:
  Maybe.default(&2, String, List.head(&2, String, ls), "")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("started", doing(started()), "Run bash command and report output")
    C.Check.str("its steps stay off the thread", entries(stepped(), "t100-1"), entries(started(), "t100-1"))
    C.Check.str("its steps go to its log", entries(stepped(), M.Bg.log("t100-1")), "3")
    C.Check.str("at work: open with its steps", rows(stepped()), "toolu_1|Run bash command and report output|running|Run bash command and report output|open|2|2;")
    C.Check.str("at work: its title kept through progress", rows(after(stepped(), 104n, "{\"type\":\"system\",\"subtype\":\"task_progress\",\"task_id\":\"a847\",\"description\":\"Running ls\"}")),
      "toolu_1|Run bash command and report output|running|Running ls|open|2|2;")
    C.Check.str("ended: listed, shut", rows(stepped.ended()), "toolu_1|Run bash command and report output|done||shut|2|0;")
    # the panel: open while one works, folded to its head once all are done
    C.Check.str("panel at work: open", panel(stepped()), "1|1 at work|1")
    C.Check.str("panel all done: folded to its head", panel(stepped.ended()), "0|1 done|0")
    C.Check.str("a click on a done panel's head asks to open it", SB.Subs.panel.ask(False{}, "t100-1"), "1subs:t100-1")
    C.Check.str("opened by hand, a done panel stays open", panel.with(stepped.ended(), clicked(SB.Subs.panel.ask(False{}, "t100-1"))), "1|1 done|1")
    C.Check.str("shut by hand, a working panel stays shut", panel.with(stepped(), clicked(SB.Subs.panel.ask(True{}, "t100-1"))), "0|1 at work|0")
    C.Check.str("a background shell is listed by its kind", rows(shell()), "b3|shell: scripts/check.sh|running|scripts/check.sh|open|0|0;")
    C.Check.str("a background shell is not an agent", SB.Subs.badge(SB.Subs.count(state(shell()), "t100-1")), "")
    C.Check.str("the sidebar's count", SB.Subs.badge(SB.Subs.count(state(stepped()), "t100-1")) ++ "/" ++ SB.Subs.badge(SB.Subs.count(state(stepped.ended()), "t100-1")), "1 agent/")
    C.Check.str("working while the turn runs", status(started()), "working")
    C.Check.str("waiting after the turn", status(done()), "waiting")
    C.Check.str("phase after the turn", phase(done()), "Monitoring 1 task")
    C.Check.str("progress", doing(progressed()), "Running Sleep for 20 seconds")
    C.Check.str("progress again writes nothing", Nat.show(List.length(&2, M.Change, progressed())), Nat.show(List.length(&2, M.Change,
      after(progressed(), 106n, "{\"type\":\"system\",\"subtype\":\"task_progress\",\"task_id\":\"a847\",\"description\":\"Running Sleep for 20 seconds\",\"session_id\":\"s\"}"))))
    C.Check.str("a subagent's bash is not listed", doing(after(done(), 104n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"b1\",\"description\":\"Sleep\",\"task_type\":\"local_bash\",\"owned_by_subagent\":true}")), "Run bash command and report output")
    C.Check.str("a foreground shell is not listed", doing(after(made(), 102n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"b2\",\"description\":\"sleep 4\",\"task_type\":\"local_bash\",\"is_backgrounded\":false}")), "")
    C.Check.str("a background shell is listed", doing(shell()), "scripts/check.sh")
    C.Check.str("the turn over, it monitors the shell", status(shell.done()), "waiting")
    C.Check.str("monitoring phase", phase(shell.done()), "Monitoring 1 task")
    C.Check.str("the shell ends: ready", status(after(shell.done(), 105n, "{\"type\":\"system\",\"subtype\":\"task_notification\",\"task_id\":\"b3\",\"status\":\"completed\"}")), "ready")
    C.Check.str("a shell moved to the background past its timeout is listed", doing(moved()), "Background shell")
    C.Check.str("moved, the turn over: monitoring", phase(List.append(&2, M.Change, moved(), [M.TurnChanged{"t100-1", M.Completed{}, 104n}])), "Monitoring 1 task")
    C.Check.str("moved, then done: ended, its outcome owed", M.Bg.status(head(M.Bg.of(state(after(moved(), 105n, "{\"type\":\"system\",\"subtype\":\"task_updated\",\"task_id\":\"b5\",\"patch\":{\"status\":\"completed\",\"end_time\":1}}")), "t100-1"))), "completed")
    C.Check.str("a monitor is listed", doing(after(made(), 102n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"b4\",\"description\":\"CI\",\"task_type\":\"monitor_mcp\"}")), "CI")
    C.Check.str("ended", doing(ended()), "")
    C.Check.str("ready after", status(ended()), "ready")
    C.Check.str("updated to completed ends it", M.Bg.status(head(M.Bg.of(state(updated()), "t100-1"))), "completed")
    C.Check.str("an ended row shows finished, reporting", rows(updated()), "toolu_1|Run bash command and report output|reporting|finished, reporting|open|0|0;")
    C.Check.str("an ended row is still work", phase(updated()), "Monitoring 1 task")
    C.Check.str("progress leaves an ended row", M.Bg.status(head(M.Bg.of(state(after(updated(), 106n, "{\"type\":\"system\",\"subtype\":\"task_progress\",\"task_id\":\"a847\",\"description\":\"late\"}")), "t100-1"))), "completed")
    C.Check.str("its notification takes it", doing(after(updated(), 106n, "{\"type\":\"system\",\"subtype\":\"task_notification\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"status\":\"completed\"}")), "")
    C.Check.str("gone from the open list: ended", M.Bg.status(head(M.Bg.of(state(after(progressed(), 105n, "{\"type\":\"system\",\"subtype\":\"background_tasks_changed\",\"tasks\":[{\"task_id\":\"zz\"}]}")), "t100-1"))), "done")
    C.Check.str("still on the open list: at work", doing(after(progressed(), 105n, "{\"type\":\"system\",\"subtype\":\"background_tasks_changed\",\"tasks\":[{\"task_id\":\"a847\"}]}")), "Running Sleep for 20 seconds")
    C.Check.str("the open list adds nothing", doing(after(made(), 105n, "{\"type\":\"system\",\"subtype\":\"background_tasks_changed\",\"tasks\":[{\"task_id\":\"a847\"}]}")), "")
    C.Check.str("exit clears", doing(List.append(&2, M.Change, progressed(), H.Queue.changes(H.Hub.agent_gone(state(progressed()), 107n, "t100-1", 0)))), "")
    C.Check.str("restart clears", doing(List.append(&2, M.Change, progressed(), H.Queue.changes(H.Hub.recover(state(progressed()), 107n)))), "")
