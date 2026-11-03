import AppKit
import Foundation
import Darwin
import Lottie

struct ActivityEvent: Decodable {
    let event: String
    let session: String
    let turn: String
    let tool: String?
    let time: TimeInterval
    let home: String
}

enum ActivityDisplay: Equatable {
    case working, tool, completed
    var icon: String {
        switch self { case .working: return "loading"; case .tool: return "terminal"; case .completed: return "checkmark" }
    }
    var label: String {
        switch self { case .working: return "Codex working"; case .tool: return "Codex using a tool"; case .completed: return "Codex finished" }
    }
}

final class ActivityMonitor {
    private struct Turn {
        var state: ActivityDisplay
        var tools: Set<String>
        var timestamp: TimeInterval
        var lockPath: String
    }
    private var turns: [String: Turn] = [:]
    private var completedUntil: TimeInterval = 0
    private var timer: Timer?
    private let directory: URL
    var onChange: ((ActivityDisplay?) -> Void)?
    private var shown: ActivityDisplay?

    init(base: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/CodexBar/Activity", isDirectory: true)) {
        directory = base.appendingPathComponent("listener-\(getpid())", isDirectory: true)
    }
    func start() {
        guard timer == nil else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        } catch { return }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        turns.removeAll(); completedUntil = 0; shown = nil
        try? FileManager.default.removeItem(at: directory)
    }
    private func writerIsAlive(_ path: String) -> Bool {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { flock(fd, LOCK_UN); return false }
        return errno == EWOULDBLOCK || errno == EAGAIN
    }
    func poll(now: TimeInterval = Date().timeIntervalSince1970) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var incoming: [ActivityEvent] = []
        for url in files where url.lastPathComponent.hasPrefix("event-") {
            if let data = try? Data(contentsOf: url), data.count < 4096, let event = try? JSONDecoder().decode(ActivityEvent.self, from: data), abs(event.time - now) < 30 { incoming.append(event) }
            try? FileManager.default.removeItem(at: url)
        }
        for event in incoming.sorted(by: { $0.time < $1.time }) {
            guard UUID(uuidString: event.session) != nil, UUID(uuidString: event.turn) != nil, event.home.hasPrefix("/"), !event.home.contains("\0") else { continue }
            let key = event.session + ":" + event.turn
            if let old = turns[key], old.timestamp > event.time { continue }
            let lock = (event.home as NSString).appendingPathComponent("thread-writer-locks/\(event.session).lock")
            switch event.event {
            case "UserPromptSubmit", "PreToolUse", "PostToolUse":
                guard writerIsAlive(lock) else { continue }
                var tools = turns[key]?.tools ?? []
                let tool = event.tool ?? ""
                if event.event == "PreToolUse" { tools.insert(tool) }
                if event.event == "PostToolUse" { tools.remove(tool) }
                turns[key] = Turn(state: tools.isEmpty ? .working : .tool, tools: tools, timestamp: event.time, lockPath: lock)
                completedUntil = 0
            case "Stop":
                if turns.removeValue(forKey: key) != nil && turns.isEmpty { completedUntil = now + 3 }
            case "Interrupt": turns.removeValue(forKey: key); completedUntil = 0
            default: break
            }
        }
        turns = turns.filter { writerIsAlive($0.value.lockPath) }
        let next: ActivityDisplay? = turns.values.contains(where: { $0.state == .tool }) ? .tool : (!turns.isEmpty ? .working : (now < completedUntil ? .completed : nil))
        if next != shown { shown = next; onChange?(next) }
    }
}

struct ActivityBarLayout {
    let width: CGFloat
    let codexIcon: CGFloat?
    let claudeIcon: CGFloat?
    let codexMark: CGFloat?
    let claudeMark: CGFloat?
    let codexBars: CGFloat?
    let claudeBars: CGFloat?
    init(codex: Bool, claude: Bool, codexActive: Bool, claudeActive: Bool) {
        let dual = codex && claude
        var x: CGFloat = 0
        var ci: CGFloat?, ai: CGFloat?, cm: CGFloat?, am: CGFloat?, cb: CGFloat?, ab: CGFloat?
        if codex {
            if codexActive { ci = x + 1; x += 22 }
            if dual { cm = x + 1; x += 16 }
            cb = x + 1; x += 34
        }
        if claude {
            if claudeActive { ai = x + 1; x += 22 }
            if dual { am = x + 1; x += 16 }
            ab = x + 1; x += 34
        }
        width = x; codexIcon = ci; claudeIcon = ai; codexMark = cm; claudeMark = am; codexBars = cb; claudeBars = ab
    }
}

