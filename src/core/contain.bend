import Base

# Agent containment
# -----------------
# Each agent process (claude, codex, grok, and the shells and builds it
# runs, which are its children) starts in a transient systemd scope of its
# own with a memory limit, so a runaway child is killed by the kernel
# inside that scope and never takes the hub's service down with it. Without
# user systemd the process starts as it always did. Pure: the limit, the
# unit's name, the command line and the words for an out-of-memory end.
#
# Limits are in MiB and written with systemd's M suffix. The hub setting
# agent.memory is a whole number of GiB (clamped to 2 GiB .. 90% of the
# machine's memory; unset: half of it). agent.memory.mb is for tests only:
# whole MiB, never clamped.

def Contain.num.acc(live: Bool, digit: Bool, +c: U32, +acc: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(live, digit), Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))), acc)

# a count written in decimal, up to the first other character ("" : 0)
def Contain.num(s: String, +acc: Nat, +live: Bool) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Contain.num(t, Contain.num.acc(live, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), c, acc), Bool.and(live, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))))

def Contain.num.of(s: String) -> Nat:
  Contain.num(s, 0n, True{})

def Contain.ram.pick(+acc: Nat, hit: Bool, +l: String) -> Nat:
  Bool.pick(Nat, Nat.is_gt(acc, 0n), acc, Bool.pick(Nat, hit, Contain.num.of(String.trim(String.drop(l, 9n))), 0n))

def Contain.ram.lines(ls: List<&2, String>, +acc: Nat) -> Nat:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Contain.ram.lines(t, Contain.ram.pick(acc, String.starts_with(l, "MemTotal:"), l))

# the machine's memory in KiB from /proc/meminfo's text (0: not found)
def Contain.ram(text: String) -> Nat:
  Contain.ram.lines(String.split(text, '\n'), 0n)

# g is how many units make a GiB (1024: the units are MiB). Laws use a
# small g so no big number is ever normalized.
def Contain.fallback(+g: Nat) -> Nat:
  Nat.mul(g, 8n)

def Contain.clamp(+n: Nat, +lo: Nat, +hi: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(n, lo), lo, Bool.pick(Nat, Nat.is_gt(n, hi), hi, n))

def Contain.max(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), a, b)

# the most a limit may be: 90% of the machine, never under 2 GiB
def Contain.top(+ram: Nat, +g: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_gt(ram, 0n), Contain.max(Nat.mul(g, 2n), Nat.div(Nat.mul(ram, 9n), 10n)), Contain.fallback(g))

def Contain.units.k(test: Bool, set: Bool, +ram: Nat, +gib: Nat, +mib: Nat, +g: Nat) -> Nat:
  match test set:
    case True{} _:
      mib
    case False{} True{}:
      Contain.clamp(Nat.mul(gib, g), Nat.mul(g, 2n), Contain.top(ram, g))
    case False{} False{}:
      Contain.clamp(Bool.pick(Nat, Nat.is_gt(ram, 0n), Nat.div(ram, 2n), Contain.fallback(g)), Nat.mul(g, 2n), Contain.top(ram, g))

# the limit: the test setting (taken as it is) wins, then agent.memory in
# GiB, else half the machine; ram in the same units
def Contain.units(+ram: Nat, +gib: Nat, +mib: Nat, +g: Nat) -> Nat:
  Contain.units.k(Nat.is_gt(mib, 0n), Nat.is_gt(gib, 0n), ram, gib, mib, g)

# the limit in MiB
def Contain.mib(+ram: Nat, +gib: Nat, +mib: Nat) -> Nat:
  Contain.units(ram, gib, mib, 1024n)

# the limit as systemd writes it, from /proc/meminfo's text (kB) and the
# two settings' values
def Contain.limit(meminfo: String, gib: String, mib: String) -> String:
  Nat.show(Contain.mib(Nat.div(Contain.ram(meminfo), 1024n), Contain.num.of(gib), Contain.num.of(mib))) ++ "M"

def Contain.safe.ok(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.or(U32.is_eq(c, 45), U32.is_eq(c, 95))))

