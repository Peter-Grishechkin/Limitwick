import Foundation

func durationName(_ minutes: Int) -> String {
    if minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
    if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
    return "\(minutes)-minute"
}

// Relative time leads; the clock time drops the date when it is today and the year when it is this year.
// No-break spaces keep "in 2h 15m" and the clock time whole, so a narrow panel wraps only after "·".
struct ResetText {
    static func describe(_ date: Date?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date = date else { return "Reset unavailable" }
        let absolute = absoluteText(date, now: now, calendar: calendar, locale: locale)
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset\u{00A0}passed\u{00A0}· \(absolute)" }
        return unbroken("in \(relativeText(seconds))") + "\u{00A0}· \(absolute)"
    }
    /// Two lines for the card: "RST 3d 4h" and the moment of the reset ("4:30 PM", "Mon 4:30 PM", "Nov 8, 10:15 AM").
    static func parts(_ date: Date?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> (relative: String, absolute: String) {
        guard let date = date else { return ("Reset unavailable", "") }
        let absolute = absoluteText(date, now: now, calendar: calendar, locale: locale)
        let seconds = date.timeIntervalSince(now)
        return (seconds > 0 ? "RST \(relativeText(seconds))" : "Reset passed", absolute)
    }
    private static func absoluteText(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        func format(_ template: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }
        let time = format("jmm")
        let day = calendar.isDate(date, inSameDayAs: now) ? nil
            : abs(date.timeIntervalSince(now)) < 6 * 86400 ? format("EEE") + " "
            : format(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMd" : "yMMMd") + ", "
        return unbroken((day ?? "") + time)
    }
    private static func relativeText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
    private static func unbroken(_ text: String) -> String { text.replacingOccurrences(of: " ", with: "\u{00A0}") }
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
            // The old reset date is kept until the notice is delivered: NoticeService drops the delivery mark after a refusal,
            // and the next poll must still see the reset as new.
            var resetPending = false
            if reset, let previous = previous, previous <= time, stamp > previous, delivered[key("reset")] == nil {
                result.append(Notice(kind: "reset", duration: window.durationMinutes, reset: stamp, remaining: remaining))
                delivered[key("reset")] = time
                resetPending = true
            }
            if low, window.remaining <= Double(threshold), delivered[key("low")] == nil {
                result.append(Notice(kind: "low", duration: window.durationMinutes, reset: stamp, remaining: remaining))
                delivered[key("low")] = time
            }
            if !resetPending { resets[period] = stamp }
        }
        return result
    }
}

// The same boundary is used by every quota indicator.
func isLowQuota(_ value: Double?, threshold: Int) -> Bool {
    guard let value = value, value.isFinite else { return false }
    return value <= Double(threshold)
}

func isMajorUpdate(_ availableVersion: String, installedVersion: String) -> Bool {
    guard let available = availableVersion.split(separator: ".").first.flatMap({ Int($0) }),
          let installed = installedVersion.split(separator: ".").first.flatMap({ Int($0) }) else { return false }
    return available > installed
}

// Another registered copy with the same bundle ID can supply stale widgets to the gallery.
func otherAppCopies(_ urls: [URL], running: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [URL] {
    func key(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    var seen: Set<String> = [key(running)]
    return urls.filter { !key($0).contains("/AppTranslocation/") && exists($0) && seen.insert(key($0)).inserted }
}

// Launch Services keeps reporting apps that are already in the Trash.
func isInTrash(_ url: URL) -> Bool {
    url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
}

// Hooks that call a script inside a removed app bundle would fail once the bundle is in the Trash.
func hooksUseBundles(_ config: String, _ bundles: [URL], script: String) -> Bool {
    bundles.contains { config.contains($0.path + "/Contents/Resources/useAnimations/" + script) }
}
