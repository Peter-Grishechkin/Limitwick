import Foundation

// Sessions window model: tiles built from the activity hooks of Claude Code and Codex.
// Foundation only, so Tests/SessionTests.swift can compile it without AppKit or SwiftUI.

enum SessionProvider: String, Codable { case claude, codex }
enum SessionState: String, Codable { case working, waiting, idle }
/// How the last turn ended when it did not simply stop: an API error (StopFailure), your interrupt (Codex),
/// or a process that exited or went silent.
enum SessionOutcome: String, Codable { case failed, interrupted, lost }
/// The kind of tool a session runs, as its hook reports it; the tool name never leaves the hook.
enum ToolKind: String { case edit, shell, read, search, web, agent, plan, mcp, other }

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
    /// Tool call ID of PreToolUse and PostToolUse events.
    var tool: String? = nil
    /// Kind of tool of a PreToolUse; hook copies from before 2026-11-11 do not send it.
    var category: String? = nil
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
    /// A turn finished while you were away: true until you open the session, start a new turn or mark all as seen.
    /// Saved with the tile; files without it read as seen.
    var unseen: Bool? = nil
    /// How the last turn ended when it did not simply stop. Saved with the tile; files without it read as a plain stop.
    var outcome: SessionOutcome? = nil
    var key: String { provider.rawValue + ":" + id }
}

/// A live change a tile plays once: a new session appears, a turn has just finished, failed or was interrupted, a tool failed.
/// Only `apply` records it, from a fresh hook event, so tiles from history or a saved file never animate. Kept in memory only.
struct SessionMoment: Equatable {
    enum Kind { case appeared, finished, toolFailed, failed, interrupted }
    var kind: Kind
    var at: TimeInterval
}

/// A tool call that started and has not returned yet. Kept in memory only; the kind is nil when the hook does not say (older hook copies).
struct SessionTool: Equatable {
    var id: String
    var kind: ToolKind?
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
    private static let outcomes: [String: SessionOutcome] = ["StopFailure": .failed, "Interrupt": .interrupted, "Ended": .lost]
    /// Open calls kept per tile: a call whose PostToolUse never came must not grow the list without end.
    static let openTools = 32

    /// An event older than this when it arrives changes the tile without playing its moment.
    static let fresh: TimeInterval = 10

