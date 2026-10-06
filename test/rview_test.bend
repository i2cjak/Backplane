import Base
import ./check.bend as C
import ../src/core/rview.bend as RV

# A window on another machine's hub (core/rview.bend): where the copy of a
# hub's file lives, what the hub answers, and that a path never leaves the
# folder it names.

def yn(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("a path already in the copies is not copied twice", RV.Rview.at("/c/remote/hb", "/c/remote/hb/p/child.kicad_sch"), "/c/remote/hb/p/child.kicad_sch")
    C.Check.str("encoding", RV.Rview.enc("a b/c\n=&é"), "a%20b/c%0A%3D%26%C3%A9")
    C.Check.str("a plain name stays", RV.Rview.enc("hw/board-1.kicad_pcb"), "hw/board-1.kicad_pcb")
    C.Check.str("a hub's folder", RV.Rview.key("http://100.64.0.2:3787"), "hhttp___100.64.0.2_3787")
    C.Check.str("copies live under the cache", RV.Rview.pre("/c", "http://b:1"), "/c/remote/hhttp___b_1")
    C.Check.str("a hub path is read in the copy", RV.Rview.at("/c/remote/hb", "/home/u/p/a.kicad_pcb"), "/c/remote/hb/home/u/p/a.kicad_pcb")
    C.Check.str("a path that climbs reads nothing", "[" ++ RV.Rview.at("/c/remote/hb", "/home/u/../../../etc/passwd") ++ "]", "[]")
    C.Check.str("no copy folder: as it was", RV.Rview.at("", "/home/u/p"), "/home/u/p")
    C.Check.str("a version is not a file here", RV.Rview.at("/c/remote/hb", "git\t/p/.git\tabc\t2\t/p/x"), "git\t/p/.git\tabc\t2\t/p/x")
    C.Check.str("back to the hub's path", RV.Rview.back("/c/remote/hb", "/c/remote/hb/home/u/p"), "/home/u/p")
    C.Check.str("a path elsewhere is not a copy", "[" ++ RV.Rview.back("/c/remote/hb", "/etc/passwd") ++ "]", "[]")
    C.Check.str("the file a source names", RV.Rview.want("/c/remote/hb", "/c/remote/hb/p", "/c/remote/hb/p/hw/a.step"), "hw/a.step")
    C.Check.str("none for the project's own board", "[" ++ RV.Rview.want("/c/remote/hb", "/c/remote/hb/p", "") ++ "]", "[]")
    C.Check.str("none for a hidden file", "[" ++ RV.Rview.want("/c/remote/hb", "/c/remote/hb/p", "/c/remote/hb/p/.env") ++ "]", "[]")
    C.Check.str("none outside the folder", "[" ++ RV.Rview.want("/c/remote/hb", "/c/remote/hb/p", "/c/remote/hb/q/a.step") ++ "]", "[]")
    C.Check.str("a spec's parts", RV.Rview.part(RV.Rview.spec("http://b:1", "/c/x", "t1", "tag#2"), 2n) ++ "|" ++ RV.Rview.part(RV.Rview.spec("http://b:1", "/c/x", "t1", "tag#2"), 3n), "t1|tag#2")
    C.Check.str("no hub, no spec", "[" ++ RV.Rview.spec("", "/c/x", "t", "g") ++ "]", "[]")
    C.Check.str("a thread's own folder", RV.Rview.root.k(True{}, False{}, "/h", "", "/home/u/p", ""), "/home/u/p")
    C.Check.str("a mirrored thread's folder is the cache the client names", RV.Rview.root.k(False{}, True{}, "/h", "beta", "", "/h/farfs/beta/home/u/p"), "/h/farfs/beta/home/u/p")
    C.Check.str("another link's cache is not it", "[" ++ RV.Rview.root.k(False{}, True{}, "/h", "beta", "", "/h/farfs/gamma/home/u/p") ++ "]", "[]")
    C.Check.str("nor a folder out of the cache", "[" ++ RV.Rview.root.k(False{}, True{}, "/h", "beta", "", "/h/farfs/beta/../../etc") ++ "]" ++ "[" ++ RV.Rview.root.k(False{}, True{}, "/h", "beta", "", "/etc") ++ "]" ++ "[" ++ RV.Rview.root.k(False{}, True{}, "/h", "beta", "", "") ++ "]", "[][][]")
    C.Check.str("a thread here ignores the claim", RV.Rview.root.k(True{}, False{}, "/h", "", "/home/u/p", "/etc"), "/home/u/p")
    C.Check.str("an unknown thread has none", "[" ++ RV.Rview.root.k(False{}, False{}, "/h", "", "/home/u/p", "") ++ "]", "[]")
    C.Check.str("a relative folder has none", "[" ++ RV.Rview.root.k(True{}, False{}, "/h", "", "p", "") ++ "]", "[]")
    C.Check.str("requests", Nat.show(RV.Rview.kind("/view/ver")) ++ Nat.show(RV.Rview.kind("/view/get")) ++ Nat.show(RV.Rview.kind("/view/git")) ++ Nat.show(RV.Rview.kind("/view/x")), "1230")
    C.Check.str("a listing of safe files", yn(RV.Rview.ask.ok("/view/ver", "/p", "", "hw/a.kicad_pcb\nb.step", "")), "yes")
    C.Check.str("a listing naming a hidden file", yn(RV.Rview.ask.ok("/view/ver", "/p", "", "a\n.ssh/id_rsa", "")), "no")
    C.Check.str("a listing naming ../", yn(RV.Rview.ask.ok("/view/ver", "/p", "", "../x", "")), "no")
    C.Check.str("a file", yn(RV.Rview.ask.ok("/view/get", "/p", "", "", "hw/a.kicad_pcb")), "yes")
    C.Check.str("a file up", yn(RV.Rview.ask.ok("/view/get", "/p", "", "", "../a")), "no")
    C.Check.str("a file absolute", yn(RV.Rview.ask.ok("/view/get", "/p", "", "", "/etc/passwd")), "no")
    C.Check.str("a hidden file", yn(RV.Rview.ask.ok("/view/get", "/p", "", "", ".env")), "no")
    C.Check.str("no folder, no answer", yn(RV.Rview.ask.ok("/view/get", "", "", "", "a.kicad_pcb")), "no")
    C.Check.str("a file of a commit", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "git\t/p/.git\tabc123\t2\t/p/hw/a.kicad_pcb")), "yes")
    C.Check.str("a commit of another repository", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "git\t/private/.git\tabc123\t8\t/private/a.kicad_pcb")), "no")
    C.Check.str("a hidden file of a commit", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "git\t/p/.git\tabc123\t2\t/p/.env")), "no")
    C.Check.str("a worktree's commit in its project's repository", yn(RV.Rview.ask.ok("/view/git", "/wt/x", "/p", "", "git\t/p/.git/worktrees/x\tabc123\t5\t/wt/x/a.kicad_pcb")), "yes")
    C.Check.str("a commit that is an option", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "git\t/p/.git\t--output=/tmp/x\t2\t/p/hw/a.kicad_pcb")), "no")
    C.Check.str("a git dir that is no history", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "git\t/etc\tabc123\t2\t/p/hw/a.kicad_pcb")), "no")
    C.Check.str("a path in a commit that climbs", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "git\t/p/.git\tabc123\t2\t/p/../../etc/passwd")), "no")
    C.Check.str("history outside git", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "git\t/p/.backplane/history.git\tabc123\t2\t/p/a.kicad_sch")), "yes")
    C.Check.str("a live file is not a version", yn(RV.Rview.ask.ok("/view/git", "/p", "", "", "/p/a.kicad_pcb")), "no")
    IO.pure(Unit, Unit{})
