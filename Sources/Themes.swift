import AppKit

// Themes are data: a palette per theme and mode. The card (QuotaCard.swift) is the only view that draws
// quotas; the panel, the Picture-in-Picture window and the widgets all show it.

enum PanelTheme: String, CaseIterable {
    case industrial, dots, paper, terminal
    var title: String {
        switch self {
        case .industrial: return "Industrial"
        case .dots: return "Dot Matrix"
        case .paper: return "Paper"
        case .terminal: return "Terminal"
        }
    }
    static let fallback = PanelTheme.industrial
    /// Themes removed in 2.2 (Classic, Capsules) and unset values fall back to Industrial.
    init(stored value: String?) { self = PanelTheme(rawValue: value ?? "") ?? .fallback }
    /// Card height in points; Paper needs a second text row of its own.
    var cardHeight: CGFloat { self == .paper ? 182 : 170 }
    func palette(dark: Bool) -> ThemePalette { tokens(dark: dark).palette }
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

struct RGB: Equatable {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(white: Double) { self.init(white, white, white) }
    /// `amount` of the way from this color toward `other`.
    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
    }
    var ns: NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
}

struct CardTokens {
    var bg: RGB, surface: RGB, text: RGB, secondary: RGB, track: RGB, accent: RGB, second: RGB, warning: RGB
    var palette: ThemePalette {
        ThemePalette(background: bg.ns, surface: surface.ns, text: text.ns, secondary: secondary.ns, track: track.ns, accent: accent.ns, second: second.ns)
    }
    /// Previous data recedes: every ink color moves 40 % toward the background (the footer only 20 %, see `QuotaCard`).
    func receded(_ amount: Double = 0.4) -> CardTokens {
        func f(_ c: RGB) -> RGB { c.mixed(with: bg, amount) }
        return CardTokens(bg: bg, surface: surface, text: f(text), secondary: f(secondary), track: f(track), accent: f(accent), second: f(second), warning: f(warning))
    }
}

extension PanelTheme {
    func tokens(dark: Bool) -> CardTokens {
        let red = dark ? RGB(1.00, 0.27, 0.23) : RGB(1.00, 0.23, 0.19)
        switch (self, dark) {
        case (.industrial, false):
            return CardTokens(bg: RGB(0.93, 0.93, 0.90), surface: RGB(white: 0.95), text: RGB(white: 0.13), secondary: RGB(white: 0.32), track: RGB(white: 0.72), accent: RGB(white: 0.25), second: RGB(0.14, 0.29, 0.45), warning: red)
        case (.industrial, true):
            return CardTokens(bg: RGB(white: 0.08), surface: RGB(white: 0.10), text: RGB(white: 0.92), secondary: RGB(white: 0.72), track: RGB(white: 0.25), accent: RGB(white: 0.72), second: RGB(0.47, 0.64, 0.82), warning: red)
        case (.dots, false):
            return CardTokens(bg: RGB(white: 0.92), surface: RGB(white: 1), text: RGB(white: 0), secondary: RGB(white: 0.34), track: RGB(white: 0.81), accent: RGB(white: 0), second: RGB(white: 0), warning: red)
        case (.dots, true):
            return CardTokens(bg: RGB(white: 0), surface: RGB(white: 0.10), text: RGB(white: 1), secondary: RGB(white: 0.72), track: RGB(white: 0.27), accent: RGB(white: 1), second: RGB(white: 1), warning: red)
        case (.paper, false):
            return CardTokens(bg: RGB(0.96, 0.95, 0.92), surface: RGB(white: 1), text: RGB(white: 0.10), secondary: RGB(white: 0.35), track: RGB(white: 0.72), accent: RGB(white: 0.10), second: RGB(white: 0.10), warning: red)
        case (.paper, true):
            return CardTokens(bg: RGB(0.07, 0.065, 0.055), surface: RGB(white: 0), text: RGB(white: 0.92), secondary: RGB(white: 0.70), track: RGB(white: 0.30), accent: RGB(white: 0.92), second: RGB(white: 0.92), warning: red)
        case (.terminal, false):
            return CardTokens(bg: RGB(0.96, 0.96, 0.95), surface: RGB(white: 1), text: RGB(white: 0.13), secondary: RGB(white: 0.33), track: RGB(white: 0.72), accent: RGB(0.17, 0.43, 0.27), second: RGB(white: 0.13), warning: red)
        case (.terminal, true):
            return CardTokens(bg: RGB(0.055, 0.065, 0.075), surface: RGB(white: 0), text: RGB(white: 0.90), secondary: RGB(white: 0.72), track: RGB(white: 0.30), accent: RGB(0.47, 0.76, 0.57), second: RGB(white: 0.90), warning: red)
        }
    }
}
