import SwiftUI
import WidgetKit

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct Provider: TimelineProvider {
    let source: WidgetSource

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(date: now, snapshot: WidgetSnapshot(five: 72, week: 53,
            fiveReset: now.addingTimeInterval(7_200), weekReset: now.addingTimeInterval(172_800),
            updated: now, state: .current))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The footer shows the age of the data; three entries keep "Updated N min ago" within five minutes.
        let now = Date(), snapshot = WidgetSnapshot.read(source)
        let entries = (0..<3).map { Entry(date: now.addingTimeInterval(Double($0) * 300), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }

    private func currentEntry() -> Entry {
        Entry(date: Date(), snapshot: WidgetSnapshot.read(source))
    }
}

private struct QuotaWidget: Widget {
    let variant: WidgetVariant

    init() { self.init(.codex, .industrial, .light) }

    init(_ source: WidgetSource, _ theme: PanelTheme, _ appearance: WidgetAppearance) {
        variant = WidgetVariant(source: source, theme: theme.rawValue, appearance: appearance)
    }

    var body: some WidgetConfiguration {
        // WidgetKit on macOS 14 rejects interpolated LocalizedStringKey metadata.
        let description: String = "See your five-hour and weekly \(variant.source.title) limits."
        return StaticConfiguration(kind: variant.kind, provider: Provider(source: variant.source)) { entry in
            QuotaWidgetView(variant: variant, entry: entry)
        }
        .configurationDisplayName(displayName)
        .description(description)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }

    private var displayName: String {
        let title = PanelTheme(stored: variant.theme).title
        return "\(title) · \(variant.source.title) · \(variant.appearance.rawValue.capitalized)"
    }
}

private struct QuotaWidgetView: View {
    let variant: WidgetVariant
    let entry: Entry

    private var theme: PanelTheme { PanelTheme(stored: variant.theme) }
    private var scheme: ColorScheme { variant.appearance == .light ? .light : .dark }

    var body: some View {
        let model = self.model
        QuotaCardFit(model: model, theme: theme, scheme: scheme)
            .environment(\.colorScheme, scheme)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibility)
            .containerBackground(for: .widget) {
                theme.tokens(dark: scheme == .dark).bg.color
            }
    }

    /// The card needs no extra rows: when there is nothing to show, the footer says why.
    private var model: QuotaCardModel {
        let snapshot = entry.snapshot
        var model = QuotaCardModel.make(provider: variant.source.title, five: snapshot?.five, week: snapshot?.week,
                                        fiveReset: snapshot?.fiveReset, weekReset: snapshot?.weekReset,
                                        stale: snapshot?.state == .stale, loading: snapshot?.state == .waiting,
                                        updated: snapshot?.updated, threshold: snapshot?.threshold ?? 20, now: entry.date)
        if snapshot?.hasData != true {
            let note: String
            switch snapshot?.state {
            case .none: note = "Open Limitwick to load limits"
            case .waiting: note = "Waiting for limits"
            default: note = "Limits unavailable · Check CLI sign-in"
            }
            model.footer = "\(variant.source.title) · \(note)"
        }
        return model
    }
}

@main
struct LimitwickWidgets: WidgetBundle {
    var body: some Widget {
        QuotaWidget(.codex, .industrial, .light)
        QuotaWidget(.codex, .industrial, .dark)
        QuotaWidget(.claude, .industrial, .light)
        QuotaWidget(.claude, .industrial, .dark)
        QuotaWidget(.codex, .dots, .light)
        QuotaWidget(.codex, .dots, .dark)
        QuotaWidget(.claude, .dots, .light)
        QuotaWidget(.claude, .dots, .dark)
        QuotaWidget(.codex, .paper, .light)
        QuotaWidget(.codex, .paper, .dark)
        QuotaWidget(.claude, .paper, .light)
        QuotaWidget(.claude, .paper, .dark)
        QuotaWidget(.codex, .terminal, .light)
        QuotaWidget(.codex, .terminal, .dark)
        QuotaWidget(.claude, .terminal, .light)
        QuotaWidget(.claude, .terminal, .dark)
    }
}
