import SwiftUI
import AppKit
import CoreText

// One card per provider, drawn here and nowhere else: the menu bar panel, the Picture-in-Picture window and
// the widgets all show this view. Coordinates are points on a 340-wide card (170 high, Paper 182).

// MARK: - Model

struct QuotaCardModel: Equatable {
    struct Period: Equatable {
        var remaining: Double?
        var resetLine: String   // "RST 3d 4h"
        var resetTime: String   // "Nov 8, 10:15 AM"
    }
    var provider: String
    var five: Period
    var week: Period
    var stale: Bool
    var threshold: Int
    var footer: String
    var accessibility: String

    static func age(_ date: Date?, now: Date = Date()) -> String {
        guard let date = date else { return "No data yet" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return minutes == 0 ? "Updated just now" : "Updated \(minutes) min ago"
    }

    /// "Codex · Updated 2 min ago"; with old values "Codex · Previous data · Updated 12 min ago".
    static func footer(provider: String, hasData: Bool, stale: Bool, loading: Bool, updated: Date?, now: Date = Date()) -> String {
        var parts = [provider]
        if !hasData && loading { parts.append("Loading…") }
        else {
            if stale && hasData { parts.append("Previous data") }
            parts.append(age(updated, now: now))
        }
        return parts.joined(separator: " · ")
    }

    static func make(provider: String, five: Double?, week: Double?, fiveReset: Date?, weekReset: Date?,
                     stale: Bool, loading: Bool = false, updated: Date?, threshold: Int, now: Date = Date(), locale: Locale = .current) -> QuotaCardModel {
        func period(_ value: Double?, _ reset: Date?) -> Period {
            let parts = ResetText.parts(reset, now: now, locale: locale)
            return Period(remaining: value, resetLine: parts.relative, resetTime: parts.absolute)
        }
        let footer = footer(provider: provider, hasData: five != nil || week != nil, stale: stale, loading: loading, updated: updated, now: now)
        func spoken(_ name: String, _ value: Double?, _ reset: Date?) -> String {
            guard let value = value else { return "\(name): unavailable" }
            return "\(name): \(Int(value.rounded())) percent remaining, \(ResetText.describe(reset, now: now))"
        }
        let summary = "\(provider). \(spoken("5 hours", five, fiveReset)). \(spoken("Week", week, weekReset)). \(footer)"
        return QuotaCardModel(provider: provider, five: period(five, fiveReset), week: period(week, weekReset),
                              stale: stale, threshold: threshold, footer: footer, accessibility: summary)
    }

    static func make(provider: String, quota: Quota?, stale: Bool, loading: Bool, updated: Date?, threshold: Int, now: Date = Date()) -> QuotaCardModel {
        make(provider: provider, five: quota?.fiveHour?.remaining, week: quota?.weekly?.remaining,
             fiveReset: quota?.fiveHour?.reset, weekReset: quota?.weekly?.reset,
             stale: stale, loading: loading, updated: updated, threshold: threshold, now: now)
    }
}

// MARK: - Fonts

enum CardFonts {
    /// Terminal is set in VT323 (SIL OFL, bundled in Resources/fonts). Without it the card falls back to the system monospaced font.
    static let terminalAvailable: Bool = {
        var urls: [URL] = []
        if let bundled = Bundle.main.url(forResource: "VT323-Regular", withExtension: "ttf") { urls.append(bundled) }
        if let path = ProcessInfo.processInfo.environment["LIMITWICK_FONT_PATH"] { urls.append(URL(fileURLWithPath: path)) }
        urls.append(URL(fileURLWithPath: "Resources/fonts/VT323-Regular.ttf"))
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            break
        }
        return NSFont(name: "VT323", size: 12) != nil
    }()
    static func terminal(_ size: CGFloat) -> Font {
        terminalAvailable ? .custom("VT323", size: size) : .system(size: size - 2, weight: .regular, design: .monospaced)
    }
    /// VT323 has no Cyrillic: dates in other locales ("Сб 20:52") use the system monospaced font instead of a mismatched fallback.
    static func terminal(_ size: CGFloat, for text: String) -> Font {
        text.unicodeScalars.allSatisfy { $0.value < 0x250 } ? terminal(size) : .system(size: size - 5, weight: .regular, design: .monospaced)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

// MARK: - Card

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

private extension View {
    /// Places a view in a box of the given size at card coordinates; the content is centered vertically in its box.
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ alignment: Alignment = .leading) -> some View {
        frame(width: w, height: h, alignment: alignment).offset(x: x, y: y)
    }
    func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: RGB, radius: CGFloat = 0, opacity: Double = 1) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color.color.opacity(opacity)).frame(width: w, height: h).offset(x: x, y: y)
    }
}

