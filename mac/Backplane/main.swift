// Backplane.app: the hub and its web client in a Mac window.
//
// The window shell holds no product logic. It finds a hub already running
// for the home (<home>/hub.lock: "<pid> <port>", a live Backplane) or starts
// the bundled one (Contents/Resources/backplane/backplane), waits for
// /hello, and shows the web client. Quitting stops the hub it started.
// scripts/package-mac.sh builds it; see mac/README.md.
//
//   BACKPLANE_HOME  the home (default ~/.backplane-bend)
//   BACKPLANE_PORT  the port a hub it starts listens on (default 3787)

import Cocoa
import WebKit

// MARK: The hub

// why the hub could not start, as the window says it
struct Why: Error {
  let text: String
}

final class Hub {
  let home: String
  let port: Int
  private(set) var process: Process?
  private(set) var url: URL?
  let log: String

  init() {
    let env = ProcessInfo.processInfo.environment
    home = env["BACKPLANE_HOME"].map { ($0 as NSString).expandingTildeInPath }
      ?? NSHomeDirectory() + "/.backplane-bend"
    port = env["BACKPLANE_PORT"].flatMap { Int($0) } ?? 3787
    log = home + "/app.log"
  }

  var exe: String { Bundle.main.resourcePath! + "/backplane/backplane" }

  // a live Backplane holding the home's lock, by its port
  func running() -> Int? {
    guard let text = try? String(contentsOfFile: home + "/hub.lock", encoding: .utf8) else { return nil }
    let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
    guard parts.count >= 2, let pid = Int32(parts[0]), let port = Int(parts[1]), pid > 0 else { return nil }
    guard kill(pid, 0) == 0 else { return nil }
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
    let path = String(cString: buf)
    return path.hasSuffix("/backplane") || path.hasSuffix("/backplane-serve") ? port : nil
  }

  // the login shell's PATH: an app opened from Finder gets only the system's,
  // and agents need claude, git, gh, node, bun... where the person keeps them
  static func loginPath() -> String {
    let fallback = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin",
                    NSHomeDirectory() + "/.bun/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: shell)
    p.arguments = ["-ilc", "printf '\\n__BP_PATH__%s\\n' \"$PATH\""]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    var found: [String] = []
    if (try? p.run()) != nil {
      let deadline = Date().addingTimeInterval(5)
      while p.isRunning && Date() < deadline { usleep(50_000) }
      if p.isRunning { p.terminate() }
      let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      if let line = text.split(separator: "\n").last(where: { $0.hasPrefix("__BP_PATH__") }) {
        found = line.dropFirst("__BP_PATH__".count).split(separator: ":").map(String.init)
      }
    }
    var seen = Set<String>()
    return (found + fallback).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
  }

  // start the bundled hub unless one runs for the home; answers its URL or why not
  func start() -> Result<URL, Why> {
    if let p = running() {
      url = URL(string: "http://127.0.0.1:\(p)/")
      return .success(url!)
    }
    guard FileManager.default.isExecutableFile(atPath: exe) else { return .failure(Why(text: "no hub at \(exe)")) }
    try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: log, contents: nil)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = ["--home", home, "--port", String(port)]
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = Hub.loginPath()
    // the app updates as a whole (a new Backplane.app), not file by file inside it
    env["BACKPLANE_NO_UPDATE"] = "1"
    p.environment = env
    p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
    if let h = FileHandle(forWritingAtPath: log) {
      p.standardOutput = h
      p.standardError = h
    }
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return .failure(Why(text: "cannot start the hub: \(error.localizedDescription)")) }
    process = p
    url = URL(string: "http://127.0.0.1:\(port)/")
    return .success(url!)
  }

  // /hello answers (true), or the hub this app started has exited (false)
  func ready(_ url: URL, within seconds: Double) -> Bool {
    let hello = url.appendingPathComponent("hello")
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if let p = process, !p.isRunning { return false }
      let done = DispatchSemaphore(value: 0)
      var ok = false
      var req = URLRequest(url: hello)
      req.timeoutInterval = 1
      URLSession.shared.dataTask(with: req) { _, resp, _ in
        ok = (resp as? HTTPURLResponse)?.statusCode == 200
        done.signal()
      }.resume()
      done.wait()
      if ok { return true }
      usleep(200_000)
    }
    return false
  }

  func logTail() -> String {
    let text = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").suffix(8).joined(separator: "\n")
  }

  // stop the hub this app started (SIGTERM, then SIGKILL after 5 s)
  func stop() {
    guard let p = process, p.isRunning else { return }
    p.terminate()
    let deadline = Date().addingTimeInterval(5)
    while p.isRunning && Date() < deadline { usleep(50_000) }
    if p.isRunning { kill(p.processIdentifier, SIGKILL) }
  }
}

