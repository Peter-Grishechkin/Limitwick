import Foundation
import Darwin
import CoreFoundation

struct QuotaWindow: Equatable {
    let durationMinutes: Int
    let remaining: Double
    let reset: Date?
}

struct Quota {
    let windows: [QuotaWindow]
    let conflictingDurations: [Int]
    var fiveHour: QuotaWindow? { windows.first { $0.durationMinutes == 300 } }
    var weekly: QuotaWindow? { windows.first { $0.durationMinutes == 10080 } }
    var additional: [QuotaWindow] { windows.filter { $0.durationMinutes != 300 && $0.durationMinutes != 10080 } }
}

enum QuotaError: Error, LocalizedError {
    case cliNotFound, launchFailed, timeout, serverError(String), invalidResponse, noLimits, disconnected, cancelled
    var errorDescription: String? {
        switch self {
        case .cliNotFound: return "Codex CLI not found. Install it or add it to your PATH."
        case .launchFailed: return "Could not start Codex CLI. Check its installation and permissions."
        case .timeout: return "Codex CLI did not respond in time. Check your connection and try Refresh."
        case .serverError(let message): return message == "Not authenticated" ? "Codex is not signed in. Run codex login in Terminal." : "Codex request failed. Check login and network, then try Refresh."
        case .invalidResponse: return "Unexpected response from Codex CLI. Update the CLI and try again."
        case .noLimits: return "No usable limits available for this account."
        case .disconnected: return "Codex CLI stopped responding. Check login and network."
        case .cancelled: return "Update cancelled."
        }
    }
}

enum QuotaParser {
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func parse(_ result: [String: Any]) throws -> Quota {
        guard let limits = result["rateLimits"] as? [String: Any] else { throw QuotaError.invalidResponse }
        var found: [Int: QuotaWindow] = [:]
        var conflicts = Set<Int>()
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any],
                  let duration = number(window["windowDurationMins"]), duration > 0,
                  duration.rounded(.towardZero) == duration, duration <= Double(Int32.max),
                  let used = number(window["usedPercent"]) else { continue }
            let minutes = Int(duration)
            let timestamp = number(window["resetsAt"])
            let reset = timestamp.flatMap { $0 > 0 && $0 <= 253402300799 ? Date(timeIntervalSince1970: $0) : nil }
            let value = QuotaWindow(durationMinutes: minutes, remaining: max(0, min(100, 100 - used)), reset: reset)
            if let previous = found[minutes], previous != value { conflicts.insert(minutes) }
            else if found[minutes] == nil { found[minutes] = value }
        }
        for duration in conflicts { found.removeValue(forKey: duration) }
        guard !found.isEmpty || !conflicts.isEmpty else { throw QuotaError.noLimits }
        return Quota(windows: found.values.sorted { $0.durationMinutes < $1.durationMinutes }, conflictingDurations: conflicts.sorted())
    }
}

final class QuotaClient {
    let timeout: TimeInterval
    private let lock = NSLock()
    private var active: Process?
    private var cancelled = false
    init(timeout: TimeInterval = 20) { self.timeout = timeout }

    static func findCLI(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let home = NSHomeDirectory()
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.cargo/bin"]
        return paths.map { ($0 as NSString).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process = active, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func fetch(path: String) -> Result<Quota, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled || active != nil { lock.unlock(); return .failure(QuotaError.cancelled) }
        do { try process.run(); active = process; lock.unlock() }
        catch { lock.unlock(); return .failure(QuotaError.launchFailed) }
        defer {
            lock.lock()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            lock.unlock()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            process.waitUntilExit()
            lock.lock(); active = nil; lock.unlock()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        func send(_ json: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: json); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        do {
            try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_bar", "version": "1.7.0"]]])
            var buffer = Data()
            var totalBytes = 0
            var initialized = false
            while true {
                lock.lock(); let stopped = cancelled; lock.unlock()
                if stopped { throw QuotaError.cancelled }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                if remaining <= 0 { throw QuotaError.timeout }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                let ready = poll(&descriptor, 1, Int32(min(100, max(1, remaining * 1000))))
                if ready < 0 { if errno == EINTR { continue }; throw QuotaError.disconnected }
                if ready == 0 { continue }
                let data = output.fileHandleForReading.availableData
                if data.isEmpty { throw QuotaError.disconnected }
                totalBytes += data.count
                buffer.append(data)
                if totalBytes > 1_048_576 { throw QuotaError.invalidResponse }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
                    guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let id = obj["id"] as? Int else { continue }
                    guard id == (initialized ? 2 : 1) else { continue }
                    if let error = obj["error"] as? [String: Any] {
                        let message = (error["message"] as? String) == "Not authenticated" ? "Not authenticated" : "Request failed; check login and network."
                        throw QuotaError.serverError(message)
                    }
                    if !initialized {
                        guard obj["result"] != nil else { throw QuotaError.invalidResponse }
                        initialized = true
                        try send(["method": "initialized", "params": [:]])
                        try send(["id": 2, "method": "account/rateLimits/read"])
                    } else {
                        guard let result = obj["result"] as? [String: Any] else { throw QuotaError.invalidResponse }
                        guard ProcessInfo.processInfo.systemUptime < deadline else { throw QuotaError.timeout }
                        return .success(try QuotaParser.parse(result))
                    }
                }
            }
        } catch {
            lock.lock(); let stopped = cancelled; lock.unlock()
            if stopped { return .failure(QuotaError.cancelled) }
            if ProcessInfo.processInfo.systemUptime >= deadline { return .failure(QuotaError.timeout) }
            return .failure(error)
        }
    }
}

// A separate connection listens for changes; the existing client remains the
// authoritative snapshot and fallback for changes outside this connection.
final class QuotaListener {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if let process = process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    func run(findPath: () -> String?, onChange: @escaping () -> Void) {
        while !isStopped {
            if let path = findPath() { listen(path: path, onChange: onChange) }
            // Retry without a tight loop when CLI is missing or the server exits.
            for _ in 0..<30 {
                if isStopped { return }
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    private func listen(path: String, onChange: () -> Void) {
        let child = Process(), input = Pipe(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = ["app-server"]
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); return }
        defer {
            lock.lock()
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            lock.unlock()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            child.waitUntilExit()
            lock.lock(); process = nil; lock.unlock()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        do {
            try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_bar", "version": "1.7.0"]]])
            var buffer = Data()
            var initialized = false
            let deadline = ProcessInfo.processInfo.systemUptime + 20
            while !isStopped {
                if !initialized && ProcessInfo.processInfo.systemUptime >= deadline { return }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                let ready = poll(&descriptor, 1, 200)
                if ready < 0 { if errno == EINTR { continue }; return }
                if ready == 0 { continue }
                let data = output.fileHandleForReading.availableData
                if data.isEmpty { return }
                buffer.append(data)
                if buffer.count > 1_048_576 { return }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
                    guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
                    if !initialized, let id = object["id"] as? Int, id == 1 {
                        guard object["result"] != nil, object["error"] == nil else { return }
                        initialized = true
                        try send(["method": "initialized", "params": [:]])
                    } else if initialized, object["method"] as? String == "account/rateLimits/updated" {
                        onChange()
                    }
                }
            }
        } catch { return }
    }
}
