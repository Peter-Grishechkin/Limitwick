import Foundation

@main struct NoticeServiceTests {
    static func main() {
        let suite = "codexbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = date.addingTimeInterval(3600)
        func quota(_ remaining: Double) -> Quota { Quota(windows: [QuotaWindow(durationMinutes: 300, remaining: remaining, reset: reset)], conflictingDurations: []) }
        var current = quota(10), stale = false
        var authorization: [(Bool) -> Void] = []
        var deliveries: [(Bool) -> Void] = []
        let service = NoticeService(settings: settings, authorize: { authorization.append($0) }, deliver: { _, _, _, done in deliveries.append(done) }, current: { (current, stale) }, now: { date })
        service.process(current); precondition(authorization.isEmpty)
        settings.setEnabled(true, key: "noticeLow")
        service.process(current); service.process(current)
        precondition(authorization.count == 1)
        authorization.removeFirst()(false); precondition(deliveries.isEmpty)
        service.process(current); precondition(authorization.count == 1)
        current = quota(90); authorization.removeFirst()(true); precondition(deliveries.isEmpty)
        current = quota(10); service.process(current)
        settings.setEnabled(false, key: "noticeLow"); authorization.removeFirst()(true); precondition(deliveries.isEmpty)
        settings.setEnabled(true, key: "noticeLow"); service.process(current)
        stale = true; authorization.removeFirst()(true); precondition(deliveries.isEmpty)
        stale = false; service.process(current); authorization.removeFirst()(true)
        precondition(deliveries.count == 1); deliveries.removeFirst()(false)
        service.process(current); authorization.removeFirst()(true); deliveries.removeFirst()(true)
        service.process(current); precondition(authorization.isEmpty)
        let restored = NoticeService(settings: settings, authorize: { authorization.append($0) }, deliver: { _, _, _, done in deliveries.append(done) }, current: { (current, stale) }, now: { date })
        restored.process(current); precondition(authorization.isEmpty)
        var claudeKeys: [String] = []
        settings.setEnabled(true, kind: "low", for: "claude")
        let claude = NoticeService(settings: settings, authorize: { $0(true) }, deliver: { key, _, _, done in claudeKeys.append(key); done(true) }, current: { (current, stale) }, now: { date }, provider: "claude")
        claude.process(current)
        precondition(claudeKeys.count == 1 && claudeKeys[0].hasPrefix("claude:"))
        claude.process(current); precondition(claudeKeys.count == 1)
        precondition(!settings.noticeDelivered(for: "codex").isEmpty && !settings.noticeDelivered(for: "claude").isEmpty)
        precondition(settings.providers == .codex)
        settings.providers = .both; precondition(AppSettings(defaults).providers == .both)
        settings.setThreshold(10, for: "codex"); settings.setThreshold(45, for: "claude")
        settings.setTheme("paper", for: "codex"); settings.setTheme("terminal", for: "claude")
        settings.setAppearance("light", for: "codex"); settings.setAppearance("dark", for: "claude")
        settings.setEnabled(false, kind: "low", for: "codex")
        precondition(settings.enabled("low", for: "claude") && !settings.enabled("low", for: "codex"))
        precondition(settings.threshold(for: "codex") == 10 && settings.threshold(for: "claude") == 45)
        precondition(settings.theme(for: "codex") == "paper" && settings.theme(for: "claude") == "terminal")
        precondition(settings.appearance(for: "codex") == "light" && settings.appearance(for: "claude") == "dark")
        let legacySuite = "legacy-\(UUID().uuidString)"; let legacy = UserDefaults(suiteName: legacySuite)!
        defer { legacy.removePersistentDomain(forName: legacySuite) }
        legacy.set("dots", forKey: "panelTheme"); legacy.set("dark", forKey: "appearanceMode")
        legacy.set(35, forKey: "noticeThreshold"); legacy.set(true, forKey: "noticeLow"); legacy.set(false, forKey: "activityEnabled")
        let migrated = AppSettings(legacy)
        for name in ["codex", "claude"] {
            precondition(migrated.theme(for: name) == "dots" && migrated.appearance(for: name) == "dark")
            precondition(migrated.threshold(for: name) == 35 && migrated.enabled("low", for: name) && !migrated.activityEnabled(for: name))
        }
        migrated.setThreshold(12, for: "claude"); precondition(AppSettings(legacy).threshold(for: "claude") == 12)
        print("Notice service tests passed")
    }
}
