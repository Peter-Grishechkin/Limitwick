import AppKit
import SwiftUI

// Renders README images from the real card, status bar and Sessions views with fixed demo values.
// Built and run by scripts/render-screenshots.sh, which also turns the Sessions frames into an animated PNG with ffmpeg.

let scale: CGFloat = 2
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images", isDirectory: true)
let framesOutput = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/readme-frames", isDirectory: true)
let appearances: [(String, NSAppearance)] = [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)]
let posix = Locale(identifier: "en_US_POSIX")
// One fixed moment for every image, so reset times, ages, session captions and the menu bar clock agree between runs.
let demoNow = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 41))!
let demoTime = demoNow.timeIntervalSince1970

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

/// A SwiftUI view of the app drawn at the README scale.
@MainActor func image<V: View>(_ view: V, _ size: NSSize, dark: Bool) -> NSImage {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, dark ? .dark : .light))
    renderer.scale = scale
    return NSImage(cgImage: renderer.cgImage!, size: size)
}

// Writes straight (non-premultiplied) RGBA. Fully transparent pixels take the colour of the nearest
// visible pixel in their row, so viewers that scale without premultiplying do not show a dark fringe.
func save(_ rep: NSBitmapImageRep, _ name: String, in folder: URL = output, quiet: Bool = false) {
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
    try! out.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    if !quiet { print("Wrote \(name) (\(width)×\(height))") }
}

