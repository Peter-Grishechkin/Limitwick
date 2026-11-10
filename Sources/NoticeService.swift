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
    private let provider: String

    init(settings: AppSettings, authorize: @escaping (@escaping (Bool) -> Void) -> Void,
         deliver: @escaping (String, Notice, QuotaWindow, @escaping (Bool) -> Void) -> Void,
         current: @escaping () -> (Quota?, Bool), now: @escaping () -> Date = Date.init, provider: String = "codex") {
        self.settings = settings; self.authorize = authorize; self.deliver = deliver
        self.current = current; self.now = now
        self.provider = provider
        tracker = NoticeTracker(resets: settings.noticeResets(for: provider), delivered: settings.noticeDelivered(for: provider))
    }

    func process(_ quota: Quota) {
        let candidates = tracker.evaluate(quota.windows, now: now(), low: settings.enabled("low", for: provider), reset: settings.enabled("reset", for: provider), threshold: settings.threshold(for: provider))
        settings.setNoticeResets(tracker.resets, for: provider)
        for notice in candidates {
            let key = "\(notice.kind):\(notice.duration):\(Int64(notice.reset))"
            tracker.delivered.removeValue(forKey: key)
            guard pending.insert(key).inserted else { continue }
            authorize { [weak self] allowed in
                guard let self = self else { return }
                let (quota, stale) = self.current()
                guard allowed, self.settings.enabled(notice.kind, for: self.provider), !stale,
                      let window = quota?.windows.first(where: { $0.durationMinutes == notice.duration }),
                      window.reset?.timeIntervalSince1970 == notice.reset, notice.reset > self.now().timeIntervalSince1970,
                      notice.kind != "low" || window.remaining <= Double(self.settings.threshold(for: self.provider)) else {
                    self.pending.remove(key); return
                }
                self.deliver("\(self.provider):\(key)", notice, window) { [weak self] success in
                    guard let self = self else { return }
                    self.pending.remove(key)
                    guard success else { return }
                    self.tracker.delivered[key] = self.now().timeIntervalSince1970
                    self.tracker.confirm(notice)
                    self.settings.setNoticeResets(self.tracker.resets, for: self.provider)
                    self.settings.setNoticeDelivered(self.tracker.delivered, for: self.provider)
                }
            }
        }
        settings.setNoticeDelivered(tracker.delivered, for: provider)
    }
}
