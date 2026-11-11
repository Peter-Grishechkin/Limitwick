import Foundation

@main struct SessionTests {
    static func main() throws {
        let t0: TimeInterval = 1_800_000_000
        let id = "aa787cb0-d859-4a06-aeb1-ce873dbd2ea9"
        func event(_ name: String, _ session: String = id, at offset: TimeInterval, provider: SessionProvider = .claude,
                   folder: String? = nil, app: String? = nil, entry: String? = nil, pid: Int32? = nil,
                   tool: String? = nil, category: String? = nil) -> SessionEvent {
            SessionEvent(provider: provider, session: session, event: name, time: t0 + offset, name: folder, app: app, entry: entry, pid: pid,
                         tool: tool, category: category)
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
        precondition(SessionStore.status(store.sessions["claude:\(id)"]!, now: t0 + 30) == "feed me!")
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
        precondition(restored.sessions == saved.sessions && restored.sessions["codex:\(other)"]?.unseen == true, "the unseen mark is saved")
        let rebooted = SessionStore(file: file)
        rebooted.load(now: t0 + 60, booted: t0 + 50, alive: { _ in true })
        precondition(rebooted.sessions.values.allSatisfy { $0.state == .idle } && rebooted.sessions.count == 2)
        try Data("not json".utf8).write(to: file)
        let broken = SessionStore(file: file); broken.load(now: t0)
        precondition(broken.sessions.isEmpty)
        // A file saved before titles existed still loads; a title with "/" survives saving.
        try Data(#"[{"provider":"claude","id":"x","name":"City21","state":"idle","started":\#(t0),"turnStarted":\#(t0),"changed":\#(t0)}]"#.utf8).write(to: file)
        let older = SessionStore(file: file); older.load(now: t0 + 60, booted: t0 - 100, alive: { _ in true })
        precondition(older.sessions["claude:x"]?.name == "City21" && older.sessions["claude:x"]?.title == nil && older.sessions["claude:x"]?.unseen == nil)
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

        // Waiting captions get hungrier with time and fit a tile; VoiceOver hears plain words and "new" for an unseen result.
        var hungry = Session(provider: .claude, id: "w", name: "W", state: .waiting, started: t0, turnStarted: t0, changed: t0)
        precondition(SessionStore.status(hungry, now: t0 + 30) == "feed me!")
        precondition(SessionStore.status(hungry, now: t0 + 130) == "hungry · 2m")
        precondition(SessionStore.status(hungry, now: t0 + 720) == "starving · 12m")
        precondition(SessionStore.status(hungry, now: t0 + 7200) == "starving · 2h")
        for seconds in [0.0, 59, 299, 3599, 7200, 86_000] { precondition(SessionStore.status(hungry, now: t0 + seconds).count <= 14) }
        precondition(SessionStore.spokenStatus(hungry, now: t0 + 30) == "needs your permission")
        precondition(SessionStore.spokenStatus(hungry, now: t0 + 130) == "needs your permission · 2m")
        hungry.state = .idle; hungry.unseen = true
        precondition(SessionStore.spokenStatus(hungry, now: t0 + 30) == "done · just now, new")

        // Unseen: a turn that stops by itself or fails marks the tile; an interrupt, an end, silence or history does not.
        let seen = SessionStore()
        seen.apply(event("UserPromptSubmit", "u1", at: 0), now: t0)
        precondition(seen.sessions["claude:u1"]?.unseen == nil)
        seen.apply(event("Stop", "u1", at: 5), now: t0 + 5)
        precondition(seen.sessions["claude:u1"]?.unseen == true && seen.hasUnseen)
        precondition(!seen.apply(event("Idle", "u1", at: 70), now: t0 + 70) && seen.sessions["claude:u1"]?.unseen == true, "the idle notice keeps the mark")
        seen.apply(event("UserPromptSubmit", "u1", at: 80), now: t0 + 80)
        precondition(seen.sessions["claude:u1"]?.unseen == nil, "a new prompt means you are back")
        seen.apply(event("Stop", "u1", at: 90), now: t0 + 90)
        precondition(seen.markSeen("claude:u1") && !seen.markSeen("claude:u1") && seen.sessions["claude:u1"]?.unseen == nil)
        seen.apply(event("UserPromptSubmit", "u2", at: 100, provider: .codex), now: t0 + 100)
        seen.apply(event("Interrupt", "u2", at: 101, provider: .codex), now: t0 + 101)
        seen.apply(event("UserPromptSubmit", "u3", at: 100), now: t0 + 100)
        seen.apply(event("SessionEnd", "u3", at: 102), now: t0 + 102)
        seen.apply(event("UserPromptSubmit", "u4", at: 100), now: t0 + 100)
        seen.apply(event("StopFailure", "u4", at: 103), now: t0 + 103)
        precondition(seen.sessions["claude:u4"]?.unseen == true && seen.markSeen("claude:u4"), "a failed turn has a result to look at")
        seen.apply(event("UserPromptSubmit", "u5", at: 100), now: t0 + 100)
        seen.tick(now: t0 + 100 + 1801, alive: { _ in true })
        precondition(seen.sessions["claude:u5"]?.state == .idle && !seen.hasUnseen, "interrupt, end and silence leave no mark")
        seen.apply(event("UserPromptSubmit", "u6", at: 2000, provider: .codex), now: t0 + 2000)
        seen.apply(event("Stop", "u6", at: 2001, provider: .codex), now: t0 + 2001)
        seen.apply(event("UserPromptSubmit", "u7", at: 2000), now: t0 + 2000)
        seen.apply(event("Stop", "u7", at: 2002), now: t0 + 2002)
        precondition(seen.sessions["codex:u6"]?.unseen == true && seen.markAllSeen() && !seen.hasUnseen && !seen.markAllSeen())
        var fromDisk = SessionHistory.Found()
        fromDisk.sessions = [Session(provider: .claude, id: "h1", name: "H", state: .idle, started: t0, turnStarted: t0, changed: t0 + 2000)]
        seen.merge(fromDisk, now: t0 + 2003)
        precondition(seen.sessions["claude:h1"]?.unseen == nil && seen.moments["claude:h1"] == nil, "history never marks or animates")

        // Moments play only for fresh events and expire; a late stop still marks the result.
        let fresh = SessionStore()
        fresh.apply(event("UserPromptSubmit", "m1", at: 0), now: t0 + 1)
        precondition(fresh.moments["claude:m1"] == SessionMoment(kind: .appeared, at: t0 + 1))
        fresh.apply(event("Stop", "m1", at: 30), now: t0 + 31)
        precondition(fresh.moments["claude:m1"] == SessionMoment(kind: .finished, at: t0 + 31))
        fresh.apply(event("UserPromptSubmit", "m2", at: 0), now: t0 + 60)
        fresh.apply(event("Stop", "m2", at: 50), now: t0 + 60)
        precondition(fresh.moments["claude:m2"] == nil && fresh.sessions["claude:m2"]?.unseen == true)
        fresh.tick(now: t0 + 60, alive: { _ in true })
        precondition(fresh.moments.isEmpty, "moments expire")

        // Frames: working mascots move from their own phase; waiting waves, blinks and crawls; idle stands still.
        func look(_ s: Session, _ moment: SessionMoment? = nil, tool: SessionTool? = nil, at time: TimeInterval, motion: Bool = true) -> SessionLook {
            SessionLook.of(s, moment: moment, tool: tool, now: time, motion: motion)
        }
        let claudeWork = Session(provider: .claude, id: "p1", name: "P", state: .working, started: t0, turnStarted: t0, changed: t0)
        let steps = (0..<4).map { look(claudeWork, at: t0 + Double($0) * SessionLook.tick + 0.01) }
        precondition(Set(steps.map(\.lift)) == [0, 1] && steps.contains { $0.legs == .leftUp } && steps.contains { $0.legs == .rightUp })
        precondition(steps.allSatisfy { $0.bold && $0.hint == .none && $0.light == .off && $0.awake == 1 })
        precondition(look(claudeWork, at: t0, motion: false) == SessionLook(lift: 1, bold: true), "Reduce Motion: one standing pose")
        let phased = (0..<20).map { "phase-\($0)" }
        var first = claudeWork, second = claudeWork
        first.id = phased.first { SessionStore.hat(for: $0, count: 4) == 0 }!
        second.id = phased.first { SessionStore.hat(for: $0, count: 4) == 1 }!
        precondition(look(first, at: t0 + 0.01) != look(second, at: t0 + 0.01), "working mascots do not move in step")
        var codexWork = claudeWork; codexWork.provider = .codex
        let cursor = (0..<4).map { look(codexWork, at: t0 + Double($0) * SessionLook.tick + 0.01) }
        precondition(cursor.filter(\.cursor).count == 2 && cursor.allSatisfy { $0.lift == 1 }, "the cursor blinks, the cloud does not bob")

        let waitingTile = Session(provider: .claude, id: "p1", name: "P", state: .waiting, started: t0, turnStarted: t0, changed: t0)
        let waits = stride(from: 0.0, to: 3.92, by: SessionLook.fastTick).map { look(waitingTile, at: t0 + $0 + 0.001) }
        precondition(Set(waits.map(\.stripes)).count == 12 && Set(waits.map(\.light)) == [.waiting, .waitingDim])
        var pause = 0, longest = 0
        for frame in waits + waits { pause = frame.armUp ? 0 : pause + 1; longest = max(longest, pause) }
        precondition(waits.filter(\.armUp).count >= 9 && longest >= 23, "three waves, then a pause of about two seconds")
        precondition(look(waitingTile, at: t0, motion: false) == SessionLook(lift: 1, armUp: true, light: .waiting, bold: true), "Reduce Motion: a raised hand, a steady light, still stripes")

        var idleTile = Session(provider: .claude, id: "p1", name: "P", state: .idle, started: t0, turnStarted: t0, changed: t0)
        precondition(look(idleTile, at: t0 + 600) == SessionLook(eyesClosed: true, awake: 0, hint: .sleep(1)))
        precondition(look(idleTile, at: t0 + 600) == look(idleTile, at: t0 + 600.5), "idle stands still")
        precondition(look(idleTile, at: t0 + 2 * 3600).hint == .sleep(2) && look(idleTile, at: t0 + 7 * 3600).hint == .sleep(3))
        idleTile.unseen = true
        precondition(look(idleTile, at: t0 + 600).light == .unseen && look(idleTile, at: t0 + 600).bold)

        // Just finished: a jump and a check, then asleep in four colour steps; Codex blinks its cursor three times instead.
        let done = SessionMoment(kind: .finished, at: t0)
        precondition((0..<5).map { look(idleTile, done, at: t0 + Double($0) * SessionLook.fastTick + 0.001).lift } == [2, 3, 3, 2, 1])
        let checked = look(idleTile, done, at: t0 + 1)
        precondition(checked.hint == .check && checked.awake == 1 && !checked.eyesClosed && checked.light == .unseen)
        precondition([2.41, 2.57, 2.73, 2.89].map { look(idleTile, done, at: t0 + $0).awake } == [0.75, 0.5, 0.25, 0])
        precondition(look(idleTile, done, at: t0 + 2.9).eyesClosed && look(idleTile, done, at: t0 + 2.9).lift == 0)
        precondition(look(idleTile, done, at: t0 + 3.1) == look(idleTile, at: t0 + 3.1), "after the moment the tile is plain idle")
        precondition(look(idleTile, done, at: t0 + 0.1, motion: false) == look(idleTile, at: t0 + 0.1), "Reduce Motion skips moments")
        var codexDone = idleTile; codexDone.provider = .codex
        precondition(stride(from: 0.0, to: 0.96, by: 0.16).map { look(codexDone, done, at: t0 + $0 + 0.001).cursor } == [false, true, false, true, false, true])
        precondition(look(codexDone, done, at: t0 + 0.05).lift == 1)
        precondition(look(claudeWork, done, at: t0 + 0.1) == look(claudeWork, at: t0 + 0.1), "a finished moment shows only on an idle tile")
        let born = SessionMoment(kind: .appeared, at: t0)
        precondition((0..<5).map { look(claudeWork, born, at: t0 + Double($0) * SessionLook.fastTick + 0.001).reveal } == [0.2, 0.4, 0.6, 0.8, 1.0])
        precondition(look(claudeWork, born, at: t0 + 0.5).reveal == 1)

        // One clock: fast while a shown tile plays a moment, then as slow as the tiles allow; without motion always slow.
        precondition(SessionLook.clock([idleTile], moments: [:], now: t0, motion: true) == (0, SessionLook.idleTick))
        precondition(SessionLook.clock([idleTile, claudeWork], moments: [:], now: t0, motion: true).step == SessionLook.tick)
        precondition(SessionLook.clock([claudeWork, waitingTile], moments: [:], now: t0, motion: true).step == SessionLook.waitTick)
        precondition(SessionLook.clock([idleTile], moments: [idleTile.key: done], now: t0 + 1, motion: true).fastUntil == t0 + SessionLook.finishing)
        precondition(SessionLook.clock([idleTile], moments: [idleTile.key: done], now: t0 + 4, motion: true).fastUntil == 0)
        precondition(SessionLook.clock([idleTile], moments: ["claude:other": done], now: t0 + 1, motion: true).fastUntil == 0, "only shown tiles count")
        precondition(SessionLook.clock([waitingTile], moments: [waitingTile.key: done], now: t0 + 1, motion: false) == (0, SessionLook.idleTick))

        // Tool calls: the last call started shows; calls close by ID; a new prompt, the end of a turn and silence clear them.
        let calls = SessionStore()
        let ck = "claude:t1"
        calls.apply(event("UserPromptSubmit", "t1", at: 0), now: t0)
        precondition(calls.running[ck] == nil)
        calls.apply(event("PreToolUse", "t1", at: 1, tool: "a", category: "shell"), now: t0 + 1)
        calls.apply(event("PreToolUse", "t1", at: 2, tool: "b", category: "edit"), now: t0 + 2)
        precondition(calls.running[ck] == SessionTool(id: "b", kind: .edit) && calls.tools[ck]?.count == 2)
        calls.apply(event("PostToolUse", "t1", at: 3, tool: "b"), now: t0 + 3)
        precondition(calls.running[ck] == SessionTool(id: "a", kind: .shell), "the earlier call shows again")
        calls.apply(event("PostToolUseFailure", "t1", at: 4, tool: "a"), now: t0 + 4)
        precondition(calls.running[ck] == nil && calls.moments[ck] == SessionMoment(kind: .toolFailed, at: t0 + 4))
        calls.apply(event("PreToolUse", "t1", at: 5, tool: "c", category: "mcp__server"), now: t0 + 5)
        precondition(calls.running[ck]?.kind == .other, "an unknown kind is just a tool")
        calls.apply(event("PreToolUse", "t1", at: 6, tool: "c", category: "read"), now: t0 + 6)
        precondition(calls.tools[ck]?.count == 1 && calls.running[ck]?.kind == .read, "a repeated call ID replaces the call")
        calls.apply(event("UserPromptSubmit", "t1", at: 7), now: t0 + 7)
        precondition(calls.running[ck] == nil, "a new prompt forgets calls that never returned")
        for i in 0..<40 { calls.apply(event("PreToolUse", "t1", at: 8 + Double(i) / 100, tool: "x\(i)", category: "web"), now: t0 + 8) }
        precondition(calls.tools[ck]?.count == SessionStore.openTools && calls.running[ck]?.id == "x39")
        calls.apply(event("Stop", "t1", at: 9), now: t0 + 9)
        precondition(calls.running[ck] == nil && calls.tools[ck] == nil)
        calls.apply(event("PreToolUse", "x1", at: 10, provider: .codex, tool: "call"), now: t0 + 10)
        precondition(calls.running["codex:x1"] == SessionTool(id: "call", kind: nil), "an older hook copy runs a tool without a kind")
        precondition(calls.tick(now: t0 + 10 + 1801, alive: { _ in true }) && calls.running["codex:x1"] == nil)
        calls.apply(event("UserPromptSubmit", "t2", at: 0), now: t0 + 60)
        calls.apply(event("PostToolUseFailure", "t2", at: 1, tool: "a"), now: t0 + 60)
        precondition(calls.moments["claude:t2"] == nil, "a late tool error does not shake")
        // Tool kinds stay in memory: sessions.json has no trace of them.
        let toolFile = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: toolFile) }
        let kept = SessionStore(file: toolFile)
        kept.apply(event("PreToolUse", "t3", at: 0, tool: "toolu_secret", category: "search"), now: t0)
        kept.save()
        let keptText = try String(contentsOf: toolFile, encoding: .utf8)
        precondition(!keptText.contains("search") && !keptText.contains("toolu_secret") && !keptText.contains("category"), keptText)

        // How a turn ended: failed (marked, red), interrupted (no mark), lost (silence or a dead process); a new turn clears it.
        let ends = SessionStore()
        ends.apply(event("UserPromptSubmit", "e1", at: 0), now: t0)
        ends.apply(event("StopFailure", "e1", at: 5), now: t0 + 5)
        var ended = ends.sessions["claude:e1"]!
        precondition(ended.outcome == .failed && ended.unseen == true && ends.moments["claude:e1"] == SessionMoment(kind: .failed, at: t0 + 5))
        precondition(SessionStore.status(ended, now: t0 + 30) == "just failed" && SessionStore.status(ended, now: t0 + 185) == "failed 3m ago")
        for seconds in [0.0, 59, 60, 3599, 3600, 86_399] { precondition(SessionStore.status(ended, now: t0 + 5 + seconds).count <= 14, "\(seconds)") }
        precondition(SessionStore.spokenStatus(ended, now: t0 + 185) == "failed 3m ago, new")
        ends.apply(event("UserPromptSubmit", "e1", at: 10), now: t0 + 10)
        precondition(ends.sessions["claude:e1"]?.outcome == nil && ends.sessions["claude:e1"]?.unseen == nil, "a new turn clears the failure")
        ends.apply(event("Stop", "e1", at: 15), now: t0 + 15)
        precondition(ends.sessions["claude:e1"]?.outcome == nil)
        ends.apply(event("UserPromptSubmit", "e2", at: 0, provider: .codex), now: t0)
        ends.apply(event("Interrupt", "e2", at: 3, provider: .codex), now: t0 + 3)
        ended = ends.sessions["codex:e2"]!
        precondition(ended.outcome == .interrupted && ended.unseen == nil && ends.moments["codex:e2"] == SessionMoment(kind: .interrupted, at: t0 + 3))
        precondition(SessionStore.status(ended, now: t0 + 200) == "done · 3m ago")
        ends.apply(event("UserPromptSubmit", "e3", at: 0, provider: .codex), now: t0)
        ends.apply(event("Ended", "e3", at: 4, provider: .codex), now: t0 + 4)
        precondition(ends.sessions["codex:e3"]?.outcome == .lost && ends.moments["codex:e3"]?.kind == .appeared, "a lost process plays no moment")
        ends.apply(event("UserPromptSubmit", "e4", at: 0, pid: 77), now: t0)
        ends.apply(event("UserPromptSubmit", "e5", at: 0), now: t0)
        precondition(ends.tick(now: t0 + 20, alive: { $0 != 77 }) && ends.sessions["claude:e4"]?.outcome == .lost && ends.sessions["claude:e5"]?.outcome == nil)
        precondition(ends.tick(now: t0 + 1801, alive: { _ in true }) && ends.sessions["claude:e5"]?.outcome == .lost)
        // The outcome is saved; files without it read as a plain stop; turns cut short by a reboot are lost.
        let endFile = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: endFile) }
        let endSaved = SessionStore(file: endFile)
        endSaved.apply(event("UserPromptSubmit", "e6", at: 0), now: t0); endSaved.apply(event("StopFailure", "e6", at: 1), now: t0 + 1)
        endSaved.apply(event("UserPromptSubmit", "e7", at: 0), now: t0)
        endSaved.save()
        let endRestored = SessionStore(file: endFile); endRestored.load(now: t0 + 60, booted: t0 + 30, alive: { _ in true })
        precondition(endRestored.sessions["claude:e6"]?.outcome == .failed && endRestored.sessions["claude:e6"]?.unseen == true)
        precondition(endRestored.sessions["claude:e7"]?.state == .idle && endRestored.sessions["claude:e7"]?.outcome == .lost)
        precondition(endRestored.moments.isEmpty && endRestored.running.isEmpty, "a loaded file plays nothing")
        try Data(#"[{"provider":"codex","id":"y","name":"Old","state":"idle","started":\#(t0),"turnStarted":\#(t0),"changed":\#(t0),"unseen":true}]"#.utf8).write(to: endFile)
        let endOlder = SessionStore(file: endFile); endOlder.load(now: t0 + 60, booted: t0 - 100, alive: { _ in true })
        precondition(endOlder.sessions["codex:y"]?.outcome == nil && endOlder.sessions["codex:y"]?.unseen == true)

        // A running tool: Claude types with alternating hands every 0.16 s and does not bob; Codex runs its cursor; the icon stays.
        let edit = SessionTool(id: "a", kind: .edit)
        let typing = (0..<4).map { look(claudeWork, tool: edit, at: t0 + Double($0) * SessionLook.waitTick + 0.01) }
        precondition(Set(typing.map(\.typing)) == [.left, .right] && zip(typing, typing.dropFirst()).allSatisfy { $0.typing != $1.typing })
        precondition(typing.allSatisfy { $0.lift == 1 && $0.legs == .both && $0.hint == .tool(.edit) && $0.bold })
        precondition(look(claudeWork, tool: edit, at: t0, motion: false) == SessionLook(lift: 1, hint: .tool(.edit), bold: true), "Reduce Motion keeps the icon")
        precondition(look(claudeWork, tool: SessionTool(id: "a", kind: nil), at: t0 + 0.01).hint == .none, "no kind, no icon")
        let running = (0..<6).map { look(codexWork, tool: SessionTool(id: "a", kind: nil), at: t0 + Double($0) * SessionLook.waitTick + 0.01) }
        let shifts = running.map(\.cursorShift)
        precondition(Set(shifts) == [0, 1, 2] && running.allSatisfy { $0.cursor && $0.hint == .none }, "\(shifts)")
        precondition(zip(shifts, shifts.dropFirst()).allSatisfy { $1 == ($0 + 1) % 3 }, "the cursor runs right and starts over")
        // A tool error: a shake of four 0.08 s frames and "!" for a second, then back to the tool; only on a working tile.
        let oops = SessionMoment(kind: .toolFailed, at: t0)
        precondition((0..<5).map { look(claudeWork, oops, tool: edit, at: t0 + Double($0) * SessionLook.fastTick + 0.001).shake } == [-1, 1, -1, 1, 0])
        precondition(look(claudeWork, oops, tool: edit, at: t0 + 0.5).hint == .alert && look(claudeWork, oops, tool: edit, at: t0 + 1.01).hint == .tool(.edit))
        precondition(look(claudeWork, oops, at: t0 + 1.01).hint == .none && look(claudeWork, oops, at: t0 + 0.1, motion: false) == look(claudeWork, at: t0 + 0.1, motion: false))
        precondition(look(idleTile, oops, at: t0 + 0.1) == look(idleTile, at: t0 + 0.1), "a tool error shows only while working")

        // A failed turn: shake, then crossed eyes as the colour drains; red light until seen; no z.
        var failedTile = Session(provider: .claude, id: "p1", name: "P", state: .idle, started: t0, turnStarted: t0, changed: t0)
        failedTile.outcome = .failed; failedTile.unseen = true
        let crash = SessionMoment(kind: .failed, at: t0)
        precondition((0..<4).map { look(failedTile, crash, at: t0 + Double($0) * SessionLook.fastTick + 0.001).shake } == SessionLook.shakes)
        precondition(!look(failedTile, crash, at: t0 + 0.1).crossed && look(failedTile, crash, at: t0 + 0.1).awake == 1)
        precondition([0.33, 0.49, 0.65, 0.81].map { look(failedTile, crash, at: t0 + $0).awake } == [0.75, 0.5, 0.25, 0])
        precondition(look(failedTile, crash, at: t0 + 0.33).crossed && look(failedTile, crash, at: t0 + 0.81).lift == 0)
        let failedRest = look(failedTile, at: t0 + 600)
        precondition(failedRest == look(failedTile, crash, at: t0 + 600) && failedRest.crossed && failedRest.light == .failed && failedRest.hint == .none && failedRest.bold)
        precondition(look(failedTile, crash, at: t0 + 0.1, motion: false) == look(failedTile, at: t0 + 0.1), "Reduce Motion skips the shake")
        failedTile.unseen = nil
        precondition(look(failedTile, at: t0 + 600).light == .off && look(failedTile, at: t0 + 600).crossed && !look(failedTile, at: t0 + 600).bold)
        // Interrupted: like finished without the jump, the blinks and the check; then plain sleep.
        var stopped = idleTile; stopped.provider = .codex; stopped.unseen = nil; stopped.outcome = .interrupted
        let halt = SessionMoment(kind: .interrupted, at: t0)
        precondition(stride(from: 0.0, to: 2.4, by: 0.08).allSatisfy { let l = look(stopped, halt, at: t0 + $0 + 0.001); return l.lift == 1 && l.cursor && l.hint == .none && l.awake == 1 })
        precondition([2.41, 2.57, 2.73, 2.89].map { look(stopped, halt, at: t0 + $0).awake } == [0.75, 0.5, 0.25, 0])
        precondition(look(stopped, halt, at: t0 + 2.5).hint == .sleep(1) && look(stopped, halt, at: t0 + 3.1) == look(stopped, at: t0 + 3.1))
        precondition(look(stopped, at: t0 + 600) == SessionLook(eyesClosed: true, awake: 0, hint: .sleep(1)))
        // Lost: "?" instead of z, no movement.
        var lostTile = idleTile; lostTile.unseen = nil; lostTile.outcome = .lost
        precondition(look(lostTile, at: t0 + 7 * 3600) == SessionLook(eyesClosed: true, awake: 0, hint: .question))

        // The clock steps every 0.16 s while a shown tile runs a tool and stays fast while new moments play.
        precondition(SessionLook.clock([claudeWork], moments: [:], running: [claudeWork.key: edit], now: t0, motion: true).step == SessionLook.waitTick)
        precondition(SessionLook.clock([claudeWork], moments: [:], running: ["claude:other": edit], now: t0, motion: true).step == SessionLook.tick)
        precondition(SessionLook.clock([claudeWork], moments: [claudeWork.key: oops], now: t0 + 0.5, motion: true).fastUntil == t0 + SessionLook.alertShown)
        precondition(SessionLook.clock([failedTile], moments: [failedTile.key: crash], now: t0 + 0.5, motion: true).fastUntil == t0 + SessionLook.failing)
        precondition(SessionLook.clock([stopped], moments: [stopped.key: halt], now: t0 + 0.5, motion: true).fastUntil == t0 + SessionLook.finishing)
        precondition(SessionLook.clock([claudeWork], moments: [:], running: [claudeWork.key: edit], now: t0, motion: false) == (0, SessionLook.idleTick))

        // Hat colour depends only on the session ID.
        precondition(SessionStore.hat(for: id, count: 6) == SessionStore.hat(for: id, count: 6))
        precondition((0..<6).contains(SessionStore.hat(for: other, count: 6)))
        precondition(Set((0..<40).map { SessionStore.hat(for: "session-\($0)", count: 6) }).count > 3)
        print("Session tests passed")
    }
}
