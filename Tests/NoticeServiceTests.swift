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
        print("Notice service tests passed")
    }
}
