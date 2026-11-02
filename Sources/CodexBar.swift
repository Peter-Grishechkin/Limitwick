import AppKit
import Foundation

final class Bars: NSView {
    var values: [Double?] = [nil, nil] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<2 {
            let rect = NSRect(x: 1, y: 4 + CGFloat(i) * 8, width: 30, height: 4)
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            if let value = values[i] {
                let width = rect.width * max(0, min(1, value / 100))
                if width > 0 {
                    (value < 20 ? NSColor.systemRed : NSColor.labelColor).setFill()
                    NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: max(2, width), height: rect.height), xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 34)
    let bars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let menu = NSMenu()
    let state = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
    let fiveHour = NSMenuItem(title: "5 hours: —", action: nil, keyEquivalent: "")
    let weekly = NSMenuItem(title: "Week: —", action: nil, keyEquivalent: "")
    let updated = NSMenuItem(title: "Last updated: —", action: nil, keyEquivalent: "")
    let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    let client = QuotaClient()
    var timer: Timer?
    var running = false
    var lastUpdate: Date?
    var lastQuota: Quota?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        bars.frame.origin = NSPoint(x: 1, y: (button.bounds.height - 20) / 2)
        bars.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(bars)
        button.toolTip = "Codex: top — 5 hours, bottom — week"
        button.setAccessibilityLabel("Codex usage limits, loading")
        for item in [state, fiveHour, weekly, updated] { item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator())
        refresh.target = self; menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Codex Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = menu
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in self?.refreshNow() }
    }
    @objc func refreshNow() {
        guard !running else { return }
        running = true; refresh.isEnabled = false
        state.title = lastQuota == nil ? "Loading…" : "Updating…"
        guard let path = QuotaClient.findCLI() else { finish(.failure(QuotaError.cliNotFound)); return }
        DispatchQueue.global(qos: .utility).async {
            let result = self.client.fetch(path: path)
            DispatchQueue.main.async { self.finish(result) }
        }
    }
    func finish(_ result: Result<Quota, Error>) {
        running = false; refresh.isEnabled = true
        switch result {
        case .success(let quota):
            lastQuota = quota; lastUpdate = Date()
            state.title = "Up to date"
        case .failure(let error):
            state.title = "\(error.localizedDescription)\(lastQuota == nil ? "" : " — showing previous data")"
        }
        if let quota = lastQuota {
            bars.values = [quota.fiveHour?.remaining, quota.weekly?.remaining]
            fiveHour.title = describe("5 hours", quota.fiveHour)
            weekly.title = describe("Week", quota.weekly)
        }
        if let date = lastUpdate { updated.title = "Last updated: \(format(date))" }
        status.button?.setAccessibilityLabel("Codex. \(state.title). \(fiveHour.title). \(weekly.title). \(updated.title)")
    }
    func describe(_ name: String, _ window: QuotaWindow?) -> String {
        guard let window = window else { return "\(name): unavailable" }
        let reset = window.reset.map { " · resets \(format($0))" } ?? " · reset unavailable"
        return "\(name): \(Int(window.remaining.rounded()))% remaining\(reset)"
    }
    func format(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
@main struct CodexBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
