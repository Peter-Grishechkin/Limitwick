import Foundation

// Sessions window model: tiles built from the activity hooks of Claude Code and Codex.
// Foundation only, so Tests/SessionTests.swift can compile it without AppKit or SwiftUI.

enum SessionProvider: String, Codable { case claude, codex }
enum SessionState: String, Codable { case working, waiting, idle }

/// One hook event after the monitor validated its file. Optional details come only from the hooks.
struct SessionEvent {
    var provider: SessionProvider
    var session: String
    var event: String
    var time: TimeInterval
    var name: String? = nil
    var app: String? = nil
    var entry: String? = nil
    var pid: Int32? = nil
    var host: String? = nil
}

struct Session: Codable, Equatable {
    var provider: SessionProvider
    var id: String
    /// Folder name; a tile shows the title instead when the Claude app has one.
    var name: String
    /// Title the Claude app gives a Code session after its first turn.
    var title: String? = nil
    var app: String?
    var entry: String?
    var pid: Int32?
    var host: String?
    var state: SessionState
    var started: TimeInterval
    var turnStarted: TimeInterval
    var changed: TimeInterval
    var key: String { provider.rawValue + ":" + id }
}

enum SessionTarget: Equatable { case url(URL), app(String), none }

final class SessionStore {
    static let retention: TimeInterval = 24 * 3600
    static let capacity = 16
    /// A turn without hook events for this long is treated as finished: its process may have been killed.
    static let stale: TimeInterval = 1800
    private static let creating: Set<String> = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure"]
    private static let working: Set<String> = creating
    private static let finishing: Set<String> = ["Stop", "StopFailure", "Idle", "SessionEnd", "Interrupt", "Ended"]

    private(set) var sessions: [String: Session] = [:]
    let file: URL?
    init(file: URL? = nil) { self.file = file }

    static var defaultFile: URL {
        #if LIMITWICK_DEVELOPMENT
        let name = "sessions-development.json"
        #else
        let name = "sessions.json"
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Limitwick/\(name)")
    }

    /// Tiles in display order: waiting, then working, newest first; then finished sessions, most recent first.
    var ordered: [Session] {
        sessions.values.sorted { a, b in
            let pa = Self.priority(a.state), pb = Self.priority(b.state)
            if pa != pb { return pa < pb }
            let ta = a.state == .idle ? a.changed : a.started, tb = b.state == .idle ? b.changed : b.started
            return ta != tb ? ta > tb : a.key < b.key
        }
    }
    private static func priority(_ state: SessionState) -> Int { state == .waiting ? 0 : state == .working ? 1 : 2 }

    /// Applies one event; returns true when the tiles changed.
    @discardableResult
    func apply(_ event: SessionEvent, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard !event.session.isEmpty, event.session.count <= 100, now - event.time < Self.retention else { return false }
        let key = event.provider.rawValue + ":" + event.session
        var session: Session
        if let existing = sessions[key] {
            guard event.time >= existing.changed else { return false }
            session = existing
        } else {
            // Stop, SessionEnd or a notification alone must not create a tile: only real work does.
            guard Self.creating.contains(event.event) else { return false }
            session = Session(provider: event.provider, id: event.session, name: event.provider == .claude ? "Claude" : "Codex",
                              state: .idle, started: event.time, turnStarted: event.time, changed: event.time)
            if let name = Self.clean(event.name) { session.name = name }
        }
        // The first folder name stays: the current folder changes when the agent runs cd.
        if sessions[key] != nil, session.name == (event.provider == .claude ? "Claude" : "Codex"), let name = Self.clean(event.name) { session.name = name }
        if session.app == nil, let app = event.app, Self.matches(app, "[A-Za-z0-9.-]{1,100}") { session.app = app }
        if session.entry == nil, let entry = event.entry, Self.matches(entry, "[a-z0-9-]{1,40}") { session.entry = entry }
        if session.host == nil, let host = event.host, Self.matches(host, "[A-Za-z0-9_-]{1,80}") { session.host = host }
        if session.pid == nil, let pid = event.pid, pid > 0 { session.pid = pid }
        if Self.working.contains(event.event) {
            if event.event == "UserPromptSubmit" || session.state == .idle { session.turnStarted = event.time }
            session.state = .working
        } else if event.event == "Permission" {
            session.state = .waiting
        } else if Self.finishing.contains(event.event) {
            // A later Idle or SessionEnd must not move a finished tile forward in time.
            if session.state == .idle && sessions[key] != nil { return false }
            session.state = .idle
        } else {
            return false
        }
        session.changed = event.time
        sessions[key] = session
        prune(now: now)
        return true
    }