func label(_ value: String, at point: NSPoint, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, alignment: NSTextAlignment = .center) {
    let style = NSMutableParagraphStyle(); style.alignment = alignment
    let lines = CGFloat(value.components(separatedBy: "\n").count)
    (value as NSString).draw(in: NSRect(x: point.x, y: point.y, width: width, height: size * 1.4 * lines),
                             withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}

/// Text that wraps inside `rect`, from its top.
func paragraph(_ value: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; style.lineSpacing = 2
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}

func rgb(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

/// Text colours of GitHub's light and dark themes, for captions on a transparent background.
func titleInk(_ dark: Bool) -> NSColor { rgb(dark ? 0xF0F6FC : 0x1F2328) }
func mutedInk(_ dark: Bool) -> NSColor { rgb(dark ? 0x9198A1 : 0x59636E) }

// MARK: Cards

struct DemoCard {
    var provider: String
    var five: Double
    var week: Double
    var theme: PanelTheme
    var fiveReset: TimeInterval = 2 * 3600 + 15 * 60
    var weekReset: TimeInterval = 4 * 86400 + 6 * 3600
    var model: QuotaCardModel {
        QuotaCardModel.make(provider: provider, five: five, week: week,
                            fiveReset: demoNow.addingTimeInterval(fiveReset), weekReset: demoNow.addingTimeInterval(weekReset),
                            stale: false, updated: demoNow.addingTimeInterval(-120), threshold: 20, now: demoNow, locale: posix)
    }
    static func codex(_ theme: PanelTheme) -> DemoCard { DemoCard(provider: "Codex", five: 72, week: 46, theme: theme) }
    static func claude(_ theme: PanelTheme) -> DemoCard {
        DemoCard(provider: "Claude", five: 38, week: 81, theme: theme, fiveReset: 3600 + 5 * 60, weekReset: 2 * 86400 + 19 * 3600)
    }
}

@MainActor func cardImage(_ card: DemoCard, dark: Bool) -> NSImage {
    image(QuotaCardView(model: card.model, theme: card.theme, scheme: dark ? .dark : .light), NSSize(width: 340, height: card.theme.cardHeight), dark: dark)
}

/// The panel and the Picture-in-Picture window: one card per provider, each in its own theme.
@MainActor func panelImage(_ cards: [DemoCard], dark: Bool) -> NSImage {
    let entries = cards.map { QuotaPanelEntry(id: $0.provider.lowercased(), model: $0.model, theme: $0.theme, scheme: nil, message: "") }
    return image(QuotaPanelView(entries: entries), NSSize(width: QuotaPanelLayout.width, height: QuotaPanelLayout.height(entries)), dark: dark)
}

/// A medium desktop widget: the card fitted to the widget with the theme background behind it, as in Widget/LimitwickWidget.swift.
let widgetSize = NSSize(width: 340, height: 160)
@MainActor func widgetImage(_ card: DemoCard, dark: Bool) -> NSImage {
    image(QuotaCardFit(model: card.model, theme: card.theme, scheme: dark ? .dark : .light).background(card.theme.tokens(dark: dark).bg.color),
          widgetSize, dark: dark)
}

// Draws a window or panel image floating: rounded corners, hairline border and soft shadow.
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

// MARK: Status item and desktop

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

/// A macOS menu bar across the top of `size` with Limitwick's status item highlighted; returns the highlight frame.
func drawMenuBar(_ size: NSSize, item: NSImage, dark: Bool) -> NSRect {
    let bar: CGFloat = 30
    let menuBar = NSRect(x: 0, y: size.height - bar, width: size.width, height: bar)
    menuBarColor(dark).setFill(); menuBar.fill(using: .sourceOver)
    // Right side: Limitwick, generic system items and the clock of the demo moment.
    var x = size.width - 16
    let formatter = DateFormatter(); formatter.locale = posix; formatter.dateFormat = "EEE MMM d  h:mm"
    let clock = formatter.string(from: demoNow)
    let clockFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    x -= (clock as NSString).size(withAttributes: [.font: clockFont]).width
    (clock as NSString).draw(at: NSPoint(x: x, y: menuBar.minY + 7), withAttributes: [.font: clockFont, .foregroundColor: NSColor.labelColor])
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular).applying(.init(paletteColors: [.labelColor]))
    for symbol in ["switch.2", "magnifyingglass", "wifi", "battery.75percent"] {
        guard let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
        x -= icon.size.width + 16
        icon.draw(in: NSRect(x: x, y: menuBar.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
    }
    x -= item.size.width + 18
    let highlight = NSRect(x: x - 5, y: menuBar.minY + 3, width: item.size.width + 10, height: bar - 6)
    (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.10)).setFill()
    NSBezierPath(roundedRect: highlight, xRadius: 5, yRadius: 5).fill()
    item.draw(in: NSRect(x: x, y: menuBar.midY - item.size.height / 2, width: item.size.width, height: item.size.height))
    return highlight
}

/// Rounds a finished opaque scene in one pass, so the corners antialias against a single layer.
func saveScene(_ scene: NSBitmapImageRep, _ size: NSSize, appearance: NSAppearance, _ name: String) {
    let frame = NSRect(origin: .zero, size: size)
    let rep = render(size, appearance: appearance) {
        NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18).addClip()
        scene.draw(in: frame)
    }
    save(rep, name)
}

// MARK: Sessions

/// A session ID whose hash gives the wanted outfit and hat colour, so every demo tile wears something different.
func demoID(_ headwear: SessionOutfit.Headwear, _ eyewear: SessionOutfit.Eyewear, hat: Int) -> String {
    for n in 0... {
        let id = "demo-\(n)"
        if SessionOutfit.of(id) == SessionOutfit(headwear: headwear, eyewear: eyewear) && SessionStore.hat(for: id, count: SessionMascot.hats.count) == hat {
            return id
        }
    }
    fatalError("no demo ID")
}

/// Hat colours, by index into SessionMascot.hats.
enum Hat { static let blue = 0, green = 1, white = 2, purple = 3, yellow = 4, pink = 5 }

/// A demo session whose turn started (or that last changed) `ago` seconds before the demo moment.
/// Names and titles are made up for the README.
func demoSession(_ provider: SessionProvider, _ headwear: SessionOutfit.Headwear, _ eyewear: SessionOutfit.Eyewear, hat: Int,
                 name: String, title: String? = nil, state: SessionState, ago: TimeInterval,
                 unseen: Bool = false, outcome: SessionOutcome? = nil) -> Session {
    let time = demoTime - ago
    return Session(provider: provider, id: demoID(headwear, eyewear, hat: hat), name: name, title: title, state: state,
                   started: time - 600, turnStarted: time, changed: time, unseen: unseen ? true : nil, outcome: outcome)
}

struct DemoTile {
    var session: Session
    var tool: SessionTool? = nil
    var moment: SessionMoment? = nil
    func look(_ now: TimeInterval, motion: Bool) -> SessionLook { SessionLook.of(session, moment: moment, tool: tool, now: now, motion: motion) }
}

/// The animation loop: 48 frames of SessionLook.fastTick, 3.84 s. That is a whole number of walking, typing,
/// cursor and stripe cycles, so the animation loops without a jump.
let loopFrames = 48

/// The Sessions window `t` seconds into the loop. Three tiles change during the loop: a turn finishes, a tool call fails
/// and a turn fails; the rest keep their state.
func demoTiles(at t: TimeInterval) -> [DemoTile] {
    var tiles = [
        DemoTile(session: demoSession(.claude, .cap, .none, hat: Hat.blue, name: "auth-service", title: "Fix login redirect loop", state: .working, ago: 4 * 60)),
        DemoTile(session: demoSession(.codex, .topHat, .sunglasses, hat: Hat.green, name: "weather-app", state: .working, ago: 2 * 60),
                 tool: SessionTool(id: "shell", kind: .shell)),
        DemoTile(session: demoSession(.claude, .headphones, .none, hat: Hat.pink, name: "blog", state: .working, ago: 70),
                 tool: SessionTool(id: "edit", kind: .edit)),
        DemoTile(session: demoSession(.claude, .crown, .monocle, hat: Hat.yellow, name: "mobile-app", title: "Plan the v3 onboarding", state: .waiting, ago: 190)),
    ]
    // Finishes its turn at 0.48 s: a jump and a check, then it falls asleep with a green light.
    let finish = 0.48
    var landing = demoSession(.claude, .beanie, .sunglasses, hat: Hat.purple, name: "landing-page", state: .working, ago: 6 * 60)
    if t >= finish { landing.state = .idle; landing.changed = demoTime + finish; landing.unseen = true }
    tiles.append(DemoTile(session: landing, moment: t >= finish ? SessionMoment(kind: .finished, at: demoTime + finish) : nil))
    // A tool call fails at 2.24 s: a shake and "!", then back to work.
    let toolError = 2.24
    let api = demoSession(.codex, .beanie, .monocle, hat: Hat.pink, name: "api-server", state: .working, ago: 3 * 60)
    tiles.append(t < toolError ? DemoTile(session: api, tool: SessionTool(id: "read", kind: .read))
                               : DemoTile(session: api, moment: SessionMoment(kind: .toolFailed, at: demoTime + toolError)))
    // The turn fails at 1.6 s: a shake, crossed eyes, the sunglasses fall off and a red light comes on.
    let failure = 1.6
    var dotfiles = demoSession(.claude, .topHat, .sunglasses, hat: Hat.white, name: "dotfiles", state: .working, ago: 2 * 60)
    if t >= failure { dotfiles.state = .idle; dotfiles.changed = demoTime + failure; dotfiles.unseen = true; dotfiles.outcome = .failed }
    tiles.append(DemoTile(session: dotfiles, moment: t >= failure ? SessionMoment(kind: .failed, at: demoTime + failure) : nil))
    tiles.append(DemoTile(session: demoSession(.codex, .headphones, .sunglasses, hat: Hat.blue, name: "notes", state: .idle, ago: 25 * 60)))
    return tiles
}

let sessionsBackground = Color(red: 15 / 255, green: 16 / 255, blue: 18 / 255)
let tileFill = rgb(0x18191C), tileBorder = rgb(0x2A2C30)

/// The Sessions window as SessionGridView lays it out, with the real tiles at a fixed time instead of its clock.
struct DemoSessionsWindow: View {
    let tiles: [DemoTile]
    let now: TimeInterval
    var motion = true
    var size: CGSize { SessionGridLayout.size(limit: tiles.count) }
    var body: some View {
        let columns = SessionGridLayout.columns
        VStack(alignment: .leading, spacing: SessionGridLayout.gap) {
            ForEach(0..<(tiles.count + columns - 1) / columns, id: \.self) { row in
                HStack(spacing: SessionGridLayout.gap) {
                    ForEach(row * columns..<min(tiles.count, row * columns + columns), id: \.self) { index in
                        SessionTileView(session: tiles[index].session, now: now, look: tiles[index].look(now, motion: motion))
                    }
                }
            }
        }
        .padding(SessionGridLayout.padding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(sessionsBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor func sessionsImage(_ tiles: [DemoTile], at t: TimeInterval) -> NSImage {
    let window = DemoSessionsWindow(tiles: tiles, now: demoTime + t)
    return image(window, NSSize(width: window.size.width, height: window.size.height), dark: true)
}

/// The still window of the hero: the loop near its end, with the finished turn two minutes old,
/// so it shows a green light and "done · 2m ago" next to the failed turn and the tool error.
func heroTiles() -> [DemoTile] {
    var tiles = demoTiles(at: 3.0)
    tiles[4].session.changed = demoTime - 120
    tiles[4].moment = nil
    return tiles
}

@MainActor func tileImage(_ tile: DemoTile, at t: TimeInterval = 0, motion: Bool) -> NSImage {
    let size = NSSize(width: SessionGridLayout.tile.width, height: SessionGridLayout.tile.height)
    return image(SessionTileView(session: tile.session, now: demoTime + t, look: tile.look(demoTime + t, motion: motion)), size, dark: true)
}

// MARK: Images

@MainActor func renderIcon() {
    guard let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") else { print("Resources/AppIcon.icns not found"); return }
    let size = NSSize(width: 128, height: 128)
    save(render(size, appearance: appearances[0].1) { icon.draw(in: NSRect(origin: .zero, size: size)) }, "icon.png")
}

@MainActor func renderHero() {
    let size = NSSize(width: 1040, height: 520)
    let sessions = sessionsImage(heroTiles(), at: 3.0)
    for (name, appearance) in appearances {
        let dark = isDark(appearance)
        let panel = panelImage([.codex(.industrial), .claude(.terminal)], dark: dark)
        let item = snapshot(statusItem([72, 46], both: [38, 81], appearance: appearance))
        let scene = render(size, appearance: appearance) {
            wallpaper(NSRect(origin: .zero, size: size), dark: dark)
            let highlight = drawMenuBar(size, item: item, dark: dark)
            let panelRect = NSRect(x: min(highlight.midX - panel.size.width / 2, size.width - panel.size.width - 16), y: highlight.minY - 11 - panel.size.height,
                                   width: panel.size.width, height: panel.size.height)
            drawFloating(panel, in: panelRect, dark: dark)
            drawFloating(sessions, in: NSRect(x: 56, y: 40, width: sessions.size.width, height: sessions.size.height), dark: dark)
            let ink = dark ? NSColor.white : NSColor(white: 0.08, alpha: 1)
            label("Limitwick", at: NSPoint(x: 54, y: size.height - 120), width: 440, size: 44, weight: .bold, color: ink, alignment: .left)
            label("Codex and Claude Code limits and sessions,\nright in your menu bar.", at: NSPoint(x: 57, y: size.height - 192), width: 460, size: 19,
                  color: ink.withAlphaComponent(dark ? 0.78 : 0.72), alignment: .left)
        }
        saveScene(scene, size, appearance: appearance, "hero-\(name).png")
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
                label(variant.0, at: NSPoint(x: x, y: 14), width: cell.width, size: 13, weight: .medium, color: mutedInk(dark))
            }
        }
        save(rep, "menubar-\(name).png")
    }
}

/// All four themes in one 2 × 2 image per appearance, Codex and Claude mixed, one card below the warning threshold.
@MainActor func renderThemes() {
    let cards: [DemoCard] = [.codex(.industrial), DemoCard(provider: "Claude", five: 14, week: 81, theme: .dots, fiveReset: 3600 + 5 * 60, weekReset: 2 * 86400 + 19 * 3600),
                             .codex(.paper), .claude(.terminal)]
    let padding: CGFloat = 28, gap: CGFloat = 32, caption: CGFloat = 26
    let rows = [max(cards[0].theme.cardHeight, cards[1].theme.cardHeight), max(cards[2].theme.cardHeight, cards[3].theme.cardHeight)]
    let size = NSSize(width: padding * 2 + 340 * 2 + gap, height: padding * 2 + gap + rows.reduce(0, +) + caption * 2)
    for (name, appearance) in appearances {
        let dark = isDark(appearance)
        let rep = render(size, appearance: appearance) {
            for (index, card) in cards.enumerated() {
                let column = CGFloat(index % 2), row = index / 2
                let top = padding + (row == 0 ? 0 : rows[0] + caption + gap)
                let x = padding + column * (340 + gap)
                label(card.theme.title, at: NSPoint(x: x + 2, y: size.height - top - 20), width: 340, size: 14, weight: .semibold, color: titleInk(dark), alignment: .left)
                drawFloating(cardImage(card, dark: dark), in: NSRect(x: x, y: size.height - top - caption - card.theme.cardHeight, width: 340, height: card.theme.cardHeight), dark: dark)
            }
        }
        save(rep, "themes-\(name).png")
    }
}

/// Two desktop widgets and the Picture-in-Picture window on the desktop.
@MainActor func renderWidgets() {
    let size = NSSize(width: 880, height: 420)
    for (name, appearance) in appearances {
        let dark = isDark(appearance)
        let widgets = [widgetImage(.codex(.dots), dark: dark), widgetImage(.claude(.paper), dark: dark)]
        let pip = panelImage([.codex(.industrial), .claude(.terminal)], dark: dark)
        let scene = render(size, appearance: appearance) {
            wallpaper(NSRect(origin: .zero, size: size), dark: dark)
            let column = widgetSize.height * 2 + 24
            for (index, widget) in widgets.enumerated() {
                let top = (size.height - column) / 2 + CGFloat(index) * (widgetSize.height + 24)
                drawFloating(widget, in: NSRect(x: 56, y: size.height - top - widgetSize.height, width: widgetSize.width, height: widgetSize.height), dark: dark, radius: 22)
            }
            drawFloating(pip, in: NSRect(x: size.width - 56 - pip.size.width, y: (size.height - pip.size.height) / 2, width: pip.size.width, height: pip.size.height), dark: dark)
        }
        saveScene(scene, size, appearance: appearance, "widgets-\(name).png")
    }
}

/// Frames of the animated Sessions window, floating with its shadow, for ffmpeg in render-screenshots.sh.
@MainActor func renderSessionsFrames() {
    try? FileManager.default.removeItem(at: framesOutput)
    try! FileManager.default.createDirectory(at: framesOutput, withIntermediateDirectories: true)
    let window = SessionGridLayout.size(limit: demoTiles(at: 0).count)
    let side: CGFloat = 26, bottom: CGFloat = 34
    let size = NSSize(width: window.width + side * 2, height: window.height + side + bottom)
    for frame in 0..<loopFrames {
        // The middle of each frame, so no step boundary falls on a sample.
        let t = (Double(frame) + 0.5) * SessionLook.fastTick
        let picture = sessionsImage(demoTiles(at: t), at: t)
        let rep = render(size, appearance: appearances[1].1) {
            drawFloating(picture, in: NSRect(x: side, y: bottom, width: window.width, height: window.height), dark: false)
        }
        save(rep, String(format: "sessions-%02d.png", frame), in: framesOutput, quiet: true)
    }
    print("Wrote \(loopFrames) Sessions frames to \(framesOutput.path)")
}

/// The ten outfits in a row: every headwear on Claude and on Codex, with the eyewear and hat colours mixed.
@MainActor func renderOutfits() {
    let items: [(SessionProvider, SessionOutfit.Headwear, SessionOutfit.Eyewear, Int)] = [
        (.claude, .cap, .none, Hat.blue), (.codex, .cap, .sunglasses, Hat.green),
        (.claude, .topHat, .sunglasses, Hat.pink), (.codex, .topHat, .none, Hat.yellow),
        (.claude, .beanie, .none, Hat.green), (.codex, .beanie, .monocle, Hat.pink),
        (.claude, .crown, .sunglasses, Hat.yellow), (.codex, .crown, .none, Hat.purple),
        (.claude, .headphones, .monocle, Hat.blue), (.codex, .headphones, .sunglasses, Hat.white),
    ]
    var standing = SessionLook(); standing.lift = 1
    let cell: CGFloat = 80, gap: CGFloat = 8
    let size = NSSize(width: cell * CGFloat(items.count) + gap * CGFloat(items.count - 1), height: cell)
    let mascots = items.map { item in
        image(SessionMascotView(provider: item.0, hat: item.3, outfit: SessionOutfit(headwear: item.1, eyewear: item.2), look: standing),
              NSSize(width: SessionMascot.frame.width, height: SessionMascot.frame.height), dark: true)
    }
    let rep = render(size, appearance: appearances[1].1) {
        for (index, mascot) in mascots.enumerated() {
            let box = NSRect(x: CGFloat(index) * (cell + gap), y: 0, width: cell, height: cell)
            let shape = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            tileFill.setFill(); shape.fill()
            tileBorder.setStroke(); shape.lineWidth = 1; shape.stroke()
            mascot.draw(in: NSRect(x: box.midX - mascot.size.width / 2, y: box.midY - mascot.size.height / 2, width: mascot.size.width, height: mascot.size.height))
        }
    }
    save(rep, "session-outfits.png")
}

/// Every tile state with a caption, and the tool icons below: the legend of the Sessions window.
@MainActor func renderSessionStates() {
    let tiles = demoTiles(at:)
    let states: [(DemoTile, TimeInterval, Bool, String, String)] = [
        (tiles(0.04)[0], 0.04, true, "Working", "The figure steps in place; the cloud blinks the _ of its >_ face."),
        (tiles(0.04)[2], 0.04, true, "Running a tool", "Typing hands or a running _, with the kind of tool by the head."),
        (tiles(2.7)[5], 2.7, true, "Tool failed", "A shake and a red !, then back to work."),
        (tiles(0)[3], 0, false, "Waiting for you", "Claude Code asks for permission. The caption gets hungrier as it waits."),
        (tiles(0.88)[4], 0.88, true, "Turn finished", "A jump and a green check, then the mascot falls asleep."),
        (DemoTile(session: demoSession(.codex, .cap, .none, hat: Hat.yellow, name: "scraper", state: .idle, ago: 2 * 60, unseen: true)), 0, false,
         "New result", "Green light: the turn finished and you have not opened the session yet."),
        (DemoTile(session: demoSession(.claude, .crown, .none, hat: Hat.green, name: "website", state: .idle, ago: 2 * 3600 + 600)), 0, false,
         "Idle", "One z under an hour, two under six hours, three after that."),
        (DemoTile(session: demoSession(.claude, .topHat, .sunglasses, hat: Hat.white, name: "dotfiles", state: .idle, ago: 3 * 60, unseen: true, outcome: .failed)), 0, false,
         "Failed", "The error knocks the glasses off. The red light stays until you open the session."),
        (DemoTile(session: demoSession(.codex, .beanie, .none, hat: Hat.blue, name: "scripts", state: .idle, ago: 40 * 60, outcome: .lost)), 0, false,
         "Lost", "Silent for 30 minutes, or its process exited during a turn."),
    ]
    let tools: [(ToolKind, String)] = [(.edit, "edit"), (.shell, "shell"), (.read, "read"), (.search, "search"), (.web, "web"),
                                       (.agent, "subagent"), (.plan, "plan"), (.mcp, "MCP"), (.other, "other")]
    let tile = SessionGridLayout.tile
    let text: CGFloat = 170, inner: CGFloat = 14, gap: CGFloat = 22, margin: CGFloat = 8
    let cell = tile.width + inner + text
    let grid = NSSize(width: cell * 3 + gap * 2, height: tile.height * 3 + gap * 2)
    let chip: CGFloat = 32, toolsTop = margin + grid.height + 34
    let size = NSSize(width: grid.width + margin * 2, height: toolsTop + chip + 26 + margin)
    let pictures = states.map { tileImage($0.0, at: $0.1, motion: $0.2) }
    for (name, appearance) in appearances {
        let dark = isDark(appearance)
        let rep = render(size, appearance: appearance) {
            for (index, state) in states.enumerated() {
                let x = margin + CGFloat(index % 3) * (cell + gap)
                let top = margin + CGFloat(index / 3) * (tile.height + gap)
                pictures[index].draw(in: NSRect(x: x, y: size.height - top - tile.height, width: tile.width, height: tile.height))
                let textX = x + tile.width + inner
                paragraph(state.3, in: NSRect(x: textX, y: size.height - top - 40, width: text, height: 20), size: 14, weight: .semibold, color: titleInk(dark))
                paragraph(state.4, in: NSRect(x: textX, y: size.height - top - 112, width: text, height: 70), size: 12.5, color: mutedInk(dark))
            }
            // Tool icons in 4 pt pixels on a tile-coloured chip.
            let step = grid.width / CGFloat(tools.count)
            for (index, tool) in tools.enumerated() {
                let center = margin + step * (CGFloat(index) + 0.5)
                let box = NSRect(x: center - chip / 2, y: size.height - toolsTop - chip, width: chip, height: chip)
                let shape = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
                tileFill.setFill(); shape.fill()
                tileBorder.setStroke(); shape.lineWidth = 1; shape.stroke()
                rgb(0xB4B9C0).setFill()
                for (row, line) in (SessionMascot.tools[tool.0] ?? []).enumerated() {
                    for (column, mark) in line.enumerated() where mark != "." {
                        NSRect(x: box.minX + 6 + CGFloat(column) * 4, y: box.maxY - 6 - CGFloat(row + 1) * 4, width: 4, height: 4).fill()
                    }
                }
                label(tool.1, at: NSPoint(x: center - step / 2, y: box.minY - 22), width: step, size: 12, color: mutedInk(dark))
            }
        }
        save(rep, "session-states-\(name).png")
    }
}

@main struct ReadmeScreenshots {
    @MainActor static func main() {
        _ = NSApplication.shared
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        renderIcon()
        renderHero()
        renderMenuBar()
        renderThemes()
        renderWidgets()
        renderOutfits()
        renderSessionStates()
        renderSessionsFrames()
    }
}
