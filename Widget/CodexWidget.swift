import SwiftUI
import WidgetKit
import os.log

private let widgetLog = Logger(subsystem: "local.codexbar.app.widget", category: "timeline")

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: WidgetSnapshot(five: 72, week: 53, fiveReset: nil, weekReset: nil, updated: Date(), stale: false, threshold: 20))
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let snapshot = WidgetSnapshot.read()
        widgetLog.info("Snapshot requested; available: \(snapshot != nil, privacy: .public), image: \(snapshot?.panelImage != nil, privacy: .public)")
        completion(Entry(date: Date(), snapshot: snapshot))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.read()
        widgetLog.info("Timeline requested; available: \(snapshot != nil, privacy: .public), image: \(snapshot?.panelImage != nil, privacy: .public)")
        completion(Timeline(entries: [Entry(date: now, snapshot: snapshot)], policy: .after(now.addingTimeInterval(900))))
    }
}

private struct Gauge: View {
    let title: String
    let value: Double?
    let reset: Date?
    let threshold: Int
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 7)
                if let value = value {
                    Circle().trim(from: 0, to: CGFloat(max(0, min(1, value / 100))))
                        .stroke(value <= Double(threshold) ? Color.red : Color.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(title).font(.system(size: 21, weight: .semibold))
            }.frame(width: 58, height: 58)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "—").font(.system(size: 16, weight: .semibold)).monospacedDigit()
            if let reset = reset {
                Text(reset, style: .relative).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            } else {
                Text("Reset unavailable").font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }.frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title == "5" ? "5 hours" : "Week"), \(value.map { "\(Int($0.rounded())) percent remaining" } ?? "unavailable")")
    }
}

private struct WidgetContent: View {
    let entry: Entry
    var body: some View {
        if entry.snapshot?.provider == "both" {
            VStack(alignment: .leading, spacing: 12) {
                dualRow("Codex", entry.snapshot?.five, entry.snapshot?.week)
                dualRow("Claude", entry.snapshot?.claudeFive, entry.snapshot?.claudeWeek)
            }.padding(16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.snapshot?.accessibility ?? "Codex and Claude limits unavailable")
        } else {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Gauge(title: "5", value: entry.snapshot?.five, reset: entry.snapshot?.fiveReset, threshold: entry.snapshot?.threshold ?? 20)
                Gauge(title: "W", value: entry.snapshot?.week, reset: entry.snapshot?.weekReset, threshold: entry.snapshot?.threshold ?? 20)
            }
            if let updated = entry.snapshot?.updated {
                HStack(spacing: 3) {
                    Text(entry.snapshot?.stale == true ? "Previous data ·" : "Updated")
                    Text(updated, style: .relative)
                }.font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            } else {
                Text("Open Limitwick to update").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }.padding(8)
        }
    }
    private func dualRow(_ name: String, _ five: Double?, _ week: Double?) -> some View {
        HStack {
            Text(name).font(.headline).frame(width: 65, alignment: .leading)
            Text("5h: \(five.map { "\(Int($0.rounded()))%" } ?? "—")")
            Spacer()
            Text("Week: \(week.map { "\(Int($0.rounded()))%" } ?? "—")")
        }.font(.system(size: 13)).monospacedDigit()
    }
}

private struct WidgetView: View {
    let entry: Entry
    var panel: some View {
        Group {
            if let data = entry.snapshot?.panelImage, let image = NSImage(data: data) {
                GeometryReader { geometry in
                    Image(nsImage: image).resizable()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .accessibilityLabel(entry.snapshot?.accessibility ?? "Codex usage limits")
                }
            } else if entry.snapshot != nil {
                WidgetContent(entry: entry)
            } else {
                VStack(spacing: 8) {
                    Text("Limitwick").font(.headline)
                    Text("Open Limitwick to load your limits.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }.padding()
            }
        }
    }
    var body: some View {
        if #available(macOS 14.0, *) {
            panel.containerBackground(.background, for: .widget)
        } else {
            panel.background(Color(NSColor.windowBackgroundColor))
        }
    }
}

@main
struct CodexWidget: Widget {
    let kind = WidgetSnapshot.widgetKind
    var body: some WidgetConfiguration {
        configuration.contentMarginsDisabled()
    }
    private var configuration: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in WidgetView(entry: entry) }
            .configurationDisplayName(widgetDisplayName)
            .description("See your five-hour and weekly Codex and Claude limits.")
            .supportedFamilies([.systemMedium])
    }
    private var widgetDisplayName: String {
        #if LIMITWICK_DEVELOPMENT
        return "Limitwick Development"
        #else
        return "Limitwick"
        #endif
    }
}