final class ActivityIcon: LottieAnimationView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func show(_ state: ActivityDisplay?) {
        stop()
        guard let state = state else { isHidden = true; return }
        animation = LottieAnimation.named(state.icon, bundle: .main, subdirectory: "useAnimations")
        guard animation != nil else { isHidden = true; return }
        isHidden = false
        recolor()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { currentProgress = state == .completed ? 1 : 0.5 }
        else { loopMode = state == .completed ? .playOnce : .loop; play() }
    }
    private func recolor() {
        let color = NSColor.white.usingColorSpace(.deviceRGB) ?? .white
        let provider = ColorValueProvider(LottieColor(r: Double(color.redComponent), g: Double(color.greenComponent), b: Double(color.blueComponent), a: Double(color.alphaComponent)))
        setValueProvider(provider, keypath: AnimationKeypath(keypath: "**.Color"))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); recolor() }
}

// Claude hooks identify a session, rather than a Codex turn or writer lock.
final class ClaudeActivityMonitor {
    private struct Session { var tools: Set<String>; var timestamp: TimeInterval }
    private var sessions: [String: Session] = [:]
    private var completedUntil: TimeInterval = 0
    private var shown: ActivityDisplay?
    private var timer: Timer?
    private let directory: URL
    var onChange: ((ActivityDisplay?) -> Void)?
    private(set) var lastEvent: TimeInterval?
    init(base: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/CodexBar/ClaudeActivity", isDirectory: true)) {
        directory = base.appendingPathComponent("listener-\(getpid())", isDirectory: true)
    }
    func start() {
        guard timer == nil else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        } catch { return }
    }
    func stop() {
        timer?.invalidate(); timer = nil; sessions.removeAll(); completedUntil = 0; shown = nil
        try? FileManager.default.removeItem(at: directory)
    }
    // Matches the marker that claude-activity-setup.py uses to find its own handlers.
    static func hooksInstalled(config: URL = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) -> Bool {
        guard let text = try? String(contentsOf: config.appendingPathComponent("settings.json"), encoding: .utf8) else { return false }
        return text.contains("/useAnimations/claude-activity-hook.py")
    }
    func poll(now: TimeInterval = Date().timeIntervalSince1970) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        struct Event: Decodable { let event: String; let session: String; let tool: String; let time: TimeInterval }
        var events: [Event] = []
        for url in files where url.lastPathComponent.hasPrefix("event-") {
            if let data = try? Data(contentsOf: url), data.count < 4096, let event = try? JSONDecoder().decode(Event.self, from: data), abs(event.time - now) < 30, !event.session.isEmpty, event.session.count <= 100 { events.append(event) }
            try? FileManager.default.removeItem(at: url)
        }
        if let latest = events.map(\.time).max() { lastEvent = max(lastEvent ?? 0, latest) }
        for event in events.sorted(by: { $0.time < $1.time }) {
            if let prior = sessions[event.session], prior.timestamp > event.time { continue }
            switch event.event {
            case "UserPromptSubmit": sessions[event.session] = Session(tools: [], timestamp: event.time); completedUntil = 0
            case "PreToolUse":
                var session = sessions[event.session] ?? Session(tools: [], timestamp: event.time)
                session.tools.insert(event.tool); session.timestamp = event.time; sessions[event.session] = session; completedUntil = 0
            case "PostToolUse", "PostToolUseFailure":
                if var session = sessions[event.session] { session.tools.remove(event.tool); session.timestamp = event.time; sessions[event.session] = session }
            case "Stop":
                if sessions.removeValue(forKey: event.session) != nil && sessions.isEmpty { completedUntil = now + 3 }
            case "SessionEnd", "StopFailure", "Idle": sessions.removeValue(forKey: event.session); completedUntil = 0
            default: break
            }
        }
        sessions = sessions.filter { now - $0.value.timestamp < 1800 }
        let next: ActivityDisplay? = sessions.values.contains(where: { !$0.tools.isEmpty }) ? .tool : (!sessions.isEmpty ? .working : (now < completedUntil ? .completed : nil))
        if next != shown { shown = next; onChange?(next) }
    }
}
