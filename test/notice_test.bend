import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/notice.bend as NO
import ../src/mobile/notify.bend as N
import ../src/core/client.bend as U

# One room exchange as it happened on 2026-09-25 18:28:55: the person asks
# in #ring-requests (shared by the desktop hub's Bub and the backplane
# hub's Pebble), Pebble answers first, Bub answers the person, Pebble
# reads it, Bub thanks Pebble, Pebble reads that. Five turns ended across
# the two hubs; before this change each one alerted (two APNs pushes from
# the desktop, five alerts on a phone paired with both hubs). Now: one.

def log(cs: List<&2, M.Change>) -> M.State:
  M.State.replay(cs, M.State.empty())

def more(s: M.State, cs: List<&2, M.Change>) -> M.State:
  M.State.replay(cs, s)

def show(n: NO.Notice) -> String:
  match n:
    case NO.Notice{+k, key}:
      Bool.pick(String, String.is_empty(k), "quiet", k ++ " " ++ key)

# a bot's turn: woken by `text`, maybe posting `post` in room r1 as `name`
def turn(+th: String, +id: String, +text: String, +at: Nat) -> List<&2, M.Change>:
  [M.MessagePosted{th, "u" ++ id, M.User{}, text, at}, M.TurnChanged{th, M.Running{}, at}]

def post(+th: String, +id: String, +name: String, +text: String, +at: Nat) -> List<&2, M.Change>:
  [M.ActivityLogged{th, "a" ++ id, "tool", "mcp__backplane__room_post", "mcp__backplane__room_post", at},
   M.RoomPosted{"p" ++ id, "r1", name, text, 2n, at}]

def done(+th: String, +id: String, +at: Nat) -> List<&2, M.Change>:
  [M.MessagePosted{th, "m" ++ id, M.Assistant{}, "Said it in the room.", at}, M.TurnChanged{th, M.Completed{}, at}]

def cat(xss: List<&2, List<&2, M.Change>>) -> List<&2, M.Change>:
  match xss:
    case Nil{}:
      Nil{}
    case xs <> t:
      List.append(&2, M.Change, xs, cat(t))

# The desktop hub: Bub, and Pebble as Pebble@backplane
def desk0() -> M.State:
  log([M.ThreadCreated{"tb", "", "Bub", M.Local{}, "", "", "claude", "", 100n},
    M.BotSet{"b1", "Bub", "tb", 0n, "", 100n},
    M.ThreadCreated{"tw", "", "Smarter notifications", M.Local{}, "", "", "claude", "", 100n},
    M.RoomSet{"r1", "ring-requests", "b1\nPebble@backplane", 100n}])

# after Bub's first turn: the person asked, Pebble answered first, Bub answered
def desk1() -> M.State:
  more(desk0(), cat([
    [M.RoomPosted{"p0", "r1", "you", "Idk what this does", 0n, 1000n}],
    turn("tb", "1", "[message from you in #ring-requests]\nIdk what this does", 1000n),
    [M.RoomPosted{"pp1", "r1", "Pebble@backplane", "Short version of PR #42", 1n, 1007n}],
    post("tb", "1", "Bub", "You're right that it changes nothing you'd see", 1015n),
    done("tb", "1", 1016n)]))

# Bub's second turn: woken by Pebble's post, thanks Pebble in the room
def desk2() -> M.State:
  more(desk1(), cat([
    turn("tb", "2", "[message from Pebble@backplane in #ring-requests]\nShort version of PR #42", 1016n),
    post("tb", "2", "Bub", "Thanks, Pebble. #42 is already merged", 1019n),
    done("tb", "2", 1020n)]))

# The backplane hub: Pebble, and Bub as Bub@desktop
def pb0() -> M.State:
  log([M.ThreadCreated{"tp", "", "Pebble", M.Local{}, "", "", "claude", "", 100n},
    M.BotSet{"b2", "Pebble", "tp", 0n, "", 100n},
    M.RoomSet{"r1", "ring-requests", "b2\nBub@desktop", 100n}])

# Pebble answers the person first
def pb1() -> M.State:
  more(pb0(), cat([
    [M.RoomPosted{"q0", "r1", "you@desktop", "Idk what this does", 0n, 1000n}],
    turn("tp", "1", "[message from you@desktop in #ring-requests]\nIdk what this does", 1000n),
    post("tp", "1", "Pebble", "Short version of PR #42", 1007n),
    done("tp", "1", 1008n)]))

# Pebble reads Bub's answer and posts nothing
def pb2() -> M.State:
  more(pb1(), cat([
    [M.RoomPosted{"q1", "r1", "Bub@desktop", "You're right that it changes nothing you'd see", 2n, 1015n}],
    turn("tp", "2", "[message from Bub@desktop in #ring-requests]\nYou're right", 1015n),
    done("tp", "2", 1017n)]))

# Pebble reads Bub's thanks and says "noted" in the room
def pb3() -> M.State:
  more(pb2(), cat([
    [M.RoomPosted{"q2", "r1", "Bub@desktop", "Thanks, Pebble. #42 is already merged", 2n, 1019n}],
    turn("tp", "3", "[message from Bub@desktop in #ring-requests]\nThanks, Pebble", 1019n),
    post("tp", "3", "Pebble", "Noted.", 1021n),
    done("tp", "3", 1022n)]))

def hub(+s: M.State, +th: String) -> String:
  show(NO.Notice.of(s, th, False{}, True{}))

