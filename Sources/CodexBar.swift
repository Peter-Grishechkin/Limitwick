import AppKit
import Foundation

final class Bars: NSView {
    var values: [Double?] = [nil, nil] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<2 {
            let rect = NSRect(x: 1, y: 4 + CGFloat(i) * 8, width: 30, height: 4)
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            if let value = values[i] {
                let width = rect.width * max(0, min(1, value / 100))
                if width > 0 {
                    (value < 20 ? NSColor.systemRed : NSColor.white).setFill()
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
    let info = NSMenuItem(title: "Загрузка…", action: nil, keyEquivalent: "")
    let resetInfo = NSMenuItem(title: "Сброс 5 ч: —", action: nil, keyEquivalent: "")
    var timer: Timer?
    var running = false
    var lastUpdate: Date?
    let codexPaths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        bars.frame.origin = NSPoint(x: 1, y: (button.bounds.height - 20) / 2)
        bars.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(bars)
        button.toolTip = "Codex: сверху — 5 часов, снизу — неделя"
        info.isEnabled = false
        menu.addItem(info)
        resetInfo.isEnabled = false
        menu.addItem(resetInfo)
        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Обновить", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Завершить Codex Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = menu
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in self?.refreshNow() }
    }
    @objc func refreshNow() {
        guard !running else { return }
        guard let path = codexPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            info.title = "Codex CLI не найден"; resetInfo.title = "Сброс 5 ч: —"; bars.values = [nil, nil]; return
        }
        running = true
        DispatchQueue.global(qos: .utility).async {
            let result = self.fetch(path: path)
            DispatchQueue.main.async {
                self.running = false
                switch result {
                case .success(let quota):
                    let values = quota.values
                    self.bars.values = values
                    self.lastUpdate = Date()
                    let a = values[0].map { "\(Int($0.rounded()))%" } ?? "—"
                    let b = values[1].map { "\(Int($0.rounded()))%" } ?? "—"
                    self.info.title = "Осталось: 5 ч — \(a), неделя — \(b)"
                    if let reset = quota.fiveHourReset {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .short
                        self.resetInfo.title = "Сброс 5 ч: \(formatter.string(from: reset))"
                    } else {
                        self.resetInfo.title = "Сброс 5 ч: —"
                    }
                case .failure:
                    self.bars.values = [nil, nil]
                    self.resetInfo.title = "Сброс 5 ч: —"
                    self.info.title = "Нет данных — проверьте вход в Codex и сеть"
                }
            }
        }
    }
    enum FetchError: Error { case failed }
    struct Quota { let values: [Double?]; let fiveHourReset: Date? }
    func fetch(path: String) -> Result<Quota, Error> {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(error) }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel(); if process.isRunning { process.terminate() }; try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
        func send(_ json: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: json); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        do {
            try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_bar", "version": "1.0"]]])
            var buffer = Data()
            while true {
                let data = output.fileHandleForReading.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
                    guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let id = obj["id"] as? Int else { continue }
                    if id == 1 {
                        guard obj["result"] != nil else { return .failure(FetchError.failed) }
                        try send(["method": "initialized", "params": [:]])
                        try send(["id": 2, "method": "account/rateLimits/read"])
                    } else if id == 2 {
                        guard let result = obj["result"] as? [String: Any], let limits = result["rateLimits"] as? [String: Any] else { return .failure(FetchError.failed) }
                        var values: [Double?] = [nil, nil]
                        var fiveHourReset: Date?
                        for key in ["primary", "secondary"] {
                            guard let window = limits[key] as? [String: Any], let minutes = window["windowDurationMins"] as? Int, let used = window["usedPercent"] as? Double else { continue }
                            let remaining = max(0, min(100, 100 - used))
                            if minutes == 300 {
                                values[0] = remaining
                                if let timestamp = window["resetsAt"] as? Double, timestamp > 0 {
                                    fiveHourReset = Date(timeIntervalSince1970: timestamp)
                                }
                            }
                            if minutes == 10080 { values[1] = remaining }
                        }
                        if values.allSatisfy({ $0 == nil }) { return .failure(FetchError.failed) }
                        return .success(Quota(values: values, fiveHourReset: fiveHourReset))
                    }
                }
            }
        } catch { return .failure(error) }
        return .failure(FetchError.failed)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
