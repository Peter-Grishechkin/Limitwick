import AppKit

// A dedicated 2:1 composition keeps popup height and error messages from
// changing the widget's proportions. Coordinates are in a 340 × 170 canvas.
final class WidgetThemeView: ThemeView {
    let theme: PanelTheme
    let previous: Bool
    private let paletteView: ThemeView?
    init(theme: PanelTheme, data: ThemeData, previous: Bool, appearance: NSAppearance?) {
        self.theme = theme
        self.previous = previous
        self.paletteView = theme.makeView()
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 170))
        self.appearance = appearance
        paletteView?.appearance = appearance
        self.data = data
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var palette: ThemePalette {
        if let view = paletteView { return view.palette }
        return ThemePalette(background: dark ? .init(white: 0.12, alpha: 1) : .init(white: 0.96, alpha: 1), surface: dark ? .init(white: 0.18, alpha: 1) : .white, text: dark ? .white : .black, secondary: dark ? .lightGray : .darkGray, track: .gray, accent: .systemBlue, second: .systemBlue)
    }
    override func draw(_ dirtyRect: NSRect) {
        background()
        switch theme {
        case .classic: drawClassic()
        case .industrial: drawIndustrial()
        case .dots: drawDots()
        case .paper: drawPaper()
        case .capsules: drawCapsules()
        case .terminal: drawTerminal()
        }
        if previous {
            fill(NSRect(x: 112, y: 151, width: 116, height: 14), palette.background, radius: 4)
            text("Previous data", NSRect(x: 112, y: 151, width: 116, height: 14), size: 9, color: palette.secondary, alignment: .center)
        }
    }
    private var items: [(Int, Double?, String)] { [(0, data.fiveHour, data.fiveReset), (1, data.weekly, data.weekReset)] }
    private func reset(_ value: String, _ rect: NSRect, color: NSColor, mono: Bool = false, alignment: NSTextAlignment = .left) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: 9, weight: .regular) : NSFont.systemFont(ofSize: 9)
        text(value, rect, size: 9, color: color, font: font, alignment: alignment, wrap: true)
    }
    private func drawClassic() {
        let p = palette
        for (i, value, date) in items {
            let x = CGFloat(12 + i * 164)
            fill(NSRect(x: x, y: 10, width: 152, height: 148), p.surface, radius: 14)
            let center = NSPoint(x: x + 76, y: 44), radius: CGFloat = 25
            let track = NSBezierPath(ovalIn: NSRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)); track.lineWidth = 6; p.track.withAlphaComponent(0.5).setStroke(); track.stroke()
            if let value = value, value > 0 {
                let path = NSBezierPath(); path.lineWidth = 6; path.lineCapStyle = .round
                if value >= 100 { path.appendOval(in: NSRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)) }
                else { path.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 + 360 * fraction(value), clockwise: false) }
                quotaColor(value, normal: p.accent).setStroke(); path.stroke()
            }
            text(i == 0 ? "5" : "W", NSRect(x: x+46, y: 29, width: 60, height: 29), size: 22, color: p.text, font: .systemFont(ofSize: 22, weight: .semibold), alignment: .center)
            text(percent(value), NSRect(x: x+10, y: 77, width: 132, height: 26), size: 20, color: p.text, font: .systemFont(ofSize: 20, weight: .semibold), alignment: .center)
            reset(date, NSRect(x: x+8, y: 110, width: 136, height: 32), color: p.secondary, alignment: .center)
        }
    }
    private func drawIndustrial() {
        let p = palette, mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        for (i, value, date) in items {
            let x = CGFloat(12 + i*164)
            text(i == 0 ? "5H / LIMIT" : "WEEK / LIMIT", NSRect(x: x+8, y: 12, width: 136, height: 15), size: 10, color: p.text, font: mono)
            text(percent(value), NSRect(x: x+6, y: 31, width: 140, height: 49), size: 39, color: p.text)
            for n in 0...10 { let xx = x+8+CGFloat(n)*13.5; line(NSPoint(x: xx, y: 87), NSPoint(x: xx, y: n % 5 == 0 ? 94 : 92), p.secondary) }
            bar(NSRect(x: x+8, y: 99, width: 135, height: 10), value: value, color: i == 0 ? p.accent : p.second)
            reset("RST  " + date, NSRect(x: x+8, y: 119, width: 136, height: 28), color: p.text, mono: true)
        }
        line(NSPoint(x: 170, y: 10), NSPoint(x: 170, y: 149), p.track)
    }
    private func drawDots() {
        let p = palette, glyphs = DotThemeView().glyphs
        for (i, value, date) in items {
            let x = CGFloat(12 + i*164)
            fill(NSRect(x: x, y: 10, width: 152, height: 148), p.surface, radius: 16)
            text(i == 0 ? "5H" : "W", NSRect(x: x+13, y: 17, width: 120, height: 21), size: 16, color: p.text, font: .monospacedSystemFont(ofSize: 16, weight: .medium))
            let s = percent(value), step: CGFloat = 6
            var gx = x + (152 - (CGFloat(s.count)*step*4-step))/2
            for character in s {
                if let rows = glyphs[character] { for (row, bits) in rows.enumerated() { for (col, bit) in bits.enumerated() where bit == "1" { fill(NSRect(x: gx+CGFloat(col)*step, y: 42+CGFloat(row)*step, width: 5, height: 5), p.text, radius: 2.5) } } }
                gx += step*4
            }
            for column in 0..<10 { for row in 0..<2 {
                let dot = NSRect(x: x+13+CGFloat(column)*13, y: 82+CGFloat(row)*12, width: 8, height: 8)
                fill(dot, p.track, radius: 4)
                let amount = value == nil ? 0 : max(0, min(1, fraction(value)*10-CGFloat(column)))
                if amount > 0 { NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: NSRect(x: dot.minX, y: dot.minY, width: dot.width*amount, height: dot.height)).addClip(); fill(dot, quotaColor(value, normal: i == 0 ? p.accent : p.second), radius: 4); NSGraphicsContext.restoreGraphicsState() }
            } }
            reset(date, NSRect(x: x+8, y: 114, width: 136, height: 30), color: p.secondary, mono: true, alignment: .center)
        }
    }
    private func drawPaper() {
        let p = palette
        for (i, value, date) in items {
            let y = CGFloat(12 + i*75)
            text(i == 0 ? "5-Hour Quota" : "Weekly Quota", NSRect(x: 16, y: y+3, width: 190, height: 20), size: 14, color: p.text, font: .monospacedSystemFont(ofSize: 14, weight: .regular))
            text(percent(value), NSRect(x: 208, y: y-3, width: 116, height: 32), size: 26, color: p.text, font: NSFont(name: "Times New Roman", size: 26), alignment: .right)
            bar(NSRect(x: 16, y: y+32, width: 308, height: 3), value: value, color: p.accent, radius: 1.5)
            reset(date, NSRect(x: 16, y: y+42, width: 308, height: 25), color: p.secondary)
            if i == 0 { line(NSPoint(x: 16, y: y+70), NSPoint(x: 324, y: y+70), p.track) }
        }
    }
    private func drawCapsules() {
        let p = palette
        for (i, value, date) in items {
            let y = CGFloat(12 + i*74), rect = NSRect(x: 14, y: y, width: 312, height: 64)
            fill(rect, p.track, radius: 32)
            let progress = NSRect(x: 80, y: y, width: 246*fraction(value), height: 64)
            if value != nil && progress.width > 0 { NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32).addClip(); fill(progress, quotaColor(value, normal: i == 0 ? p.accent : p.second)); NSGraphicsContext.restoreGraphicsState() }
            fill(NSRect(x: 21, y: y+7, width: 50, height: 50), dark ? .init(white: 0.08, alpha: 1) : .white, radius: 25)
            text(i == 0 ? "5h" : "W", NSRect(x: 21, y: y+18, width: 50, height: 30), size: 22, color: p.text, font: .systemFont(ofSize: 22, weight: .bold), alignment: .center)
            let dateRect = NSRect(x: 83, y: y+17, width: 125, height: 32)
            reset(date, dateRect, color: p.text)
            if !dark, value != nil, fraction(value) > 0 { NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32).addClip(); NSBezierPath(rect: progress).addClip(); reset(date, dateRect, color: .white); NSGraphicsContext.restoreGraphicsState() }
            text(percent(value), NSRect(x: 211, y: y+18, width: 103, height: 30), size: 22, color: p.text, font: .systemFont(ofSize: 22, weight: .bold), alignment: .right)
        }
    }
    private func drawTerminal() {
        let p = palette, mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), bold = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        text(">", NSRect(x: 17, y: 10, width: 12, height: 16), size: 10, color: p.accent, font: bold)
        text("CODEX / LIMITS", NSRect(x: 30, y: 10, width: 270, height: 16), size: 10, color: p.text, font: bold)
        line(NSPoint(x: 17, y: 29), NSPoint(x: 323, y: 29), p.track)
        for (i, value, date) in items {
            let y = CGFloat(38 + i*57)
            text(i == 0 ? "5H" : "WEEK", NSRect(x: 17, y: y, width: 57, height: 16), size: 10, color: p.text, font: bold)
            text("[", NSRect(x: 76, y: y, width: 9, height: 16), size: 10, color: p.secondary, font: mono)
            text("]", NSRect(x: 260, y: y, width: 9, height: 16), size: 10, color: p.secondary, font: mono)
            for n in 0..<21 { let active = value != nil && CGFloat(n) < fraction(value)*21; text(active ? "#" : "·", NSRect(x: 84+CGFloat(n)*8.3, y: y, width: 9, height: 16), size: 10, color: active ? quotaColor(value, normal: p.text) : p.track, font: mono) }
            text(percent(value), NSRect(x: 270, y: y, width: 53, height: 16), size: 10, color: p.accent, font: bold, alignment: .right)
            reset("reset: " + date, NSRect(x: 17, y: y+20, width: 306, height: 27), color: p.secondary, mono: true)
        }
        line(NSPoint(x: 17, y: 151), NSPoint(x: 323, y: 151), p.track)
    }
}
