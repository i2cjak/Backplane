import Base
import ./model.bend as M
import ./icons.bend as I

# The thread header's buttons, one list for every client (the window, the
# web, the phones): each an icon (core/icons.bend), a word or two, what it
# does in a sentence (the tooltip), and whether it is on. They come in
# groups, left to right: stopping the turn; where the thread sits in the
# list (pin, settle, snooze, archive, delete); forking; what shows beside
# it (the terminal, the panel). `gap` starts a group.
type Tool is Data:
  Tool{icon: String, label: String, tip: String, action: String, value: String, on: Bool, danger: Bool, gap: Bool}

# what the header shows of a thread
type Head is Data:
  Head{running: Bool, settled: Bool, pinned: Bool, snoozed: Bool, archived: Bool, del: Bool, forked: Bool, term: Bool, panel: Bool}

# settled by hand, or by itself (an answer the person has seen)
def Tools.settled(o: M.Override, auto: Bool) -> Bool:
  match o auto:
    case M.ForcedSettled{} _:
      True{}
    case M.NoOverride{} True{}:
      True{}
    case _ _:
      False{}

def Tools.stop(running: Bool) -> List<&2, Tool>:
  match running:
    case True{}:
      [Tool{"stop", "Stop", "Stop the running turn", "interrupt", "", False{}, True{}, False{}}]
    case False{}:
      Nil{}

def Tools.pin(p: Bool) -> Tool:
  match p:
    case True{}:
      Tool{"pin", "Pinned", "Unpin: it sorts with the rest again", "unpin", "", True{}, False{}, True{}}
    case False{}:
      Tool{"pin", "Pin", "Keep it at the top of the list", "pin", "", False{}, False{}, True{}}

def Tools.settle(s: Bool) -> Tool:
  match s:
    case True{}:
      Tool{"circle-check", "Settled", "Bring it back to the active threads", "unsettle", "", True{}, False{}, False{}}
    case False{}:
      Tool{"circle-check", "Settle", "Done for now: it leaves the active threads", "settle", "", False{}, False{}, False{}}

# snoozed: it wakes; else it offers the snooze choices, through the
# client's own action (a, v)
def Tools.snooze(s: Bool, a: String, v: String) -> Tool:
  match s:
    case True{}:
      Tool{"clock", "Snoozed", "Wake it now", "snooze", "off", True{}, False{}, False{}}
    case False{}:
      Tool{"clock", "Snooze", "Hide it until later", a, v, False{}, False{}, False{}}

def Tools.archive(a: Bool) -> Tool:
  match a:
    case True{}:
      Tool{"archive", "Archived", "Bring it back from the archive", "unarchive", "", True{}, False{}, False{}}
    case False{}:
      Tool{"archive", "Archive", "Put it away in the archive", "archive", "", False{}, False{}, False{}}

# Delete asks first: once armed it reads "Delete thread" beside Cancel
def Tools.del(on: Bool) -> List<&2, Tool>:
  match on:
    case True{}:
      [Tool{"trash", "Delete thread", "Delete it for good", "delete", "", False{}, True{}, False{}},
       Tool{"x", "Cancel", "Keep it", "delete-no", "", False{}, False{}, False{}}]
    case False{}:
      [Tool{"trash", "Delete", "Delete this thread (asks first)", "delete", "", False{}, False{}, False{}}]

def Tools.fork() -> Tool:
  Tool{"git-fork", "Fork thread", "A new thread that goes on from here", "fork", "", False{}, False{}, True{}}

def Tools.back(forked: Bool) -> List<&2, Tool>:
  match forked:
    case True{}:
      [Tool{"undo", "Bring back", "Send what this fork did to the thread it came from, with its next message", "back", "", False{}, False{}, False{}}]
    case False{}:
      Nil{}

def Tools.term(on: Bool, a: String, v: String) -> Tool:
  Tool{"terminal", "Terminal", "A shell in the thread's folder (ctrl+j)", a, v, on, False{}, True{}}

def Tools.panel(on: Bool) -> Tool:
  Tool{"panel-right", "Viewer", "Board, schematic, 3D, Mech, files, diff and browser beside the thread", "panel", "", on, False{}, False{}}

# the header's buttons, left to right; (sa, sv) opens the client's snooze
# choices and (ta, tv) its terminal
def Tools.head(h: Head, sa: String, sv: String, ta: String, tv: String) -> List<&2, Tool>:
  match h:
    case Head{running, settled, pinned, snoozed, archived, del, forked, term, panel}:
      List.concat(&2, Tool, [Tools.stop(running),
        [Tools.pin(pinned), Tools.settle(settled), Tools.snooze(snoozed, sa, sv), Tools.archive(archived)], Tools.del(del),
        [Tools.fork()], Tools.back(forked),
        [Tools.term(term, ta, tv), Tools.panel(panel)]])

# a button's label, which the first-run tour names it by
def Tools.label(t: Tool) -> String:
  match t:
    case Tool{_, +l, _, _, _, _, _, _}:
      l

def Tools.icons(ts: List<&2, Tool>) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case Tool{i, _, _, _, _, _, _, _} <> t:
      i <> Tools.icons(t)

# every header this could show: every flag both ways
def Tools.every() -> List<&2, Tool>:
  List.concat(&2, Tool, [
    Tools.head(Head{True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}}, "", "", "", ""),
    Tools.head(Head{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}}, "", "", "", "")])

# every button has a label and a tooltip to go with its icon
def Tools.labelled(ts: List<&2, Tool>) -> Bool:
  match ts:
    case Nil{}:
      True{}
    case Tool{_, +l, +tip, _, _, _, _, _} <> t:
      Bool.and(Bool.and(Bool.not(String.is_empty(l)), Bool.not(String.is_empty(tip))), Tools.labelled(t))

# the icons every header uses, none missing from the set
def Tools.missing() -> List<&2, String>:
  I.Icon.missing(Tools.icons(Tools.every()))