// MARK: The window

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
  let hub = Hub()
  var window: NSWindow!
  var web: WKWebView!
  let status = NSTextField(labelWithString: "Starting Backplane…")

  func applicationDidFinishLaunching(_ n: Notification) {
    NSApp.mainMenu = App.menu()
    let config = WKWebViewConfiguration()
    config.preferences.setValue(true, forKey: "developerExtrasEnabled")
    config.mediaTypesRequiringUserActionForPlayback = []
    web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.uiDelegate = self
    web.allowsMagnification = true
    if #available(macOS 13.3, *) { web.isInspectable = true }
    web.isHidden = true

    let root = NSView()
    for v in [web!, status] as [NSView] {
      v.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(v)
    }
    status.textColor = .secondaryLabelColor
    status.alignment = .center
    status.maximumNumberOfLines = 0
    NSLayoutConstraint.activate([
      web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      web.topAnchor.constraint(equalTo: root.topAnchor),
      web.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      status.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      status.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      status.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -48),
    ])

    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                      styleMask: [.titled, .closable, .miniaturizable, .resizable],
                      backing: .buffered, defer: false)
    window.title = "Backplane"
    window.contentView = root
    window.minSize = NSSize(width: 480, height: 360)
    window.delegate = self
    window.center()
    window.setFrameAutosaveName("Backplane")
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.global(qos: .userInitiated).async { self.boot() }
  }

  func boot() {
    switch hub.start() {
    case .failure(let why):
      DispatchQueue.main.async { self.fail(why.text) }
    case .success(let url):
      let ok = hub.ready(url, within: 60)
      DispatchQueue.main.async {
        if ok {
          self.web.load(URLRequest(url: url))
        } else {
          self.fail("The hub did not start.\n\n" + self.hub.logTail() + "\n\n(" + self.hub.log + ")")
        }
      }
    }
  }

  func fail(_ why: String) {
    status.stringValue = why
    status.isHidden = false
    web.isHidden = true
  }

  func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
    status.isHidden = true
    web.isHidden = false
  }

  // the hub's pages stay here; every other link opens in the browser
  func local(_ url: URL?) -> Bool {
    guard let url = url else { return true }
    if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return true }
    return (url.host == "127.0.0.1" || url.host == "localhost") && url.port == hub.url?.port
  }

  func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if local(action.request.url) || action.targetFrame?.isMainFrame == false {
      decisionHandler(.allow)
    } else {
      NSWorkspace.shared.open(action.request.url!)
      decisionHandler(.cancel)
    }
  }

  // target=_blank and window.open
  func webView(_ w: WKWebView, createWebViewWith config: WKWebViewConfiguration,
               for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if let url = action.request.url { NSWorkspace.shared.open(url) }
    return nil
  }

  func webView(_ w: WKWebView, runOpenPanelWith p: WKOpenPanelParameters, initiatedByFrame f: WKFrameInfo,
               completionHandler: @escaping ([URL]?) -> Void) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = p.allowsMultipleSelection
    panel.canChooseDirectories = p.allowsDirectories
    panel.canChooseFiles = true
    panel.beginSheetModal(for: window) { r in completionHandler(r == .OK ? panel.urls : nil) }
  }

  func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo,
               completionHandler: @escaping () -> Void) {
    let a = NSAlert()
    a.messageText = m
    a.beginSheetModal(for: window) { _ in completionHandler() }
  }

  func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo,
               completionHandler: @escaping (Bool) -> Void) {
    let a = NSAlert()
    a.messageText = m
    a.addButton(withTitle: "OK")
    a.addButton(withTitle: "Cancel")
    a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
  }

  func webView(_ w: WKWebView, runJavaScriptTextInputPanelWithPrompt m: String, defaultText d: String?,
               initiatedByFrame f: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    let a = NSAlert()
    a.messageText = m
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = d ?? ""
    a.accessoryView = field
    a.addButton(withTitle: "OK")
    a.addButton(withTitle: "Cancel")
    a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn ? field.stringValue : nil) }
  }

  // a crashed web process leaves a blank page: load it again
  func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
    if let url = hub.url { w.load(URLRequest(url: url)) }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

  func applicationWillTerminate(_ n: Notification) { hub.stop() }

  @objc func reload(_ s: Any?) {
    if let url = hub.url { web.load(URLRequest(url: url)) }
  }

  @objc func zoomIn(_ s: Any?) { web.pageZoom = min(web.pageZoom + 0.1, 3) }
  @objc func zoomOut(_ s: Any?) { web.pageZoom = max(web.pageZoom - 0.1, 0.5) }
  @objc func zoomReset(_ s: Any?) { web.pageZoom = 1 }

  @objc func showLog(_ s: Any?) {
    NSWorkspace.shared.open(URL(fileURLWithPath: hub.log))
  }

  @objc func openInBrowser(_ s: Any?) {
    if let url = hub.url { NSWorkspace.shared.open(url) }
  }

  // the standard menus: without Edit, copy and paste do nothing in a web view
  static func menu() -> NSMenu {
    let bar = NSMenu()
    func add(_ title: String, _ items: [NSMenuItem]) {
      let top = NSMenuItem()
      let m = NSMenu(title: title)
      items.forEach(m.addItem)
      top.submenu = m
      bar.addItem(top)
    }
    func item(_ t: String, _ a: Selector?, _ k: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
      let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
      i.keyEquivalentModifierMask = mods
      return i
    }
    add("Backplane", [
      item("About Backplane", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
      .separator(),
      item("Hide Backplane", #selector(NSApplication.hide(_:)), "h"),
      item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
      item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
      .separator(),
      item("Quit Backplane", #selector(NSApplication.terminate(_:)), "q"),
    ])
    add("Edit", [
      item("Undo", Selector(("undo:")), "z"),
      item("Redo", Selector(("redo:")), "z", [.command, .shift]),
      .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x"),
      item("Copy", #selector(NSText.copy(_:)), "c"),
      item("Paste", #selector(NSText.paste(_:)), "v"),
      item("Select All", #selector(NSText.selectAll(_:)), "a"),
    ])
    add("View", [
      item("Reload", #selector(App.reload(_:)), "r"),
      .separator(),
      item("Actual Size", #selector(App.zoomReset(_:)), "0"),
      item("Zoom In", #selector(App.zoomIn(_:)), "="),
      item("Zoom Out", #selector(App.zoomOut(_:)), "-"),
      .separator(),
      item("Open in Browser", #selector(App.openInBrowser(_:)), "o", [.command, .shift]),
      item("Hub Log", #selector(App.showLog(_:)), "l", [.command, .shift]),
      .separator(),
      item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
    ])
    add("Window", [
      item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
      item("Zoom", #selector(NSWindow.performZoom(_:)), ""),
      item("Close", #selector(NSWindow.performClose(_:)), "w"),
    ])
    return bar
  }
}

// the hub stops with the app, whichever way it is asked to end
signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { NSApp.terminate(nil) }
term.resume()

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
