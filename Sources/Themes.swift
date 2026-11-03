import AppKit

// Themes consume a presentation model and do not know how quotas are fetched.
struct ThemeData {
    var fiveHour: Double?
    var weekly: Double?
    var fiveReset: String
    var weekReset: String
    var accessibility: String
    var warningThreshold: Int = 20
    var providerName: String? = nil
    var stale = false
}

enum PanelTheme: String, CaseIterable {
    case classic, industrial, dots, paper, capsules, terminal
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .industrial: return "Industrial"
        case .dots: return "Dot Matrix"
        case .paper: return "Paper"
        case .capsules: return "Capsules"
        case .terminal: return "Terminal"
        }
    }
    func makeView() -> ThemeView? {
        switch self {
        case .classic: return nil
        case .industrial: return IndustrialThemeView()
        case .dots: return DotThemeView()
        case .paper: return PaperThemeView()
        case .capsules: return CapsuleThemeView()
        case .terminal: return TerminalThemeView()
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case auto, light, dark
    var title: String { rawValue.capitalized }
    var appearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct ThemePalette {
    let background: NSColor, surface: NSColor, text: NSColor, secondary: NSColor, track: NSColor, accent: NSColor, second: NSColor
}

class ThemeView: NSView {
    var data = ThemeData(fiveHour: nil, weekly: nil, fiveReset: "—", weekReset: "—", accessibility: "Limits unavailable") {
        didSet { setAccessibilityLabel(data.accessibility); needsDisplay = true }
    }
    var appearanceChanged: (() -> Void)?
    var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    var palette: ThemePalette { fatalError("Theme must provide a palette") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; appearanceChanged?() }
    func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
        color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    func line(_ a: NSPoint, _ b: NSPoint, _ color: NSColor, width: CGFloat = 1) {
        let path = NSBezierPath(); path.move(to: a); path.line(to: b); path.lineWidth = width; color.setStroke(); path.stroke()
    }
    func text(_ value: String, _ rect: NSRect, size: CGFloat, color: NSColor, font: NSFont? = nil, alignment: NSTextAlignment = .left, wrap: Bool = false) {
        let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        (value as NSString).draw(in: rect, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: style])
    }
    func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "—" }
    func fraction(_ value: Double?) -> CGFloat { CGFloat(max(0, min(1, (value ?? 0) / 100))) }
    func background() { fill(bounds, palette.background) }
    func resetHeight(_ value: String, width: CGFloat, font: NSFont) -> CGFloat {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        return ceil((value as NSString).boundingRect(with: NSSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: style]).height) + 2
    }
    // Bottom edge of drawn content; the panel adds an equal outer inset.
    var preferredContentHeight: CGFloat { 184 }
    var outerInset: CGFloat { 12 }

    // Red is reserved for low quota; previous data recedes so it is not read as current.
    var warningColor: NSColor { .systemRed }
    func quotaColor(_ value: Double?, normal: NSColor) -> NSColor {
        let color = isLowQuota(value, threshold: data.warningThreshold) ? warningColor : normal
        return data.stale ? color.withAlphaComponent(0.4) : color
    }
    func bar(_ rect: NSRect, value: Double?, color: NSColor, radius: CGFloat = 0) {
        fill(rect, palette.track, radius: radius)
        if value != nil && fraction(value) > 0 { fill(NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction(value), height: rect.height), quotaColor(value, normal: color), radius: radius) }
    }
}