    /// Finishes turns whose process has exited or that went silent, and drops old tiles. Returns true when the tiles changed.
    @discardableResult
    func tick(now: TimeInterval = Date().timeIntervalSince1970, alive: (Int32) -> Bool = SessionStore.processAlive) -> Bool {
        var changed = false
        for (key, var session) in sessions where session.state != .idle {
            let dead = session.pid.map { !alive($0) } ?? false
            // A permission prompt can wait for hours while its process is alive; without a process ID only silence tells.
            let silent = now - session.changed > Self.stale && (session.state == .working || session.pid == nil)
            if dead || silent { session.state = .idle; sessions[key] = session; changed = true }
        }
        return prune(now: now) || changed
    }

    @discardableResult
    private func prune(now: TimeInterval) -> Bool {
        let before = sessions.count
        sessions = sessions.filter { now - $0.value.changed < Self.retention }
        if sessions.count > Self.capacity {
            // Finished sessions go first, oldest first; active ones only when more than 16 are active.
            let keep = sessions.values.sorted { a, b in
                let pa = Self.priority(a.state) == 2, pb = Self.priority(b.state) == 2
                return pa != pb ? !pa : a.changed > b.changed
            }.prefix(Self.capacity)
            sessions = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0) })
        }
        return sessions.count != before
    }

    static func processAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    // MARK: Saved tiles

    /// Reads saved tiles. Turns saved before the last boot are finished: their process IDs may now belong to other programs.
    func load(now: TimeInterval = Date().timeIntervalSince1970, booted: TimeInterval = SessionStore.bootTime,
              alive: (Int32) -> Bool = SessionStore.processAlive) {
        guard let file = file, let data = try? Data(contentsOf: file), data.count < 1_000_000,
              let saved = try? JSONDecoder().decode([Session].self, from: data) else { return }
        sessions = [:]
        for var session in saved where !session.id.isEmpty && session.id.count <= 100 {
            session.name = Self.clean(session.name) ?? (session.provider == .claude ? "Claude" : "Codex")
            session.title = Self.cleanTitle(session.title)
            if session.changed < booted { session.state = .idle }
            sessions[session.key] = session
        }
        tick(now: now, alive: alive)
    }
    static var bootTime: TimeInterval {
        var value = timeval(), size = MemoryLayout<timeval>.size, mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000
    }

    func save() {
        guard let file = file, let data = try? JSONEncoder().encode(ordered) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if (try? data.write(to: file, options: .atomic)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    // MARK: Helpers

    static func clean(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, !name.contains("/"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return String(name.prefix(60))
    }
    /// A session title may contain "/" ("CI/CD"); control and format characters and extra spaces go.
    static func cleanTitle(_ title: String?) -> String? {
        guard let title = title else { return nil }
        let hidden = CharacterSet.controlCharacters.union(.illegalCharacters)
        let words = String(String.UnicodeScalarView(title.unicodeScalars.map { hidden.contains($0) ? " " : $0 }))
            .split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        return String(words.joined(separator: " ").prefix(80))
    }
    /// Sets the title of a tile; returns true when it changed.
    @discardableResult
    func retitle(_ key: String, _ title: String?) -> Bool {
        guard let title = Self.cleanTitle(title), var session = sessions[key], session.title != title else { return false }
        session.title = title
        sessions[key] = session
        return true
    }
    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: "^\(pattern)$", options: .regularExpression) != nil
    }
    /// The Claude app's own session ID; its continue link accepts only this form (or "last").
    static let appSessionPattern = "local_[A-Za-z0-9-]{1,64}"

    /// Where a click on the tile goes. Sessions in the Claude app open by link; others bring their app forward.
    static func target(for session: Session) -> SessionTarget {
        if session.provider == .claude, session.entry == "claude-desktop", let host = session.host, matches(host, appSessionPattern),
           let url = URL(string: "claude://code/continue?session=\(host)") { return .url(url) }
        if let app = session.app { return .app(app) }
        return .none
    }

    /// Adds sessions found on disk as finished tiles. Live tiles keep their state and take the current title;
    /// tiles archived in the Claude app go away.
    @discardableResult
    func merge(_ found: SessionHistory.Found, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        var changed = false
        for key in found.archived where sessions[key]?.state == .idle { sessions[key] = nil; changed = true }
        for session in found.sessions where now - session.changed < Self.retention {
            guard let existing = sessions[session.key] else { sessions[session.key] = session; changed = true; continue }
            var updated = existing
            if updated.host == nil { updated.host = session.host }
            if updated.app == nil { updated.app = session.app }
            if updated.entry == nil { updated.entry = session.entry }
            // The Claude app renames sessions (it keeps previousTitles), so a newer title replaces the old one.
            if let title = session.title { updated.title = title }
            if updated.state == .idle && session.changed > updated.changed { updated.changed = session.changed }
            if updated != existing { sessions[session.key] = updated; changed = true }
        }
        return prune(now: now) || changed
    }

    /// Stable across launches, unlike Hasher: FNV-1a of the session ID.
    static func hat(for id: String, count: Int) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash % UInt32(max(1, count)))
    }

    static func status(_ session: Session, now: TimeInterval) -> String {
        func span(_ seconds: TimeInterval) -> String {
            let minutes = Int(max(0, seconds) / 60)
            return minutes < 1 ? "<1m" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
        }
        switch session.state {
        case .working: return "working · \(span(now - session.turnStarted))"
        case .waiting: return "needs you"
        case .idle: return now - session.changed < 60 ? "done · just now" : "done · \(span(now - session.changed)) ago"
        }
    }
}

