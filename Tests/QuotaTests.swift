import Foundation

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
        let fake = CommandLine.arguments[1]
        func run(_ scenario: String, timeout: TimeInterval = 2) -> Result<Quota, Error> {
            setenv("FAKE_SCENARIO", scenario, 1)
            return QuotaClient(timeout: timeout).fetch(path: fake)
        }
        if case .success(let q) = run("success") { check(q.fiveHour?.remaining == 75 && q.weekly?.remaining == 20, "protocol success") } else { fatalError("protocol failed") }
        if case .failure(QuotaError.serverError(let message)) = run("auth") { check(message == "Not authenticated", "auth message") } else { fatalError("auth error not reported") }
        if case .failure(QuotaError.timeout) = run("timeout", timeout: 0.2) {} else { fatalError("timeout not reported") }
        if case .failure(QuotaError.launchFailed) = QuotaClient().fetch(path: "/does/not/exist") {} else { fatalError("missing CLI") }
        print("All quota tests passed")
    }
}