final class IndustrialThemeView: ThemeView {
    var extraReset: CGFloat { max(0, max(resetHeight("RST  " + data.fiveReset, width: 136, font: .monospacedSystemFont(ofSize: 11, weight: .regular)), resetHeight("RST  " + data.weekReset, width: 136, font: .monospacedSystemFont(ofSize: 11, weight: .regular))) - 28) }
    override var preferredContentHeight: CGFloat { 184 + extraReset }
    override var palette: ThemePalette { dark ? ThemePalette(background: .init(white: 0.08, alpha: 1), surface: .init(white: 0.10, alpha: 1), text: .init(white: 0.92, alpha: 1), secondary: .init(white: 0.72, alpha: 1), track: .init(white: 0.25, alpha: 1), accent: .init(white: 0.72, alpha: 1), second: .init(calibratedRed: 0.47, green: 0.64, blue: 0.82, alpha: 1)) : ThemePalette(background: .init(calibratedRed: 0.93, green: 0.93, blue: 0.90, alpha: 1), surface: .init(white: 0.95, alpha: 1), text: .init(white: 0.13, alpha: 1), secondary: .init(white: 0.32, alpha: 1), track: .init(white: 0.72, alpha: 1), accent: .init(white: 0.25, alpha: 1), second: .init(calibratedRed: 0.20, green: 0.38, blue: 0.56, alpha: 1)) }
    override func draw(_ dirtyRect: NSRect) {
        background(); let p = palette; let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        for (i, value, reset) in [(0, data.fiveHour, data.fiveReset), (1, data.weekly, data.weekReset)] {
            let x = CGFloat(12 + i * 164); let w: CGFloat = 152
            text(i == 0 ? "5H / LIMIT" : "WEEK / LIMIT", NSRect(x: x+8, y: 17, width: w-16, height: 16), size: 10, color: p.text, font: mono)
            text(percent(value), NSRect(x: x+6, y: 44, width: w-12, height: 57), size: 44, color: p.text, font: .systemFont(ofSize: 44, weight: .regular))
            for n in 0...10 { let xx = x+8+CGFloat(n)*13.5; line(NSPoint(x: xx, y: 110), NSPoint(x: xx, y: n % 5 == 0 ? 119 : 116), p.secondary) }
            bar(NSRect(x: x+8, y: 123, width: 135, height: 13), value: value, color: i == 0 ? p.accent : p.second)
            text("RST  \(reset)", NSRect(x: x+8, y: 150, width: w-16, height: 28 + extraReset), size: 11, color: p.text, font: .monospacedSystemFont(ofSize: 11, weight: .regular), wrap: true)
        }
        line(NSPoint(x: 170, y: 12), NSPoint(x: 170, y: 184 + extraReset), p.track)
    }
}