    private(set) var sessions: [String: Session] = [:]
    private(set) var moments: [String: SessionMoment] = [:]
    /// Open tool calls per tile, oldest first. In memory only, like moments.
    private(set) var tools: [String: [SessionTool]] = [:]
    /// The call each tile shows: the last one started that has not returned.
    var running: [String: SessionTool] { tools.compactMapValues(\.last) }
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
        let live = now - event.time < Self.fresh
        let isNew = sessions[key] == nil
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
            if event.event == "UserPromptSubmit" || session.state == .idle { session.turnStarted = event.time; session.outcome = nil }
            // A new prompt means you are back in this session; calls of the last turn that never returned are over.
            if event.event == "UserPromptSubmit" { session.unseen = nil; tools[key] = nil }
            session.state = .working
            let call = event.tool ?? ""
            if event.event == "PreToolUse" {
                var open = (tools[key] ?? []).filter { $0.id != call }
                open.append(SessionTool(id: call, kind: event.category.map { ToolKind(rawValue: $0) ?? .other }))
                tools[key] = Array(open.suffix(Self.openTools))
            } else if event.event == "PostToolUse" || event.event == "PostToolUseFailure" {
                tools[key]?.removeAll { $0.id == call }
                if event.event == "PostToolUseFailure" && live { moments[key] = SessionMoment(kind: .toolFailed, at: now) }
            }
        } else if event.event == "Permission" {
            session.state = .waiting
        } else if Self.finishing.contains(event.event) {
            // A later Idle or SessionEnd must not move a finished tile forward in time.
            if session.state == .idle && sessions[key] != nil { return false }
            session.state = .idle
            session.outcome = Self.outcomes[event.event]
            tools[key] = nil
            // A turn that ended by itself or failed has a result to look at; an interrupt, a closed session or silence does not.
            switch event.event {
            case "Stop", "StopFailure":
                session.unseen = true
                if live { moments[key] = SessionMoment(kind: event.event == "Stop" ? .finished : .failed, at: now) }
            case "Interrupt":
                if live { moments[key] = SessionMoment(kind: .interrupted, at: now) }
            default: break
            }
        } else {
            return false
        }
        if isNew && live { moments[key] = SessionMoment(kind: .appeared, at: now) }
        session.changed = event.time
        sessions[key] = session
        prune(now: now)
        return true
    }

    /// Clears the unseen mark of one tile; returns true when it changed.
    @discardableResult
    func markSeen(_ key: String) -> Bool {
        guard sessions[key]?.unseen != nil else { return false }
        sessions[key]?.unseen = nil
        return true
    }
    @discardableResult
    func markAllSeen() -> Bool {
        let keys = sessions.filter { $0.value.unseen != nil }.map(\.key)
        for key in keys { sessions[key]?.unseen = nil }
        return !keys.isEmpty
    }
    var hasUnseen: Bool { sessions.values.contains { $0.unseen != nil } }

    /// Finishes turns whose process has exited or that went silent, and drops old tiles. Returns true when the tiles changed.
    @discardableResult
    func tick(now: TimeInterval = Date().timeIntervalSince1970, alive: (Int32) -> Bool = SessionStore.processAlive) -> Bool {
        var changed = false
        for (key, var session) in sessions where session.state != .idle {
            let dead = session.pid.map { !alive($0) } ?? false
            // A permission prompt can wait for hours while its process is alive; without a process ID only silence tells.
            let silent = now - session.changed > Self.stale && (session.state == .working || session.pid == nil)
            if dead || silent { session.state = .idle; session.outcome = .lost; sessions[key] = session; tools[key] = nil; changed = true }
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
        moments = moments.filter { sessions[$0.key] != nil && now - $0.value.at < Self.fresh }
        tools = tools.filter { sessions[$0.key] != nil }
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
            if session.changed < booted && session.state != .idle { session.state = .idle; session.outcome = .lost }
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

    private static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return minutes < 1 ? "<1m" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }
    /// At most 14 characters ("done · 11m ago", "failed 59m ago"): that fits a tile in 10 pt monospaced type.
    /// A waiting session gets hungrier the longer it waits, like the device in the reference photo.
    static func status(_ session: Session, now: TimeInterval) -> String {
        switch session.state {
        case .working: return "working · \(span(now - session.turnStarted))"
        case .waiting:
            let waited = now - session.changed
            return waited < 60 ? "feed me!" : "\(waited < 300 ? "hungry" : "starving") · \(span(waited))"
        case .idle:
            let ago = now - session.changed
            if session.outcome == .failed { return ago < 60 ? "just failed" : "failed \(span(ago)) ago" }
            return ago < 60 ? "done · just now" : "done · \(span(ago)) ago"
        }
    }
    /// What VoiceOver says: the playful waiting caption in plain words, and "new" for an unseen result.
    static func spokenStatus(_ session: Session, now: TimeInterval) -> String {
        let waited = now - session.changed
        var words = session.state != .waiting ? status(session, now: now)
            : "needs your permission" + (waited < 60 ? "" : " · \(span(waited))")
        if session.unseen != nil { words += ", new" }
        return words
    }
}

/// One frame of a tile, worked out from the session, its live moment, its running tool and the time, so frames are testable without drawing.
/// Frames move in whole pixels and change in fixed steps, like the screen of a device.
/// Idle tiles stand still; with Reduce Motion every state keeps one static pose.
struct SessionLook: Equatable {
    enum Legs { case both, leftUp, rightUp }
    enum Side { case none, left, right }
    /// Shown beside the mascot's head, one at a time: the running tool, "!" after a tool error, a check right after a turn,
    /// z's that grow with the age of an idle tile, or "?" when the session went silent or its process exited.
    enum Hint: Equatable { case none, check, sleep(Int), tool(ToolKind), alert, question }
    /// The square in the tile corner, like a device LED: orange waits for you, green is an unseen result, red an unseen failure.
    enum Light { case off, waiting, waitingDim, unseen, failed }