# characters a unit's name may hold
def Contain.safe(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      SCon{Chr{Bool.pick(U32, Contain.safe.ok(c), c, 95)}, Contain.safe(t)}

# an agent's scope: one per thread and generation
def Contain.unit(thread: String, gen: String) -> String:
  "bp-agent-" ++ Contain.safe(thread) ++ "-" ++ Contain.safe(gen)

# `sh -c` script: the scope when the user's systemd answers, else the
# command itself. systemd-run --scope puts this very process in the scope
# and then runs the command in place, so the pid the hub holds is the
# agent's, and stdin, stdout and the working folder are the ones given. A
# scope that ends failed stays until it is read (Contain.show.args) and
# reset, which is how an out-of-memory end is told from any other.
# systemd-run expands ${VAR} and $VAR in the arguments it is given, and a
# prompt may hold such text: --expand-environment=no turns that off, and a
# systemd too old to have the flag gets every $ written $$ (its escape for a
# literal one). TimeoutStopSec bounds how long stopping a scope waits
# before it kills what is left.
def Contain.script() -> String:
  "l=$1; u=$2; d=$3; shift 3\nif command -v systemd-run >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then\n  if systemd-run --help 2>&1 | grep -q -- --expand-environment; then\n    exec systemd-run --user --scope --quiet --expand-environment=no \"--unit=$u\" \"--description=$d\" \"--property=MemoryMax=$l\" --property=MemorySwapMax=0 --property=OOMPolicy=kill --property=TimeoutStopSec=5s -- \"$@\"\n  fi\n  n=$#\n  while [ \"$n\" -gt 0 ]; do\n    a=$(printf '%sx' \"$1\" | sed 's/\\$/$$/g'); a=${a%x}\n    shift; set -- \"$@\" \"$a\"; n=$((n - 1))\n  done\n  exec systemd-run --user --scope --quiet \"--unit=$u\" \"--description=$d\" \"--property=MemoryMax=$l\" --property=MemorySwapMax=0 --property=OOMPolicy=kill --property=TimeoutStopSec=5s -- \"$@\"\nfi\nexec \"$@\"\n"

# the program and arguments that start cmd contained
def Contain.argv(limit: String, unit: String, tag: String, cmd: String, args: List<&2, String>) -> List<&2, String>:
  "-c" <> Contain.script() <> "sh" <> limit <> unit <> tag <> cmd <> args

# which hub a scope belongs to (its description): a hub stops only its
# own leftovers, so a test or throwaway hub on a copy of the log, whose
# home differs, never touches the live hub's agents
def Contain.tag(home: String) -> String:
  "backplane " ++ home


# the scope's own answer after its process ended
def Contain.show.args(unit: String) -> List<&2, String>:
  ["3", "systemctl", "--user", "show", "-p", "Result", "-p", "MemoryMax", unit ++ ".scope"]

def Contain.reset.args(unit: String) -> List<&2, String>:
  ["3", "systemctl", "--user", "reset-failed", unit ++ ".scope"]

def Contain.oom(result: String) -> Bool:
  String.starts_with(result, "oom-kill")

def Contain.words.g(+n: Nat, +g: Nat) -> String:
  Bool.pick(String, Nat.is_ge(n, g), Nat.show(Nat.div(n, g)) ++ " GB", Nat.show(n) ++ " MB")

# a limit in MiB for people: "8 GB", or "200 MB" below one GiB
def Contain.words(limit: String) -> String:
  Contain.words.g(Contain.num.of(limit), 1024n)

def Contain.exit_text.k(oom: Bool, +code: U32, limit: String) -> String:
  match oom:
    case True{}:
      "agent ran out of memory (limit " ++ Contain.words(limit) ++ ")"
    case False{}:
      "agent exited with code " ++ U32.show(code)

# what a turn that ended with the agent's exit says
def Contain.exit_text(code: U32, result: String, limit: String) -> String:
  Contain.exit_text.k(Contain.oom(result), code, limit)

# worth asking the scope: the process was killed by a signal
def Contain.ask(+code: U32) -> Bool:
  U32.is_ge(code, 128)

# a `Name=value` line's value in `systemctl show` text ("" when absent)
def Contain.prop.pick(+acc: String, hit: Bool, +l: String, +n: Nat) -> String:
  Bool.pick(String, Bool.not(String.is_empty(acc)), acc, Bool.pick(String, hit, String.trim(String.drop(l, n)), ""))

def Contain.prop.lines(ls: List<&2, String>, +p: String, +acc: String) -> String:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Contain.prop.lines(t, p, Contain.prop.pick(acc, String.starts_with(l, p), l, String.length(p)))

def Contain.prop(text: String, +p: String) -> String:
  Contain.prop.lines(String.split(text, '\n'), p, "")

# b is how many bytes make a MiB (1048576); laws use a small one
def Contain.mem.b(text: String, +b: Nat) -> String:
  Nat.show(Nat.div(Contain.num.of(Contain.prop(text, "MemoryMax=")), b)) ++ "M"

# what the scope's own answer (Contain.show.args) says about an agent a
# signal ended: the out-of-memory words with the limit the scope held, ""
# when it was not an out-of-memory kill
def Contain.why.b(+text: String, +code: U32, +b: Nat) -> String:
  Bool.pick(String, Contain.oom(Contain.prop(text, "Result=")), Contain.exit_text(code, "oom-kill", Contain.mem.b(text, b)), "")

def Contain.why(text: String, code: U32) -> String:
  Contain.why.b(text, code, 1048576n)
# ending a scope (a process of it ended or was retired): what is left in
# it is stopped, SIGTERM then SIGKILL after TimeoutStopSec; and scopes a
# previous hub run left
def Contain.stop.args(unit: String) -> List<&2, String>:
  ["10", "systemctl", "--user", "stop", unit ++ ".scope"]

def Contain.stale.args() -> List<&2, String>:
  ["5", "systemctl", "--user", "list-units", "--plain", "--no-legend", "--all", "bp-agent-*.scope"]

def Contain.first(ps: List<&2, String>) -> String:
  match ps:
    case +t <> _:
      t
    case Nil{}:
      ""

# the unit a `list-units` line names ("bp-agent-<thread>-<n>-<n>"), "" for
# any other line
def Contain.unit.line.k(+c: String) -> String:
  Bool.pick(String, Bool.and(String.starts_with(c, "bp-agent-"), String.ends_with(c, ".scope")), String.take(c, Nat.sub(String.length(c), 6n)), "")

def Contain.unit.line(l: String) -> String:
  Contain.unit.line.k(Contain.first(String.split(String.trim(l), ' ')))

def Contain.units.keep(+u: String, +rest: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(u), rest, u <> rest)

def Contain.units.of(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Contain.units.keep(Contain.unit.line(l), Contain.units.of(t))

# the units in `list-units` output
def Contain.stale(out: String) -> List<&2, String>:
  Contain.units.of(String.split(out, '\n'))

# a `list-units` line's description: what follows its four columns (unit,
# load, active, sub)
def Contain.lcols(ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Contain.units.keep(p, Contain.lcols(t))

def Contain.line.desc(l: String) -> String:
  String.join(List.drop(&2, String, Contain.lcols(String.split(String.trim(l), ' ')), 4n), " ")

# this hub's own: the line's description is its tag (Contain.tag)
def Contain.line.mine(+l: String, +tag: String) -> String:
  Bool.pick(String, String.eq(Contain.line.desc(l), tag), Contain.unit.line(l), "")

def Contain.mine.of(ls: List<&2, String>, +tag: String) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Contain.units.keep(Contain.line.mine(l, tag), Contain.mine.of(t, tag))

# the units in `list-units` output that this hub started (another hub's,
# a test's or a throwaway's, are left out)
def Contain.stale.mine(out: String, +tag: String) -> List<&2, String>:
  Contain.mine.of(String.split(out, '\n'), tag)

# the thread a unit was made for: its name without "bp-agent-" and the
# generation's two last parts
def Contain.thread.of.k(+ps: List<&2, String>) -> String:
  String.join(List.take(&2, String, ps, Nat.sub(List.length(&2, String, ps), 2n)), "-")

def Contain.thread.of(unit: String) -> String:
  Contain.thread.of.k(String.split(String.drop(unit, 9n), '-'))