struct QuotaCardView: View {
    let model: QuotaCardModel
    let theme: PanelTheme
    var scheme: ColorScheme? = nil
    /// Inactive desktop widget: macOS removes the container background and maps luminance to opacity,
    /// so the card draws no background of its own and uses light ink (dark tokens) whatever the appearance.
    var vibrant = false
    @Environment(\.colorScheme) private var systemScheme

    private var dark: Bool { vibrant || (scheme ?? systemScheme) == .dark }
    private var base: CardTokens { theme.tokens(dark: dark) }
    private var ink: CardTokens { model.stale ? base.receded() : base }
    private var footerInk: RGB { model.stale ? base.secondary.mixed(with: base.bg, 0.2) : base.secondary }

    private func periods() -> [(Int, QuotaCardModel.Period)] { [(0, model.five), (1, model.week)] }
    private func low(_ p: QuotaCardModel.Period) -> Bool { isLowQuota(p.remaining, threshold: model.threshold) }
    private func percent(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
    private func fraction(_ v: Double?) -> CGFloat { CGFloat(max(0, min(1, (v ?? 0) / 100))) }
    /// Previous data: bar fills are already receded, and the mockup dims them once more.
    private var fillOpacity: Double { model.stale ? 0.4 : 1 }
    private func fillColor(_ i: Int, _ p: QuotaCardModel.Period) -> RGB { low(p) ? ink.warning : (i == 0 ? ink.accent : ink.second) }
    private func digitColor(_ p: QuotaCardModel.Period, normal: RGB) -> RGB { low(p) ? ink.warning : normal }

    private func reset(_ p: QuotaCardModel.Period, font: Font, first: RGB, second: RGB, alignment: HorizontalAlignment, size: CGFloat) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(p.resetLine).font(font).foregroundColor(first.color).lineLimit(1).minimumScaleFactor(0.7)
            if !p.resetTime.isEmpty { Text(p.resetTime).font(font).foregroundColor(second.color).lineLimit(1).minimumScaleFactor(0.7) }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !vibrant { Rectangle().fill(base.bg.color) }
            switch theme {
            case .industrial: industrial
            case .dots: dots
            case .paper: paper
            case .terminal: terminal
            }
        }
        .frame(width: 340, height: theme.cardHeight, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibility)
    }

    // MARK: Industrial

    private var industrial: some View {
        ZStack(alignment: .topLeading) {
            ForEach(periods(), id: \.0) { i, p in
                let x = CGFloat(12 + 164 * i)
                Text(i == 0 ? "5H / LEFT" : "WEEK / LEFT").font(CardFonts.mono(10)).foregroundColor(ink.text.color).box(x + 8, 12, 136, 15)
                Text(percent(p.remaining)).font(.system(size: 44)).foregroundColor(digitColor(p, normal: ink.text).color)
                    .lineLimit(1).minimumScaleFactor(0.6).box(x + 6, 31, 140, 49)
                Canvas { ctx, _ in
                    for n in 0...10 {
                        let h: CGFloat = n % 5 == 0 ? 7 : 5
                        ctx.fill(Path(CGRect(x: CGFloat(n) * 13.5, y: 0, width: 1, height: h)), with: .color(ink.secondary.color))
                    }
                }.frame(width: 140, height: 7).offset(x: x + 8, y: 87)
                block(x + 8, 99, 135, 10, ink.track)
                if p.remaining != nil && fraction(p.remaining) > 0 { block(x + 8, 99, 135 * fraction(p.remaining), 10, fillColor(i, p), opacity: fillOpacity) }
                reset(p, font: CardFonts.mono(10), first: ink.text, second: ink.secondary, alignment: .leading, size: 10).box(x + 8, 119, 136, 24, .topLeading)
            }
            block(170, 10, 1, 139, ink.track)
            footerText(.system(size: 10), nil).box(8, 155, 324, 15, .center)
        }
    }

    private func footerText(_ font: Font, _ onBar: RGB?) -> some View {
        Text(model.footer).font(font).foregroundColor((onBar ?? footerInk).color).lineLimit(1).minimumScaleFactor(0.8)
    }

    // MARK: Dot Matrix

    private static let glyphs: [Character: [String]] = ["0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"], "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"], "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"], "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"], "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"], "%": ["11001", "11010", "00100", "01011", "10011"], "—": ["000", "000", "111", "000", "000"]]

    private var dots: some View {
        ZStack(alignment: .topLeading) {
            ForEach(periods(), id: \.0) { i, p in
                let x = CGFloat(12 + 164 * i)
                block(x, 10, 152, 148, ink.surface, radius: 16)
                Text(i == 0 ? "5H left" : "Week left").font(CardFonts.mono(16, .medium)).foregroundColor(ink.text.color).lineLimit(1).box(x + 13, 17, 126, 21)
                let digits = percent(p.remaining), color = digitColor(p, normal: ink.text)
                Canvas { ctx, size in
                    let step: CGFloat = 6
                    let rows = digits.compactMap { QuotaCardView.glyphs[$0] }
                    let columns = rows.reduce(0) { $0 + $1[0].count } + max(0, rows.count - 1)
                    var gx = (size.width - CGFloat(columns) * step) / 2
                    for glyph in rows {
                        for (r, bits) in glyph.enumerated() {
                            for (c, bit) in bits.enumerated() where bit == "1" {
                                ctx.fill(Path(ellipseIn: CGRect(x: gx + CGFloat(c) * step, y: CGFloat(r) * step, width: 5, height: 5)), with: .color(color.color))
                            }
                        }
                        gx += CGFloat(glyph[0].count + 1) * step
                    }
                }.frame(width: 152, height: 30).offset(x: x, y: 42)
                Canvas { ctx, _ in
                    for column in 0..<10 {
                        let amount = p.remaining == nil ? 0 : max(0, min(1, fraction(p.remaining) * 10 - CGFloat(column)))
                        for row in 0..<2 {
                            let dot = CGRect(x: CGFloat(column) * 13, y: CGFloat(row) * 12, width: 8, height: 8)
                            ctx.fill(Path(ellipseIn: dot), with: .color(ink.track.color))
                            if amount > 0 {
                                var clipped = ctx
                                clipped.clip(to: Path(CGRect(x: dot.minX, y: dot.minY, width: dot.width * amount, height: dot.height)))
                                clipped.fill(Path(ellipseIn: dot), with: .color(fillColor(i, p).color.opacity(fillOpacity)))
                            }
                        }
                    }
                }.frame(width: 130, height: 20).offset(x: x + 13, y: 82)
                reset(p, font: CardFonts.mono(10), first: ink.text, second: ink.secondary, alignment: .center, size: 10).box(x + 8, 114, 136, 24, .top)
            }
            block(0, 155, 340, 15, base.bg)
            footerText(.system(size: 10), nil).box(8, 155, 324, 15, .center)
        }
    }

    // MARK: Paper

    private var paper: some View {
        ZStack(alignment: .topLeading) {
            ForEach(periods(), id: \.0) { i, p in
                let y = CGFloat(81 * i)
                Text(i == 0 ? "5H quota left" : "Week quota left").font(CardFonts.mono(13)).foregroundColor(ink.text.color).lineLimit(1).box(16, y + 15, 190, 20)
                Text(percent(p.remaining)).font(.custom("Times New Roman", size: 28)).foregroundColor(digitColor(p, normal: ink.text).color)
                    .lineLimit(1).box(208, y + 9, 116, 32, .trailing)
                block(16, y + 44, 308, 3, ink.track, radius: 1.5)
                if p.remaining != nil && fraction(p.remaining) > 0 { block(16, y + 44, 308 * fraction(p.remaining), 3, fillColor(i, p), radius: 1.5, opacity: fillOpacity) }
                reset(p, font: CardFonts.mono(10), first: ink.text, second: ink.secondary, alignment: .leading, size: 10).box(16, y + 54, 308, 24, .topLeading)
            }
            block(16, 88, 308, 1, ink.track)
            footerText(CardFonts.mono(10), nil).box(8, 167, 324, 15, .center)
        }
    }

    // MARK: Terminal

    private var terminal: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().stroke(ink.text.color, lineWidth: 1).frame(width: 331, height: 147).offset(x: 4.5, y: 4.5)
            Rectangle().stroke(ink.text.color, lineWidth: 1).frame(width: 325, height: 141).offset(x: 7.5, y: 7.5)
            block(10, 10, 320, 20, ink.text)
            Text("\(model.provider.uppercased()) / LIMITS LEFT").font(CardFonts.terminal(18, for: model.provider)).foregroundColor(base.bg.color).lineLimit(1).box(16, 11, 308, 18)
            ForEach(periods(), id: \.0) { i, p in
                let y = CGFloat(58 * i)
                Text(i == 0 ? "5H" : "WEEK").font(CardFonts.terminal(18)).foregroundColor(ink.text.color).box(16, y + 35, 52, 18)
                let cells = p.remaining == nil ? 0 : (fraction(p.remaining) > 0 ? max(1, Int((fraction(p.remaining) * 20).rounded())) : 0)
                Canvas { ctx, _ in
                    for n in 0..<20 {
                        ctx.fill(Path(CGRect(x: CGFloat(n) * 10, y: 0, width: 8, height: 12)),
                                 with: .color((n < cells ? (low(p) ? ink.warning : ink.text) : ink.track).color))
                    }
                }.frame(width: 198, height: 12).offset(x: 68, y: y + 38)
                Text(percent(p.remaining)).font(CardFonts.terminal(18)).foregroundColor(digitColor(p, normal: ink.accent).color).lineLimit(1).box(274, y + 35, 50, 18, .trailing)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.resetLine).font(CardFonts.terminal(16, for: p.resetLine)).foregroundColor(ink.text.color).lineLimit(1).frame(height: 16)
                    Text(p.resetTime).font(CardFonts.terminal(16, for: p.resetTime)).foregroundColor(ink.secondary.color).lineLimit(1).frame(height: 16)
                }.frame(width: 200, height: 32, alignment: .topLeading).offset(x: 68, y: y + 55)
            }
            block(0, 154, 340, 16, ink.text)
            footerText(CardFonts.terminal(16, for: model.footer), base.bg).box(8, 154, 324, 16, .center)
        }
    }
}

