import Foundation
import Observation
import UIKit

// Feeds every paired hub's socket and the user's actions to the Bend
// client, and shows whatever screen it answers. Runs its commands (send,
// copy, scroll, notify) and keeps the Live Activity in step with the
// screen's island. Each hub is keyed by its host:port (Pairing.key).
@MainActor
@Observable
final class AppModel {
    private let engine = Engine()
    // the client's state, kept for the next launch (StateStore)
    private let kept = StateStore()
    // something changed since the state was last kept
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var hubs: [String: Hub] = [:]
    // push tokens by kind, sent again to a hub paired later
    @ObservationIgnored private var tokens: [String: String] = [:]
    // each hub's Live Activity token, sent again when that hub reconnects
    @ObservationIgnored private var hubTokens: [String: String] = [:]
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var island: IslandController?
    @ObservationIgnored private var ready = false

    // the pairing links, one per hub, in the order they were paired
    private(set) var links: [String] = UserDefaults.standard.stringArray(forKey: "links")
        ?? UserDefaults.standard.string(forKey: "link").map { [$0] } ?? []
    private(set) var screen: Screen?
    // the island tapped while several threads work: which one to open
    var picking = false
    // the board viewer's plots, which come straight from the socket
    let plots = PlotStore()
    // the composer's text, owned here so typing never waits on Bend
    var composer = ""
    private(set) var scrolls = 0
    // an entry of the open thread to show (a "jump"): n counts the jumps, so
    // the same entry shown twice scrolls twice
    private(set) var jump: Jump?
    // a jump waiting for a screen that holds its entry (the jump opens folds
    // and pages first), and how many more screens it waits
    @ObservationIgnored private var jumping: (id: String, left: Int)?
    // each hub's socket as this phone sees it (HubsView, the list's pill)
    private(set) var conn: [String: HubConn] = [:]
    // the last screen of each thread shown, by its id: a thread tapped
    // again shows at once while its fresh screen is made
    private(set) var seen: [String: ThreadView] = [:]
    @ObservationIgnored private var seenOrder: [String] = []
    // messages sent from this phone the client has not answered yet: shown
    // at once as sending, dropped when the answer (with its own sending
    // row) is on screen
    private(set) var outgoing: [Outgoing] = []
    // the navigation stack's path: moved at once by a tap or a swipe back,
    // and by the screen only when its selection changes, so a screen that
    // answers an older action never pulls a thread back open
    private(set) var path: [String] = []
    @ObservationIgnored private var shownSel = ""
    // a new thread's page was opened while the hub makes it
    @ObservationIgnored private var shownMaking = false
    // the hub whose plots are drawn: frames from any other are dropped
    @ObservationIgnored private var shownHub = ""
    var active = true
    // drafts sent to Bend and not yet answered: until then a screen may
    // carry an older draft than the one on screen
    @ObservationIgnored private var typing = 0
    #if DEBUG
    // headless checks: SIMCTL_CHILD_BACKPLANE_SELECT=<thread id> opens it
    @ObservationIgnored private var opening = ProcessInfo.processInfo.environment["BACKPLANE_SELECT"]
    // and SIMCTL_CHILD_BACKPLANE_VIEW=board (or schematic) opens its viewer
    @ObservationIgnored private var viewing = ProcessInfo.processInfo.environment["BACKPLANE_VIEW"]
    // and SIMCTL_CHILD_BACKPLANE_ACTS="diff;;term-toggle=$SIZE;;…" runs
    // actions two seconds apart once the thread is open
    @ObservationIgnored private var acting = ProcessInfo.processInfo.environment["BACKPLANE_ACTS"]
    // and SIMCTL_CHILD_BACKPLANE_BOT=<bot or room name> opens it (then ACTS run)
    @ObservationIgnored private var botting = ProcessInfo.processInfo.environment["BACKPLANE_BOT"]
    #endif

    // this install's id, part of every message id (a resend is stored once)
    private static var cid: String {
        if let c = UserDefaults.standard.string(forKey: "cid") { return c }
        let c = String(format: "%08x", UInt32.random(in: 0 ... UInt32.max))
        UserDefaults.standard.set(c, forKey: "cid")
        return c
    }