/// Sessions of the last 24 hours read from disk, so the window is not empty until each session sends its next hook event.
/// Reads only IDs, folders, times, the archived flag and the titles of Claude app sessions; never prompts or replies.
enum SessionHistory {
    struct Found { var sessions: [Session] = []; var archived: Set<String> = [] }
    /// Limitwick's own /usage probe runs claude in this folder.
    static let probeFolder = "/Library/Application Support/Limitwick/ClaudeProbe"
    static let appIndex = "Library/Application Support/Claude/claude-code-sessions"

    static func scan(now: TimeInterval = Date().timeIntervalSince1970, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     claudeConfig: URL? = nil, codexHome: URL? = nil) -> Found {
        let environment = ProcessInfo.processInfo.environment
        let claude = claudeConfig ?? environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        let codex = codexHome ?? environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        var found = Found()
        appSessions(home.appendingPathComponent(appIndex), now: now, into: &found)
        transcripts(claude.appendingPathComponent("projects"), now: now, into: &found)
        codexSessions(codex.appendingPathComponent("sessions"), now: now, into: &found)
        return found
    }

    /// The current title of one Claude app session, by its local_ ID. The app names a session after its first turn
    /// and may rename it later, so a live tile rereads it when a turn starts or ends.
    static func appTitle(host: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        guard SessionStore.matches(host, SessionStore.appSessionPattern) else { return nil }
        for account in children(home.appendingPathComponent(appIndex)) { for organization in children(account) {
            let file = organization.appendingPathComponent(host + ".json")
            guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 8_000_000,
                  let data = try? Data(contentsOf: file), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  object["sessionId"] as? String == host else { continue }
            return SessionStore.cleanTitle(object["title"] as? String)
        }}
        return nil
    }

