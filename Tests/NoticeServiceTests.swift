import Foundation

@main struct NoticeServiceTests {
    static func main() {
        let suite = testSuite("notice")
        let defaults = UserDefaults(suiteName: suite)!
        defer { removeTestDefaults(suite) }
        let settings = AppSettings(defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = date.addingTimeInterval(3600)
        func quota(_ remaining: Double) -> Quota { Quota(windows: [QuotaWindow(durationMinutes: 300, remaining: remaining, reset: reset)], conflictingDurations: []) }
        var current = quota(10), stale = false
        var authorization: [(Bool) -> Void] = []
        var deliveries: [(Bool) -> Void] = []
        let service = NoticeService(settings: settings, authorize: { authorization.append($0) }, deliver: { _, _, _, done in deliveries.append(done) }, current: { (current, stale) }, now: { date })
        service.process(current); precondition(authorization.isEmpty)
        settings.setEnabled(true, kind: "low", for: "codex")
        service.process(current); service.process(current)
        precondition(authorization.count == 1)
        authorization.removeFirst()(false); precondition(deliveries.isEmpty)
        service.process(current); precondition(authorization.count == 1)
        current = quota(90); authorization.removeFirst()(true); precondition(deliveries.isEmpty)
        current = quota(10); service.process(current)
        settings.setEnabled(false, kind: "low", for: "codex"); authorization.removeFirst()(true); precondition(deliveries.isEmpty)
        settings.setEnabled(true, kind: "low", for: "codex"); service.process(current)
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
        precondition(defaults.dictionary(forKey: "noticeDelivered") != nil && defaults.dictionary(forKey: "noticeDelivered.claude") != nil && defaults.object(forKey: "noticeDelivered.codex") == nil)
        precondition(defaults.dictionary(forKey: "noticeResets") != nil && defaults.object(forKey: "noticeResets.codex") == nil)
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
        let fresh = testSuite("fresh"); let freshDefaults = UserDefaults(suiteName: fresh)!
        defer { removeTestDefaults(fresh) }
        precondition(AppSettings(freshDefaults).activityEnabled(for: "codex") && AppSettings(freshDefaults).activityEnabled(for: "claude"))
        let legacySuite = testSuite("legacy"); let legacy = UserDefaults(suiteName: legacySuite)!
        defer { removeTestDefaults(legacySuite) }
        legacy.set("dots", forKey: "panelTheme"); legacy.set("dark", forKey: "appearanceMode")
        legacy.set(35, forKey: "noticeThreshold"); legacy.set(true, forKey: "noticeLow"); legacy.set(false, forKey: "activityEnabled")
        let migrated = AppSettings(legacy)
        for name in ["codex", "claude"] {
            precondition(migrated.theme(for: name) == "dots" && migrated.appearance(for: name) == "dark")
            precondition(migrated.threshold(for: name) == 35 && migrated.enabled("low", for: name) && !migrated.activityEnabled(for: name))
        }
        migrated.setThreshold(12, for: "claude"); precondition(AppSettings(legacy).threshold(for: "claude") == 12)
        let renamedSuite = testSuite("renamed"); let renamed = UserDefaults(suiteName: renamedSuite)!
        defer { removeTestDefaults(renamedSuite) }
        renamed.set("paper", forKey: "panelTheme.codex")
        AppSettings.importLegacy(["panelTheme.codex": "dots", "providers": "both"], into: renamed)
        AppSettings.importLegacy(["providers": "claude"], into: renamed)
        precondition(AppSettings(renamed).theme(for: "codex") == "paper" && AppSettings(renamed).providers == .both)
        // A reset notice refused by authorization or by the system must be offered again on the next poll, and delivered once.
        let resetSuite = testSuite("reset"); let resetDefaults = UserDefaults(suiteName: resetSuite)!
        defer { removeTestDefaults(resetSuite) }
        let resetSettings = AppSettings(resetDefaults); resetSettings.setEnabled(true, kind: "reset", for: "codex")
        var clock = date, resetQuota = Quota(windows: [QuotaWindow(durationMinutes: 300, remaining: 40, reset: date.addingTimeInterval(60))], conflictingDurations: [])
        var resetAuthorization: [(Bool) -> Void] = [], resetDeliveries: [(Bool) -> Void] = [], resetDelivered = 0
        func resetService() -> NoticeService {
            NoticeService(settings: resetSettings, authorize: { resetAuthorization.append($0) },
                          deliver: { _, notice, _, done in precondition(notice.kind == "reset"); resetDeliveries.append { ok in if ok { resetDelivered += 1 }; done(ok) } },
                          current: { (resetQuota, false) }, now: { clock })
        }
        let resets = resetService()
        resets.process(resetQuota); precondition(resetAuthorization.isEmpty)
        clock = date.addingTimeInterval(120)
        resetQuota = Quota(windows: [QuotaWindow(durationMinutes: 300, remaining: 100, reset: clock.addingTimeInterval(18_000))], conflictingDurations: [])
        resets.process(resetQuota); precondition(resetAuthorization.count == 1)
        resetAuthorization.removeFirst()(false); precondition(resetDeliveries.isEmpty)
        resets.process(resetQuota); precondition(resetAuthorization.count == 1, "Reset notice lost after refused authorization")
        resetAuthorization.removeFirst()(true); precondition(resetDeliveries.count == 1)
        resetDeliveries.removeFirst()(false)
        resets.process(resetQuota); precondition(resetAuthorization.count == 1, "Reset notice lost after failed delivery")
        resetAuthorization.removeFirst()(true); resetDeliveries.removeFirst()(true)
        resets.process(resetQuota); precondition(resetAuthorization.isEmpty && resetDelivered == 1)
        resetService().process(resetQuota); precondition(resetAuthorization.isEmpty && resetDelivered == 1)
        // An unused window reports a new reset date on every poll; the delivered reset must not repeat.
        let slideSuite = testSuite("slide"); let slideDefaults = UserDefaults(suiteName: slideSuite)!
        defer { removeTestDefaults(slideSuite) }
        let slideSettings = AppSettings(slideDefaults); slideSettings.setEnabled(true, kind: "reset", for: "codex")
        var slideClock = date, slideDelivered = 0
        func sliding(_ remaining: Double) -> Quota { Quota(windows: [QuotaWindow(durationMinutes: 300, remaining: remaining, reset: slideClock.addingTimeInterval(slideClock == date ? 60 : 18_000))], conflictingDurations: []) }
        func slideService() -> NoticeService {
            NoticeService(settings: slideSettings, authorize: { $0(true) }, deliver: { _, _, _, done in slideDelivered += 1; done(true) },
                          current: { (sliding(100), false) }, now: { slideClock })
        }
        let slide = slideService()
        slide.process(sliding(40))
        for step in 1...4 {
            slideClock = date.addingTimeInterval(120 + 180 * Double(step - 1))
            slide.process(sliding(100))
        }
        precondition(slideDelivered == 1, "Reset notice repeated on a sliding window: \(slideDelivered)")
        // After a sleep longer than the window, a reset from a full window to a full one stays silent.
        slideClock = slideClock.addingTimeInterval(20_000)
        slideService().process(sliding(100)); precondition(slideDelivered == 1, "Reset notice sent for a full-to-full reset")
        print("Notice service tests passed")
    }
}
