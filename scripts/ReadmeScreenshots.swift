import AppKit

// Renders README images from the real theme and status bar views with fixed demo values.
// Built and run by scripts/render-screenshots.sh.

let scale: CGFloat = 2
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images", isDirectory: true)
let appearances: [(String, NSAppearance)] = [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)]
let demo = (five: 72.0, week: 46.0, fiveReset: "in\u{00A0}2h\u{00A0}15m\u{00A0}· 4:30\u{00A0}PM", weekReset: "in\u{00A0}4d\u{00A0}6h\u{00A0}· Sat\u{00A0}8:15\u{00A0}PM")

func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

func render(_ size: NSSize, appearance: NSAppearance, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    appearance.performAsCurrentDrawingAppearance(draw)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func snapshot(_ view: NSView, pixelScale: CGFloat = scale) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * pixelScale), pixelsHigh: Int(view.bounds.height * pixelScale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    return image
}

// Writes straight (non-premultiplied) RGBA. Fully transparent pixels take the colour of the nearest
// visible pixel in their row, so viewers that scale without premultiplying do not show a dark fringe.
func save(_ rep: NSBitmapImageRep, _ name: String) {
    let width = rep.pixelsWide, height = rep.pixelsHigh
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bitmapFormat: .alphaNonpremultiplied, bytesPerRow: width * 4, bitsPerPixel: 32)!
    out.size = rep.size
    let target = out.bitmapData!
    var pixel = [Int](repeating: 0, count: 4)
    for y in 0..<height {
        let row = target + y * width * 4
        for x in 0..<width {
            rep.getPixel(&pixel, atX: x, y: y)
            let alpha = pixel[3]
            for c in 0..<3 { row[x * 4 + c] = UInt8(alpha == 0 ? 0 : min(255, pixel[c] * 255 / alpha)) }
            row[x * 4 + 3] = UInt8(alpha)
        }
        for pass in [Array(0..<width), Array((0..<width).reversed())] {
            var last: Int?
            for x in pass {
                if row[x * 4 + 3] > 0 { last = x }
                else if let source = last, pass.first == 0 || row[x * 4] == 0 && row[x * 4 + 1] == 0 && row[x * 4 + 2] == 0 {
                    for c in 0..<3 { row[x * 4 + c] = row[source * 4 + c] }
                }
            }
        }
    }
    try! out.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    print("Wrote \(name) (\(width)×\(height))")
}

