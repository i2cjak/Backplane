import Base

# Shell that runs on Linux and macOS alike. macOS has no timeout(1) or
# setsid(1) (coreutils and util-linux are GNU's); it does have perl, whose
# alarm survives exec and whose POSIX::setsid does what setsid(1) does.

# `tmo SECS CMD ARGS...`: CMD, stopped after SECS (killed a second later)
def Port.tmo() -> String:
  "tmo() { t=$1; shift; if command -v timeout >/dev/null 2>&1; then timeout -k 1 \"$t\" \"$@\"; elif command -v gtimeout >/dev/null 2>&1; then gtimeout -k 1 \"$t\" \"$@\"; else perl -e 'alarm shift; exec {$ARGV[0]} @ARGV or exit 127' \"$t\" \"$@\"; fi; }; "

# sh's arguments that run timeout(1)'s (SECS CMD ARGS...):
# P.Proc.run("sh", Port.timeout(["5", "tailscale", ...]))
def Port.timeout(+args: List<&2, String>) -> List<&2, String>:
  "-c" <> (Port.tmo() ++ "tmo \"$@\"") <> "sh" <> args
