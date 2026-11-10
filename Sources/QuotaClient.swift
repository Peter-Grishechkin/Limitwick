import Foundation
import Darwin
import CoreFoundation

struct QuotaWindow: Equatable {
    let durationMinutes: Int
    let remaining: Double
    let reset: Date?
}

struct NamedQuotaWindow: Equatable {
    let name: String
    let remaining: Double
    let reset: Date?
}

struct Quota {
    let windows: [QuotaWindow]
    let conflictingDurations: [Int]
    var namedAdditional: [NamedQuotaWindow] = []
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

// A GUI app inherits a minimal PATH, so CLIs are also looked up where installers and Node version managers put them.
// Only file checks: Settings calls this on the main thread and the Codex listener every 30 s.
enum CLILocator {
    static let systemFolders = ["/opt/homebrew/bin", "/usr/local/bin"]
    /// `preferred` paths are tried before version managers, `fallback` paths after them.
    static func find(_ name: String, environment: [String: String], home: String, system: [String] = systemFolders,
                     preferred: [String] = [], fallback: [String] = []) -> String? {
        let fixed = system + ["\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.cargo/bin", "\(home)/.bun/bin"]
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + fixed
        let candidates = folders.map { ($0 as NSString).appendingPathComponent(name) } + preferred
            + versionManagerFolders(environment: environment, home: home).map { ($0 as NSString).appendingPathComponent(name) } + fallback
        // APFS is case-insensitive: "claude" next to an app's executable would match the desktop app "Claude".
        return candidates.first { !$0.contains(".app/Contents/MacOS/") && FileManager.default.isExecutableFile(atPath: $0) }
    }

    // nvm, fnm, asdf and mise keep node next to globally installed CLIs, the default version first.
    static func versionManagerFolders(environment: [String: String], home: String) -> [String] {
        var folders: [String] = []
        let nvm = environment["NVM_DIR"] ?? "\(home)/.nvm"
        let alias = (try? String(contentsOfFile: "\(nvm)/alias/default", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wanted = alias.hasPrefix("v") ? String(alias.dropFirst()) : alias
        let nvmVersions = versions(in: "\(nvm)/versions/node")
        let isDefault = { (version: String) -> Bool in
            !wanted.isEmpty && wanted.allSatisfy({ $0.isNumber || $0 == "." }) && (version.dropFirst() == wanted || version.dropFirst().hasPrefix(wanted + "."))
        }
        folders += (nvmVersions.filter(isDefault) + nvmVersions.filter { !isDefault($0) }).map { "\(nvm)/versions/node/\($0)/bin" }
        for fnm in [environment["FNM_DIR"], "\(home)/Library/Application Support/fnm", "\(home)/.local/share/fnm", "\(home)/.fnm"].compactMap({ $0 }) {
            folders.append("\(fnm)/aliases/default/bin")
            folders += versions(in: "\(fnm)/node-versions").map { "\(fnm)/node-versions/\($0)/installation/bin" }
        }
        let asdf = environment["ASDF_DATA_DIR"] ?? "\(home)/.asdf"
        folders += versions(in: "\(asdf)/installs/nodejs").map { "\(asdf)/installs/nodejs/\($0)/bin" }
        let mise = environment["MISE_DATA_DIR"] ?? "\(home)/.local/share/mise"
        folders += versions(in: "\(mise)/installs/node").map { "\(mise)/installs/node/\($0)/bin" }
        return folders
    }

    /// Version folder names, newest first.
    private static func versions(in folder: String) -> [String] {
        func parts(_ name: String) -> [Int] { name.drop { !$0.isNumber }.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { !$0.hasPrefix(".") }
        return names.sorted { parts($0).lexicographicallyPrecedes(parts($1)) }.reversed()
    }

    /// Scripts with `#!/usr/bin/env node` need their own folder on PATH; a GUI app's PATH has no node.
    static func environment(for path: String, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let folder = (path as NSString).deletingLastPathComponent
        let inherited = (base["PATH"] ?? "").isEmpty ? "/usr/bin:/bin:/usr/sbin:/sbin" : base["PATH"]!
        environment["PATH"] = inherited.split(separator: ":").first.map(String.init) == folder ? inherited : "\(folder):\(inherited)"
        return environment
    }
}

/// Version sent as `clientInfo.version`; test binaries have no Info.plist, hence the fallback.
func clientVersion(_ info: [String: Any]?) -> String {
    (info?["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "0.0.0"
}

// Each client owns its connection; only process setup and message framing are shared.
private final class AppServerConnection {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    init(path: String) {
        process.executableURL = URL(fileURLWithPath: path)
        process.environment = CLILocator.environment(for: path)
        process.arguments = ["app-server"]
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }
    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func initialize() throws {
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "limitwick", "version": clientVersion(Bundle.main.infoDictionary)]]])
    }
    func close() {
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        process.waitUntilExit()
    }
}

final class QuotaClient {
    let timeout: TimeInterval
    private let lock = NSLock()
    private var active: Process?
    private var cancelled = false
    init(timeout: TimeInterval = 20) { self.timeout = timeout }

    static func findCLI(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory(),
                        system: [String] = CLILocator.systemFolders, applications: [String]? = nil) -> String? {
        // The Codex desktop app (bundle com.openai.codex, named ChatGPT.app or Codex.app) ships the CLI in its resources.
        let bundled = (applications ?? ["/Applications", "\(home)/Applications"]).flatMap { root in
            ["Codex.app", "ChatGPT.app"].map { "\(root)/\($0)" }
        }.filter { Bundle(path: $0)?.bundleIdentifier == "com.openai.codex" }.map { "\($0)/Contents/Resources/codex-cli/bin/codex" }
        return CLILocator.find("codex", environment: environment, home: home, system: system, fallback: bundled)
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process = active, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func fetch(path: String) -> Result<Quota, Error> {
        let connection = AppServerConnection(path: path)
        let process = connection.process, output = connection.output
        lock.lock()
        if cancelled || active != nil { lock.unlock(); return .failure(QuotaError.cancelled) }
        do { try process.run(); active = process; lock.unlock() }
        catch { lock.unlock(); return .failure(QuotaError.launchFailed) }
        defer {
            lock.lock()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            lock.unlock()
            connection.close()
            lock.lock(); active = nil; lock.unlock()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        do {
            try connection.initialize()
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
                        try connection.send(["method": "initialized", "params": [:]])
                        try connection.send(["id": 2, "method": "account/rateLimits/read"])
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
        let connection = AppServerConnection(path: path)
        let child = connection.process, output = connection.output
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); return }
        defer {
            lock.lock()
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            lock.unlock()
            connection.close()
            lock.lock(); process = nil; lock.unlock()
        }
        do {
            try connection.initialize()
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
                        try connection.send(["method": "initialized", "params": [:]])
                    } else if initialized, object["method"] as? String == "account/rateLimits/updated" {
                        onChange()
                    }
                }
            }
        } catch { return }
    }
}