def phone(+s: M.State, +th: String) -> String:
  show(NO.Notice.of(s, th, False{}, False{}))

def alerted(+x: String) -> Nat:
  Bool.pick(Nat, String.eq(x, "quiet"), 0n, 1n)

def sum(xs: List<&2, String>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case +x <> t:
      Nat.add(alerted(x), sum(t))

# the phone's alerts for one hub's frame: `th` was seen running before it
def ph.alerts(+s: M.State, +th: String) -> Nat:
  List.length(&2, J.Json, N.Note.alerts(U.Ui.threads(s), [N.Seen{th, True{}}], s, M.State.entries.all(s), ""))

def main() -> IO(Unit):
  do IO<Unit>:
    # the hub (APNs): each hub counts its own bots' posts
    C.Check.str("desk: Bub answers the person", hub(desk1(), "tb"), "done room-r1")
    C.Check.str("desk: Bub thanks Pebble", hub(desk2(), "tb"), "quiet")
    C.Check.str("pb: Pebble answers first", hub(pb1(), "tp"), "done room-r1")
    C.Check.str("pb: Pebble reads, posts nothing", hub(pb2(), "tp"), "quiet")
    C.Check.str("pb: Pebble says noted", hub(pb3(), "tp"), "quiet")
    C.Check.str("hub pushes per hub", Nat.show(sum([hub(desk1(), "tb"), hub(desk2(), "tb")])) ++ " "
      ++ Nat.show(sum([hub(pb1(), "tp"), hub(pb2(), "tp"), hub(pb3(), "tp")])), "1 1")
    # the phone, paired with both: any bot counts, so the first answer alerts
    C.Check.str("phone: all five turns alert once", Nat.show(sum([phone(desk1(), "tb"), phone(desk2(), "tb"),
      phone(pb1(), "tp"), phone(pb2(), "tp"), phone(pb3(), "tp")])), "1")
    C.Check.str("phone alerts through notify", Nat.show(Nat.add(Nat.add(ph.alerts(desk1(), "tb"), ph.alerts(desk2(), "tb")),
      Nat.add(ph.alerts(pb1(), "tp"), Nat.add(ph.alerts(pb2(), "tp"), ph.alerts(pb3(), "tp"))))), "1")
    # kept: failures, work the person started, asks, a new exchange
    C.Check.str("failure alerts", show(NO.Notice.of(desk2(), "tb", True{}, True{})), "fail turn-tb")
    # work out: a finished turn tells nothing until the work is done; a
    # failure or a question still does
    +busy : M.State = more(desk2(), cat([turn("tw", "9", "go", 1030n), [M.WorkSet{"tw", "bg", "b1\tsleep 8\tc1\tsleep 8\tshell", 1035n}], done("tw", "9", 1040n)]))
    C.Check.str("busy: a finished turn waits for its work", hub(busy, "tw"), "quiet")
    C.Check.str("busy: a failure still alerts", show(NO.Notice.of(busy, "tw", True{}, True{})), "fail turn-tw")
    C.Check.str("busy: a question still alerts", hub(more(busy, [M.AskOpened{"k9", "tw", "question", "AskUserQuestion", "Which?", "", 1041n}]), "tw"), "done turn-tw")
    C.Check.str("busy: the turn that ends the work alerts", hub(more(busy, cat([[M.WorkSet{"tw", "bg", "", 1050n}], turn("tw", "10", "more", 1051n), done("tw", "10", 1060n)])), "tw"), "done turn-tw")
    C.Check.str("busy: a running child keeps it quiet", hub(more(desk2(), cat([turn("tw", "9", "go", 1030n), [M.TaskDelegated{"k1", "tw", "tc", 1n, "codex", "", 1031n}], done("tw", "9", 1040n)])), "tw"), "quiet")
    C.Check.str("thread finishing alerts", hub(more(desk2(), cat([turn("tw", "9", "go", 1030n), done("tw", "9", 1040n)])), "tw"), "done turn-tw")
    C.Check.str("person in the bot's thread", hub(more(desk2(), cat([turn("tb", "3", "What's left?", 1030n), done("tb", "3", 1040n)])), "tb"), "done turn-tb")
    C.Check.str("bot asking the person", hub(more(desk2(), cat([turn("tb", "4", "[message from Pebble@backplane in #ring-requests]\nq", 1030n),
      [M.AskOpened{"k1", "tb", "question", "AskUserQuestion", "Merge #42?", "", 1031n}], done("tb", "4", 1040n)])), "tb"), "done turn-tb")
    C.Check.str("person posts again: new exchange", hub(more(desk2(), cat([[M.RoomPosted{"p9", "r1", "you", "and now?", 0n, 1050n}],
      turn("tb", "5", "[message from you in #ring-requests]\nand now?", 1050n), post("tb", "5", "Bub", "Now it is done.", 1055n), done("tb", "5", 1056n)])), "tb"), "done room-r1")
    C.Check.str("after the window: new exchange", hub(more(desk2(), cat([
      turn("tb", "6", "[message from Pebble@backplane in #ring-requests]\nnew ring request", 1400n), post("tb", "6", "Bub", "Got it.", 1405n), done("tb", "6", 1406n)])), "tb"), "done room-r1")
    C.Check.str("within the window: same exchange", hub(more(desk2(), cat([
      turn("tb", "7", "[message from Pebble@backplane in #ring-requests]\nmore", 1200n), post("tb", "7", "Bub", "Ok.", 1205n), done("tb", "7", 1206n)])), "tb"), "quiet")