    /// Pixels above the resting position: 0 rests (idle), 1 stands (working), 2–3 in a jump.
    var lift = 0
    var legs = Legs.both
    var armUp = false
    var eyesClosed = false
    /// Codex: the "_" of the ">_" face.
    var cursor = true
    /// 1 is full colour, 0 grey; a finished mascot falls asleep in four steps.
    var awake = 1.0
    /// Share of pixels drawn while a new tile appears.
    var reveal = 1.0
    var hint = Hint.none
    var light = Light.off
    /// Offset of the waiting stripes in points, 0..<12 (one stripe period).
    var stripes = 0
    /// Name in white semibold: active sessions and unseen results.
    var bold = false
    /// Claude while a tool runs: one hand a pixel up, then the other, as if typing.
    var typing = Side.none
    /// Codex while a tool runs: how far the "_" has run to the right, 0...2 pixels.
    var cursorShift = 0
    /// Pixels sideways while the mascot shakes after an error.
    var shake = 0
    /// The turn failed: crossed-out eyes (Claude) or ">x" (Codex).
    var crossed = false

    static let tick: TimeInterval = 0.32
    static let waitTick: TimeInterval = 0.16
    static let fastTick: TimeInterval = 0.08
    static let appearing: TimeInterval = 0.4
    static let checkShown: TimeInterval = 2.4
    static let finishing: TimeInterval = 3.04
    /// A shake: ±1 pixel, four frames of 0.08 s.
    static let shaking: TimeInterval = 0.32
    static let shakes = [-1, 1, -1, 1]
    /// "!" stays a second after a tool error.
    static let alertShown: TimeInterval = 1
    /// A failed turn shakes, then greys out in four steps with crossed eyes.
    static let failing: TimeInterval = 0.96
    static let idleTick: TimeInterval = 20

    static func duration(_ kind: SessionMoment.Kind) -> TimeInterval {
        switch kind {
        case .appeared: return appearing
        case .finished, .interrupted: return finishing
        case .toolFailed: return alertShown
        case .failed: return failing
        }
    }

