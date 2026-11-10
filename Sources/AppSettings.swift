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
    #if LIMITWICK_DEVELOPMENT
    static let legacyBundleID = "local.codexbar.development"
    #else
    static let legacyBundleID = "local.codexbar.app"
    #endif
    // Limitwick 2.0 replaced the CodexBar bundle IDs; settings saved under the old ID are copied once.
    static func importLegacy(_ legacy: [String: Any]?, into defaults: UserDefaults) {
        guard !defaults.bool(forKey: "legacySettingsImported") else { return }
        for (key, value) in legacy ?? [:] where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: "legacySettingsImported")
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
    var providers: ProviderSelection {
        get { ProviderSelection(rawValue: defaults.string(forKey: "providers") ?? "codex") ?? .codex }
        set { defaults.set(newValue.rawValue, forKey: "providers") }
    }
    var desktopVisible: Bool { get { defaults.bool(forKey: "desktopVisible") } set { defaults.set(newValue, forKey: "desktopVisible") } }
    // Codex notice dates predate the Claude provider and keep their unsuffixed keys; renaming them would repeat delivered notices.
    private func noticeKey(_ base: String, for provider: String) -> String { provider == "codex" ? base : "\(base).\(provider)" }
    func noticeResets(for provider: String) -> [String: Double] { defaults.dictionary(forKey: noticeKey("noticeResets", for: provider)) as? [String: Double] ?? [:] }
    func noticeDelivered(for provider: String) -> [String: Double] { defaults.dictionary(forKey: noticeKey("noticeDelivered", for: provider)) as? [String: Double] ?? [:] }
    func setNoticeResets(_ value: [String: Double], for provider: String) { defaults.set(value, forKey: noticeKey("noticeResets", for: provider)) }
    func setNoticeDelivered(_ value: [String: Double], for provider: String) { defaults.set(value, forKey: noticeKey("noticeDelivered", for: provider)) }
    var availableUpdate: [String: String]? { get { defaults.dictionary(forKey: "availableUpdate") as? [String: String] } set { defaults.set(newValue, forKey: "availableUpdate") } }
}
