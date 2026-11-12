import Foundation
import Darwin

enum ProviderSelection: String, CaseIterable {
    case codex, claude, both
    var includesCodex: Bool { self != .claude }
    var includesClaude: Bool { self != .codex }
    var title: String { self == .both ? "Both" : rawValue.capitalized }
}

enum ClaudeError: Error, LocalizedError {
    case notInstalled, launchFailed, timeout, notSignedIn, usageFailed, invalidResponse, cancelled
    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Claude Code not found. Install it and sign in, then refresh."
        case .launchFailed: return "Could not start Claude Code. Check its installation and permissions."
        case .timeout: return "Claude Code did not return usage in time. Check login and network, then refresh."
        case .notSignedIn: return "Claude Code is not signed in. Run claude in Terminal and sign in."
        case .usageFailed: return "Claude could not load usage. Check your connection or try again later."
        case .invalidResponse: return "Could not read Claude usage. Check /usage in Claude Code and refresh."
        case .cancelled: return "Claude update cancelled."
        }
    }
}

// Claude Code could not refresh usage and showed bars it had loaded earlier; age is how old they are, when it says.
struct ClaudeLastKnownUsage: Error, LocalizedError {
    let quota: Quota
    let age: TimeInterval?
    var errorDescription: String? { "Claude Code could not refresh usage. Try again later." }
}

enum UsageFreshness: Equatable {
    case current, refreshing, lastKnown(age: TimeInterval?)
}

