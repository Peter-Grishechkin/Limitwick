import Foundation
import Darwin
import Lottie

@main struct ActivityTests {
    static func main() throws {
        for name in ["loading", "edit", "terminal", "alertTriangle", "checkmark"] {
            let path = "Resources/useAnimations/\(name).json"
            precondition(LottieAnimation.filepath(path) != nil, "Could not load \(path)")
        }
        let idle = ActivityBarLayout(codex: true, claude: true, codexActive: false, claudeActive: false)
        let one = ActivityBarLayout(codex: true, claude: true, codexActive: false, claudeActive: true)
        let both = ActivityBarLayout(codex: true, claude: true, codexActive: true, claudeActive: true)
        precondition(idle.width == 110 && idle.codexIcon == nil && idle.claudeIcon == nil)
        precondition(one.width == 132 && one.claudeIcon != nil && one.codexIcon == nil)
        precondition(both.width == 154 && both.codexIcon != nil && both.claudeIcon != nil)
        let single = ActivityBarLayout(codex: false, claude: true, codexActive: true, claudeActive: false)
        precondition(single.width == 34 && single.codexIcon == nil && single.claudeIcon == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let base = root.appendingPathComponent("listeners")
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("thread-writer-locks"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = ActivityMonitor(base: base)
        var displayed: ActivityDisplay?
        monitor.onChange = { displayed = $0 }
        monitor.start()
        defer { monitor.stop() }
        let directory = base.appendingPathComponent("listener-\(getpid())")
        let session1 = UUID().uuidString, session2 = UUID().uuidString
        let turn1 = UUID().uuidString, turn2 = UUID().uuidString
        func lock(_ session: String) -> Int32 {
            let p = home.appendingPathComponent("thread-writer-locks/\(session).lock").path
            let fd = open(p, O_CREAT | O_RDWR, 0o600)
            precondition(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
            return fd
        }
        let fd1 = lock(session1), fd2 = lock(session2)
        defer { close(fd1); close(fd2) }
        let now = Date().timeIntervalSince1970
        var seq = 0
        func send(_ event: String, _ session: String, _ turn: String, tool: String = "") throws {
            seq += 1
            let object: [String: Any] = ["event": event, "session": session, "turn": turn, "tool": tool, "time": now + Double(seq) / 100, "home": home.path]
            try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent("event-\(seq)"))
            monitor.poll(now: now + Double(seq) / 100)
        }
        try send("UserPromptSubmit", session1, turn1); precondition(displayed == .working)
        try send("PreToolUse", session1, turn1, tool: "a"); precondition(displayed == .tool)
        try send("PreToolUse", session1, turn1, tool: "b"); precondition(displayed == .tool)
        try send("UserPromptSubmit", session2, turn2); precondition(displayed == .tool)
        try send("PostToolUse", session1, turn1, tool: "a"); precondition(displayed == .tool)
        try send("PostToolUse", session1, turn1, tool: "b"); precondition(displayed == .working)
        try send("Stop", session1, turn1); precondition(displayed == .working)
        try send("Stop", session2, turn2); precondition(displayed == .completed)
        monitor.poll(now: now + 4); precondition(displayed == nil)
        try send("UserPromptSubmit", session1, turn1); precondition(displayed == .working)
        monitor.stop(); precondition(!FileManager.default.fileExists(atPath: directory.path))
        displayed = nil
        monitor.start(); monitor.poll(now: now + 4)
        precondition(displayed == nil)
        try send("UserPromptSubmit", session1, turn1); precondition(displayed == .working)
        flock(fd1, LOCK_UN); monitor.poll(now: now + 4.1); precondition(displayed == nil)
        precondition(monitor.lastEvent != nil)
        precondition(!ActivityMonitor.hooksInstalled(home: home))
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/python3 /Applications/Limitwick.app/Contents/Resources/useAnimations/claude-activity-hook.py"}]}]}}"#.write(to: home.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        precondition(!ActivityMonitor.hooksInstalled(home: home))
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/python3 /Applications/Limitwick.app/Contents/Resources/useAnimations/activity-hook.py"}]}]}}"#.write(to: home.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        precondition(ActivityMonitor.hooksInstalled(home: home))
        let claudeBase = root.appendingPathComponent("claude")
        let claude = ClaudeActivityMonitor(base: claudeBase)
        var claudeShown: ActivityDisplay?
        claude.onChange = { claudeShown = $0 }; claude.start(); defer { claude.stop() }
        let claudeDir = claudeBase.appendingPathComponent("listener-\(getpid())")
        func claudeSend(_ event: String, _ session: String, _ tool: String = "") throws {
            seq += 1
            let time = now + Double(seq) / 100
            let payload: [String: Any] = ["event": event, "session": session, "tool": tool, "time": time]
            try JSONSerialization.data(withJSONObject: payload).write(to: claudeDir.appendingPathComponent("event-\(seq)"))
            claude.poll(now: time)
        }
        try claudeSend("UserPromptSubmit", "one"); precondition(claudeShown == .working)
        try claudeSend("PreToolUse", "one", "a"); try claudeSend("PreToolUse", "one", "b"); precondition(claudeShown == .tool)
        try claudeSend("PostToolUseFailure", "one", "a"); precondition(claudeShown == .tool)
        try claudeSend("PostToolUse", "one", "b"); precondition(claudeShown == .working)
        try claudeSend("UserPromptSubmit", "two"); try claudeSend("Stop", "one"); precondition(claudeShown == .working)
        try claudeSend("SessionEnd", "two"); precondition(claudeShown == nil)
        try claudeSend("UserPromptSubmit", "one"); try claudeSend("Stop", "one"); precondition(claudeShown == .completed)
        claude.poll(now: now + 5); precondition(claudeShown == nil)
        try claudeSend("UserPromptSubmit", "one"); try claudeSend("Idle", "one"); precondition(claudeShown == nil)
        try claudeSend("UserPromptSubmit", "one"); claude.poll(now: now + 1801); precondition(claudeShown == nil)
        let config = root.appendingPathComponent("claude-config"); try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        precondition(!ClaudeActivityMonitor.hooksInstalled(config: config))
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/python3 /Applications/CodexBar.app/Contents/Resources/useAnimations/claude-activity-hook.py"}]}]}}"#.write(to: config.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        precondition(ClaudeActivityMonitor.hooksInstalled(config: config))
        precondition(claude.lastEvent != nil)
        print("Activity tests passed")
    }
}
