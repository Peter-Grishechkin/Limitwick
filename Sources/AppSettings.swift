import Foundation

final class AppSettings {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    var theme: String { get { defaults.string(forKey: "panelTheme") ?? "" } set { defaults.set(newValue, forKey: "panelTheme") } }
    var appearance: String { get { defaults.string(forKey: "appearanceMode") ?? "" } set { defaults.set(newValue, forKey: "appearanceMode") } }
    var activityEnabled: Bool { get { defaults.object(forKey: "activityEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "activityEnabled") } }
    var desktopVisible: Bool { get { defaults.bool(forKey: "desktopVisible") } set { defaults.set(newValue, forKey: "desktopVisible") } }
    var threshold: Int {
        get { let value = defaults.integer(forKey: "noticeThreshold"); return value == 0 ? 20 : min(99, max(1, value)) }
        set { defaults.set(newValue, forKey: "noticeThreshold") }
    }
    func enabled(_ kind: String) -> Bool { defaults.bool(forKey: kind == "low" ? "noticeLow" : "noticeReset") }
    func setEnabled(_ value: Bool, key: String) { defaults.set(value, forKey: key) }
    var resets: [String: Double] { get { defaults.dictionary(forKey: "noticeResets") as? [String: Double] ?? [:] } set { defaults.set(newValue, forKey: "noticeResets") } }
    var delivered: [String: Double] { get { defaults.dictionary(forKey: "noticeDelivered") as? [String: Double] ?? [:] } set { defaults.set(newValue, forKey: "noticeDelivered") } }
    var availableUpdate: [String: String]? { get { defaults.dictionary(forKey: "availableUpdate") as? [String: String] } set { defaults.set(newValue, forKey: "availableUpdate") } }
}