final class DotThemeView: ThemeView {
    var extraReset: CGFloat { max(0, max(resetHeight(data.fiveReset, width: 136, font: .monospacedSystemFont(ofSize: 11, weight: .regular)), resetHeight(data.weekReset, width: 136, font: .monospacedSystemFont(ofSize: 11, weight: .regular))) - 28) }
    override var preferredContentHeight: CGFloat { 186 + extraReset }
    override var palette: ThemePalette { dark ? ThemePalette(background: .black, surface: .init(white: 0.10, alpha: 1), text: .white, secondary: .init(white: 0.72, alpha: 1), track: .init(white: 0.27, alpha: 1), accent: .white, second: .white) : ThemePalette(background: .init(white: 0.92, alpha: 1), surface: .white, text: .black, secondary: .init(white: 0.34, alpha: 1), track: .init(white: 0.81, alpha: 1), accent: .black, second: .black) }
    // Three-by-five dot glyphs are rendered locally; no external font is needed.
    let glyphs: [Character: [String]] = ["0":["111","101","101","101","111"],"1":["010","110","010","010","111"],"2":["111","001","111","100","111"],"3":["111","001","111","001","111"],"4":["101","101","111","001","001"],"5":["111","100","111","001","111"],"6":["111","100","111","101","111"],"7":["111","001","010","010","010"],"8":["111","101","111","101","111"],"9":["111","101","111","001","111"],"%":["101","001","010","100","101"],"—":["000","000","111","000","000"]]
    override func draw(_ dirtyRect: NSRect) {
        background(); let p = palette
        NSGraphicsContext.saveGraphicsState()
        let inset = NSAffineTransform(); inset.translateX(by: 0, yBy: 2); inset.concat()
        defer { NSGraphicsContext.restoreGraphicsState() }
        for (i, value, reset) in [(0, data.fiveHour, data.fiveReset), (1, data.weekly, data.weekReset)] {
            let x = CGFloat(12 + i*164); fill(NSRect(x: x, y: 10, width: 152, height: 174 + extraReset), p.surface, radius: 16)
            text(i == 0 ? "5H" : "W", NSRect(x: x+13, y: 19, width: 120, height: 23), size: 18, color: p.text, font: .monospacedSystemFont(ofSize: 18, weight: .medium))
            let s = percent(value); let step: CGFloat = 7.5; let width = CGFloat(s.count) * step * 4 - step
            var gx = x + (152-width)/2
            for character in s { if let rows = glyphs[character] { for (row, bits) in rows.enumerated() { for (col, bit) in bits.enumerated() where bit == "1" { fill(NSRect(x: gx+CGFloat(col)*step, y: 51+CGFloat(row)*step, width: 6.2, height: 6.2), p.text, radius: 3.1) } } }; gx += step*4 }
            for column in 0..<10 {
                for row in 0..<2 {
                    let dot = NSRect(x: x+13+CGFloat(column)*13, y: 103+CGFloat(row)*13, width: 9, height: 9)
                    fill(dot, p.track, radius: 4.5)
                    let amount = value == nil ? 0 : max(0, min(1, fraction(value)*10-CGFloat(column)))
                    if amount > 0 {
                        NSGraphicsContext.saveGraphicsState()
                        NSBezierPath(rect: NSRect(x: dot.minX, y: dot.minY, width: dot.width*amount, height: dot.height)).addClip()
                        fill(dot, quotaColor(value, normal: i == 0 ? p.accent : p.second), radius: 4.5)
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
            }
            text(reset, NSRect(x: x+8, y: 143, width: 136, height: 28 + extraReset), size: 11, color: p.secondary, font: .monospacedSystemFont(ofSize: 11, weight: .regular), alignment: .center, wrap: true)
        }
    }
}

final class PaperThemeView: ThemeView {
    func extra(_ reset: String) -> CGFloat { max(0, resetHeight(reset, width: 308, font: .systemFont(ofSize: 11)) - 20) }
    override var preferredContentHeight: CGFloat { 172 + extra(data.fiveReset) + extra(data.weekReset) }
    override var outerInset: CGFloat { 14 }
    override var palette: ThemePalette { dark ? ThemePalette(background: .init(calibratedRed: 0.07, green: 0.065, blue: 0.055, alpha: 1), surface: .black, text: .init(white: 0.92, alpha: 1), secondary: .init(white: 0.70, alpha: 1), track: .init(white: 0.30, alpha: 1), accent: .init(white: 0.92, alpha: 1), second: .init(white: 0.92, alpha: 1)) : ThemePalette(background: .init(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1), surface: .white, text: .init(white: 0.10, alpha: 1), secondary: .init(white: 0.35, alpha: 1), track: .init(white: 0.72, alpha: 1), accent: .init(white: 0.10, alpha: 1), second: .init(white: 0.10, alpha: 1)) }
    override func draw(_ dirtyRect: NSRect) {
        background(); let p = palette
        for (i, value, reset) in [(0, data.fiveHour, data.fiveReset), (1, data.weekly, data.weekReset)] {
            let y = CGFloat(14 + i*86) + (i == 1 ? extra(data.fiveReset) : 0)
            text(i == 0 ? "5-Hour Quota" : "Weekly Quota", NSRect(x: 16, y: y+6, width: 190, height: 22), size: 15, color: p.text, font: .monospacedSystemFont(ofSize: 15, weight: .regular))
            text(percent(value), NSRect(x: 208, y: y-2, width: 116, height: 34), size: 28, color: p.text, font: NSFont(name: "Times New Roman", size: 28) ?? .systemFont(ofSize: 28), alignment: .right)
            bar(NSRect(x: 16, y: y+42, width: 308, height: 3), value: value, color: p.accent, radius: 1.5)
            text(reset, NSRect(x: 16, y: y+52, width: 308, height: 20 + extra(reset)), size: 11, color: p.secondary, wrap: true)
            if i == 0 { line(NSPoint(x: 16, y: y+80+extra(reset)), NSPoint(x: 324, y: y+80+extra(reset)), p.track) }
        }
    }
}

final class CapsuleThemeView: ThemeView {
    func extra(_ reset: String) -> CGFloat { max(0, resetHeight(reset, width: 125, font: .systemFont(ofSize: 11)) - 48) }
    override var preferredContentHeight: CGFloat { 167 + extra(data.fiveReset) + extra(data.weekReset) }
    override var outerInset: CGFloat { 14 }
    // A deeper red keeps white dates on the warning fill above 4.5:1.
    override var warningColor: NSColor { .init(calibratedRed: 0.76, green: 0.15, blue: 0.13, alpha: 1) }
    override var palette: ThemePalette { dark ? ThemePalette(background: .init(calibratedRed: 0.07, green: 0.09, blue: 0.11, alpha: 1), surface: .init(white: 0.1, alpha: 1), text: .white, secondary: .init(white: 0.80, alpha: 1), track: .init(calibratedRed: 0.13, green: 0.16, blue: 0.21, alpha: 1), accent: .init(calibratedRed: 0.25, green: 0.34, blue: 0.49, alpha: 1), second: .init(calibratedRed: 0.19, green: 0.46, blue: 0.44, alpha: 1)) : ThemePalette(background: .init(calibratedRed: 0.94, green: 0.95, blue: 0.97, alpha: 1), surface: .white, text: .init(calibratedRed: 0.13, green: 0.17, blue: 0.23, alpha: 1), secondary: .init(white: 0.31, alpha: 1), track: .init(calibratedRed: 0.85, green: 0.87, blue: 0.90, alpha: 1), accent: .init(calibratedRed: 0.31, green: 0.37, blue: 0.48, alpha: 1), second: .init(calibratedRed: 0.16, green: 0.42, blue: 0.40, alpha: 1)) }
    override func draw(_ dirtyRect: NSRect) {
        background(); let p = palette
        for (i, value, reset) in [(0, data.fiveHour, data.fiveReset), (1, data.weekly, data.weekReset)] {
            let y = CGFloat(14 + i*85) + (i == 1 ? extra(data.fiveReset) : 0); let pillHeight = 68 + extra(reset); let rect = NSRect(x: 14, y: y, width: 312, height: pillHeight)
            // Keep the badge clear; clip the fill to the full capsule, not to a
            // shrinking rounded rectangle that produces a halo at low values.
            fill(rect, p.track, radius: 34)
            let progress = NSRect(x: 80, y: y, width: max(0, rect.maxX - 80) * fraction(value), height: pillHeight)
            if value != nil && progress.width > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34).addClip()
                fill(progress, quotaColor(value, normal: i == 0 ? p.accent : p.second))
                NSGraphicsContext.restoreGraphicsState()
            }
            fill(NSRect(x: 21, y: y+(pillHeight-54)/2, width: 54, height: 54), dark ? .init(white: 0.08, alpha: 1) : .white, radius: 27)
            let symbol = i == 0 ? "5h" : "W"
            let symbolFont = NSFont.systemFont(ofSize: 23, weight: .bold)
            let symbolHeight = (symbol as NSString).size(withAttributes: [.font: symbolFont]).height
            text(symbol, NSRect(x: 21, y: y+(pillHeight-symbolHeight)/2, width: 54, height: symbolHeight+1), size: 23, color: p.text, font: symbolFont, alignment: .center)
            let dateFont = NSFont.systemFont(ofSize: 11)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            let dateHeight = ceil((reset as NSString).boundingRect(with: NSSize(width: 125, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: dateFont, .paragraphStyle: paragraph]).height)
            let dateRect = NSRect(x: 83, y: y+(pillHeight-dateHeight)/2, width: 125, height: dateHeight+1)
            text(reset, dateRect, size: 11, color: p.text, font: dateFont, wrap: true)
            if !dark, !data.stale, value != nil, fraction(value) > 0 {
                // Redraw only the part over the filled capsule in a light color.
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34).addClip()
                NSBezierPath(rect: progress).addClip()
                text(reset, dateRect, size: 11, color: .white, font: dateFont, wrap: true)
                NSGraphicsContext.restoreGraphicsState()
            }
            text(percent(value), NSRect(x: 211, y: y+(pillHeight-36)/2, width: 103, height: 36), size: 23, color: p.text, font: .systemFont(ofSize: 23, weight: .bold), alignment: .right)
        }
    }
}

