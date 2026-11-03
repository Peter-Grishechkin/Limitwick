import Foundation

enum WidgetSource: String, CaseIterable {
    case codex, claude

    var title: String { self == .codex ? "Codex" : "Claude" }

    func needsRefresh(menuVisible: Bool, installed: Set<WidgetSource>) -> Bool {
        menuVisible || installed.contains(self)
    }
}

enum WidgetAppearance: String, CaseIterable {
    case light, dark
}

struct WidgetVariant: Equatable {
    static let themes = ["classic", "industrial", "dots", "paper", "capsules", "terminal"]
    #if LIMITWICK_DEVELOPMENT
    private static let prefix = "LimitwickDevelopmentQuota"
    #else
    private static let prefix = "LimitwickQuota"
    #endif

    let source: WidgetSource
    let theme: String
    let appearance: WidgetAppearance

    var kind: String { "\(Self.prefix).\(source.rawValue).\(theme).\(appearance.rawValue)" }

    static var all: [Self] {
        themes.flatMap { theme in
            WidgetSource.allCases.flatMap { source in
                WidgetAppearance.allCases.map { Self(source: source, theme: theme, appearance: $0) }
            }
        }
    }

    static func installed(in kinds: Set<String>) -> [Self] {
        all.filter { kinds.contains($0.kind) }
    }
}

struct WidgetSnapshot: Codable, Equatable {
    enum State: String, Codable {
        case waiting, current, stale, unavailable
    }

    #if LIMITWICK_DEVELOPMENT
    static let group = "group.local.limitwick.development.shared"
    #else
    static let group = "group.local.limitwick.shared"
    #endif

    var five: Double? = nil
    var week: Double? = nil
    var fiveReset: Date? = nil
    var weekReset: Date? = nil
    var updated: Date? = nil
    var state: State = .waiting
    var threshold = 20

    var hasData: Bool { five != nil || week != nil }

    private static func key(_ source: WidgetSource) -> String { "quotaSnapshot.v2.\(source.rawValue)" }

    static func read(_ source: WidgetSource, defaults: UserDefaults? = UserDefaults(suiteName: group)) -> Self? {
        guard let data = defaults?.data(forKey: key(source)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    @discardableResult
    func write(_ source: WidgetSource, defaults: UserDefaults? = UserDefaults(suiteName: group)) -> Bool {
        guard let defaults, self != Self.read(source, defaults: defaults),
              let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.key(source))
        return true
    }

    static func migrate(_ source: WidgetSource, defaults: UserDefaults? = UserDefaults(suiteName: group)) -> Self? {
        guard let data = defaults?.data(forKey: "quotaSnapshot"),
              let old = try? JSONDecoder().decode(LegacySnapshot.self, from: data) else { return nil }
        return old.snapshot(for: source)
    }

    private struct LegacySnapshot: Decodable {
        let provider: String?
        let five: Double?
        let week: Double?
        let fiveReset: Date?
        let weekReset: Date?
        let updated: Date?
        let threshold: Int?
        let claudeFive: Double?
        let claudeWeek: Double?
        let claudeFiveReset: Date?
        let claudeWeekReset: Date?

        func snapshot(for source: WidgetSource) -> WidgetSnapshot? {
            let provider = provider ?? "codex"
            guard provider == source.rawValue || provider == "both" else { return nil }
            let secondary = provider == "both" && source == .claude
            let snapshot = WidgetSnapshot(five: secondary ? claudeFive : five,
                                          week: secondary ? claudeWeek : week,
                                          fiveReset: secondary ? claudeFiveReset : fiveReset,
                                          weekReset: secondary ? claudeWeekReset : weekReset,
                                          updated: secondary ? nil : updated,
                                          state: .stale, threshold: secondary ? 20 : threshold ?? 20)
            return snapshot.hasData ? snapshot : nil
        }
    }
}
