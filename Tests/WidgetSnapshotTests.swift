import Foundation
@main struct SnapshotTests {
    static func main() throws {
        let old = #"{"five":42,"week":81,"stale":true,"threshold":20}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: old)
        precondition(decoded.five == 42 && decoded.week == 81 && decoded.stale && decoded.panelImage == nil && decoded.appVersion == nil)
        let sample = WidgetSnapshot(five: 31, week: 55, fiveReset: Date(timeIntervalSince1970: 100), weekReset: nil, updated: Date(timeIntervalSince1970: 90), stale: false, threshold: 20, panelImage: Data([1, 2, 3]), accessibility: "panel", appVersion: "1.9.0")
        let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(sample))
        precondition(roundTrip.five == 31 && roundTrip.week == 55 && roundTrip.panelImage == Data([1, 2, 3]) && roundTrip.accessibility == "panel" && roundTrip.appVersion == "1.9.0")
        var both = sample
        both.provider = "both"; both.claudeFive = 73; both.claudeWeek = 20
        let restoredBoth = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(both))
        precondition(restoredBoth.provider == "both" && restoredBoth.five == 31 && restoredBoth.claudeFive == 73 && restoredBoth.claudeWeek == 20)
        #if CODEXBAR_DEVELOPMENT
        precondition(WidgetSnapshot.widgetKind == "CodexBarQuotaWideDevelopment" && WidgetSnapshot.group == "group.local.codexbar.development.shared")
        #else
        precondition(WidgetSnapshot.widgetKind == "CodexBarQuotaWideV2" && WidgetSnapshot.group == "group.local.codexbar.shared")
        #endif
        print("Widget snapshot compatibility checks passed")
    }
}
