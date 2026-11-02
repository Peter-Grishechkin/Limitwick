import Foundation
import Darwin

@main struct QuotaTests {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func json(_ string: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(string.utf8)) as! [String: Any]
        }
        let quota = try QuotaParser.parse(json("""
        {"rateLimits":{"primary":{"windowDurationMins":300,"usedPercent":25,"resetsAt":1700000000},"secondary":{"windowDurationMins":10080,"usedPercent":80,"resetsAt":1700100000}}}
        """))
        check(quota.fiveHour?.remaining == 75 && quota.weekly?.remaining == 20, "both windows")
        check(quota.fiveHour?.reset != nil && quota.weekly?.reset != nil, "reset dates")
        let partial = try QuotaParser.parse(json("""
        {"rateLimits":{"primary":{"windowDurationMins":300,"usedPercent":120}}}
        """))
        check(partial.fiveHour?.remaining == 0 && partial.weekly == nil, "partial and clamped")
        do { _ = try QuotaParser.parse(["other": 1]); fatalError("invalid accepted") } catch QuotaError.invalidResponse { }
        do { _ = try QuotaParser.parse(["rateLimits": [:]]); fatalError("missing accepted") } catch QuotaError.noLimits { }
        let swapped = try QuotaParser.parse(json("""
        {"rateLimits":{"primary":{"windowDurationMins":10080,"usedPercent":1},"secondary":{"windowDurationMins":300,"usedPercent":2},"extra":true}}
        """))
        check(swapped.fiveHour?.remaining == 98 && swapped.weekly?.remaining == 99, "order independent")
        let unknown = try QuotaParser.parse(json("""
        {"rateLimits":{"primary":{"windowDurationMins":90,"usedPercent":20,"resetsAt":-1}}}
        """))
        check(unknown.additional.first?.durationMinutes == 90 && unknown.additional.first?.reset == nil && unknown.weekly == nil, "unknown duration")
        let duplicate = try QuotaParser.parse(json("""
        {"rateLimits":{"primary":{"windowDurationMins":300,"usedPercent":20},"secondary":{"windowDurationMins":300,"usedPercent":21}}}
        """))
        check(duplicate.fiveHour == nil && duplicate.conflictingDurations == [300], "conflicting duplicates")
        let same = try QuotaParser.parse(json("""
        {"rateLimits":{"primary":{"windowDurationMins":300,"usedPercent":20},"secondary":{"windowDurationMins":300,"usedPercent":20}}}
        """))
        check(same.fiveHour?.remaining == 80 && same.conflictingDurations.isEmpty, "identical duplicates")
        for invalid in ["true", "null", "-1", "1.5", "0"] {
            let input = try json("{\"rateLimits\":{\"primary\":{\"windowDurationMins\":\(invalid),\"usedPercent\":20}}}")
            do { _ = try QuotaParser.parse(input); fatalError("invalid duration accepted") } catch QuotaError.noLimits { }
        }
        let invalidUsed = try json("{\"rateLimits\":{\"primary\":{\"windowDurationMins\":300,\"usedPercent\":true}}}")
        do { _ = try QuotaParser.parse(invalidUsed); fatalError("invalid percentage accepted") } catch QuotaError.noLimits { }
        let fake = CommandLine.arguments[1]
        func run(_ scenario: String, timeout: TimeInterval = 2) -> Result<Quota, Error> {
            setenv("FAKE_SCENARIO", scenario, 1)
            return QuotaClient(timeout: timeout).fetch(path: fake)
        }
        if case .success(let q) = run("success") { check(q.fiveHour?.remaining == 75 && q.weekly?.remaining == 20, "protocol success") } else { fatalError("protocol failed") }
        if case .failure(QuotaError.serverError(let message)) = run("auth") { check(message == "Not authenticated", "auth message") } else { fatalError("auth error not reported") }
        if case .failure(QuotaError.timeout) = run("timeout", timeout: 0.2) {} else { fatalError("timeout not reported") }
        if case .failure(QuotaError.launchFailed) = QuotaClient().fetch(path: "/does/not/exist") {} else { fatalError("missing CLI") }
        if case .failure(QuotaError.disconnected) = run("truncated") {} else { fatalError("truncated stream") }
        if case .failure(QuotaError.invalidResponse) = run("large") {} else { fatalError("large stream") }
        if case .failure(QuotaError.timeout) = run("late", timeout: 0.1) {} else { fatalError("late reply must time out") }
        let pidFile = NSTemporaryDirectory() + "codexbar-test-\(UUID().uuidString)"
        setenv("FAKE_PID_FILE", pidFile, 1)
        if case .failure(QuotaError.timeout) = run("timeout", timeout: 0.3) {} else { fatalError("process timeout") }
        let pidText = try String(contentsOfFile: pidFile, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: pidFile)
        unsetenv("FAKE_PID_FILE")
        guard let pid = Int32(pidText) else { fatalError("fake pid") }
        check(kill(pid, 0) == -1 && errno == ESRCH, "timed out process reaped")
        let client = QuotaClient(timeout: 10)
        setenv("FAKE_SCENARIO", "timeout", 1)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            if case .failure(QuotaError.cancelled) = client.fetch(path: fake) {} else { fatalError("cancelled request") }
            done.signal()
        }
        Thread.sleep(forTimeInterval: 0.1)
        client.cancel()
        check(done.wait(timeout: .now() + 2) == .success, "cancel finishes promptly")
        if case .success = run("success") {} else { fatalError("repeat after failure") }
        print("All quota tests passed")
    }
}
