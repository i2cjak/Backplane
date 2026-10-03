import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/store.bend as ST
import ../src/core/hub.bend as H

# A delegated task's delivery torn by a crash at every byte: the log is
# cut after each byte of the step that finishes child t1's task k1 (its
# turn completes, the task is done, the result reaches idle parent t0,
# whose turn starts, TaskDelivered last), read back as the hub reads it at
# start-up, and recovered (Hub.recover, then Hub.carry, as the server
# does; restart.continue off, so a child cut short fails and delivers
# rather than carrying on). Every cut ends with exactly one result message in the parent, the
# task delivered, and the parent's turn running.

def base() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "p", "/p", 1n}, M.ThreadCreated{"t0", "p1", "root", M.Local{}, "", "", "codex", "", 1n},
   M.ThreadCreated{"t1", "p1", "child", M.Local{}, "", "", "claude", "", 1n}, M.TaskDelegated{"k1", "t0", "t1", 1n, "claude", "", 1n},
   M.TaskStateSet{"k1", M.TaskRunning{}, "", 1n}, M.MessagePosted{"t1", "u1", M.User{}, "do it", 2n}, M.TurnChanged{"t1", M.Running{}, 2n},
   M.MessagePosted{"t1", "a1", M.Assistant{}, "it is done", 3n}, M.SettingSet{"restart.continue", "off", 3n}]

def lines(cs: List<&2, M.Change>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      J.Json.show(K.Change.encode(c)) <> lines(t)

def state(cs: List<&2, M.Change>) -> M.State:
  M.State.replay(cs, M.State.empty())

# the step the crash tears: the child's result line
def step() -> List<&2, M.Change>:
  H.Queue.changes(H.Hub.agent_line(state(base()), 9n, "t1", "{\"type\":\"result\",\"is_error\":false,\"result\":\"it is done\"}"))

def nonempty(ls: List<&2, String>) -> List<&2, String>:
  M.Bg.nonempty(ls)

# the log as the hub reads it back
def read(+text: String) -> M.State:
  ST.Loaded.st(ST.Store.load(nonempty(String.split(text, '\n')), ST.Loaded{M.State.empty(), Nil{}}))

def recovered.k(+before: M.State, +after: M.State) -> M.State:
  M.State.replay(H.Queue.changes(H.Hub.carry(before, after, 20n)), after)

def recovered(+s: M.State) -> M.State:
  recovered.k(s, M.State.replay(H.Queue.changes(H.Hub.recover(s, 20n)), s))

def results(es: List<&2, M.Entry>) -> Nat:
  match es:
    case Nil{}:
      0n
    case M.Msg{+id, _, _, _, _} <> t:
      Nat.add(Bool.pick(Nat, String.eq(id, H.Task.msg("t1", "k1")), 1n, 0n), results(t))
    case _ <> t:
      results(t)

def delivered.k(m: Maybe<&2, M.Task>) -> String:
  match m:
    case Some{M.Task{_, _, _, _, st, _, dl, _, _}}:
      Bool.show(Bool.and(M.TaskState.terminal(st), dl))
    case None{}:
      "none"

# what a cut leaves after recovery: results in t0 / delivered / t0's turn
# started (now running, or already running at the crash: with
# restart.continue off the restart stops that one)
def after.k(+before: M.State, +s: M.State) -> String:
  Nat.show(results(M.State.mine(s, "t0"))) ++ "/" ++ delivered.k(H.Task.of_child(s, "t1")) ++ "/" ++ Bool.show(Bool.or(H.Hub.running(H.Hub.thread(before, "t0")), H.Hub.running(H.Hub.thread(s, "t0"))))

def after(+before: M.State) -> String:
  after.k(before, recovered(before))

def bad.one(+k: Nat, +got: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(got, "1/True/True"), Nil{}, [Nat.show(k) ++ ":" ++ got])

# the cuts that leave anything else, "k:what"
def bad(n: Nat, +k: Nat, +head: String, +text: String, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n:
      acc
    case 1n+p:
      bad(p, 1n+k, head, text, List.append(&2, String, acc, bad.one(k, after(read(head ++ String.take(text, k))))))

def main() -> IO(Unit):
  do IO<Unit>:
    +head : String = ST.Store.text(lines(base()))
    +text : String = ST.Store.text(lines(step()))
    C.Check.str("the step delivers, TaskDelivered last", Maybe.default(&2, String, List.head(&2, String, List.reverse(&2, String, lines(step()))), ""), J.Json.show(K.Change.encode(M.TaskDelivered{"k1", 9n})))
    C.Check.str("whole step: one result, delivered, parent running", after(read(head ++ text)), "1/True/True")
    C.Check.str("no step at all: one result, delivered, parent running", after(read(head)), "1/True/True")
    C.Check.str("cut after every byte of the step (" ++ Nat.show(String.length(text)) ++ " bytes)", String.join(List.take(&2, String, bad(1n+String.length(text), 0n, head, text, Nil{}), 5n), " "), "")
    C.Check.str("a torn line resyncs: the next line reads", Nat.show(List.length(&2, M.Change, ST.Store.changes(nonempty(String.split(String.take(text, 20n) ++ ST.Store.tail_fix([65]) ++ J.Json.show(K.Change.encode(M.ProjectRemoved{"p9", 1n})) ++ "\n", '\n'))))), "1")
