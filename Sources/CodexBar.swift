import AppKit
import Sparkle
import Foundation

final class Bars: NSView {
    var values: [Double?] = [nil, nil] { didSet { needsDisplay = true } }
    var stale = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<2 {
            let rect = NSRect(x: 1, y: 4 + CGFloat(i) * 8, width: 30, height: 4)
            NSColor.labelColor.withAlphaComponent(stale ? 0.12 : 0.25).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            if let value = values[i] {
                let width = rect.width * max(0, min(1, value / 100))
                if width > 0 {
                    (value < 20 ? NSColor.systemRed : NSColor.labelColor).withAlphaComponent(stale ? 0.35 : 1).setFill()
                    NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: max(2, width), height: rect.height), xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }
}

final class QuotaTile: NSView {
    let symbol: String
    let ring = RingView()
    let symbolLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "—")
    let resetLabel = NSTextField(wrappingLabelWithString: "Reset unavailable")

    init(symbol: String) {
        self.symbol = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: 152, height: 180))
        ring.frame = NSRect(x: 31, y: 77, width: 90, height: 90)
        symbolLabel.stringValue = symbol
        symbolLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        symbolLabel.alignment = .center
        symbolLabel.frame = NSRect(x: 31, y: 99, width: 90, height: 45)
        valueLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: 8, y: 46, width: 136, height: 28)
        resetLabel.font = .systemFont(ofSize: 10.5)
        resetLabel.textColor = .secondaryLabelColor
        resetLabel.alignment = .center
        resetLabel.maximumNumberOfLines = 2
        resetLabel.frame = NSRect(x: 6, y: 8, width: 140, height: 34)
        for view in [ring, symbolLabel, valueLabel, resetLabel] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        update(nil, reset: "Reset unavailable")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.56).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }
    func update(_ window: QuotaWindow?, reset: String) {
        ring.value = window?.remaining
        valueLabel.stringValue = window.map { "\(Int($0.remaining.rounded()))%" } ?? "—"
        resetLabel.stringValue = reset
        let period = symbol == "5" ? "5 hours" : "Week"
        setAccessibilityLabel("\(period), \(window == nil ? "unavailable" : valueLabel.stringValue + " remaining"), \(reset)")
    }
}

