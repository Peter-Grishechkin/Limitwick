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
        precondition(ClaudeUsageParser.freshness(text) == .current)
        precondition(ClaudeUsageParser.freshness(text + "\nShowing last-known usage as of 12m ago (rate limited until 3:15pm)") == .lastKnown(age: 720))
        precondition(ClaudeUsageParser.freshness("Showing last-known usage as of 45s ago (could not refresh)") == .lastKnown(age: 45))
        precondition(ClaudeUsageParser.freshness("Showing last-known usage (could not refresh)") == .lastKnown(age: nil))
        precondition(ClaudeUsageParser.freshness(text + "\nRefreshing\u{2026}") == .refreshing)
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
        // Bars Claude Code kept from an earlier load are previous data, not an update.
        setenv("FAKE_CLAUDE_SCENARIO", "lastknown", 1)
        switch ClaudeClient(timeout: 12).fetch(path: path, directory: directory) {
        case .failure(let error as ClaudeLastKnownUsage): precondition(error.quota.fiveHour?.remaining == 77 && error.age == 720)
        case let other: fatalError("Last-known usage taken as \(other)")
        }
        // Saved bars shown while the request runs must wait for its result: here the note arrives after 2 s of silence.
        setenv("FAKE_CLAUDE_SCENARIO", "slow", 1)
        switch ClaudeClient(timeout: 12).fetch(path: path, directory: directory) {
        case .failure(let error as ClaudeLastKnownUsage): precondition(error.quota.fiveHour?.remaining == 77 && error.age == 120)
        case let other: fatalError("Bars under Refreshing… taken as \(other)")
        }
        setenv("FAKE_CLAUDE_SCENARIO", "exit", 1)
        func cpuSeconds() -> Double {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let started = Date(), startedCPU = cpuSeconds()
        let exited = ClaudeClient(timeout: 30).fetch(path: path, directory: directory)
        let wall = Date().timeIntervalSince(started), cpu = cpuSeconds() - startedCPU
        if case .failure(ClaudeError.invalidResponse) = exited {} else { fatalError("Exited CLI: unexpected result \(exited)") }
        precondition(wall < 2, "Exited CLI kept the client busy for \(wall) s")
        precondition(cpu < 0.5, "Exited CLI cost \(cpu) s of CPU")
        unsetenv("FAKE_CLAUDE_SCENARIO")
        if case .failure(ClaudeError.timeout) = ClaudeClient(timeout: 0.2).fetch(path: path, directory: directory) {} else { fatalError("Timeout not detected") }
        try locatorTests(fake: path, directory: directory)
        print("Claude parser and PTY tests passed")
    }

    static func locatorTests(fake: String, directory: URL) throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("limitwick-locator-\(UUID().uuidString)").path
        defer { try? fm.removeItem(atPath: root) }
        func tool(_ path: String, _ body: String = "#!/bin/sh\n") {
            try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try! body.write(toFile: path, atomically: true, encoding: .utf8)
            try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        var count = 0
        func freshHome() -> String { count += 1; let home = "\(root)/home\(count)"; try! fm.createDirectory(atPath: home, withIntermediateDirectories: true); return home }
        let none: [String: String] = ["PATH": ""]
        func claude(_ home: String, _ env: [String: String] = ["PATH": ""]) -> String? { ClaudeClient.findCLI(environment: env, home: home, system: []) }
        func codex(_ home: String, _ env: [String: String] = ["PATH": ""]) -> String? { QuotaClient.findCLI(environment: env, home: home, system: [], applications: ["\(home)/Applications"]) }

        // One layout per installer or version manager, with an empty PATH as a GUI app might have.
        let layouts: [(String, String)] = [
            ("claude", ".claude/local/claude"), ("claude", ".claude/local/node_modules/.bin/claude"), ("claude", ".bun/bin/claude"),
            ("claude", ".nvm/versions/node/v22.20.0/bin/claude"), ("codex", ".nvm/versions/node/v22.20.0/bin/codex"),
            ("claude", "Library/Application Support/fnm/node-versions/v20.11.0/installation/bin/claude"),
            ("codex", "Library/Application Support/fnm/aliases/default/bin/codex"), ("claude", ".local/share/fnm/node-versions/v22.1.0/installation/bin/claude"),
            ("claude", ".fnm/node-versions/v18.0.0/installation/bin/claude"), ("claude", ".asdf/installs/nodejs/22.3.0/bin/claude"),
            ("codex", ".local/share/mise/installs/node/22.3.0/bin/codex"), ("codex", ".cargo/bin/codex"), ("claude", ".volta/bin/claude"),
        ]
        for (name, relative) in layouts {
            let home = freshHome(); tool("\(home)/\(relative)")
            let found = name == "claude" ? claude(home) : codex(home)
            precondition(found == "\(home)/\(relative)", "\(relative): found \(found ?? "nothing")")
        }
        precondition(claude(freshHome(), none) == nil && codex(freshHome(), none) == nil, "empty home")

        // nvm: the default alias wins over a newer version; without an alias the newest version wins.
        var home = freshHome()
        tool("\(home)/.nvm/versions/node/v20.5.0/bin/claude"); tool("\(home)/.nvm/versions/node/v22.20.0/bin/claude"); tool("\(home)/.nvm/versions/node/v9.0.0/bin/claude")
        precondition(claude(home) == "\(home)/.nvm/versions/node/v22.20.0/bin/claude", "newest nvm version")
        try fm.createDirectory(atPath: "\(home)/.nvm/alias", withIntermediateDirectories: true); try "20\n".write(toFile: "\(home)/.nvm/alias/default", atomically: true, encoding: .utf8)
        precondition(claude(home) == "\(home)/.nvm/versions/node/v20.5.0/bin/claude", "nvm default alias")
        precondition(claude(home, ["PATH": "", "NVM_DIR": "\(home)/missing"]) == nil, "NVM_DIR overrides ~/.nvm")

        // PATH wins over every fixed folder; the migrate-installer copy wins over version managers.
        home = freshHome()
        tool("\(home)/custom/claude"); tool("\(home)/.local/bin/claude"); tool("\(home)/.claude/local/claude"); tool("\(home)/.nvm/versions/node/v22.0.0/bin/claude")
        precondition(claude(home, ["PATH": "\(home)/custom"]) == "\(home)/custom/claude", "PATH first")
        precondition(claude(home) == "\(home)/.local/bin/claude", "fixed folders before ~/.claude/local")
        try fm.removeItem(atPath: "\(home)/.local/bin/claude")
        precondition(claude(home) == "\(home)/.claude/local/claude", "~/.claude/local before nvm")

        // A desktop app's executable must not pass for the CLI on a case-insensitive disk.
        home = freshHome(); tool("\(home)/Claude.app/Contents/MacOS/Claude")
        let appFolder = ["PATH": "\(home)/Claude.app/Contents/MacOS"]
        precondition(claude(home, appFolder) == nil, "app executable taken for CLI")

        // Codex desktop app: only a bundle with the Codex identifier, and only after user-installed CLIs.
        home = freshHome()
        for (app, identifier) in [("ChatGPT.app", "com.openai.codex"), ("Codex.app", "com.example.other")] {
            let contents = "\(home)/Applications/\(app)/Contents"
            try fm.createDirectory(atPath: contents, withIntermediateDirectories: true)
            precondition((["CFBundleIdentifier": identifier] as NSDictionary).write(toFile: "\(contents)/Info.plist", atomically: true))
            tool("\(contents)/Resources/codex-cli/bin/codex")
        }
        let bundled = "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        precondition(codex(home) == bundled, "bundled Codex CLI: \(codex(home) ?? "nothing")")
        tool("\(home)/.nvm/versions/node/v22.0.0/bin/codex")
        precondition(codex(home) == "\(home)/.nvm/versions/node/v22.0.0/bin/codex", "nvm before the bundled CLI")

        // Child environment: the CLI's own folder leads PATH, so `#!/usr/bin/env node` finds node next to it.
        precondition(CLILocator.environment(for: "/x/bin/claude", base: ["PATH": "/usr/bin"])["PATH"] == "/x/bin:/usr/bin")
        precondition(CLILocator.environment(for: "/x/bin/claude", base: ["PATH": "/x/bin:/usr/bin"])["PATH"] == "/x/bin:/usr/bin")
        precondition(CLILocator.environment(for: "/x/bin/claude", base: [:])["PATH"] == "/x/bin:/usr/bin:/bin:/usr/sbin:/sbin")

        // End to end: a node-style CLI in an nvm folder starts with the minimal PATH of a GUI app.
        home = freshHome()
        let bin = "\(home)/.nvm/versions/node/v22.0.0/bin"
        tool("\(bin)/fakenode", "#!/bin/bash\nexec /bin/bash \"$@\"\n")
        let script = try String(contentsOfFile: fake, encoding: .utf8)
        tool("\(bin)/claude", "#!/usr/bin/env fakenode\n" + script.drop { $0 != "\n" }.dropFirst())
        guard let found = claude(home) else { fatalError("nvm claude not found") }
        let savedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1); defer { setenv("PATH", savedPath, 1) }
        switch ClaudeClient(timeout: 12).fetch(path: found, directory: directory) {
        case .success(let parsed): precondition(parsed.fiveHour?.remaining == 77)
        case .failure(let error): fatalError("Node-style CLI did not start with a minimal PATH: \(error)")
        }
    }
}
