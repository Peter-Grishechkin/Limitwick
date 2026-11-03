import Foundation

// Callbacks are delivered on the main queue, like the application state they inspect.
final class NoticeService {
    private let settings: AppSettings
    private let authorize: (@escaping (Bool) -> Void) -> Void
    private let deliver: (String, Notice, QuotaWindow, @escaping (Bool) -> Void) -> Void
    private let current: () -> (Quota?, Bool)
    private let now: () -> Date
    private var tracker: NoticeTracker
    private var pending = Set<String>()

    init(settings: AppSettings, authorize: @escaping (@escaping (Bool) -> Void) -> Void,
         deliver: @escaping (String, Notice, QuotaWindow, @escaping (Bool) -> Void) -> Void,
         current: @escaping () -> (Quota?, Bool), now: @escaping () -> Date = Date.init) {
        self.settings = settings; self.authorize = authorize; self.deliver = deliver
        self.current = current; self.now = now
        tracker = NoticeTracker(resets: settings.resets, delivered: settings.delivered)
    }

    func process(_ quota: Quota) {
        let candidates = tracker.evaluate(quota.windows, now: now(), low: settings.enabled("low"), reset: settings.enabled("reset"), threshold: settings.threshold)
        settings.resets = tracker.resets
        for notice in candidates {
            let key = "\(notice.kind):\(notice.duration):\(Int64(notice.reset))"
            tracker.delivered.removeValue(forKey: key)
            guard pending.insert(key).inserted else { continue }
            authorize { [weak self] allowed in
                guard let self = self else { return }
                let (quota, stale) = self.current()
                guard allowed, self.settings.enabled(notice.kind), !stale,
                      let window = quota?.windows.first(where: { $0.durationMinutes == notice.duration }),
                      window.reset?.timeIntervalSince1970 == notice.reset, notice.reset > self.now().timeIntervalSince1970,
                      notice.kind != "low" || window.remaining <= Double(self.settings.threshold) else {
                    self.pending.remove(key); return
                }
                self.deliver(key, notice, window) { [weak self] success in
                    guard let self = self else { return }
                    self.pending.remove(key)
                    guard success else { return }
                    self.tracker.delivered[key] = self.now().timeIntervalSince1970
                    self.settings.delivered = self.tracker.delivered
                }
            }
        }
        settings.delivered = tracker.delivered
    }
}
