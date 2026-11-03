import Foundation

@main struct ClaudeTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_798_761_600) // 2026-12-31 00:00 UTC
        let text = """
        Current session
        █████ 23% used
        Resets 11:59pm (UTC)
        Current week (all models)
        41% used
        Resets Jan 3, 11:59pm (UTC)
        Current week (Sonnet only)
        95% used
        """
        let quota = try ClaudeUsageParser.parse(text, now: now)
        precondition(quota.fiveHour?.remaining == 77 && quota.weekly?.remaining == 59)
        precondition(quota.namedAdditional.first?.name == "Sonnet only" && quota.namedAdditional.first?.remaining == 5)
        precondition(quota.fiveHour?.reset != nil && quota.weekly?.reset != nil)
        precondition(quota.weekly!.reset! > now)
        let partial = try ClaudeUsageParser.parse("Current week (all models): 20% remaining · resets Jan 3 at 11pm (UTC)", now: now)
        precondition(partial.fiveHour == nil && partial.weekly?.remaining == 20 && partial.weekly?.reset != nil)
        precondition((try? ClaudeUsageParser.parse("Current week (Sonnet only): 10% used")) == nil)
        precondition((try? ClaudeUsageParser.parse("Current session 101% used")) == nil)
        precondition(ClaudeUsageParser.parseReset("Jan 3 11pm (Not/AZone)", now: now) == nil)
        var screen = ClaudeScreen()
        screen.append("Old 0% used\u{1b}[2J\u{1b}[HCurrent session\r\n23% used")
        precondition(!screen.text.contains("Old 0%") && screen.text.contains("23% used"))
        screen.append("\u{1b}[2;1H\u{1b}[2K50% used")
        precondition(!screen.text.contains("23% used") && screen.text.contains("50% used"))
        precondition(ProviderSelection(rawValue: "both")?.includesCodex == true && ProviderSelection.claude.includesCodex == false)
        let path = CommandLine.arguments[1]
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("claude-probe-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        switch ClaudeClient(timeout: 12).fetch(path: path, directory: directory) {
        case .success(let parsed): precondition(parsed.fiveHour?.remaining == 77 && parsed.weekly?.remaining == 59)
        case .failure(let error): fatalError("Fake CLI failed: \(error)")
        }
        setenv("FAKE_CLAUDE_SCENARIO", "trust", 1)
        switch ClaudeClient(timeout: 12).fetch(path: path, directory: directory) {
        case .success(let parsed): precondition(parsed.fiveHour?.remaining == 77)
        case .failure(let error): fatalError("Trust dialog was not accepted: \(error)")
        }
        setenv("FAKE_CLAUDE_SCENARIO", "login", 1)
        if case .failure(ClaudeError.notSignedIn) = ClaudeClient(timeout: 5).fetch(path: path, directory: directory) {} else { fatalError("Login error not detected") }
        setenv("FAKE_CLAUDE_SCENARIO", "error", 1)
        if case .failure(ClaudeError.usageFailed) = ClaudeClient(timeout: 8).fetch(path: path, directory: directory) {} else { fatalError("Usage failure not detected") }
        unsetenv("FAKE_CLAUDE_SCENARIO")
        if case .failure(ClaudeError.timeout) = ClaudeClient(timeout: 0.2).fetch(path: path, directory: directory) {} else { fatalError("Timeout not detected") }
        print("Claude parser and PTY tests passed")
    }
}
