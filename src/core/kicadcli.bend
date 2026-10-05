import Base

# Which kicad-cli the hub may use on a machine (pure; laws kicad_cli_*).
# Backplane KiCad (the fork, with IPC) is built for Linux x86-64 and for
# Apple-silicon Macs; elsewhere it is never picked or installed. Each build
# installs in a folder of its own, so a copy for another machine (the Linux
# one a Mac once downloaded, which cannot run there) is never picked. A Mac
# without the fork uses its KiCad.app, in /Applications or ~/Applications.
# server/kicad.bend resolves the first of these that exists (after an
# explicit BACKPLANE_KICAD_CLI), else PATH's.

def Cli.asset.k(+p: String) -> String:
  Bool.pick(String, String.eq(p, "Linux x86_64"), "linux-x86_64", Bool.pick(String, String.eq(p, "Darwin arm64"), "macos-arm64", ""))

# the fork's build for a machine (`uname -sm`), as its release names it; ""
# where there is none
def Cli.asset(+plat: String) -> String:
  Cli.asset.k(String.trim(plat))

def Cli.fork_runs(+plat: String) -> Bool:
  Bool.not(String.is_empty(Cli.asset(plat)))

def Cli.is_mac(+plat: String) -> Bool:
  String.starts_with(String.trim(plat), "Darwin")

# where the fork installs: Linux x86-64 keeps <data>/kicad/<version> (where
# installs have always been), any other build <version>-<asset>
def Cli.dir(+data: String, +ver: String, +asset: String) -> String:
  data ++ "/kicad/" ++ Bool.pick(String, String.eq(asset, "linux-x86_64"), ver, ver ++ "-" ++ asset)

# the release asset holding a build
def Cli.package(+asset: String, +ver: String) -> String:
  "backplane-kicad-" ++ asset ++ "-" ++ ver ++ ".tar.gz"

# the fork beside this install, then in our data directory
def Cli.fork(+exe: String, +data: String, +ver: String, +asset: String) -> List<&2, String>:
  [exe ++ "/kicad/bin/kicad-cli", Cli.dir(data, ver, asset) ++ "/bin/kicad-cli"]

def Cli.mac(+user: String) -> List<&2, String>:
  ["/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli", user ++ "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"]

def Cli.system() -> List<&2, String>:
  ["/usr/bin/kicad-cli", "/usr/local/bin/kicad-cli"]

def Cli.candidates.k(fork: Bool, mac: Bool, +exe: String, +data: String, +ver: String, +asset: String, +user: String) -> List<&2, String>:
  match fork mac:
    case True{} True{}:
      List.append(&2, String, Cli.fork(exe, data, ver, asset), List.append(&2, String, Cli.mac(user), Cli.system()))
    case True{} False{}:
      List.append(&2, String, Cli.fork(exe, data, ver, asset), Cli.system())
    case False{} True{}:
      List.append(&2, String, Cli.mac(user), Cli.system())
    case False{} False{}:
      Cli.system()

# where to look, in order, on a machine (`uname -sm`; user is $HOME)
def Cli.candidates(+plat: String, +exe: String, +data: String, +ver: String, +user: String) -> List<&2, String>:
  Cli.candidates.k(Cli.fork_runs(plat), Cli.is_mac(plat), exe, data, ver, Cli.asset(plat), user)

# what installing the fork answers where there is no build of it
def Cli.no_fork() -> String:
  "Backplane KiCad is built for Linux x86-64 and Apple-silicon Macs only: on this machine install KiCad from kicad.org/download (Backplane finds it)"