    // The Claude app keeps one JSON file per Code session: its own ID for the open link, the CLI session ID the hooks send,
    // the folder, the title, the last activity and the archived flag.
    private static func appSessions(_ root: URL, now: TimeInterval, into found: inout Found) {
        for account in children(root) { for organization in children(account) {
            for file in children(organization) where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                guard modified(file, now: now) != nil, let data = try? Data(contentsOf: file),
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let local = object["sessionId"] as? String, SessionStore.matches(local, SessionStore.appSessionPattern),
                      let cli = object["cliSessionId"] as? String, !cli.isEmpty, cli.count <= 100 else { continue }
                if object["isArchived"] as? Bool == true { found.archived.insert("claude:" + cli); continue }
                guard let last = (object["lastActivityAt"] as? NSNumber)?.doubleValue, now - last / 1000 < SessionStore.retention else { continue }
                let changed = last / 1000, created = (object["createdAt"] as? NSNumber)?.doubleValue ?? last
                found.sessions.append(Session(provider: .claude, id: cli, name: folder(object["originCwd"] ?? object["cwd"]) ?? "Claude",
                                              title: SessionStore.cleanTitle(object["title"] as? String), app: "com.anthropic.claudefordesktop", entry: "claude-desktop", host: local,
                                              state: .idle, started: min(created / 1000, changed), turnStarted: changed, changed: changed))
            }
        }}
    }

    // Claude Code in a terminal: one transcript per session, whose first lines hold the folder and entry point.
    private static func transcripts(_ root: URL, now: TimeInterval, into found: inout Found) {
        for project in children(root) { for file in children(project) where file.pathExtension == "jsonl" {
            let id = file.deletingPathExtension().lastPathComponent
            guard id.count <= 100, let changed = modified(file, now: now), let head = prefix(file, 65_536) else { continue }
            var cwd: String?, entry: String?
            for line in head.split(separator: UInt8(ascii: "\n")) {
                guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
                cwd = cwd ?? object["cwd"] as? String; entry = entry ?? object["entrypoint"] as? String
                if cwd != nil && entry != nil { break }
            }
            // Claude app sessions come from the app's own list, which also knows archived ones.
            guard entry != "claude-desktop", let path = cwd, !path.hasSuffix(probeFolder), let name = folder(path) else { continue }
            found.sessions.append(Session(provider: .claude, id: id, name: name, entry: entry.flatMap { SessionStore.matches($0, "[a-z0-9-]{1,40}") ? $0 : nil },
                                          state: .idle, started: changed, turnStarted: changed, changed: changed))
        }}
    }

    // Codex keeps sessions in sessions/YYYY/MM/DD by start date; the first line is session_meta with the ID and folder.
    // Threads of subagents carry their parent's session_id and are skipped.
    private static func codexSessions(_ root: URL, now: TimeInterval, into found: inout Found) {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        var visited = 0
        for case let file as URL in files where file.pathExtension == "jsonl" {
            visited += 1; if visited > 20_000 { break }
            guard let changed = modified(file, now: now), let head = prefix(file, 1_000_000),
                  let line = head.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
                  let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any], object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any], let id = payload["id"] as? String, UUID(uuidString: id) != nil,
                  (payload["session_id"] as? String).map({ $0 == id }) ?? true, let name = folder(payload["cwd"]) else { continue }
            found.sessions.append(Session(provider: .codex, id: id, name: name, state: .idle, started: changed, turnStarted: changed, changed: changed))
        }
    }

    private static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
    }
    /// Modification time when the file changed within 24 hours and is a sane size.
    private static func modified(_ url: URL, now: TimeInterval) -> TimeInterval? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]), let date = values.contentModificationDate,
              now - date.timeIntervalSince1970 < SessionStore.retention, (values.fileSize ?? 0) < 8_000_000 else { return nil }
        return date.timeIntervalSince1970
    }
    private static func prefix(_ url: URL, _ limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit)
    }
    private static func folder(_ path: Any?) -> String? {
        guard let path = path as? String, path.hasPrefix("/") else { return nil }
        return SessionStore.clean((path as NSString).lastPathComponent)
    }
}