/// The widget family can be a little narrower or shorter than the card; scale the card to fit instead of cropping it.
struct QuotaCardFit: View {
    let model: QuotaCardModel
    let theme: PanelTheme
    var scheme: ColorScheme? = nil
    var vibrant = false
    var body: some View {
        GeometryReader { geo in
            let h = theme.cardHeight
            let scale = min(geo.size.width / 340, geo.size.height / h)
            QuotaCardView(model: model, theme: theme, scheme: scheme, vibrant: vibrant)
                .frame(width: 340, height: h)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Panel (popover and Picture-in-Picture)

struct QuotaPanelEntry: Identifiable {
    let id: String
    var model: QuotaCardModel
    var theme: PanelTheme
    var scheme: ColorScheme?
    /// Refresh failure shown under the card ("Codex CLI not found…"); empty when there is none.
    var message: String

    var messageHeight: CGFloat { QuotaPanelLayout.messageHeight(message) }
    var height: CGFloat { theme.cardHeight + messageHeight }
}

enum QuotaPanelLayout {
    static let width: CGFloat = 340
    static let messageFont = NSFont.systemFont(ofSize: 13)
    static func messageHeight(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        let height = (text as NSString).boundingRect(with: NSSize(width: width - 28, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: messageFont, .paragraphStyle: style]).height
        return ceil(height) + 20
    }
    static func height(_ entries: [QuotaPanelEntry]) -> CGFloat { entries.reduce(0) { $0 + $1.height } }
}

struct QuotaPanelView: View {
    let entries: [QuotaPanelEntry]
    var maxHeight: CGFloat = .greatestFiniteMagnitude
    var body: some View {
        let stack = VStack(spacing: 0) { ForEach(entries) { QuotaPanelEntryView(entry: $0) } }.frame(width: QuotaPanelLayout.width)
        if QuotaPanelLayout.height(entries) > maxHeight { ScrollView(.vertical) { stack } } else { stack }
    }
}

private struct QuotaPanelEntryView: View {
    let entry: QuotaPanelEntry
    @Environment(\.colorScheme) private var systemScheme
    var body: some View {
        let tokens = entry.theme.tokens(dark: (entry.scheme ?? systemScheme) == .dark)
        VStack(spacing: 0) {
            QuotaCardView(model: entry.model, theme: entry.theme, scheme: entry.scheme)
            if !entry.message.isEmpty {
                Text(entry.message).font(.system(size: 13)).foregroundColor(tokens.secondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: QuotaPanelLayout.width - 28, alignment: .leading)
                    .padding(.top, 8)
                    .frame(width: QuotaPanelLayout.width, height: entry.messageHeight, alignment: .top)
                    .background(tokens.bg.color)
            }
        }
    }
}