    static func of(_ session: Session, moment: SessionMoment?, tool: SessionTool? = nil, now: TimeInterval, motion: Bool) -> SessionLook {
        var look = SessionLook()
        // Each session runs its cycles from its own phase, so working mascots do not move in step.
        let phase = SessionStore.hat(for: session.id, count: 4)
        let beat = Int((now / tick).rounded(.down)) + phase
        let t = moment.map { now - $0.at } ?? -1
        switch session.state {
        case .working:
            look.lift = 1; look.bold = true
            // The icon stands still: the mascot moves, not the icon. It stays with Reduce Motion, since it says what runs.
            if let kind = tool?.kind { look.hint = .tool(kind) }
            guard motion else { break }
            if tool != nil {
                // Types (Claude) or runs its cursor (Codex) a step every 0.16 s, without bobbing.
                let step = Int((now / waitTick).rounded(.down)) + phase
                if session.provider == .claude { look.typing = step % 2 == 0 ? .left : .right } else { look.cursorShift = step % 3 }
            } else if session.provider == .claude {
                // Bobs and steps in place: up with the left legs lifted, down, up with the right legs lifted, down.
                switch beat % 4 { case 0: look.legs = .leftUp; case 2: look.legs = .rightUp; default: look.lift = 0 }
            } else {
                look.cursor = beat % 4 < 2
            }
            // A tool error: a shake and "!" for a second, then back to work.
            if moment?.kind == .toolFailed, t >= 0, t < alertShown {
                look.hint = .alert
                if t < shaking { look.shake = shakes[Int(t / fastTick)] }
            }
        case .waiting:
            look.lift = 1; look.bold = true; look.light = .waiting
            // Without motion a raised hand alone says "over here".
            look.armUp = session.provider == .claude
            guard motion else { break }
            look.stripes = Int((now / waitTick).rounded(.down)) % 12
            look.light = Int((now * 2).rounded(.down)) % 2 == 0 ? .waiting : .waitingDim
            if session.provider == .claude {
                // Three waves, then a two-second pause.
                let cycle = (now + Double(phase) * 0.98).truncatingRemainder(dividingBy: 3.92)
                look.armUp = cycle < 1.92 && Int(cycle / tick) % 2 == 0
            }
        case .idle:
            let age = now - session.changed
            look.eyesClosed = true; look.awake = 0
            switch session.outcome {
            case .failed?: look.crossed = true
            case .lost?: look.hint = .question
            default: look.hint = .sleep(age < 3600 ? 1 : age < 6 * 3600 ? 2 : 3)
            }
            if session.unseen != nil { look.light = session.outcome == .failed ? .failed : .unseen; look.bold = true }
            guard motion, let kind = moment?.kind else { break }
            let rest = look.hint
            if kind == .finished || kind == .interrupted, t >= 0, t < finishing {
                // Just finished: a jump (Claude) or three quick cursor blinks (Codex) and a check, then asleep in four colour steps.
                // Interrupted: the same without the jump, the blinks and the check.
                let finished = kind == .finished
                look.lift = 1; look.awake = 1; look.eyesClosed = false; look.bold = true
                look.hint = t < checkShown ? (finished ? .check : .none) : rest
                if finished && session.provider == .claude {
                    let jump = [2, 3, 3, 2], frame = Int(t / fastTick)
                    if frame < jump.count { look.lift = jump[frame] }
                } else if finished && t < 0.96 {
                    look.cursor = Int(t / waitTick) % 2 == 1
                }
                if t >= checkShown {
                    look.awake = max(0, 0.75 - Double(Int((t - checkShown) / waitTick)) * 0.25)
                    if look.awake == 0 { look.lift = 0; look.eyesClosed = true }
                }
            } else if kind == .failed, t >= 0, t < failing {
                // The turn failed: a shake, then crossed eyes as the colour drains in four steps.
                look.lift = 1; look.awake = 1; look.eyesClosed = false; look.bold = true; look.crossed = false
                if t < shaking {
                    look.shake = shakes[Int(t / fastTick)]
                } else {
                    look.crossed = true
                    look.awake = max(0, 0.75 - Double(Int((t - shaking) / waitTick)) * 0.25)
                    if look.awake == 0 { look.lift = 0 }
                }
            }
        }
        if motion, moment?.kind == .appeared, t >= 0, t < appearing { look.reveal = Double(Int(t / fastTick) + 1) / 5 }
        return look
    }

    /// Steps of the one clock that drives all tiles: fast while a moment plays, then as slow as the shown tiles allow.
    static func clock(_ sessions: [Session], moments: [String: SessionMoment], running: [String: SessionTool] = [:],
                      now: TimeInterval, motion: Bool) -> (fastUntil: TimeInterval, step: TimeInterval) {
        guard motion else { return (0, idleTick) }
        let shown = Set(sessions.map(\.key))
        let ends = moments.filter { shown.contains($0.key) }.map { $0.value.at + duration($0.value.kind) }
        let fastUntil = ends.max().map { $0 > now ? $0 : 0 } ?? 0
        // Waiting stripes and a running tool step every 0.16 s; thinking every 0.32 s.
        let quick = sessions.contains { $0.state == .waiting || ($0.state == .working && running[$0.key] != nil) }
        let step = quick ? waitTick : sessions.contains { $0.state == .working } ? tick : idleTick
        return (fastUntil, step)
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
