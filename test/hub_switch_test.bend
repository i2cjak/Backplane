import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/app/nui.bend as N

# Duplicate names on two hubs must select the destination's bot even if
# an update arrives before its log. The same path covers cached switches,
# full adoption at home, and a missed BotSet arriving after a reply.
def json(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def seed(+prefix: String) -> U.Ui:
  U.Ui.info_set(U.Ui.fold([
    M.ThreadCreated{prefix ++ "-thread", "", "Kit", M.Local{}, "", "", "claude", "", 1n},
    M.BotSet{prefix ++ "-bot", "Kit", prefix ++ "-thread", 3n, "", 1n}], U.Ui.init(1n)), "origin", prefix ++ "-origin")

def selected() -> U.Ui:
  U.Act.ui(U.Bots.select(seed("local"), "local-bot"))

def remote() -> String:
  "http://localhost:3792"

def transition(+u: U.Ui, +hub: String) -> U.Ui:
  U.Act.ui(U.Far.open(False{}, u, hub, "Kit@other", "Kit"))

def update() -> J.Json:
  json("{\"t\":\"update\",\"state\":\"\"}")

def remote_log() -> J.Json:
  json("{\"t\":\"log\",\"since\":0,\"origin\":\"remote-origin\",\"info\":{},\"items\":[{\"$\":\"ThreadCreated\",\"id\":\"remote-thread\",\"title\":\"Kit\",\"env\":\"local\",\"provider\":\"claude\",\"at\":1},{\"$\":\"BotSet\",\"id\":\"remote-bot\",\"name\":\"Kit\",\"thread\":\"remote-thread\",\"look\":3,\"at\":1}]}")

def empty_log() -> J.Json:
  json("{\"t\":\"log\",\"since\":0,\"origin\":\"local-origin\",\"info\":{},\"items\":[]}")

def snapshot(+hub: String, +prefix: String) -> U.HubView:
  U.HubView{hub, U.Ui.state.of(seed(prefix)), U.Ui.infos(seed(prefix))}

# Exported to the replay measurement harness: the same actual client
# action/update/log sequence used by the native and web hosts.
def replay() -> String:
  U.Ui.sel(U.Ui.recv(U.Ui.recv(transition(selected(), remote()), update()), remote_log()))

def main() -> IO(Unit):
  +sw = transition(U.Ui.scratch_set(U.Ui.scratch_set(selected(), "@room", "old-room"), "@remote", "old@hub"), remote())
  +updated = U.Ui.recv(sw, update())
  +joined = U.Ui.recv(updated, remote_log())
  +home = N.Nui.adopt(N.Nui.init(transition(joined, ""), 800, 600), U.Ui.state.of(seed("local")), empty_log())
  +stale = U.Ui.info_set(U.Ui.info_set(U.Ui.adopt.raw(sw, U.Ui.state.of(seed("remote"))), "local.state.hub", remote()), "local.state.gen", "old-connection")
  +wrong = U.Ui.scratch_set(U.Ui.recv(sw, remote_log()), "@bot.want", "Kit")
  +wrong_hub = U.Ui.scratch_set(U.Ui.scratch_set(wrong, "@want.hub", "another-hub"), "@bot", "")
  +cache = U.HubCache.put(snapshot("", "local"), U.HubCache.put(snapshot(remote(), "remote"), Nil{}))
  +cached = U.Ui.cached(U.HubCache.get(cache, remote()), U.Ui.connection(sw, "remote#2"))
  +delta = U.Ui.recv(cached, json("{\"t\":\"log\",\"since\":2,\"origin\":\"remote-origin\",\"info\":{},\"items\":[{\"$\":\"MessagePosted\",\"thread\":\"remote-thread\",\"id\":\"new-message\",\"role\":\"user\",\"text\":\"hello\",\"at\":2}]}"))
  +many = U.HubCache.put(snapshot("third", "third"), cache)
  +waiting = U.Ui.recv(U.Ui.connection(sw, "remote#3"), empty_log())
  +later = U.Ui.recv(waiting, json("{\"t\":\"changes\",\"items\":[{\"$\":\"ThreadCreated\",\"id\":\"remote-thread\",\"title\":\"Kit\",\"env\":\"local\",\"provider\":\"claude\",\"at\":1},{\"$\":\"BotSet\",\"id\":\"remote-bot\",\"name\":\"Kit\",\"thread\":\"remote-thread\",\"look\":3,\"at\":1}]}"))
  +thread = U.Want.thread(U.Act.ui(U.Ui.machine(selected(), remote())), "remote-thread")
  +with_view = U.Ui.recv(joined, json("{\"t\":\"view\",\"thread\":\"remote-thread\",\"kind\":\"board\",\"path\":\"/tmp/remote.kicad_pcb\"}"))
  +home_view = U.Ui.info_set(U.Ui.info_set(seed("local"), "view.kind:shared", "board"), "view.path:shared", "/home/a.kicad_pcb")
  +away = U.Ui.info_set(U.Ui.recv(transition(home_view, remote()), remote_log()), "view.path:shared", "/remote/b.kicad_pcb")
  +back = U.Ui.cached(U.HubCache.get(U.HubCache.put(U.HubView{"", U.Ui.state.of(home_view), U.Ui.infos(home_view)}, Nil{}), ""), U.Ui.connection(transition(away, ""), "home#2"))
  do IO<Unit>:
    C.Check.str("another hub's log keeps no viewer of a colliding thread", U.Ui.info(U.Ui.recv(transition(home_view, remote()), remote_log()), "view.path:shared"), "")
    C.Check.str("back home, the other hub's viewer does not come along", Bool.show(String.eq(U.Ui.info(back, "view.path:shared"), "/remote/b.kicad_pcb")), "False")
    C.Check.str("back home, its own viewer", U.Ui.info(back, "view.path:shared"), "/home/a.kicad_pcb")
    C.Check.str("and home's reconnect keeps it", U.Ui.info(U.Ui.recv(back, empty_log()), "view.path:shared"), "/home/a.kicad_pcb")
    C.Check.str("nor after home's log", Bool.show(String.eq(U.Ui.info(U.Ui.recv(back, empty_log()), "view.path:shared"), "/remote/b.kicad_pcb")), "False")
    C.Check.str("machine clears selection", U.Ui.sel(sw), "")
    C.Check.str("machine clears bot", U.Ui.scratch(sw, "@bot"), "")
    C.Check.str("machine clears room", U.Ui.scratch(sw, "@room"), "")
    C.Check.str("machine clears remote", U.Ui.scratch(sw, "@remote"), "")
    C.Check.str("machine clears old model", Nat.show(U.Ui.seq(sw)), "0")
    C.Check.str("machine retains client identity", U.Ui.info(transition(U.Ui.set_cid(selected(), "window-client"), remote()), "cid"), "window-client")
    C.Check.str("pre-log update cannot consume want", U.Ui.scratch(updated, "@bot.want"), "Kit")
    C.Check.str("pre-log update cannot pick old bot", U.Ui.sel(updated), "")
    C.Check.str("destination log resolves duplicate name", U.Ui.sel(joined), "remote-thread")
    C.Check.str("destination bot selected", U.Ui.scratch(joined, "@bot"), "remote-bot")
    C.Check.str("resolved want consumed", U.Ui.scratch(joined, "@bot.want"), "")
    C.Check.str("home adoption resolves immediately", U.Ui.sel(N.Nui.ui(home)), "local-thread")
    C.Check.str("home adoption selects correct bot", U.Ui.scratch(N.Nui.ui(home), "@bot"), "local-bot")
    C.Check.str("stale generation cannot consume want", U.Ui.scratch(U.Bots.wanted(stale), "@bot.want"), "Kit")
    C.Check.str("stale generation cannot select matching bot", U.Ui.sel(U.Bots.wanted(stale)), "")
    C.Check.str("wrong hub cannot consume want", U.Ui.scratch(U.Bots.wanted(wrong_hub), "@bot.want"), "Kit")
    C.Check.str("cached state displays before log", U.Ui.sel(cached), "remote-thread")
    C.Check.str("cached sequence retained", Nat.show(U.Ui.seq(cached)), "2")
    C.Check.str("cached origin retained", U.Ui.info(cached, "origin"), "remote-origin")
    C.Check.str("cached pending rebinds to connection", U.Ui.scratch(cached, "@want.gen"), "remote#2")
    C.Check.str("delta reconnect retains bot", U.Ui.sel(delta), "remote-thread")
    C.Check.str("delta reconnect advances sequence", Nat.show(U.Ui.seq(delta)), "3")
    C.Check.str("cache bounded to two hubs", Nat.show(List.length(&2, U.HubView, many)), "2")
    C.Check.str("cache always retains home", Bool.show(Maybe.is_some(&2, U.HubView, U.HubCache.get(many, ""))), "True")
    C.Check.str("cache evicts earlier linked hub", Bool.show(Maybe.is_some(&2, U.HubView, U.HubCache.get(many, remote()))), "False")
    C.Check.str("wrong cache cannot install", Nat.show(U.Ui.seq(U.Ui.cached(Some{snapshot("wrong", "wrong")}, sw))), "0")
    C.Check.str("missing bot stays pending on join", U.Ui.scratch(waiting, "@bot.want"), "Kit")
    C.Check.str("later BotSet resolves bound want", U.Ui.sel(later), "remote-thread")
    C.Check.str("thread request waits before log", U.Ui.sel(U.Ui.recv(thread, update())), "")
    C.Check.str("manual choice cancels pending thread", U.Ui.scratch(U.Act.ui(U.Ui.act(thread, "select", "manual")), "@thread.want"), "")
    C.Check.str("thread request resolves destination", U.Ui.sel(U.Ui.recv(thread, remote_log())), "remote-thread")
    C.Check.str("reselect restores destination viewer", Bool.show(U.Ui.panel(with_view)), "True")
    C.Check.str("chat has timeline", Bool.show(U.Ui.timeline(joined)), "True")
    C.Check.str("space skips timeline", Bool.show(U.Ui.timeline(U.Ui.scratch_set(joined, "@btab", "space"))), "False")
    C.Check.str("browser skips timeline", Bool.show(U.Ui.timeline(U.Ui.scratch_set(joined, "@btab", "browser"))), "False")
    C.Check.str("settings skips timeline", Bool.show(U.Ui.timeline(U.Ui.flag_on(joined, "settings"))), "False")
    C.Check.str("transition has no timeline", Bool.show(U.Ui.timeline(sw)), "False")
