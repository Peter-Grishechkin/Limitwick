import Foundation
@main struct SnapshotTests {
    static func main() throws {
        let old = #"{"five":42,"week":81,"stale":true,"threshold":20}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: old)
        precondition(decoded.five == 42 && decoded.week == 81 && decoded.stale && decoded.panelImage == nil)
        let sample = WidgetSnapshot(five: 31, week: 55, fiveReset: Date(timeIntervalSince1970: 100), weekReset: nil, updated: Date(timeIntervalSince1970: 90), stale: false, threshold: 20, panelImage: Data([1, 2, 3]), accessibility: "panel")
        let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(sample))
        precondition(roundTrip.five == 31 && roundTrip.week == 55 && roundTrip.panelImage == Data([1, 2, 3]) && roundTrip.accessibility == "panel")
        precondition(WidgetSnapshot.widgetKind != "CodexBarQuota")
        print("Widget snapshot compatibility checks passed")
    }
}
