import Foundation

@main struct SnapshotTests {
    static func main() throws {
        let suite = "Limitwick.WidgetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let variants = WidgetVariant.all
        precondition(variants.count == 24 && Set(variants.map(\.kind)).count == 24)
        precondition(PanelTheme.allCases.map(\.rawValue) == WidgetVariant.themes)
        let registrations = try String(contentsOfFile: "Widget/LimitwickWidget.swift", encoding: .utf8)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("QuotaWidget(.") }
        precondition(registrations == variants.map {
            "QuotaWidget(.\($0.source.rawValue), .\($0.theme), .\($0.appearance.rawValue))"
        })
        #if LIMITWICK_DEVELOPMENT
        precondition(variants.allSatisfy { $0.kind.hasPrefix("LimitwickDevelopmentQuota.") })
        precondition(WidgetSnapshot.group == "group.local.limitwick.development.shared")
        #else
        precondition(variants.allSatisfy { $0.kind.hasPrefix("LimitwickQuota.") })
        precondition(WidgetSnapshot.group == "group.local.limitwick.shared")
        #endif

        let installed = WidgetVariant.installed(in: Set(variants.filter { $0.source == .claude }.prefix(2).map(\.kind))
            .union(["CodexBarQuotaWideV2", "unknown"]))
        let sources = Set(installed.map(\.source))
        precondition(installed.count == 2 && sources == [.claude])
        precondition(WidgetSource.claude.needsRefresh(menuVisible: false, installed: sources))
        precondition(!WidgetSource.codex.needsRefresh(menuVisible: false, installed: sources))
        precondition(WidgetSource.codex.needsRefresh(menuVisible: true, installed: sources))

        defaults.set(Data(#"{"five":42,"week":81,"updated":90,"stale":true,"threshold":17}"#.utf8), forKey: "quotaSnapshot")
        let codex = WidgetSnapshot.migrate(.codex, defaults: defaults)!
        precondition(codex.five == 42 && codex.week == 81 && codex.state == .stale && codex.threshold == 17)
        precondition(codex.updated == Date(timeIntervalSinceReferenceDate: 90))
        precondition(WidgetSnapshot.migrate(.claude, defaults: defaults) == nil)

        defaults.set(Data(#"{"provider":"both","five":42,"claudeFive":73,"claudeWeek":20,"claudeFiveReset":120,"updated":90,"threshold":17}"#.utf8), forKey: "quotaSnapshot")
        let claude = WidgetSnapshot.migrate(.claude, defaults: defaults)!
        precondition(claude.five == 73 && claude.week == 20 && claude.state == .stale && claude.updated == nil)
        precondition(claude.fiveReset == Date(timeIntervalSinceReferenceDate: 120))
        precondition(codex.write(.codex, defaults: defaults))
        precondition(claude.write(.claude, defaults: defaults))
        precondition(!claude.write(.claude, defaults: defaults))
        precondition(WidgetSnapshot.read(.codex, defaults: defaults) == codex)
        precondition(WidgetSnapshot.read(.claude, defaults: defaults) == claude)

        defaults.set(Data(#"{"provider":"claude","five":56,"threshold":11}"#.utf8), forKey: "quotaSnapshot")
        precondition(WidgetSnapshot.migrate(.claude, defaults: defaults)?.five == 56)
        precondition(WidgetSnapshot.migrate(.codex, defaults: defaults) == nil)
        print("Widget variants, source selection and snapshot compatibility checks passed")
    }
}