func label(_ value: String, at point: NSPoint, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, alignment: NSTextAlignment = .center) {
    let style = NSMutableParagraphStyle(); style.alignment = alignment
    let lines = CGFloat(value.components(separatedBy: "\n").count)
    (value as NSString).draw(in: NSRect(x: point.x, y: point.y, width: width, height: size * 1.4 * lines),
                             withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}

// MARK: Panel

final class ClassicPanel: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

func panel(_ theme: PanelTheme, appearance: NSAppearance) -> NSView {
    if let view = theme.makeView() {
        view.appearance = appearance
        view.data = ThemeData(fiveHour: demo.five, weekly: demo.week, fiveReset: demo.fiveReset, weekReset: demo.weekReset, accessibility: "")
        view.frame = NSRect(x: 0, y: 0, width: 340, height: view.preferredContentHeight + view.outerInset)
        return view
    }
    let view = ClassicPanel(frame: .zero)
    view.appearance = appearance
    let five = QuotaTile(symbol: "5"), week = QuotaTile(symbol: "W")
    five.update(QuotaWindow(durationMinutes: 300, remaining: demo.five, reset: nil), reset: demo.fiveReset)
    week.update(QuotaWindow(durationMinutes: 10080, remaining: demo.week, reset: nil), reset: demo.weekReset)
    let extra = max(five.extraResetHeight, week.extraResetHeight)
    five.setExtraHeight(extra); week.setExtraHeight(extra)
    five.frame.origin = NSPoint(x: 12, y: 12); week.frame.origin = NSPoint(x: 176, y: 12)
    view.addSubview(five); view.addSubview(week)
    view.frame = NSRect(x: 0, y: 0, width: 340, height: 204 + extra)
    return view
}

// Draws a panel image as a floating popover: rounded corners, hairline border and soft shadow.
func drawFloating(_ image: NSImage, in rect: NSRect, dark: Bool, radius: CGFloat = 12) {
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    // The shadow comes from the clipped panel itself, so no dark underlay shows through its antialiased corners.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22)
    shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    let context = NSGraphicsContext.current!.cgContext
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    shape.addClip()
    image.draw(in: rect)
    context.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
    (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
    border.lineWidth = 0.5; border.stroke()
}

// MARK: Status item

func statusItem(_ values: [Double?], stale: Bool = false, both: [Double?]? = nil, appearance: NSAppearance) -> NSView {
    let item = NSView(frame: NSRect(x: 0, y: 0, width: both == nil ? 34 : 100, height: 20))
    item.appearance = appearance
    func addBars(_ values: [Double?], x: CGFloat) {
        let bars = Bars(frame: NSRect(x: x, y: 0, width: 32, height: 20))
        bars.values = values; bars.stale = stale
        item.addSubview(bars)
    }
    func addMark(_ provider: String, x: CGFloat) {
        let mark = ProviderMark(frame: NSRect(x: x, y: 3, width: 13, height: 13))
        mark.provider = provider
        item.addSubview(mark)
    }
    if let claude = both {
        addMark("Codex", x: 1); addBars(values, x: 17)
        addMark("Claude", x: 51); addBars(claude, x: 67)
    } else {
        addBars(values, x: 1)
    }
    return item
}

func menuBarColor(_ dark: Bool) -> NSColor { dark ? NSColor(white: 0.13, alpha: 0.82) : NSColor(white: 0.98, alpha: 0.78) }

func wallpaper(_ rect: NSRect, dark: Bool) {
    let colors = dark
        ? [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.24, green: 0.13, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.05, green: 0.22, blue: 0.30, alpha: 1)]
        : [NSColor(srgbRed: 0.62, green: 0.75, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.84, green: 0.74, blue: 0.96, alpha: 1), NSColor(srgbRed: 0.98, green: 0.82, blue: 0.76, alpha: 1)]
    NSGradient(colors: colors)!.draw(in: rect, angle: -28)
}

// MARK: Images

func renderThemes() {
    let heights = PanelTheme.allCases.map { panel($0, appearance: appearances[0].1).frame.height }
    let padding: CGFloat = 28
    let canvas = NSSize(width: 340 + padding * 2, height: heights.max()! + padding * 2)
    for theme in PanelTheme.allCases {
        for (name, appearance) in appearances {
            let view = panel(theme, appearance: appearance)
            let image = snapshot(view)
            let rep = render(canvas, appearance: appearance) {
                drawFloating(image, in: NSRect(x: padding, y: canvas.height - padding - view.frame.height, width: 340, height: view.frame.height), dark: isDark(appearance))
            }
            save(rep, "theme-\(theme.rawValue)-\(name).png")
        }
    }
}

func renderMenuBar() {
    let variants: [(String, [Double?], Bool, [Double?]?)] = [
        ("Codex", [72, 46], false, nil),
        ("Low quota", [17, 46], false, nil),
        ("Codex + Claude", [72, 46], false, [38, 81]),
        ("Previous data", [72, 46], true, nil),
    ]
    let zoom: CGFloat = 2.4, gap: CGFloat = 36, minimumCell: CGFloat = 140
    let widths = variants.map { max(minimumCell, ($0.3 == nil ? 34 : 100) * zoom + 36) }
    let size = NSSize(width: widths.reduce(0, +) + gap * CGFloat(variants.count + 1), height: 118)
    for (name, appearance) in appearances {
        let dark = isDark(appearance)
        let rep = render(size, appearance: appearance) {
            var x = gap
            for (index, variant) in variants.enumerated() {
                let item = statusItem(variant.1, stale: variant.2, both: variant.3, appearance: appearance)
                let image = snapshot(item, pixelScale: scale * zoom)
                let itemSize = NSSize(width: item.frame.width * zoom, height: item.frame.height * zoom)
                let cell = NSSize(width: widths[index], height: size.height)
                defer { x += cell.width + gap }
                let capsule = NSRect(x: x + (cell.width - itemSize.width) / 2 - 18, y: 46, width: itemSize.width + 36, height: itemSize.height + 22)
                let shape = NSBezierPath(roundedRect: capsule, xRadius: 14, yRadius: 14)
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                wallpaper(capsule.insetBy(dx: -40, dy: -40), dark: dark)
                menuBarColor(dark).setFill(); capsule.fill(using: .sourceOver)
                NSGraphicsContext.restoreGraphicsState()
                (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.08)).setStroke()
                shape.lineWidth = 1; shape.stroke()
                image.draw(in: NSRect(x: capsule.midX - itemSize.width / 2, y: capsule.midY - itemSize.height / 2, width: itemSize.width, height: itemSize.height))
                label(variant.0, at: NSPoint(x: x, y: 14), width: cell.width, size: 13, weight: .medium, color: .secondaryLabelColor)
            }
        }
        save(rep, "menubar-\(name).png")
    }
}

