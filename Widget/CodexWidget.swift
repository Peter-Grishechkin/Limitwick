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
        let entry = currentEntry()
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(900))))
    }

    private func currentEntry() -> Entry {
        Entry(date: Date(), snapshot: WidgetSnapshot.read(source))
    }
}

private struct QuotaWidget: Widget {
    let variant: WidgetVariant

    init() { self.init(.codex, .classic, .light) }

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
        let title = PanelTheme(rawValue: variant.theme)?.title ?? variant.theme
        return "\(title) · \(variant.source.title) · \(variant.appearance.rawValue.capitalized)"
    }
}

private struct QuotaWidgetView: View {
    let variant: WidgetVariant
    let entry: Entry

    var body: some View {
        let appearance = NSAppearance(named: variant.appearance == .light ? .aqua : .darkAqua)
        Group {
            if let image = render(appearance) {
                Image(nsImage: image).resizable()
            } else {
                VStack {
                    Text(variant.source.title)
                    Text("5h: \(percent(entry.snapshot?.five)) · Week: \(percent(entry.snapshot?.week))")
                    Text(status).font(.caption)
                }
            }
        }
        .environment(\.colorScheme, variant.appearance == .light ? .light : .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .containerBackground(for: .widget) {
            Color(variant.appearance == .light ? .white : .black)
        }
    }

    private var status: String {
        switch entry.snapshot?.state {
        case .none: "Open Limitwick to load limits"
        case .waiting: "Waiting for limits"
        case .current: ""
        case .stale: "Previous data"
        case .unavailable: "Limits unavailable · Check CLI sign-in"
        }
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    private func reset(_ date: Date?) -> String {
        date.map { ResetText.describe($0, now: entry.date) } ?? "Reset unavailable"
    }

    private var summary: String {
        "\(variant.source.title). Five hours: \(percent(entry.snapshot?.five)), \(reset(entry.snapshot?.fiveReset)). Week: \(percent(entry.snapshot?.week)), \(reset(entry.snapshot?.weekReset)). \(status)"
    }

    private func render(_ appearance: NSAppearance?) -> NSImage? {
        let view = WidgetThemeView(theme: PanelTheme(rawValue: variant.theme) ?? .classic,
            data: ThemeData(fiveHour: entry.snapshot?.five, weekly: entry.snapshot?.week,
                            fiveReset: reset(entry.snapshot?.fiveReset), weekReset: reset(entry.snapshot?.weekReset),
                            accessibility: summary, warningThreshold: entry.snapshot?.threshold ?? 20,
                            providerName: variant.source.title),
            status: status, appearance: appearance)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
        } else {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

@main
struct LimitwickWidgets: WidgetBundle {
    var body: some Widget {
        QuotaWidget(.codex, .classic, .light)
        QuotaWidget(.codex, .classic, .dark)
        QuotaWidget(.claude, .classic, .light)
        QuotaWidget(.claude, .classic, .dark)
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
        QuotaWidget(.codex, .capsules, .light)
        QuotaWidget(.codex, .capsules, .dark)
        QuotaWidget(.claude, .capsules, .light)
        QuotaWidget(.claude, .capsules, .dark)
        QuotaWidget(.codex, .terminal, .light)
        QuotaWidget(.codex, .terminal, .dark)
        QuotaWidget(.claude, .terminal, .light)
        QuotaWidget(.claude, .terminal, .dark)
    }
}