final class RingView: NSView {
    var value: Double? { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 6)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = 8
        NSColor.tertiaryLabelColor.withAlphaComponent(0.32).setStroke()
        track.stroke()
        guard let value = value, value > 0 else { return }
        let fraction = max(0, min(1, value / 100))
        let path = NSBezierPath()
        path.lineWidth = 8
        path.lineCapStyle = .round
        if fraction >= 1 { path.appendOval(in: rect) }
        else {
            path.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: rect.width / 2,
                           startAngle: 90, endAngle: 90 - CGFloat(360 * fraction), clockwise: true)
        }
        NSColor.systemBlue.setStroke()
        path.stroke()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 34)
    let bars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let popover = NSPopover()
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 290))
    let fiveHourView = QuotaTile(symbol: "5")
    let weeklyView = QuotaTile(symbol: "W")
    let stateLabel = NSTextField(wrappingLabelWithString: "")
    let updatedLabel = NSTextField(labelWithString: "Last updated: —")
    let additionalLabel = NSTextField(wrappingLabelWithString: "")
    let contextMenu = NSMenu()
    let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    let client = QuotaClient()
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    var timer: Timer?
    var running = false
    var lastUpdate: Date?
    var lastQuota: Quota?
    var state = "Loading…"
    var stale = false
    var lastFailure: String?
    var requestID = 0
    var ageTimer: Timer?
    var globalClickMonitor: Any?
    var localClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        bars.frame.origin = NSPoint(x: 1, y: (button.bounds.height - 20) / 2)
        bars.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(bars)
        button.toolTip = "Codex: top — 5 hours, bottom — week"
        button.setAccessibilityLabel("Codex usage limits, loading")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        stateLabel.font = .systemFont(ofSize: 12)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.maximumNumberOfLines = 3
        additionalLabel.font = .systemFont(ofSize: 12)
        additionalLabel.textColor = .secondaryLabelColor
        updatedLabel.font = .systemFont(ofSize: 12)
        updatedLabel.textColor = .secondaryLabelColor
        refresh.target = self
        contextMenu.autoenablesItems = false
        contextMenu.addItem(refresh)
        contextMenu.addItem(.separator())
        let about = NSMenuItem(title: "About Codex Bar", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        contextMenu.addItem(about)
        checkUpdates.target = self
        contextMenu.addItem(checkUpdates)
        contextMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        contextMenu.addItem(quit)
        for view in [fiveHourView, weeklyView, stateLabel, additionalLabel, updatedLabel] as [NSView] { content.addSubview(view) }
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        layoutPanel(message: "Loading…")
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in self?.refreshNow() }
        ageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.updateAge() }
    }
    func layoutPanel(message: String?) {
        let extra: CGFloat = message == nil ? 0 : 56
        let additionalHeight: CGFloat = additionalLabel.stringValue.isEmpty ? 0 : ceil((additionalLabel.stringValue as NSString).boundingRect(with: NSSize(width: 312, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: additionalLabel.font!]).height) + 12
        let height: CGFloat = 236 + extra + additionalHeight
        content.frame = NSRect(x: 0, y: 0, width: 340, height: height)
        popover.contentSize = content.frame.size
        fiveHourView.frame.origin = NSPoint(x: 12, y: height - 192)
        weeklyView.frame.origin = NSPoint(x: 176, y: height - 192)
        updatedLabel.frame = NSRect(x: 14, y: 12, width: 312, height: 20)
        stateLabel.isHidden = message == nil
        stateLabel.stringValue = message ?? ""
        stateLabel.frame = NSRect(x: 14, y: 42, width: 312, height: 52)
        additionalLabel.frame = NSRect(x: 14, y: 42 + extra, width: 312, height: additionalHeight)
    }
    @objc func statusItemClicked() {
        guard let button = status.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if popover.isShown { startClickMonitoring() }
        }
    }
    func startClickMonitoring() {
        stopClickMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.popover.close()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self = self else { return event }
            if event.window !== self.content.window && event.window !== self.status.button?.window {
                self.popover.close()
            }
            return event
        }
    }
    func stopClickMonitoring() {
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor); globalClickMonitor = nil }
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor); localClickMonitor = nil }
    }
    func popoverDidClose(_ notification: Notification) { stopClickMonitoring() }
    @objc func activeApplicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        popover.close()
    }
    func applicationDidResignActive(_ notification: Notification) {
        popover.close()
    }
    @objc func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let alert = NSAlert()
        alert.messageText = "Codex Bar"
        alert.informativeText = "Version \(version)\nGitHub: frankydzoro\n\nA menu bar app for Codex usage limits."
        alert.addButton(withTitle: "GitHub")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/frankydzoro/codex-bar")!)
        }
    }
    @objc func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }
    @objc func refreshNow() {
        guard !running else { return }
        running = true; refresh.isEnabled = false
        requestID += 1
        let currentRequest = requestID
        state = lastQuota == nil ? "Loading…" : (stale ? "Updating… Previous attempt: \(lastFailure ?? "failed") — showing previous data" : "Updating…")
        layoutPanel(message: state)
        guard let path = QuotaClient.findCLI() else { finish(.failure(QuotaError.cliNotFound)); return }
        DispatchQueue.global(qos: .utility).async {
            let result = self.client.fetch(path: path)
            DispatchQueue.main.async { if self.requestID == currentRequest { self.finish(result) } }
        }
    }
    func finish(_ result: Result<Quota, Error>) {
        running = false; refresh.isEnabled = true
        var message: String?
        switch result {
        case .success(let quota):
            lastQuota = quota; lastUpdate = Date()
            state = "Up to date"
            stale = false
            lastFailure = nil
            let conflicts = quota.conflictingDurations.map { "Conflicting \(durationName($0)) values; unavailable" }
            let extras = quota.additional.map { "\(durationName($0.durationMinutes)): \(Int($0.remaining.rounded()))% remaining" + ($0.reset.map { " · resets \(format($0))" } ?? " · reset unavailable") }
            additionalLabel.stringValue = (extras + conflicts).joined(separator: "\n")
        case .failure(let error):
            stale = lastQuota != nil
            lastFailure = error.localizedDescription
            state = "\(error.localizedDescription)\(stale ? " — showing previous data" : "")"
            message = state
        }
        if let quota = lastQuota {
            bars.values = [quota.fiveHour?.remaining, quota.weekly?.remaining]
            fiveHourView.update(quota.fiveHour, reset: resetDescription(quota.fiveHour))
            weeklyView.update(quota.weekly, reset: resetDescription(quota.weekly))
        }
        bars.stale = stale
        updateAge()
        layoutPanel(message: message)
        status.button?.setAccessibilityLabel("Codex. \(state). \(describe("5 hours", lastQuota?.fiveHour)). \(describe("Week", lastQuota?.weekly)). \(updatedLabel.stringValue)")
    }
    func applicationWillTerminate(_ notification: Notification) {
        requestID += 1
        stopClickMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate(); ageTimer?.invalidate()
        client.cancel()
    }
    func updateAge() {
        guard let date = lastUpdate else { updatedLabel.stringValue = "Updated: —"; return }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        updatedLabel.stringValue = minutes == 0 ? "Updated just now" : "Updated \(minutes) min ago"
    }
    func durationName(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-minute"
    }
    func resetDescription(_ window: QuotaWindow?) -> String {
        window?.reset.map { shortReset($0) } ?? "—"
    }
    func describe(_ name: String, _ window: QuotaWindow?) -> String {
        guard let window = window else { return "\(name): unavailable" }
        let reset = window.reset.map { " · resets \(format($0))" } ?? " · reset unavailable"
        return "\(name): \(Int(window.remaining.rounded()))% remaining\(reset)"
    }
    func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    func shortReset(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    func format(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
@main struct CodexBarMain {
    static func main() {
        let app = NSApplication.shared
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position Item-0": 120])
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
