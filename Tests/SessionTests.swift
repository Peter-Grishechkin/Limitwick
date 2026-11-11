import Foundation

@main struct SessionTests {
    static func main() throws {
        let t0: TimeInterval = 1_800_000_000
        let id = "aa787cb0-d859-4a06-aeb1-ce873dbd2ea9"
        func event(_ name: String, _ session: String = id, at offset: TimeInterval, provider: SessionProvider = .claude,
                   folder: String? = nil, app: String? = nil, entry: String? = nil, pid: Int32? = nil) -> SessionEvent {
            SessionEvent(provider: provider, session: session, event: name, time: t0 + offset, name: folder, app: app, entry: entry, pid: pid)
        }

        // Only real work creates a tile: a lone Stop, SessionEnd or notification for an unknown session does not.
        let store = SessionStore()
        for name in ["Stop", "SessionEnd", "Idle", "Permission", "Ended", "Unknown"] {
            precondition(!store.apply(event(name, at: 0), now: t0) && store.sessions.isEmpty, name)
        }

        // Working, waiting for permission, back to work, finished.
        precondition(store.apply(event("UserPromptSubmit", at: 0, folder: "Limitwick", app: "com.anthropic.claudefordesktop", entry: "claude-desktop", pid: 1456), now: t0))
        var tile = store.sessions["claude:\(id)"]!
        precondition(tile.state == .working && tile.name == "Limitwick" && tile.pid == 1456 && tile.entry == "claude-desktop")
        precondition(SessionStore.status(tile, now: t0 + 30) == "working · <1m")
        precondition(SessionStore.status(tile, now: t0 + 180) == "working · 3m")
        store.apply(event("PreToolUse", at: 10), now: t0)
        store.apply(event("Permission", at: 20), now: t0)
        precondition(store.sessions["claude:\(id)"]!.state == .waiting)
        precondition(SessionStore.status(store.sessions["claude:\(id)"]!, now: t0 + 30) == "needs you")
        store.apply(event("PostToolUse", at: 40), now: t0)
        tile = store.sessions["claude:\(id)"]!
        precondition(tile.state == .working && tile.turnStarted == t0, "approval keeps the turn start")
        store.apply(event("Stop", at: 60), now: t0)
        tile = store.sessions["claude:\(id)"]!
        precondition(tile.state == .idle && tile.changed == t0 + 60)
        precondition(SessionStore.status(tile, now: t0 + 90) == "done · just now")
        precondition(SessionStore.status(tile, now: t0 + 60 + 7200) == "done · 2h ago")

        // A later Idle notification or SessionEnd does not move a finished tile forward; an older event is ignored.
        precondition(!store.apply(event("Idle", at: 120), now: t0) && store.sessions["claude:\(id)"]!.changed == t0 + 60)
        precondition(!store.apply(event("SessionEnd", at: 130), now: t0))
        precondition(!store.apply(event("UserPromptSubmit", at: 50), now: t0))

        // The first folder name stays when the agent changes directory; details are validated.
        store.apply(event("UserPromptSubmit", at: 200, folder: "Limitwick-Source"), now: t0)
        tile = store.sessions["claude:\(id)"]!
        precondition(tile.name == "Limitwick" && tile.turnStarted == t0 + 200)
        let other = "11111111-2222-3333-4444-555555555555"
        store.apply(event("PreToolUse", other, at: 210, provider: .codex, folder: "a/b", app: "bad id"), now: t0)
        let codex = store.sessions["codex:\(other)"]!
        precondition(codex.name == "Codex" && codex.app == nil && codex.state == .working)
        precondition(SessionStore.clean(" Long\u{7}name ") == nil && SessionStore.clean(String(repeating: "x", count: 80))?.count == 60)

        // Silence finishes a turn after 30 minutes; a dead process finishes it at once.
        precondition(store.tick(now: t0 + 210 + 1801, alive: { _ in true }))
        precondition(store.sessions["codex:\(other)"]!.state == .idle && store.sessions["claude:\(id)"]!.state == .idle)
        let s2 = SessionStore()
        s2.apply(event("UserPromptSubmit", at: 0, pid: 42), now: t0)
        precondition(!s2.tick(now: t0 + 10, alive: { _ in true }) && s2.sessions.first!.value.state == .working)
        precondition(s2.tick(now: t0 + 10, alive: { $0 != 42 }) && s2.sessions.first!.value.state == .idle)
        // A permission prompt waits while its process is alive, but not without a process ID.
        s2.apply(event("UserPromptSubmit", at: 20, pid: 42), now: t0); s2.apply(event("Permission", at: 30), now: t0)
        precondition(!s2.tick(now: t0 + 3 * 3600, alive: { _ in true }) && s2.sessions.first!.value.state == .waiting)
        let s3 = SessionStore()
        s3.apply(event("UserPromptSubmit", at: 0), now: t0); s3.apply(event("Permission", at: 5), now: t0)
        precondition(s3.tick(now: t0 + 1900, alive: { _ in true }) && s3.sessions.first!.value.state == .idle)

        // Finished tiles stay for 24 hours; at most 16 tiles, finished ones evicted first, oldest first.
        let s4 = SessionStore()
        for i in 0..<20 {
            let sid = String(format: "00000000-0000-0000-0000-%012d", i)
            s4.apply(event("UserPromptSubmit", sid, at: Double(i)), now: t0 + 30)
            if i >= 2 { s4.apply(event("Stop", sid, at: Double(i) + 0.5), now: t0 + 30) }
        }
        precondition(s4.sessions.count == 16)
        let order = s4.ordered
        precondition(order[0].state == .working && order[1].state == .working && order[0].id.hasSuffix("01"), "active first, newest first")
        precondition(order[2].id.hasSuffix("19") && order.last!.id.hasSuffix("06"), "oldest finished tiles evicted")
        precondition(s4.tick(now: t0 + 19.5 + SessionStore.retention, alive: { _ in false }))
        precondition(s4.sessions.isEmpty, "a day later every tile is gone")

        // Saved tiles come back; turns saved before the last boot are finished.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let saved = SessionStore(file: file)
        saved.apply(event("UserPromptSubmit", at: 0, folder: "City21"), now: t0)
        saved.apply(event("UserPromptSubmit", other, at: 5, provider: .codex, folder: "SEOpars"), now: t0)
        saved.apply(event("Stop", other, at: 6, provider: .codex), now: t0)
        saved.save()
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((attributes[.posixPermissions] as? Int) == 0o600)
        let restored = SessionStore(file: file)
        restored.load(now: t0 + 60, booted: t0 - 100, alive: { _ in true })
        precondition(restored.sessions == saved.sessions)
        let rebooted = SessionStore(file: file)
        rebooted.load(now: t0 + 60, booted: t0 + 50, alive: { _ in true })
        precondition(rebooted.sessions.values.allSatisfy { $0.state == .idle } && rebooted.sessions.count == 2)
        try Data("not json".utf8).write(to: file)
        let broken = SessionStore(file: file); broken.load(now: t0)
        precondition(broken.sessions.isEmpty)
        // A file saved before titles existed still loads; a title with "/" survives saving.
        try Data(#"[{"provider":"claude","id":"x","name":"City21","state":"idle","started":\#(t0),"turnStarted":\#(t0),"changed":\#(t0)}]"#.utf8).write(to: file)
        let older = SessionStore(file: file); older.load(now: t0 + 60, booted: t0 - 100, alive: { _ in true })
        precondition(older.sessions["claude:x"]?.name == "City21" && older.sessions["claude:x"]?.title == nil)
        precondition(older.retitle("claude:x", "CI/CD настройка") && !older.retitle("claude:x", "CI/CD настройка") && !older.retitle("claude:none", "T"))
        older.save()
        let titled = SessionStore(file: file); titled.load(now: t0 + 60, booted: t0 - 100, alive: { _ in true })
        precondition(titled.sessions["claude:x"]?.title == "CI/CD настройка")

        // Titles keep "/", lose control and format characters and extra spaces.
        precondition(SessionStore.cleanTitle("  Выбор\n статьи\u{202E} ") == "Выбор статьи" && SessionStore.cleanTitle(" \u{7} ") == nil && SessionStore.cleanTitle(nil) == nil)
        precondition(SessionStore.cleanTitle(String(repeating: "я", count: 100))?.count == 80)

        // Clicks: the Claude app's continue link takes only its own local_ ID (it logs "invalid ?session" for the CLI ID).
        precondition(tile.host == nil && SessionStore.target(for: tile) == .app("com.anthropic.claudefordesktop"))
        let linked = SessionStore()
        linked.apply(SessionEvent(provider: .claude, session: id, event: "UserPromptSubmit", time: t0, entry: "claude-desktop",
                                  host: "local_70c6c65e-606c-4a2e-805b-0eebfe0ddc85"), now: t0)
        precondition(SessionStore.target(for: linked.sessions.first!.value) == .url(URL(string: "claude://code/continue?session=local_70c6c65e-606c-4a2e-805b-0eebfe0ddc85")!))
        var badHost = linked.sessions.first!.value; badHost.host = "local_x&q=1"; badHost.app = nil
        precondition(SessionStore.target(for: badHost) == .none)
        var terminal = tile; terminal.entry = "cli"; terminal.app = "com.apple.Terminal"
        precondition(SessionStore.target(for: terminal) == .app("com.apple.Terminal"))
        terminal.app = nil
        precondition(SessionStore.target(for: terminal) == .none)

        // Sessions found on disk become finished tiles; live tiles keep their state and folder, gain the app session ID and take the title.
        let merged = SessionStore()
        merged.apply(event("UserPromptSubmit", at: 0, folder: "Limitwick"), now: t0)
        var history = SessionHistory.Found()
        history.sessions = [
            Session(provider: .claude, id: id, name: "Other", title: "Плитки сессий", entry: "claude-desktop", host: "local_a", state: .idle, started: t0 - 50, turnStarted: t0 - 50, changed: t0 - 50),
            Session(provider: .codex, id: other, name: "SEOpars", state: .idle, started: t0 - 600, turnStarted: t0 - 600, changed: t0 - 600),
            Session(provider: .claude, id: "old", name: "Old", state: .idle, started: t0 - 90_000, turnStarted: t0 - 90_000, changed: t0 - 90_000),
            Session(provider: .claude, id: "gone", name: "Gone", state: .idle, started: t0 - 60, turnStarted: t0 - 60, changed: t0 - 60),
        ]
        precondition(merged.merge(history, now: t0))
        let live = merged.sessions["claude:\(id)"]!
        precondition(live.state == .working && live.name == "Limitwick" && live.title == "Плитки сессий" && live.host == "local_a" && live.changed == t0)
        precondition(merged.sessions["codex:\(other)"]?.state == .idle && merged.sessions["claude:old"] == nil && merged.sessions.count == 3)
        precondition(!merged.merge(history, now: t0), "merging the same history twice changes nothing")
        history.sessions[0].title = "Переименована"
        precondition(merged.merge(history, now: t0) && merged.sessions["claude:\(id)"]?.title == "Переименована" && merged.sessions["claude:\(id)"]?.state == .working, "a renamed session takes the new title")
        history.sessions[0].title = nil
        precondition(!merged.merge(history, now: t0) && merged.sessions["claude:\(id)"]?.title == "Переименована", "a missing title does not erase the known one")
        var archived = SessionHistory.Found(); archived.archived = ["claude:gone", "claude:\(id)"]
        precondition(merged.merge(archived, now: t0) && merged.sessions["claude:gone"] == nil && merged.sessions["claude:\(id)"] != nil, "archived in the Claude app: idle tile goes, live tile stays")

        // Reading history from disk: Claude app list, terminal transcripts, Codex sessions; probe, archived and subagent threads skipped.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date().timeIntervalSince1970
        func write(_ path: String, _ text: String, age: TimeInterval = 60) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: now - age)], ofItemAtPath: url.path)
        }
        let app = "home/Library/Application Support/Claude/claude-code-sessions/account/org"
        let ms = Int((now - 300) * 1000)
        try write("\(app)/local_1111.json", #"{"sessionId":"local_1111","cliSessionId":"cli-1","originCwd":"/Users/x/Росэлторг","lastActivityAt":\#(ms),"createdAt":\#(ms - 60000),"isArchived":false,"title":"Выбор статьи"}"#)
        try write("\(app)/local_4444.json", #"{"sessionId":"local_4444","cliSessionId":"cli-6","originCwd":"/Users/x/Росэлторг","lastActivityAt":\#(ms),"isArchived":false,"title":" "}"#)
        try write("\(app)/local_5555.json", #"{"sessionId":"local_other","cliSessionId":"cli-7","originCwd":"/Users/x/Wrong","lastActivityAt":\#(ms),"isArchived":false,"title":"Wrong"}"#, age: 90_000)
        try write("\(app)/local_2222.json", #"{"sessionId":"local_2222","cliSessionId":"cli-2","originCwd":"/Users/x/Old","lastActivityAt":\#(ms),"isArchived":true}"#)
        try write("\(app)/local_3333.json", #"{"sessionId":"local_3333","cliSessionId":"cli-3","originCwd":"/Users/x/Stale","lastActivityAt":\#(ms),"isArchived":false}"#, age: 90_000)
        try write("claude/projects/-Users-x-Tool/cli-4.jsonl", #"{"type":"user","cwd":"/Users/x/Tool","entrypoint":"cli","message":"PRIVATE"}"# + "\n")
        try write("claude/projects/-Users-x-App/cli-1.jsonl", #"{"cwd":"/Users/x/Росэлторг","entrypoint":"claude-desktop"}"# + "\n")
        try write("claude/projects/-probe/cli-5.jsonl", #"{"cwd":"/Users/x/Library/Application Support/Limitwick/ClaudeProbe","entrypoint":"cli"}"# + "\n")
        let thread = "019a1c79-f6d4-7000-8000-000000000001", child = "019a1c79-f6d4-7000-8000-000000000002"
        try write("codex/sessions/2026/11/02/rollout-a.jsonl", #"{"type":"session_meta","payload":{"id":"\#(thread)","session_id":"\#(thread)","cwd":"/Users/x/LoftTaxi"}}"# + "\n{}\n")
        try write("codex/sessions/2026/11/02/rollout-b.jsonl", #"{"type":"session_meta","payload":{"id":"\#(child)","session_id":"\#(thread)","cwd":"/Users/x/LoftTaxi"}}"# + "\n")
        let scanned = SessionHistory.scan(now: now, home: root.appendingPathComponent("home"), claudeConfig: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex"))
        let keys = Set(scanned.sessions.map(\.key))
        precondition(keys == ["claude:cli-1", "claude:cli-4", "claude:cli-6", "codex:\(thread)"], "\(keys)")
        precondition(scanned.archived == ["claude:cli-2"])
        let appTile = scanned.sessions.first { $0.id == "cli-1" }!
        precondition(appTile.name == "Росэлторг" && appTile.title == "Выбор статьи" && appTile.host == "local_1111" && appTile.entry == "claude-desktop" && abs(appTile.changed - (now - 300)) < 1)
        let untitled = scanned.sessions.first { $0.id == "cli-6" }!
        precondition(untitled.name == "Росэлторг" && untitled.title == nil, "an empty title falls back to the folder")
        precondition(scanned.sessions.first { $0.id == "cli-4" }!.entry == "cli" && scanned.sessions.first { $0.provider == .codex }!.name == "LoftTaxi")
        precondition(scanned.sessions.filter { $0.title != nil }.map(\.id) == ["cli-1"], "only Claude app sessions have titles")
        precondition(!scanned.sessions.contains { $0.name.contains("PRIVATE") || ($0.title ?? "").contains("PRIVATE") }, "transcript messages are never read")

        // A live tile rereads one session's title by its local_ ID; the file must belong to that session.
        let home = root.appendingPathComponent("home")
        precondition(SessionHistory.appTitle(host: "local_1111", home: home) == "Выбор статьи")
        precondition(SessionHistory.appTitle(host: "local_4444", home: home) == nil && SessionHistory.appTitle(host: "local_9999", home: home) == nil)
        precondition(SessionHistory.appTitle(host: "local_5555", home: home) == nil, "file of another session")
        precondition(SessionHistory.appTitle(host: "../local_1111", home: home) == nil && SessionHistory.appTitle(host: "local_1111/..", home: home) == nil)

        // Hat colour depends only on the session ID.
        precondition(SessionStore.hat(for: id, count: 6) == SessionStore.hat(for: id, count: 6))
        precondition((0..<6).contains(SessionStore.hat(for: other, count: 6)))
        precondition(Set((0..<40).map { SessionStore.hat(for: "session-\($0)", count: 6) }).count > 3)
        print("Session tests passed")
    }
}
