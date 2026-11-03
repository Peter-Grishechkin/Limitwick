import Foundation

struct WidgetSnapshot: Codable {
    static let widgetKind = "CodexBarQuotaWideV2"
    static let group = "group.local.codexbar.shared"
    static let key = "quotaSnapshot"
    var five: Double?
    var week: Double?
    var fiveReset: Date?
    var weekReset: Date?
    var updated: Date?
    var stale: Bool
    var threshold: Int
    var panelImage: Data? = nil
    var accessibility: String? = nil

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
    }
}
