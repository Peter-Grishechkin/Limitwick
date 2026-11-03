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
    static func parseReset(_ raw: String, now: Date) -> Date? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var timeZone = TimeZone.current
        if let zone = match(#"\(([^)]+)\)"#, value) {
            guard let parsed = TimeZone(identifier: zone[1]) else { return nil }
            timeZone = parsed
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

final class ClaudeClient {
    let timeout: TimeInterval
    private let lock = NSLock()
    private var active: Process?
    private var cancelled = false
    init(timeout: TimeInterval = 30) { self.timeout = timeout }
    static func findCLI(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", "\(NSHomeDirectory())/.npm-global/bin", "\(NSHomeDirectory())/.volta/bin"]
        return paths.map { ($0 as NSString).appendingPathComponent("claude") }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func cancel() { lock.lock(); cancelled = true; if let p = active, p.isRunning { kill(p.processIdentifier, SIGKILL) }; lock.unlock() }
    func fetch(path: String, directory: URL? = nil) -> Result<Quota, Error> {
        let folder = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexBar/ClaudeProbe", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return .failure(ClaudeError.launchFailed) }
        if directory == nil && folder.standardizedFileURL != folder.resolvingSymlinksInPath().standardizedFileURL { return .failure(ClaudeError.launchFailed) }
        var master: Int32 = -1, slave: Int32 = -1
        var size = winsize(ws_row: 200, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { return .failure(ClaudeError.launchFailed) }
        let tty = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let process = Process(); process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--strict-mcp-config", "--allowedTools", "", "--settings", #"{"remoteControlAtStartup":false,"disableAllHooks":true}"#]
        process.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment; env["TERM"] = "xterm-256color"; env["NO_COLOR"] = "1"; env["LANG"] = "en_US.UTF-8"; env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env; process.standardInput = tty; process.standardOutput = tty; process.standardError = tty
        lock.lock()
        guard !cancelled && active == nil else { lock.unlock(); close(master); return .failure(ClaudeError.cancelled) }
        do { try process.run(); active = process; lock.unlock() } catch { lock.unlock(); close(master); return .failure(ClaudeError.launchFailed) }
        try? tty.close()
        defer { lock.lock(); if process.isRunning { kill(process.processIdentifier, SIGKILL) }; lock.unlock(); process.waitUntilExit(); close(master); lock.lock(); active = nil; lock.unlock() }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var screen = ClaudeScreen(), sent = false, trustAccepted = false, trustSelectionSent = false, trustVisible = false, lastData = ProcessInfo.processInfo.systemUptime
        var trustReadyAt: TimeInterval?
        var best: Quota?
        var bytes = 0
        while ProcessInfo.processInfo.systemUptime < deadline {
            lock.lock(); let stopped = cancelled; lock.unlock(); if stopped { return .failure(ClaudeError.cancelled) }
            var fd = pollfd(fd: master, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&fd, 1, 100)
            if ready > 0 && fd.revents & Int16(POLLIN) != 0 {
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = read(master, &buffer, buffer.count)
                if count > 0 {
                    bytes += count; if bytes > 2_000_000 { return .failure(ClaudeError.invalidResponse) }
                    screen.append(String(decoding: buffer[0..<count], as: UTF8.self)); lastData = ProcessInfo.processInfo.systemUptime
                    let current = screen.text.lowercased()
                    trustVisible = current.contains("yes, i trust this folder") && current.contains("no, exit")
                    if !trustAccepted && trustVisible {
                        if !trustSelectionSent && current.range(of: #"❯\s*(?:\d+\.\s*)?no, exit"#, options: .regularExpression) != nil {
                            _ = write(master, "\u{1b}[B", 3); trustSelectionSent = true
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
            if !trustAccepted, let ready = trustReadyAt, ProcessInfo.processInfo.systemUptime >= ready {
                _ = write(master, "\r", 1); trustAccepted = true; trustReadyAt = nil
                // The dialog can disappear without a full-screen erase.
                screen = ClaudeScreen(); trustVisible = false; lastData = ProcessInfo.processInfo.systemUptime
            }
            if !sent && !trustVisible && elapsed > 3 && (ProcessInfo.processInfo.systemUptime - lastData > 0.5 || elapsed > 10) { _ = write(master, "/usage\r", 7); sent = true }
            if let quota = best, ProcessInfo.processInfo.systemUptime - lastData > 1.2 { return .success(quota) }
            if !process.isRunning && ready <= 0 { break }
        }
        if let quota = best { return .success(quota) }
        return .failure(process.isRunning ? ClaudeError.timeout : ClaudeError.invalidResponse)
    }
}