final class TerminalThemeView: ThemeView {
    func extra(_ reset: String) -> CGFloat { max(0, resetHeight("reset: " + reset, width: 306, font: .monospacedSystemFont(ofSize: 11, weight: .regular)) - 19) }
    override var preferredContentHeight: CGFloat { 172 + extra(data.fiveReset) + extra(data.weekReset) }
    override var outerInset: CGFloat { 17 }
    override var palette: ThemePalette {
        dark
            ? ThemePalette(background: .init(calibratedRed: 0.055, green: 0.065, blue: 0.075, alpha: 1), surface: .black, text: .init(white: 0.90, alpha: 1), secondary: .init(white: 0.72, alpha: 1), track: .init(white: 0.30, alpha: 1), accent: .init(calibratedRed: 0.47, green: 0.76, blue: 0.57, alpha: 1), second: .init(white: 0.90, alpha: 1))
            : ThemePalette(background: .init(calibratedRed: 0.96, green: 0.96, blue: 0.95, alpha: 1), surface: .white, text: .init(white: 0.13, alpha: 1), secondary: .init(white: 0.33, alpha: 1), track: .init(white: 0.72, alpha: 1), accent: .init(calibratedRed: 0.17, green: 0.43, blue: 0.27, alpha: 1), second: .init(white: 0.13, alpha: 1))
    }
    override func draw(_ dirtyRect: NSRect) {
        background()
        NSGraphicsContext.saveGraphicsState()
        let inset = NSAffineTransform(); inset.translateX(by: 0, yBy: 3); inset.concat()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let p = palette
        let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        // A console readout: prompt, fixed-width rows and text-based progress bars.
        text(">", NSRect(x: 17, y: 14, width: 12, height: 18), size: 11, color: p.accent, font: bold)
        text("\(data.providerName?.uppercased() ?? "CODEX") / LIMITS", NSRect(x: 30, y: 14, width: 270, height: 18), size: 11, color: p.text, font: bold)
        line(NSPoint(x: 17, y: 36), NSPoint(x: 323, y: 36), p.track)
        for (i, value, reset) in [(0, data.fiveHour, data.fiveReset), (1, data.weekly, data.weekReset)] {
            let y = CGFloat(48 + i*59) + (i == 1 ? extra(data.fiveReset) : 0)
            text(i == 0 ? "5H" : "WEEK", NSRect(x: 17, y: y, width: 57, height: 18), size: 11, color: p.text, font: bold)
            text("[", NSRect(x: 76, y: y, width: 9, height: 18), size: 11, color: p.secondary, font: mono)
            text("]", NSRect(x: 260, y: y, width: 9, height: 18), size: 11, color: p.secondary, font: mono)
            for n in 0..<21 {
                let active = value != nil && CGFloat(n) < fraction(value)*21
                text(active ? "#" : "·", NSRect(x: 84+CGFloat(n)*8.3, y: y, width: 9, height: 18), size: 11, color: active ? quotaColor(value, normal: p.text) : p.track, font: mono)
            }
            text(percent(value), NSRect(x: 270, y: y, width: 53, height: 18), size: 11, color: p.accent, font: bold, alignment: .right)
            text("reset: \(reset)", NSRect(x: 17, y: y+22, width: 306, height: 19 + extra(reset)), size: 11, color: p.secondary, font: .monospacedSystemFont(ofSize: 11, weight: .regular), wrap: true)
        }
        line(NSPoint(x: 17, y: 169 + extra(data.fiveReset) + extra(data.weekReset)), NSPoint(x: 323, y: 169 + extra(data.fiveReset) + extra(data.weekReset)), p.track)
    }
}