func renderHero() {
    let size = NSSize(width: 880, height: 300), bar: CGFloat = 30
    for (name, appearance) in appearances {
        let dark = isDark(appearance)
        let view = panel(.classic, appearance: appearance)
        let image = snapshot(view)
        let item = snapshot(statusItem([72, 46], appearance: appearance))
        let frame = NSRect(origin: .zero, size: size)
        let scene = render(size, appearance: appearance) {
            wallpaper(frame, dark: dark)
            let menuBar = NSRect(x: 0, y: size.height - bar, width: size.width, height: bar)
            menuBarColor(dark).setFill(); menuBar.fill(using: .sourceOver)
            // Right side of the menu bar: Limitwick, generic system items and the clock.
            var x = size.width - 16
            let clock = "Tue Nov 3  9:41"
            let clockFont = NSFont.systemFont(ofSize: 13, weight: .medium)
            let clockWidth = (clock as NSString).size(withAttributes: [.font: clockFont]).width
            x -= clockWidth
            (clock as NSString).draw(at: NSPoint(x: x, y: menuBar.minY + 7), withAttributes: [.font: clockFont, .foregroundColor: NSColor.labelColor])
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular).applying(.init(paletteColors: [.labelColor]))
            for symbol in ["switch.2", "magnifyingglass", "wifi", "battery.75percent"] {
                guard let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
                x -= icon.size.width + 16
                icon.draw(in: NSRect(x: x, y: menuBar.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
            }
            x -= 34 + 18
            let highlight = NSRect(x: x - 5, y: menuBar.minY + 3, width: 44, height: bar - 6)
            (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.10)).setFill()
            NSBezierPath(roundedRect: highlight, xRadius: 5, yRadius: 5).fill()
            item.draw(in: NSRect(x: x, y: menuBar.midY - 10, width: 34, height: 20))
            let panelRect = NSRect(x: min(highlight.midX - 170, size.width - 340 - 16), y: menuBar.minY - 8 - view.frame.height, width: 340, height: view.frame.height)
            drawFloating(image, in: panelRect, dark: dark)
            // Product name on the left half.
            label("Limitwick", at: NSPoint(x: 48, y: 142), width: 380, size: 40, weight: .bold, color: dark ? .white : NSColor(white: 0.08, alpha: 1), alignment: .left)
            label("Codex and Claude Code limits\nright in your menu bar.", at: NSPoint(x: 50, y: 74), width: 380, size: 19, color: dark ? NSColor(white: 1, alpha: 0.78) : NSColor(white: 0.1, alpha: 0.72), alignment: .left)
        }
        // Round the finished opaque scene in one pass, so the corners antialias against a single layer.
        let rep = render(size, appearance: appearance) {
            NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18).addClip()
            scene.draw(in: frame)
        }
        save(rep, "hero-\(name).png")
    }
}

@main struct ReadmeScreenshots {
    static func main() {
        _ = NSApplication.shared
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        renderThemes()
        renderMenuBar()
        renderHero()
    }
}
