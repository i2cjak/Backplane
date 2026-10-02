import Base
import ./check.bend as C
import ../src/core/contain.bend as CT

# Agent containment (core/contain.bend): the limit, the scope's name and
# command line, the words for an out-of-memory end.

def meminfo() -> String:
  "MemTotal:       16000000 kB\nMemFree:         1000 kB\n"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("ram read", Nat.show(CT.Contain.ram(meminfo())), "16000000")
    C.Check.str("no ram", Nat.show(CT.Contain.ram("nothing")), "0")
    C.Check.str("half the machine", Nat.show(CT.Contain.mib(16000n, 0n, 0n)), "8000")
    C.Check.str("never under 2 GiB", Nat.show(CT.Contain.mib(1000n, 0n, 0n)), "2048")
    C.Check.str("a setting in GiB", Nat.show(CT.Contain.mib(16000n, 4n, 0n)), "4096")
    C.Check.str("a setting under 2 GiB is raised", Nat.show(CT.Contain.mib(16000n, 1n, 0n)), "2048")
    C.Check.str("90 percent at most", Nat.show(CT.Contain.mib(16000n, 100n, 0n)), "14400")
    C.Check.str("test MiB wins and is not clamped", Nat.show(CT.Contain.mib(16000n, 4n, 200n)), "200")
    C.Check.str("unknown ram", Nat.show(CT.Contain.mib(0n, 0n, 0n)), "8192")
    C.Check.str("limit text", CT.Contain.limit(meminfo(), "", "200"), "200M")
    C.Check.str("limit default", CT.Contain.limit(meminfo(), "", ""), "7812M")
    C.Check.str("unit name", CT.Contain.unit("t/1 x", "170-9"), "bp-agent-t_1_x-170-9")
    C.Check.str("argv", Nat.show(List.length(&2, String, CT.Contain.argv("1K", "u", "t", "claude", ["-p", "x"]))), "9")
    C.Check.str("own scope", Bool.show(CT.Contain.mine(" backplane /h\n", CT.Contain.tag("/h"))), "True")
    C.Check.str("another hub's scope", Bool.show(CT.Contain.mine("backplane /other", CT.Contain.tag("/h"))), "False")
    C.Check.str("no expansion", Bool.show(String.contains(CT.Contain.script(), "--expand-environment=no")), "True")
    C.Check.str("oom words", CT.Contain.exit_text(137, "oom-kill", "200M"), "agent ran out of memory (limit 200 MB)")
    C.Check.str("oom words GB", CT.Contain.exit_text(137, "oom-kill", "8192M"), "agent ran out of memory (limit 8 GB)")
    C.Check.str("other exit", CT.Contain.exit_text(3, "success", "200M"), "agent exited with code 3")
    C.Check.str("why: oom with the scope's limit", CT.Contain.why("Result=oom-kill\nMemoryMax=209715200\n", 137), "agent ran out of memory (limit 200 MB)")
    C.Check.str("why: gigabytes", CT.Contain.why("MemoryMax=8589934592\nResult=oom-kill\n", 137), "agent ran out of memory (limit 8 GB)")
    C.Check.str("why: not oom", CT.Contain.why("Result=success\nMemoryMax=209715200\n", 137), "")
    C.Check.str("why: no answer", CT.Contain.why("", 137), "")
    C.Check.str("stop args", String.join(CT.Contain.stop.args("u"), " "), "10 systemctl --user stop u.scope")
    C.Check.str("stale units", String.join(CT.Contain.stale("bp-agent-t1-5-100-7.scope loaded active running [systemd-run] sleep\nother.scope loaded active running x\n"), ","), "bp-agent-t1-5-100-7")
    C.Check.str("thread of a unit", CT.Contain.thread.of("bp-agent-t17-5-100-7"), "t17-5")
    C.Check.str("ask only after a signal", Bool.show(CT.Contain.ask(137)), "True")
    C.Check.str("a plain exit is not asked", Bool.show(CT.Contain.ask(1)), "False")
