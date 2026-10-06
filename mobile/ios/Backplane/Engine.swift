import Foundation
import JavaScriptCore

// One thread with a deep stack: the hub's log arrives as one message and
// Bend walks it recursively. A dispatch queue's 512 KB overflows on a real
// log, the call throws, and the app keeps its empty first screen.
private final class Worker: Thread, @unchecked Sendable {
    private let cond = NSCondition()
    private var jobs: [() -> Void] = []

    override init() {
        super.init()
        name = "bend"
        stackSize = 64 << 20
        qualityOfService = .userInitiated
        start()
    }

    func async(_ f: @escaping () -> Void) {
        cond.lock()
        jobs.append(f)
        cond.signal()
        cond.unlock()
    }

    override func main() {
        while true {
            cond.lock()
            while jobs.isEmpty { cond.wait() }
            let f = jobs.removeFirst()
            cond.unlock()
            f()
        }
    }
}

// The Bend client (bridge.js) in JavaScriptCore, on one thread of its own.
// Every call answers {"screen": ..., "cmds": [...]} as a string.
final class Engine: @unchecked Sendable {
    private let queue = Worker()
    private var ctx: JSContext?

    private func context() -> JSContext {
        if let ctx { return ctx }
        let c = JSContext()!
        c.exceptionHandler = { _, e in NSLog("bridge.js: %@", e?.toString() ?? "?") }
        let url = Bundle.main.url(forResource: "bridge", withExtension: "js")!
        c.evaluateScript(try! String(contentsOf: url, encoding: .utf8), withSourceURL: url)
        ctx = c
        return c
    }

    // calls queued whose answer carries a screen: while one is, the screen
    // before it is out of date before it could be drawn, so it is skipped
    private let lock = NSLock()
    private var ahead = 0
    // a screen was dropped that way: the next recv builds one even for a
    // frame that changes nothing on screen (bridge.js's owed)
    private var owe = false

    // late: the arguments decided on the queue, as the call runs
    private func call<T>(_ name: String, _ args: [Any], late: (() -> [Any])? = nil, _ finish: @escaping (String) -> T) async -> T {
        await withCheckedContinuation { k in
            queue.async {
                let b = self.context().objectForKeyedSubscript("Backplane")!
                let t0 = DispatchTime.now().uptimeNanoseconds
                let text = b.invokeMethod(name, withArguments: late?() ?? args)?.toString() ?? "{}"
                // a slow step of the Bend client, for finding what to make faster (as Android's)
                let ms = (DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
                if ms > 100 { NSLog("Backplane slow %@: %llu ms", name, ms) }
                k.resume(returning: finish(text))
            }
        }
    }

    // decoded here, off the main thread: a thread's screen is large
    // quiet: when newer calls wait behind this one, it is made with a last
    // argument true, and builds no screen (it would be dropped anyway)
    // (a quiet call is told both, as its last two arguments)
    private func out(_ name: String, _ args: [Any], screen: Bool = true, quiet: Bool = false) async -> Out? {
        if screen { lock.withLock { ahead += 1 } }
        let late: (() -> [Any])? = quiet ? {
            self.lock.withLock {
                let o = self.owe
                self.owe = false
                return args + [self.ahead > 1, o]
            }
        } : nil
        return await call(name, args, late: late) { text in
            let stale = screen && self.lock.withLock {
                self.ahead -= 1
                if self.ahead > 0 { self.owe = true }
                return self.ahead > 0
            }
            return Out.decode(text, screen: !stale)
        }
    }

    func start(_ cid: String, _ drafts: String) async -> Out? { await out("start", [cid, drafts]) }
    func hubs(_ keys: [String]) async -> Out? { await out("hubs", [keys]) }
    func resume(_ key: String) async -> String { await call("resume", [key]) { $0 } }
    func register(_ kind: String, _ token: String, env: String, bundle: String) async -> Out? {
        await out("register", ["ios", token, kind, "", env, bundle], screen: false)
    }
    func register(at hub: String, _ kind: String, _ token: String, env: String, bundle: String) async -> Out? {
        await out("registerAt", [hub, "ios", token, kind, "", env, bundle], screen: false)
    }
    func screen() async -> Out? { await out("screen", []) }
    func recv(_ key: String, _ text: String) async -> Out? { await out("recv", [key, text], quiet: true) }
    // the whole client state as text (StateStore), and the state loaded back
    func save() async -> String { await call("save", []) { $0 } }
    func load(_ text: String) async -> Out? { await out("load", [text]) }
    func act(_ action: String, _ value: String) async -> Out? { await out("act", [action, value]) }
    func quiet(_ action: String, _ value: String) async -> Out? { await out("quiet", [action, value], screen: false) }
    func online(_ key: String, _ b: Bool) async -> Out? { await out("online", [key, b]) }
    // a hub marked offline with no screen of its own (after load())
    func offline(_ key: String) async -> Out? { await out("online", [key, false, true], screen: false) }
    func tick(_ now: Int) async -> Out? { await out("tick", [now]) }
    // a cat's rig for its key ("look:mood")
    func cat(_ key: String) async -> String { await call("cat", [key]) { $0 } }
}
