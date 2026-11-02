import Foundation
import Darwin

struct QuotaWindow {
    let remaining: Double
    let reset: Date?
}

struct Quota {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
}

enum QuotaError: Error, LocalizedError {
    case cliNotFound, launchFailed, timeout, serverError(String), invalidResponse, noLimits, disconnected

    var errorDescription: String? {
        switch self {
        case .cliNotFound: return "Codex CLI not found. Install it or add it to your PATH."
        case .launchFailed: return "Could not start Codex CLI."
        case .timeout: return "Codex CLI did not respond in time."
        case .serverError(let message): return "Codex: \(message)"
        case .invalidResponse: return "Unexpected response from Codex CLI. Update the CLI and try again."
        case .noLimits: return "No 5-hour or weekly limits available for this account."
        case .disconnected: return "Codex CLI stopped responding. Check login and network."
        }
    }
}

enum QuotaParser {
    static func parse(_ result: [String: Any]) throws -> Quota {
        guard let limits = result["rateLimits"] as? [String: Any] else { throw QuotaError.invalidResponse }
        var fiveHour: QuotaWindow?
        var weekly: QuotaWindow?
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any],
                  let minutes = window["windowDurationMins"] as? Int,
                  let used = window["usedPercent"] as? Double, used.isFinite else { continue }
            let timestamp = window["resetsAt"] as? Double
            let reset = timestamp.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            let value = QuotaWindow(remaining: max(0, min(100, 100 - used)), reset: reset)
            if minutes == 300 { fiveHour = value }
            if minutes == 10080 { weekly = value }
        }
        guard fiveHour != nil || weekly != nil else { throw QuotaError.noLimits }
        return Quota(fiveHour: fiveHour, weekly: weekly)
    }
}

final class QuotaClient {
    let timeout: TimeInterval
    init(timeout: TimeInterval = 20) { self.timeout = timeout }

    static func findCLI(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let home = NSHomeDirectory()
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.cargo/bin"]
        return paths.map { ($0 as NSString).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetch(path: String) -> Result<Quota, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(QuotaError.launchFailed) }
        let lock = NSLock()
        var timedOut = false
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            lock.lock(); timedOut = true; lock.unlock()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        timer.resume()
        defer {
            timer.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ json: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: json); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        do {
            try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_bar", "version": "1.3.0"]]])
            var buffer = Data()
            while true {
                let data = output.fileHandleForReading.availableData
                if data.isEmpty { break }
                buffer.append(data)
                if buffer.count > 1_048_576 { throw QuotaError.invalidResponse }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
                    guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let id = obj["id"] as? Int else { continue }
                    guard id == 1 || id == 2 else { continue }
                    if let error = obj["error"] as? [String: Any] {
                        throw QuotaError.serverError((error["message"] as? String) ?? "Request failed; check login and network.")
                    }
                    if id == 1 {
                        guard obj["result"] != nil else { throw QuotaError.invalidResponse }
                        try send(["method": "initialized", "params": [:]])
                        try send(["id": 2, "method": "account/rateLimits/read"])
                    } else {
                        guard let result = obj["result"] as? [String: Any] else { throw QuotaError.invalidResponse }
                        return .success(try QuotaParser.parse(result))
                    }
                }
            }
            lock.lock(); let expired = timedOut; lock.unlock()
            return .failure(expired ? QuotaError.timeout : QuotaError.disconnected)
        } catch {
            lock.lock(); let expired = timedOut; lock.unlock()
            return .failure(expired ? QuotaError.timeout : error)
        }
    }
}
