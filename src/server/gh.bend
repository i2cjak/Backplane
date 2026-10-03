import Base
import ./proc.bend as P
import ../core/gh.bend as G
import ../core/port.bend as PT

# Running gh as the right GitHub account (src/core/gh.bend decides which).
# With one account (or none, or a token already in the environment) gh
# runs as it is. With several, each is tried in G.Gh.order until GitHub
# stops refusing; the one that worked is remembered in the repository's
# git config (backplane.ghuser). gh's active account is never switched.
#
# A token never goes on a command line (any user on the machine can read
# those): a small sh fetches it with `gh auth token` and exports it into
# the environment of the one command it runs, which only its owner can
# read. Nothing prompts: gh and git answer instead of waiting on a tty.

def GhRun.quiet() -> List<&2, String>:
  ["GH_PROMPT_DISABLED=1", "GH_NO_UPDATE_NOTIFIER=1", "GIT_TERMINAL_PROMPT=0"]

# cmd as it is, without prompts
def GhRun.plain(+cmd: String, +args: List<&2, String>, +cwd: String) -> IO(P.Ran):
  P.Proc.run("env", List.append(&2, String, GhRun.quiet(), cmd <> args), cwd)

def GhRun.as.sh() -> String:
  (PT.Port.tmo() ++ "h=$1 u=$2 v=$3; shift 3; t=$(tmo 20 gh auth token --hostname \"$h\" --user \"$u\" 2>/dev/null) && [ -n \"$t\" ] || exit 97; export \"$v=$t\" GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GIT_TERMINAL_PROMPT=0; exec \"$@\"")

# cmd with the account's token (exit 97: gh has no token for it)
def GhRun.as(+cwd: String, +host: String, +user: String, +cmd: String, +args: List<&2, String>) -> IO(P.Ran):
  P.Proc.run("sh", List.append(&2, String, ["-c", GhRun.as.sh(), "sh", host, user, G.Gh.token_var(host), cmd], args), cwd)

def GhRun.text(r: P.Ran) -> String:
  match r:
    case P.Ran{_, o}:
      o

def GhRun.code(r: P.Ran) -> U32:
  match r:
    case P.Ran{c, _}:
      c

def GhRun.remember(first: Bool, +cwd: String, +user: String, +r: P.Ran) -> IO(P.Ran):
  match first:
    case True{}:
      IO.pure(P.Ran, r)
    case False{}:
      IO.bind(P.Ran, P.Ran, P.Proc.run("git", ["config", "--local", "backplane.ghuser", user], cwd), _ => IO.pure(P.Ran, r))

# after one account's try: done, or (refused, or no token) the next
def GhRun.next(+r: P.Ran, first: Bool, +cwd: String, +user: String, k: Unit -> IO(P.Ran)) -> IO(P.Ran):
  Bool.pick(IO(P.Ran), U32.is_eq(GhRun.code(r), 0), GhRun.remember(first, cwd, user, r),
    Bool.pick(IO(P.Ran), Bool.or(U32.is_eq(GhRun.code(r), 97), G.Gh.refused(GhRun.text(r))), k(Unit{}), IO.pure(P.Ran, r)))

# every account refused: what the command says as it is
def GhRun.try(us: List<&2, String>, first: Bool, +cwd: String, +host: String, +cmd: String, +args: List<&2, String>, +plain: List<&2, String>) -> IO(P.Ran):
  match us:
    case Nil{}:
      GhRun.plain(cmd, plain, cwd)
    case +u <> t:
      IO.bind(P.Ran, P.Ran, GhRun.as(cwd, host, u, cmd, args), r => GhRun.next(r, first, cwd, u, _ => GhRun.try(t, False{}, cwd, host, cmd, args, plain)))

def GhRun.accounts(+cwd: String, +host: String) -> IO(List<&2, G.GhAcct>):
  IO.bind(P.Ran, List<&2, G.GhAcct>, GhRun.plain("sh", PT.Port.timeout(["20", "gh", "auth", "status", "--hostname", host]), cwd),
    r => IO.pure(List<&2, G.GhAcct>, G.Gh.accounts(GhRun.text(r), host)))

def GhRun.saved(+cwd: String) -> IO(String):
  IO.bind(P.Ran, String, P.Proc.run("git", ["config", "--get", "backplane.ghuser"], cwd), +r => IO.pure(String, Bool.pick(String, U32.is_eq(GhRun.code(r), 0), String.trim(GhRun.text(r)), "")))

def GhRun.pick(+as: List<&2, G.GhAcct>, +saved: String, +cwd: String, +owner: String, +host: String, +cmd: String, +args: List<&2, String>, +plain: List<&2, String>) -> IO(P.Ran):
  Bool.pick(IO(P.Ran), Nat.is_le(List.length(&2, G.GhAcct, as), 1n), GhRun.plain(cmd, plain, cwd),
    GhRun.try(G.Gh.order(as, saved, owner), True{}, cwd, host, cmd, args, plain))

def GhRun.remote(+url: String, +cwd: String, +cmd: String, +args: List<&2, String>, +plain: List<&2, String>) -> IO(P.Ran):
  Bool.pick(IO(P.Ran), String.is_empty(G.Gh.remote.host(G.Gh.remote(url))), GhRun.plain(cmd, plain, cwd),
    IO.bind(List<&2, G.GhAcct>, P.Ran, GhRun.accounts(cwd, G.Gh.remote.host(G.Gh.remote(url))), as =>
      IO.bind(String, P.Ran, GhRun.saved(cwd), saved =>
        GhRun.pick(as, saved, cwd, G.Gh.remote.owner(G.Gh.remote(url)), G.Gh.remote.host(G.Gh.remote(url)), cmd, args, plain))))

# the repository's GitHub remote: origin, else the first remote
def GhRun.url(+cwd: String) -> IO(String):
  IO.bind(P.Ran, String, P.Proc.run("sh", ["-c", "git remote get-url origin 2>/dev/null || git remote get-url \"$(git remote | head -n 1)\" 2>/dev/null"], cwd),
    +r => IO.pure(String, Bool.pick(String, U32.is_eq(GhRun.code(r), 0), String.trim(GhRun.text(r)), "")))

# cmd args as the repository's account (plain: the args to run it with
# when no account is chosen)
def GhRun.run(+cwd: String, +cmd: String, +args: List<&2, String>, +plain: List<&2, String>) -> IO(P.Ran):
  IO.bind(String, P.Ran, GhRun.url(cwd), url => GhRun.remote(url, cwd, cmd, args, plain))

# gh, as the repository's account
def GhRun.gh(+cwd: String, +args: List<&2, String>) -> IO(P.Ran):
  GhRun.run(cwd, "gh", args, args)

def GhRun.push.k(+r: P.Ran, +https: Bool, +cwd: String, +args: List<&2, String>) -> IO(P.Ran):
  Bool.pick(IO(P.Ran), Bool.or(U32.is_eq(GhRun.code(r), 0), Bool.not(Bool.and(https, G.Gh.refused(GhRun.text(r))))), IO.pure(P.Ran, r),
    GhRun.run(cwd, "git", List.append(&2, String, ["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"], args), args))

# git push as the user's git has it set up; refused over https, again
# through gh's credential helper with each account in turn
def GhRun.push(+cwd: String, +args: List<&2, String>) -> IO(P.Ran):
  IO.bind(P.Ran, P.Ran, GhRun.plain("git", args, cwd), r =>
    IO.bind(String, P.Ran, GhRun.url(cwd), url => GhRun.push.k(r, String.starts_with(url, "https://"), cwd, args)))
