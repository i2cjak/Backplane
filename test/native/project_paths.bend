import Base
import ../check.bend as C
import ../../src/server/proc.bend as P
import ../../src/server/server.bend as S

# Run the picker's real shell commands with the host's own utilities.
# bend test/native/project_paths.bend -o build/project_paths && build/project_paths

def Paths.out(r: P.Ran) -> String:
  match r:
    case P.Ran{code, out}:
      U32.show(code) ++ "|" ++ String.trim(out)

def Paths.path(r: P.Ran) -> String:
  match r:
    case P.Ran{_, out}:
      String.trim(out)

def main() -> IO(Unit):
  do IO<Unit>:
    tmp : P.Ran <- P.Proc.run("mktemp", ["-d", "/tmp/bp-project-paths.XXXXXX"], "/")
    +root : String = Paths.path(tmp)
    mk : P.Ran <- P.Proc.run("sh", ["-c", "set -e; cd \"$1\"; mkdir 'board space' 'board space/z' 'board space/.hidden' 'board space/a'; touch plain; ln -s 'board space' link; ln -s missing broken", "sh", root], "/")
    +resolved : P.Ran <- S.FsJob.sh(S.FsJob.resolve.sh(), root)
    +physical : String = Paths.path(resolved)
    C.Check.str("existing folder", Paths.out(resolved), "0|" ++ physical)
    linked : P.Ran <- S.FsJob.sh(S.FsJob.resolve.sh(), root ++ "/link/../link")
    C.Check.str("symlinks and spaces", Paths.out(linked), "0|" ++ physical ++ "/board space")
    home : P.Ran <- P.Proc.run("sh", ["-c", "HOME=\"$2\"; CDPATH=\"$2\"; export HOME CDPATH; " ++ S.FsJob.resolve.sh(), "sh", "~/link", root], "/")
    C.Check.str("home expansion with CDPATH", Paths.out(home), "0|" ++ physical ++ "/board space")
    relative : P.Ran <- P.Proc.run("sh", ["-c", "HOME=\"$2\"; export HOME; " ++ S.FsJob.resolve.sh(), "sh", "board space", root], "/")
    C.Check.str("relative path under home", Paths.out(relative), "0|" ++ physical ++ "/board space")
    listed : P.Ran <- S.FsJob.sh(S.FsJob.list.sh(), root ++ "/link")
    C.Check.str("sorted child folders", Paths.out(listed), "0|" ++ physical ++ "/board space\n.hidden\na\nz")
    missing : P.Ran <- S.FsJob.sh(S.FsJob.resolve.sh(), root ++ "/missing")
    C.Check.str("missing folder", Paths.out(missing), "2|no such folder: " ++ root ++ "/missing")
    plain : P.Ran <- S.FsJob.sh(S.FsJob.resolve.sh(), root ++ "/plain")
    C.Check.str("regular file", Paths.out(plain), "2|not a folder: " ++ root ++ "/plain")
    broken : P.Ran <- S.FsJob.sh(S.FsJob.resolve.sh(), root ++ "/broken")
    C.Check.str("broken symlink", Paths.out(broken), "2|no such folder: " ++ root ++ "/broken")
    made : P.Ran <- S.FsJob.sh(S.FsJob.mkdir.sh(), root ++ "/new board/child")
    C.Check.str("create with missing parents", Paths.out(made), "0|" ++ physical ++ "/new board/child")
    again : P.Ran <- S.FsJob.sh(S.FsJob.mkdir.sh(), root ++ "/new board/child")
    C.Check.str("refuse existing folder", Paths.out(again), "3|already exists: " ++ root ++ "/new board/child")
    rm : P.Ran <- P.Proc.run("rm", ["-rf", root], "/")
    return Unit{}
