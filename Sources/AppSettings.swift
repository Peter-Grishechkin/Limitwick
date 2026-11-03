import Foundation

final class AppSettings {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for provider in ["codex", "claude"] {
            for key in ["panelTheme", "appearanceMode", "activityEnabled", "noticeThreshold", "noticeLow", "noticeReset"] {
                let target = "\(key).\(provider)"
                if defaults.object(forKey: target) == nil, let value = defaults.object(forKey: key) { defaults.set(value, forKey: target) }
            }
        }
    }
    func theme(for provider: String) -> String { defaults.string(forKey: "panelTheme.\(provider)") ?? "" }
    func setTheme(_ value: String, for provider: String) { defaults.set(value, forKey: "panelTheme.\(provider)") }
    func appearance(for provider: String) -> String { defaults.string(forKey: "appearanceMode.\(provider)") ?? "" }
    func setAppearance(_ value: String, for provider: String) { defaults.set(value, forKey: "appearanceMode.\(provider)") }
    func activityEnabled(for provider: String) -> Bool { defaults.object(forKey: "activityEnabled.\(provider)") as? Bool ?? true }
    func setActivityEnabled(_ value: Bool, for provider: String) { defaults.set(value, forKey: "activityEnabled.\(provider)") }
    func threshold(for provider: String) -> Int { let value = defaults.integer(forKey: "noticeThreshold.\(provider)"); return value == 0 ? 20 : min(99, max(1, value)) }
    func setThreshold(_ value: Int, for provider: String) { defaults.set(value, forKey: "noticeThreshold.\(provider)") }
    func enabled(_ kind: String, for provider: String) -> Bool { defaults.bool(forKey: "\(kind == "low" ? "noticeLow" : "noticeReset").\(provider)") }
    func setEnabled(_ value: Bool, kind: String, for provider: String) { defaults.set(value, forKey: "\(kind == "low" ? "noticeLow" : "noticeReset").\(provider)") }
    var theme: String { get { defaults.string(forKey: "panelTheme") ?? "" } set { defaults.set(newValue, forKey: "panelTheme") } }
    var appearance: String { get { defaults.string(forKey: "appearanceMode") ?? "" } set { defaults.set(newValue, forKey: "appearanceMode") } }
    var providers: ProviderSelection {
        get { ProviderSelection(rawValue: defaults.string(forKey: "providers") ?? "codex") ?? .codex }
        set { defaults.set(newValue.rawValue, forKey: "providers") }
    }
    var activityEnabled: Bool { get { defaults.object(forKey: "activityEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "activityEnabled") } }
    var desktopVisible: Bool { get { defaults.bool(forKey: "desktopVisible") } set { defaults.set(newValue, forKey: "desktopVisible") } }
    var threshold: Int {
        get { let value = defaults.integer(forKey: "noticeThreshold.codex"); return value == 0 ? 20 : min(99, max(1, value)) }
        set { defaults.set(newValue, forKey: "noticeThreshold.codex") }
    }
    func enabled(_ kind: String) -> Bool { enabled(kind, for: "codex") }
    func setEnabled(_ value: Bool, key: String) { defaults.set(value, forKey: "\(key).codex") }
    var resets: [String: Double] { get { defaults.dictionary(forKey: "noticeResets") as? [String: Double] ?? [:] } set { defaults.set(newValue, forKey: "noticeResets") } }
    var delivered: [String: Double] { get { defaults.dictionary(forKey: "noticeDelivered") as? [String: Double] ?? [:] } set { defaults.set(newValue, forKey: "noticeDelivered") } }
    func noticeResets(for provider: String) -> [String: Double] { provider == "codex" ? resets : defaults.dictionary(forKey: "noticeResets.\(provider)") as? [String: Double] ?? [:] }
    func noticeDelivered(for provider: String) -> [String: Double] { provider == "codex" ? delivered : defaults.dictionary(forKey: "noticeDelivered.\(provider)") as? [String: Double] ?? [:] }
    func setNoticeResets(_ value: [String: Double], for provider: String) { if provider == "codex" { resets = value } else { defaults.set(value, forKey: "noticeResets.\(provider)") } }
    func setNoticeDelivered(_ value: [String: Double], for provider: String) { if provider == "codex" { delivered = value } else { defaults.set(value, forKey: "noticeDelivered.\(provider)") } }
    var availableUpdate: [String: String]? { get { defaults.dictionary(forKey: "availableUpdate") as? [String: String] } set { defaults.set(newValue, forKey: "availableUpdate") } }
}
