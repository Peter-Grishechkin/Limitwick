import Foundation

func durationName(_ minutes: Int) -> String {
    if minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
    if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
    return "\(minutes)-minute"
}

struct ResetText {
    static func describe(_ date: Date?, now: Date = Date()) -> String {
        guard let date = date else { return "Reset unavailable" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let absolute = formatter.string(from: date)
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "\(absolute) · reset passed" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        let relative: String
        if days > 0 { relative = "\(days)d \(hours)h" }
        else if hours > 0 { relative = "\(hours)h \(mins)m" }
        else { relative = "\(mins)m" }
        return "\(absolute) · in \(relative)"
    }
}

struct RefreshSchedule {
    private(set) var failures = 0
    mutating func record(success: Bool) -> TimeInterval {
        failures = success ? 0 : min(failures + 1, 3)
        return TimeInterval(180 * (1 << failures))
    }
}

struct Notice: Equatable {
    let kind: String
    let duration: Int
    let reset: TimeInterval
    let remaining: Int
}

// Only reset dates and delivery keys are retained; percentages and account data are not stored.
struct NoticeTracker {
    var resets: [String: Double]
    var delivered: [String: Double]
    mutating func evaluate(_ windows: [QuotaWindow], now: Date, low: Bool, reset: Bool, threshold: Int) -> [Notice] {
        let time = now.timeIntervalSince1970
        delivered = delivered.filter { $0.value > time - 30 * 86400 }
        resets = resets.filter { $0.value > time - 30 * 86400 }
        var result: [Notice] = []
        for window in windows {
            guard let date = window.reset, date > now else { continue }
            let period = String(window.durationMinutes), stamp = date.timeIntervalSince1970
            let previous = resets[period]
            let remaining = Int(window.remaining.rounded())
            func key(_ kind: String) -> String { "\(kind):\(period):\(Int64(stamp))" }
            if reset, let previous = previous, previous <= time, stamp > previous, delivered[key("reset")] == nil {
                result.append(Notice(kind: "reset", duration: window.durationMinutes, reset: stamp, remaining: remaining))
                delivered[key("reset")] = time
            }
            if low, window.remaining <= Double(threshold), delivered[key("low")] == nil {
                result.append(Notice(kind: "low", duration: window.durationMinutes, reset: stamp, remaining: remaining))
                delivered[key("low")] = time
            }
            resets[period] = stamp
        }
        return result
    }
}

// The same boundary is used by every quota indicator.
func isLowQuota(_ value: Double?, threshold: Int) -> Bool {
    guard let value = value, value.isFinite else { return false }
    return value <= Double(threshold)
}
