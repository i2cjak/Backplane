import Base

# The first-run tour, for every client (the window, the web, the phones):
# a short list of steps (a title, a few sentences, and the part of the
# screen it is about), and the moves between them. Pure: the client keeps
# which step is on screen as text ("" until the person moves, then the
# step's number) and the hub keeps the one fact that outlives it, the
# setting "onboard.done" (client.bend's Tour.*). The tour is up when the
# client has heard from its hub, the hub has no "onboard.done" and nobody
# has moved it yet (step 0), or when the person asked for it again.
#
# `target` names what a client may point at: "" (nothing), "sidebar",
# "add" (the sidebar's + button), "head" (the thread's buttons),
# "settings" (the sidebar's Settings button).
type Step is Data:
  Step{title: String, body: String, target: String}

def Ob.steps() -> List<&2, Step>:
  [Step{"Welcome to Backplane", "An agent next to your KiCad work, with viewers for the board, schematic and 3D model. This tour takes a minute. Esc skips it; Settings brings it back.", ""},
   Step{"Projects", "A project is a folder, usually a KiCad project. Add one with + at the top of the sidebar. Conversations that belong to no project go under Scratch.", "add"},
   Step{"Threads", "A thread is a conversation with an agent working in a project's folder. Long runs of tool calls fold into one row, and delegated work shows in the Subagents panel above the thread.", "sidebar"},
   Step{"The thread's buttons", "Along the top: stop a turn, pin, settle, snooze, archive or delete a thread, fork it, open a terminal in its folder, and Viewer. Viewer opens Board, Schematic, 3D, Mech, Files, Diff and Browser beside the thread.", "head"},
   Step{"Bots", "A bot is a persistent agent with a cat for a face, memory, routines and rooms. In a message, @bot, >thread, %project and #room refer to them; /give hands the conversation to a thread, project or bot.", "sidebar"},
   Step{"Your agents", "Claude Code, Codex and Grok run as the programs already installed and logged in on this machine; Backplane starts them as they are. Pick the provider and model from the composer or in Settings.", "settings"},
   Step{"Keys and voice", "API keys for other services are kept on this machine under Settings; agents use them without ever reading them. Voice dictation uses an OpenAI key, kept there too.", "settings"},
   Step{"Your machines", "Each machine runs one hub. Other machines on your tailnet show up in the sidebar, with a machine switch beside Settings, and their threads open here. Pair a phone by scanning the code in Settings, and open this hub's web address from other devices.", "settings"}]

# how many steps there are
def Ob.count() -> Nat:
  8n

def Ob.step(i: Nat) -> Step:
  Maybe.default(&2, Step, List.get(&2, Step, Ob.steps(), i), Step{"", "", ""})

def Ob.title.of(s: Step) -> String:
  match s:
    case Step{t, _, _}:
      t

def Ob.body.of(s: Step) -> String:
  match s:
    case Step{_, b, _}:
      b

def Ob.target.of(s: Step) -> String:
  match s:
    case Step{_, _, g}:
      g

def Ob.title(i: Nat) -> String:
  Ob.title.of(Ob.step(i))

def Ob.body(i: Nat) -> String:
  Ob.body.of(Ob.step(i))

# what a client may point at (see the top)
def Ob.target(i: Nat) -> String:
  Ob.target.of(Ob.step(i))

# a step's number read back from the client's text (digits only; anything
# else counts as 0)
def Ob.num(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Ob.num(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))))

# a step number kept in range; `count` stands for the tour being over
def Ob.clamp(+i: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(i, Ob.count()), i, Ob.count())

# The step on screen, `count` when none: nothing until the client has
# heard from its hub (`ready`); with no move yet, the first step unless the
# hub says it is done; else the step the person moved to.
def Ob.at.k(fresh: Bool, done: Bool, +raw: String) -> Nat:
  match fresh:
    case True{}:
      Bool.pick(Nat, done, Ob.count(), 0n)
    case False{}:
      Ob.clamp(Ob.num(raw, 0n))

def Ob.at(ready: Bool, done: Bool, +raw: String) -> Nat:
  match ready:
    case False{}:
      Ob.count()
    case True{}:
      Ob.at.k(String.is_empty(raw), done, raw)

# is a step on screen
def Ob.live(i: Nat) -> Bool:
  Nat.is_lt(i, Ob.count())

def Ob.next(+i: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(i, Ob.count()), 1n+i, Ob.count())

def Ob.back(+i: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(i, Ob.count()), Nat.sub(i, 1n), Nat.sub(Ob.count(), 1n))

# Skip ends the tour from any step
def Ob.skip() -> Nat:
  Ob.count()

# the client's text for a step
def Ob.raw(i: Nat) -> String:
  Nat.show(i)

# the last step's forward button reads Done
def Ob.last(i: Nat) -> Bool:
  Nat.is_eq(1n+i, Ob.count())

def Ob.forward(i: Nat) -> String:
  Bool.pick(String, Ob.last(i), "Done", "Next")

# "3 of 8"
def Ob.counter(i: Nat) -> String:
  Nat.show(1n+i) ++ " of " ++ Nat.show(Ob.count())

# every step has a title, a body and a known target
def Ob.sound(xs: List<&2, Step>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Step{+t, +b, _} <> r:
      Bool.and(Bool.and(Bool.not(String.is_empty(t)), Bool.not(String.is_empty(b))), Ob.sound(r))