    // a thread's draft, written at once (a crash loses nothing typed); "" forgets it
    private static func keep(_ thread: String, _ text: String) {
        let d = UserDefaults.standard
        var o = (try? JSONSerialization.jsonObject(with: Data((d.string(forKey: "drafts") ?? "{}").utf8))) as? [String: String] ?? [:]
        o[thread] = text.isEmpty ? nil : text
        if let data = try? JSONSerialization.data(withJSONObject: o), let s = String(data: data, encoding: .utf8) {
            d.set(s, forKey: "drafts")
        }
    }

    private static var env: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    init() {
        #if DEBUG
        if let l = ProcessInfo.processInfo.environment["BACKPLANE_LINK"] { links = l.split(separator: " ").map(String.init) }
        #endif
        notifier.open = { [weak self] id in self?.act("select", id) }
        notifier.viewing = { [weak self] id in self?.active == true && self?.screen?.sel == id }
        let e = engine
        Task {
            apply(await e.start(Self.cid, UserDefaults.standard.string(forKey: "drafts") ?? "{}"))
            // the state kept at the last launch: the screen shows at once, and
            // each hub then sends only what came since
            if let text = kept.load() {
                apply(await e.load(text))
                for l in links { if let k = Pairing.key(l) { apply(await e.offline(k)) } }
            }
            ready = true
            island = IslandController { [weak self] kind, token, hub in self?.register(kind, token, hub: hub) }
            connect()
            #if DEBUG
            // headless checks pair from the environment: no permission prompt over the screen
            if ProcessInfo.processInfo.environment["BACKPLANE_LINK"] == nil, !links.isEmpty { notifier.setUp() }
            #else
            if !links.isEmpty { notifier.setUp() }
            #endif
        }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(30))
                if ready { apply(await e.tick(Int(Date().timeIntervalSince1970))) }
                keep()
            }
        }
    }

    // a new hub, or a new link to one already paired (it replaces the old)
    func pair(_ text: String) {
        let l = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let k = Pairing.key(l) else { return }
        links = links.filter { Pairing.key($0) != k } + [l]
        save()
        notifier.setUp()
        connect()
    }

    func unpair(_ key: String) {
        links = links.filter { Pairing.key($0) != key }
        save()
        connect()
    }

    private func save() {
        UserDefaults.standard.set(links, forKey: "links")
        UserDefaults.standard.removeObject(forKey: "link")
    }

    // an APNs token for this device's alerts (from the app delegate)
    func registered(_ token: Data) {
        register("alert", token.map { String(format: "%02x", $0) }.joined())
    }

    // a token with a hub (a Live Activity's) goes to that hub alone
    private func register(_ kind: String, _ token: String, hub: String? = nil) {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        if let h = hub {
            hubTokens[h] = token
            run { await $0.register(at: h, kind, token, env: Self.env, bundle: bundle) }
            return
        }
        tokens[kind] = token
        run { await $0.register(kind, token, env: Self.env, bundle: bundle) }
    }

    // one socket per paired hub: new hubs connect, unpaired ones hang up
    private func connect() {
        guard ready else { return }
        var keyed: [String: String] = [:]
        var keys: [String] = []
        for l in links {
            if let k = Pairing.key(l), keyed[k] == nil { keyed[k] = l; keys.append(k) }
        }
        for (k, h) in hubs where keyed[k] == nil {
            h.stop()
            hubs[k] = nil
        }
        let e = engine
        let fresh = keys.contains { hubs[$0] == nil }
        Task {
            apply(await e.hubs(keys))
            for (k, l) in keyed where hubs[k] == nil { open(k, l) }
            // a hub paired later learns this phone's push tokens too
            if fresh {
                for (kind, token) in tokens { register(kind, token) }
                for (hub, token) in hubTokens where keyed[hub] != nil { register("activity", token, hub: hub) }
            }
        }
    }

    private func open(_ key: String, _ link: String) {
        let e = engine
        let h = Hub(url: {
                let r = try? JSONDecoder().decode(Resume.self, from: Data(await e.resume(key).utf8))
                return Pairing.socket(link, since: r?.since ?? "0", origin: r?.origin ?? "")
            },
            onConnecting: { [weak self] in
                self?.conn[key, default: HubConn()].phase = .connecting
            },
            onOpen: { [weak self] in
                if self?.shownHub == key { self?.plots.reset() }
                self?.conn[key, default: HubConn()].phase = .syncing
                self?.run { await $0.online(key, true) }
            },
            // plots go straight to the viewer, never through the Bend client,
            // and only the hub in focus draws
            onMessage: { [weak self] d in
                if PlotStore.isPlot(d) {
                    if self?.shownHub == key { self?.plots.receive(d) }
                } else {
                    self?.received(key, d)
                }
            },
            onClose: { [weak self] in
                self?.conn[key, default: HubConn()].phase = .offline
                self?.run { await $0.online(key, false) }
            })
        hubs[key] = h
        h.start()
    }

    // a frame from hub key: the first after a connect carries what this
    // phone missed, and the hub is up to date once it is folded in
    private func received(_ key: String, _ d: Data) {
        dirty = true
        var c = conn[key, default: HubConn()]
        c.heard = Date()
        let catching = c.phase != .online
        if catching { c.bytes = d.count }
        conn[key] = c
        let e = engine
        Task {
            apply(await e.recv(key, d.base64EncodedString()))
            if catching, conn[key]?.phase == .syncing { conn[key]?.phase = .online }
        }
    }

    private func run(_ f: @escaping (Engine) async -> Out?) {
        let e = engine
        Task { apply(await f(e)) }
    }

    func act(_ action: String, _ value: String = "") {
        run { await $0.act(action, value) }
    }

    // where the hub in focus serves a path ("/img?path=…"), with its token
    func web(_ path: String) -> URL? {
        guard let s = screen, let l = links.first(where: { Pairing.key($0) == s.hub }) ?? links.first else { return nil }
        return Pairing.web(l, path)
    }

    // a file for the next message: one POST /attach to the thread's hub with
    // the file as the body (no base64, no pieces through the engine); the
    // hub's answer goes back as "attach-end", as an attach.put's would
    func attach(_ data: Data, name: String) {
        guard !data.isEmpty, let s = screen, let named = s.thread?.id,
              let l = links.first(where: { Pairing.key($0) == s.hub }) ?? links.first else { return }
        // the hub's own id: over several hubs the screen names it "<hub>|<id>"
        let thread = named.split(separator: "|").last.map(String.init) ?? named
        let key = String(format: "%08x", UInt32.random(in: 0 ... UInt32.max))
        guard let url = Pairing.http(l, path: "/attach", query: [URLQueryItem(name: "thread", value: thread),
                                                                 URLQueryItem(name: "key", value: key), URLQueryItem(name: "name", value: name)]) else { return }
        var req = URLRequest(url: url, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        // the engine decides: one over the cap it refuses, and nothing goes
        let up = (try? JSONSerialization.data(withJSONObject: ["name": name, "size": data.count] as [String: Any])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        act("attach-up", up)
        guard data.count <= s.thread?.cap ?? 10_485_760 else { return }
        Task {
            var answer = ""
            do {
                let (body, _) = try await URLSession.shared.upload(for: req, from: data)
                answer = String(data: body, encoding: .utf8) ?? ""
            } catch {
                answer = ""
            }
            let answered = (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) is [String: Any]
            if !answered {
                let o: [String: Any] = ["text": "the upload did not reach the hub", "thread": thread, "upload": true]
                answer = (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            }
            act("attach-end", answer)
        }
    }

    func navigate(_ p: [String]) {
        path = p
        act("select", p.last ?? "")
    }

    // a thread's screen kept for the next time it is opened (the last 24)
    private func remember(_ sel: String, _ t: ThreadView) {
        seen[sel] = t
        if seenOrder.last != sel {
            seenOrder.removeAll { $0 == sel }
            seenOrder.append(sel)
            if seenOrder.count > 24 { seen[seenOrder.removeFirst()] = nil }
        }
    }

    // the cats' rigs by key ("look:mood"), each asked of the bridge once
    private(set) var cats: [String: [CatPart]] = [:]
    @ObservationIgnored private var asked: Set<String> = []

    func cat(_ key: String) async {
        guard !key.isEmpty, !asked.contains(key) else { return }
        asked.insert(key)
        cats[key] = catRig(Data(await engine.cat(key).utf8))
    }

    // a bot form's field ("bfield"), typed: Bend keeps it without a new
    // screen, the field on screen already shows it
    func field(_ name: String, _ text: String) {
        run { await $0.quiet("bfield", name + "\u{1f}" + text) }
    }

    // an address on the hub in focus (a bot's browser frame, a webhook)
    func hubURL(_ path: String, query: [URLQueryItem] = [], token: Bool = true) -> URL? {
        guard let s = screen, let l = links.first(where: { Pairing.key($0) == s.hub }) else { return nil }
        return Pairing.http(l, path: path, query: query, token: token)
    }

    // the page of a thread asked for and not yet made
    static let making = "@new"

    // what the stack shows: the thread selected, or a room or a bot on a
    // linked machine (a bot's own view is its thread's)
    static func nav(_ s: Screen) -> String {
        if let b = s.bot, b.kind != "bot" { return "@" + b.kind + ":" + b.id }
        return s.sel
    }

    // the composer's text sent now: it shows at once as sending and the
    // composer empties; the client's answer carries it on (its own sending
    // row, then the hub's message)
    func send(_ action: String = "send") {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = screen?.thread?.id ?? ""
        if !text.isEmpty { outgoing.append(Outgoing(thread: thread, text: text)) }
        composer = ""
        typing += 1
        let e = engine
        Task {
            let out = await e.act(action, "")
            typing -= 1
            apply(out, sent: text)
        }
    }

    func draft(_ text: String) {
        composer = text
        typing += 1
        let e = engine
        Task {
            let out = await e.quiet("draft", text)
            typing -= 1
            apply(out)
        }
    }

    // a URL the app was opened with: a pairing link, or a thread to show
    func open(_ url: URL) {
        guard url.scheme == "backplane" else { return }
        if url.host == "open" {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let id = q.first { $0.name == "thread" }?.value ?? ""
            if !id.isEmpty { act("select", id) }
            // the island with several threads: pick one (backplane://open?pick=1)
            else if q.contains(where: { $0.name == "pick" }), (screen?.island.lines.count ?? 0) > 1 { picking = true }
        } else {
            pair(url.absoluteString)
        }
    }

    // the state written down when it changed (the app may be ended at any
    // time once in the background)
    func keep() {
        guard dirty, ready else { return }
        dirty = false
        let e = engine, k = kept
        Task { k.save(await e.save()) }
    }

    func foreground(_ yes: Bool) {
        active = yes
        if !yes { keep() }
        if yes, let s = screen { island?.show(s.islands ?? [], foreground: true) }
    }

    private func apply(_ out: Out?, sent: String? = nil) {
        guard let o = out else {
            if let t = sent, let i = outgoing.firstIndex(where: { $0.text == t }) { outgoing.remove(at: i) }
            return
        }
        if let s = o.screen {
            if typing == 0 { composer = s.thread?.draft ?? "" }
            screen = s
            if let t = s.thread, !s.sel.isEmpty { remember(s.sel, t) }
            if s.hub != shownHub {
                shownHub = s.hub
                plots.reset()
            }
            let nav = Self.nav(s)
            if nav != shownSel {
                shownSel = nav
                path = nav.isEmpty ? [] : [nav]
            }
            // New Thread: its page opens at once and waits there for the
            // hub's thread (the selection above replaces it); a failure
            // takes it away again
            let making = s.making ?? false
            if making != shownMaking {
                shownMaking = making
                if making { path = [Self.making] } else if path == [Self.making] { path = nav.isEmpty ? [] : [nav] }
            }
            island?.show(s.islands ?? [], foreground: active)
            #if DEBUG
            if let id = opening, let row = s.projects.lazy.flatMap(\.threads).first(where: { $0.id == id || $0.id.hasSuffix("|" + id) }) {
                opening = nil
                act("select", row.id)
            } else if let id = opening, !s.hub.isEmpty, !s.projects.isEmpty {
                // a thread not on show (a settled or archived shelf): by its hub
                opening = nil
                act("select", s.hub + "|" + id)
            }
            if let n = botting, let b = s.bots.first(where: { $0.name == n }) {
                botting = nil
                act(b.act ?? (b.remote ? "remote" : "bot"), b.id)
            } else if let n = botting, let r = s.rooms.first(where: { $0.name == n }) {
                botting = nil
                act("room", r.id)
            }
            if opening == nil, let v = viewing, let t = s.thread, !t.viewer.choices.isEmpty {
                viewing = nil
                act("view", v)
            }
            if opening == nil, let a = acting, s.thread != nil {
                acting = nil
                Task {
                    for step in a.components(separatedBy: ";;") where !step.isEmpty {
                        try? await Task.sleep(for: .seconds(2))
                        let kv = step.split(separator: "=", maxSplits: 1).map(String.init)
                        // "@attach": a noisy PNG big enough to go up in several pieces
                        if kv[0] == "@attach" {
                            let img = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { c in
                                for y in stride(from: 0, to: 400, by: 2) {
                                    for x in stride(from: 0, to: 400, by: 2) {
                                        UIColor(hue: .random(in: 0 ... 1), saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                                        c.fill(CGRect(x: x, y: y, width: 2, height: 2))
                                    }
                                }
                            }
                            if let d = img.pngData() { attach(d, name: "noise.png") }
                            continue
                        }
                        act(kv[0], kv.count > 1 ? kv[1].replacingOccurrences(of: "$SIZE", with: TermSheet.size()) : "")
                    }
                }
            }
            #endif
        }
        if let t = sent, let i = outgoing.firstIndex(where: { $0.text == t }) { outgoing.remove(at: i) }
        for c in o.cmds {
            switch c.type {
            case "send": if let d = Data(base64Encoded: c.data ?? "") { hubs[c.hub ?? ""]?.send(d) }
            case "copy": UIPasteboard.general.string = c.text ?? ""
            case "scroll": scrolls += 1
            // an action come due (the design history playing), sent as a tap would
            case "later":
                let action = c.action ?? "", value = c.value ?? "", ms = max(c.ms ?? 0, 0)
                if !action.isEmpty {
                    Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(Int(ms)))
                        self?.act(action, value)
                    }
                }
            case "jump": if let id = c.id, !id.isEmpty { jumping = (id, 4) }
            case "keep": Self.keep(c.thread ?? "", c.text ?? "")
            // while asleep the hub's push carries the alert instead
            case "notify": if active { notifier.post(thread: c.thread ?? "", key: c.key ?? "", title: c.title ?? "", body: c.body ?? "") }
            default: break
            }
        }
        if let j = jumping, let t = screen?.thread {
            if let e = t.entries.first(where: { $0.id == j.id || $0.id.hasSuffix("|" + j.id) }) {
                jumping = nil
                jump = Jump(id: e.id, n: (jump?.n ?? 0) + 1)
            } else if o.screen != nil {
                jumping = j.left > 1 ? (j.id, j.left - 1) : nil
            }
        }
    }
}

struct Jump: Equatable {
    let id: String
    let n: Int
}

// a hub's socket: connecting (or trying again), offline between tries,
// syncing while what it missed comes in and is folded, then online
struct HubConn: Equatable {
    enum Phase { case connecting, offline, syncing, online }
    var phase: Phase = .connecting
    var heard: Date?
    // the size of the frame that caught this phone up
    var bytes = 0
}

struct Outgoing: Identifiable, Equatable {
    let id = UUID()
    let thread, text: String
}