// A small terminal screen, not a transcript: redraws and erased values must not become quotas.
struct ClaudeScreen {
    private let columns = 160, rows = 200
    private var cells = Array(repeating: Array(repeating: Character(" "), count: 160), count: 200)
    private var row = 0, column = 0
    private var escape = ""
    private var inEscape = false
    mutating func append(_ text: String) {
        for scalar in text.unicodeScalars {
            let c = Character(String(scalar))
            if inEscape {
                escape.append(c)
                if escape.count == 1 && c != "[" && c != "]" { inEscape = false; escape = ""; continue }
                if escape.hasPrefix("]") { if c == "\u{7}" || escape.hasSuffix("\u{1b}\\") { inEscape = false; escape = "" }; continue }
                if escape.count > 1 && c.asciiValue.map({ $0 >= 64 && $0 <= 126 }) == true {
                    applyCSI(escape); inEscape = false; escape = ""
                } else if escape.count > 128 { inEscape = false; escape = "" }
                continue
            }
            switch c {
            case "\u{1b}": inEscape = true; escape = ""
            case "\r": column = 0
            case "\n": row = min(rows - 1, row + 1)
            case "\u{8}": column = max(0, column - 1)
            case "\t": column = min(columns - 1, (column / 8 + 1) * 8)
            default:
                guard c.unicodeScalars.first.map({ $0.value >= 32 && $0.value != 127 }) == true else { continue }
                cells[row][column] = c; column += 1
                if column >= columns { column = 0; row = min(rows - 1, row + 1) }
            }
        }
    }
    private mutating func applyCSI(_ sequence: String) {
        guard let command = sequence.last else { return }
        let args = sequence.dropFirst().dropLast().split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        func arg(_ i: Int, _ fallback: Int = 1) -> Int { i < args.count && args[i] > 0 ? args[i] : fallback }
        switch command {
        case "H", "f": row = min(rows - 1, arg(0) - 1); column = min(columns - 1, arg(1) - 1)
        case "A": row = max(0, row - arg(0))
        case "B": row = min(rows - 1, row + arg(0))
        case "C": column = min(columns - 1, column + arg(0))
        case "D": column = max(0, column - arg(0))
        case "G": column = min(columns - 1, arg(0) - 1)
        case "d": row = min(rows - 1, arg(0) - 1)
        case "K":
            let mode = args.first ?? 0
            let range = mode == 2 ? 0..<columns : (mode == 1 ? 0..<(column + 1) : column..<columns)
            for i in range { cells[row][i] = " " }
        case "J":
            let mode = args.first ?? 0
            if mode == 2 || mode == 3 { cells = Array(repeating: Array(repeating: " ", count: columns), count: rows) }
            else if mode == 0 { for i in row..<rows { for j in (i == row ? column : 0)..<columns { cells[i][j] = " " } } }
        default: break
        }
    }
    var text: String { cells.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") }
}

enum ClaudeUsageParser {
    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map { i in Range(result.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
    static func parse(_ text: String, now: Date = Date()) throws -> Quota {
        let lines = text.components(separatedBy: .newlines)
        var windows: [QuotaWindow] = []
        var additional: [NamedQuotaWindow] = []
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let duration: Int?
            var name: String?
            if lower.contains("current session") { duration = 300 }
            else if lower.contains("current week") && (lower.contains("all models") || !lower.contains("(")) { duration = 10080 }
            else if lower.contains("current week"), let model = match(#"current week\s*\(([^)]+)\)"#, line), !model[1].isEmpty {
                duration = nil; name = model[1]
            }
            else { continue }
            let following = lines[i..<min(lines.count, i + 5)].prefix { candidate in
                candidate == line || (!candidate.lowercased().contains("current week") && !candidate.lowercased().contains("current session"))
            }.joined(separator: " ")
            guard let pct = match(#"(\d{1,3}(?:\.\d+)?)\s*%\s*(used|left|remaining|available)"#, following),
                  let number = Double(pct[1]), (0...100).contains(number) else { continue }
            let remaining = pct[2].lowercased() == "used" ? 100 - number : number
            let reset = match(#"resets?\s+((?:[A-Za-z]{3}\s+\d{1,2}(?:,?\s+(?:at\s+)?)?)?(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2})(?:\s*\([^)]+\))?)"#, following).flatMap { parseReset($0[1], now: now) }
            if let duration = duration {
                windows.removeAll { $0.durationMinutes == duration }
                windows.append(QuotaWindow(durationMinutes: duration, remaining: remaining, reset: reset))
            } else if let name = name {
                additional.removeAll { $0.name == name }
                additional.append(NamedQuotaWindow(name: name, remaining: remaining, reset: reset))
            }
        }
        guard !windows.isEmpty else { throw ClaudeError.invalidResponse }
        return Quota(windows: windows.sorted { $0.durationMinutes < $1.durationMinutes }, conflictingDurations: [], namedAdditional: additional)
    }
    // When the usage request fails, /usage keeps the bars it loaded on this machine in the past hour and adds
    // "Showing last-known usage as of 12m ago (rate limited until 3:15pm)"; until the request ends it shows "Refreshing…".
    static func freshness(_ text: String) -> UsageFreshness {
        if let note = match(#"showing last-known usage(?:\s+as of\s+(\d+)\s*(s|m|h|d)\s+ago)?"#, text) {
            let seconds: [String: TimeInterval] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
            let age = Double(note[1]).flatMap { value in seconds[note[2].lowercased()].map { value * $0 } }
            return .lastKnown(age: age)
        }
        return text.lowercased().contains("refreshing\u{2026}") ? .refreshing : .current
    }
    static func parseReset(_ raw: String, now: Date) -> Date? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var timeZone = TimeZone.current
        // Claude Code names the Mac's own zone, so a name Foundation does not know falls back to the current zone.
        if let zone = match(#"\(([^)]+)\)"#, value) {
            timeZone = TimeZone(identifier: zone[1]) ?? .current
            value = value.replacingOccurrences(of: zone[0], with: "")
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " at ", with: " ").replacingOccurrences(of: ",", with: "")
        let formats = ["MMM d h:mma", "MMM d ha", "h:mma", "ha", "MMM d HH:mm", "HH:mm"]
        var calendar = Calendar.current; calendar.timeZone = timeZone
        for format in formats {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = format
            f.defaultDate = calendar.startOfDay(for: now)
            guard var date = f.date(from: value) else { continue }
            if date < now { date = calendar.date(byAdding: format.hasPrefix("MMM") ? .year : .day, value: 1, to: date) ?? date }
            return date
        }
        return nil
    }
}

// `claude -p /usage --output-format stream-json` (Claude Code 2.1.x) puts the plan limits as data on the message that
// carries the /usage text: usage_report.rate_limits.limits[] with kind, percent used and resets_at.
enum ClaudeUsageJSON {
    enum Outcome {
        case current(Quota)
        // No fresh limits: older Claude Code, an error, or saved data (limits is null then). The screen tells which.
        case fallback
        // The model answered "/usage" as a prompt instead of running the command: stop using this path.
        case modelCalled
    }
    static func parse(_ output: String) -> Outcome {
        var limits: [[String: Any]]?, modelCalled = false
        for line in output.split(whereSeparator: \.isNewline) {
            guard let record = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if let report = record["usage_report"] as? [String: Any], let rate = report["rate_limits"] as? [String: Any] {
                limits = rate["limits"] as? [[String: Any]]
            }
            if record["type"] as? String == "result" {
                modelCalled = ((record["num_turns"] as? NSNumber)?.intValue ?? 0) > 0 || ((record["total_cost_usd"] as? NSNumber)?.doubleValue ?? 0) > 0
            }
        }
        if modelCalled { return .modelCalled }
        var windows: [QuotaWindow] = [], additional: [NamedQuotaWindow] = []
        for limit in limits ?? [] {
            guard let used = (limit["percent"] as? NSNumber)?.doubleValue, used.isFinite else { continue }
            let remaining = min(100, max(0, 100 - used)), reset = date(limit["resets_at"])
            func window(_ minutes: Int) {
                windows.removeAll { $0.durationMinutes == minutes }
                windows.append(QuotaWindow(durationMinutes: minutes, remaining: remaining, reset: reset))
            }
            switch limit["kind"] as? String {
            case "session": window(300)
            case "weekly_all": window(10080)
            case "weekly_scoped":
                if let name = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String, !name.isEmpty {
                    additional.append(NamedQuotaWindow(name: name, remaining: remaining, reset: reset))
                }
            default: continue
            }
        }
        guard !windows.isEmpty else { return .fallback }
        return .current(Quota(windows: windows.sorted { $0.durationMinutes < $1.durationMinutes }, conflictingDurations: [], namedAdditional: additional))
    }
    static func date(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        // Claude Code writes microseconds ("08:00:00.364570+00:00"); read the time without the fraction if they are refused.
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
    }
}

final class ClaudeClient {
    let timeout: TimeInterval
    private let lock = NSLock()
    private var active: Process?
    private var cancelled = false
    private var modelAnswered = false
    // Hooks (including Limitwick's own activity hooks), MCP servers and remote control stay off for every probe.
    private static let settings = #"{"remoteControlAtStartup":false,"disableAllHooks":true}"#
    init(timeout: TimeInterval = 30) { self.timeout = timeout }
    static func findCLI(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory(),
                        system: [String] = CLILocator.systemFolders) -> String? {
        // ~/.claude/local is the per-user npm install made by the old `claude migrate-installer`.
        CLILocator.find("claude", environment: environment, home: home, system: system,
                        preferred: ["\(home)/.claude/local/claude", "\(home)/.claude/local/node_modules/.bin/claude"])
    }
    func cancel() { lock.lock(); cancelled = true; if let p = active, p.isRunning { kill(p.processIdentifier, SIGKILL) }; lock.unlock() }
    func fetch(path: String, directory: URL? = nil) -> Result<Quota, Error> {
        let folder = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Limitwick/ClaudeProbe", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return .failure(ClaudeError.launchFailed) }
        if directory == nil && folder.standardizedFileURL != folder.resolvingSymlinksInPath().standardizedFileURL { return .failure(ClaudeError.launchFailed) }
        lock.lock(); let useJSON = !modelAnswered; lock.unlock()
        if useJSON {
            switch fetchJSON(path: path, folder: folder) {
            case .current(let quota): return .success(quota)
            case .modelCalled: lock.lock(); modelAnswered = true; lock.unlock()
            case .fallback: break
            }
        }
        // The /usage screen in a pseudo-terminal is the fallback, and the only place that says whether bars are saved ones.
        return fetchScreen(path: path, folder: folder)
    }

    // About 2 s and no model call: Claude Code runs /usage as a local command and exits.
    private func fetchJSON(path: String, folder: URL) -> ClaudeUsageJSON.Outcome {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-p", "/usage", "--output-format", "stream-json", "--verbose", "--no-session-persistence",
                             "--strict-mcp-config", "--allowedTools", "", "--settings", Self.settings]
        process.currentDirectoryURL = folder
        var env = CLILocator.environment(for: path); env["NO_COLOR"] = "1"; env["LANG"] = "en_US.UTF-8"; env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        lock.lock()
        guard !cancelled && active == nil else { lock.unlock(); return .fallback }
        do { try process.run(); active = process; lock.unlock() } catch { lock.unlock(); return .fallback }
        defer { lock.lock(); if process.isRunning { kill(process.processIdentifier, SIGKILL) }; lock.unlock(); process.waitUntilExit(); lock.lock(); active = nil; lock.unlock() }
        let reader = pipe.fileHandleForReading, deadline = ProcessInfo.processInfo.systemUptime + min(timeout, 20)
        var output = Data()
        while ProcessInfo.processInfo.systemUptime < deadline {
            lock.lock(); let stopped = cancelled; lock.unlock(); if stopped { return .fallback }
            var fd = pollfd(fd: reader.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            guard poll(&fd, 1, 100) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let count = read(reader.fileDescriptor, &buffer, buffer.count)
            if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            if count <= 0 { return ClaudeUsageJSON.parse(String(decoding: output, as: UTF8.self)) }
            output.append(contentsOf: buffer[0..<count]); if output.count > 2_000_000 { return .fallback }
        }
        return .fallback
    }

    private func fetchScreen(path: String, folder: URL) -> Result<Quota, Error> {
        var master: Int32 = -1, slave: Int32 = -1
        var size = winsize(ws_row: 200, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { return .failure(ClaudeError.launchFailed) }
        let tty = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let process = Process(); process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--strict-mcp-config", "--allowedTools", "", "--settings", Self.settings]
        process.currentDirectoryURL = folder
        var env = CLILocator.environment(for: path); env["TERM"] = "xterm-256color"; env["NO_COLOR"] = "1"; env["LANG"] = "en_US.UTF-8"; env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env; process.standardInput = tty; process.standardOutput = tty; process.standardError = tty
        lock.lock()
        guard !cancelled && active == nil else { lock.unlock(); close(master); return .failure(ClaudeError.cancelled) }
        do { try process.run(); active = process; lock.unlock() } catch { lock.unlock(); close(master); return .failure(ClaudeError.launchFailed) }
        try? tty.close()
        defer { lock.lock(); if process.isRunning { kill(process.processIdentifier, SIGKILL) }; lock.unlock(); process.waitUntilExit(); close(master); lock.lock(); active = nil; lock.unlock() }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var screen = ClaudeScreen(), sent = false, trustAccepted = false, trustOnNo = false, trustVisible = false, lastData = ProcessInfo.processInfo.systemUptime
        var trustReadyAt: TimeInterval?, trustKeySentAt: TimeInterval?
        var best: Quota?
        var bytes = 0
        func finish(_ quota: Quota) -> Result<Quota, Error> {
            switch ClaudeUsageParser.freshness(screen.text) {
            case .current: return .success(quota)
            case .refreshing: return .failure(ClaudeLastKnownUsage(quota: quota, age: nil))
            case .lastKnown(let age): return .failure(ClaudeLastKnownUsage(quota: quota, age: age))
            }
        }
        while ProcessInfo.processInfo.systemUptime < deadline {
            lock.lock(); let stopped = cancelled; lock.unlock(); if stopped { return .failure(ClaudeError.cancelled) }
            var fd = pollfd(fd: master, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&fd, 1, 100)
            // After the CLI exits, poll reports POLLHUP at once and read returns 0 or EIO; without this the loop spins until the deadline.
            var hungUp = ready > 0 && fd.revents & Int16(POLLIN) == 0 && fd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0
            if ready > 0 && fd.revents & Int16(POLLIN) != 0 {
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = read(master, &buffer, buffer.count)
                if count == 0 || (count < 0 && errno != EINTR && errno != EAGAIN) { hungUp = true }
                if count > 0 {
                    bytes += count; if bytes > 2_000_000 { return .failure(ClaudeError.invalidResponse) }
                    screen.append(String(decoding: buffer[0..<count], as: UTF8.self)); lastData = ProcessInfo.processInfo.systemUptime
                    let current = screen.text.lowercased()
                    trustVisible = current.contains("yes, i trust this folder") && current.contains("no, exit")
                    trustOnNo = false
                    if !trustAccepted && trustVisible {
                        if current.range(of: #"❯\s*(?:\d+\.\s*)?no, exit"#, options: .regularExpression) != nil {
                            trustOnNo = true; trustReadyAt = nil
                        } else if current.range(of: #"❯\s*(?:\d+\.\s*)?yes, i trust this folder"#, options: .regularExpression) != nil {
                            if trustReadyAt == nil { trustReadyAt = ProcessInfo.processInfo.systemUptime + 0.5 }
                        } else {
                            trustReadyAt = nil
                        }
                    }
                    if current.contains("not logged in") || current.contains("not authenticated") || current.contains("run /login") || current.contains("select login method") { return .failure(ClaudeError.notSignedIn) }
                    if sent && (current.contains("failed to load usage") || current.contains("error loading usage") || current.contains("rate_limit_error")) { return .failure(ClaudeError.usageFailed) }
                    if sent, let parsed = try? ClaudeUsageParser.parse(screen.text) { best = parsed }
                }
            }
            let elapsed = timeout - (deadline - ProcessInfo.processInfo.systemUptime)
            // Claude Code may reset the selection to "No, exit" after its first draw, so repeat the arrow key until it sticks.
            if !trustAccepted && trustOnNo && ProcessInfo.processInfo.systemUptime - (trustKeySentAt ?? 0) > 1 {
                _ = write(master, "\u{1b}[B", 3); trustKeySentAt = ProcessInfo.processInfo.systemUptime
            }
            if !trustAccepted, let ready = trustReadyAt, ProcessInfo.processInfo.systemUptime >= ready {
                _ = write(master, "\r", 1); trustAccepted = true; trustReadyAt = nil
                // The dialog can disappear without a full-screen erase.
                screen = ClaudeScreen(); trustVisible = false; trustOnNo = false; lastData = ProcessInfo.processInfo.systemUptime
            }
            if !sent && !trustVisible && elapsed > 3 && (ProcessInfo.processInfo.systemUptime - lastData > 0.5 || elapsed > 10) { _ = write(master, "/usage\r", 7); sent = true }
            // Bars drawn under "Refreshing…" are the saved ones; wait for the request to replace them or add its note.
            if let quota = best, ProcessInfo.processInfo.systemUptime - lastData > 1.2, ClaudeUsageParser.freshness(screen.text) != .refreshing { return finish(quota) }
            if !process.isRunning && (ready <= 0 || hungUp) { break }
            // The exit status can lag behind the hang-up for a moment; wait instead of spinning.
            if hungUp { usleep(50_000) }
        }
        if let quota = best { return finish(quota) }
        return .failure(process.isRunning ? ClaudeError.timeout : ClaudeError.invalidResponse)
    }
}
