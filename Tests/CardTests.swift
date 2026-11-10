import SwiftUI
import AppKit

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    if !condition() { fatalError("FAILED (line \(line)): \(message)") }
}

/// Mean of alpha × luminance: roughly how much of the image survives as opaque white in vibrant rendering (0…1).
func vibrantCoverage(_ image: CGImage) -> Double {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var sum = 0.0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        // Premultiplied channels already carry alpha.
        sum += (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
    }
    return sum / Double(w * h)
}

@main struct CardTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let now = Date()
        let five = now.addingTimeInterval(2 * 3600 + 15 * 60), week = now.addingTimeInterval(3 * 86400 + 4 * 3600)
        let updated = now.addingTimeInterval(-120), old = now.addingTimeInterval(-12 * 60)

        // Model: two-line reset and the single footer in every state.
        let normal = QuotaCardModel.make(provider: "Codex", five: 72, week: 41, fiveReset: five, weekReset: week, stale: false, updated: updated, threshold: 20, now: now)
        check(normal.five.resetLine == "RST 2h 15m" && normal.week.resetLine == "RST 3d 4h", "reset first line")
        check(!normal.five.resetTime.isEmpty && normal.footer == "Codex · Updated 2 min ago", "footer \(normal.footer)")
        let previous = QuotaCardModel.make(provider: "Codex", five: 72, week: 41, fiveReset: five, weekReset: week, stale: true, updated: old, threshold: 20, now: now)
        check(previous.footer == "Codex · Previous data · Updated 12 min ago", "previous footer \(previous.footer)")
        let empty = QuotaCardModel.make(provider: "Claude", five: nil, week: nil, fiveReset: nil, weekReset: nil, stale: false, loading: true, updated: nil, threshold: 20, now: now)
        check(empty.footer == "Claude · Loading…" && empty.five.resetLine == "Reset unavailable" && empty.five.remaining == nil, "empty model")
        let none = QuotaCardModel.make(provider: "Claude", five: nil, week: nil, fiveReset: nil, weekReset: nil, stale: false, updated: nil, threshold: 20, now: now)
        check(none.footer == "Claude · No data yet", "no data footer")
        check(normal.accessibility.contains("72 percent remaining") && normal.accessibility.hasSuffix("Updated 2 min ago"), "accessibility")

        // Theme migration: removed themes land on Industrial.
        check(PanelTheme(stored: "classic") == .industrial && PanelTheme(stored: "capsules") == .industrial && PanelTheme(stored: nil) == .industrial && PanelTheme(stored: "terminal") == .terminal, "theme migration")
        check(PanelTheme.allCases.map(\.rawValue) == ["industrial", "dots", "paper", "terminal"], "themes")

        // Panel layout: card heights are fixed per theme; a message adds its own height.
        let entry = QuotaPanelEntry(id: "codex", model: normal, theme: .industrial, scheme: nil, message: "")
        check(QuotaPanelLayout.height([entry]) == 170, "industrial height")
        check(QuotaPanelLayout.height([QuotaPanelEntry(id: "p", model: normal, theme: .paper, scheme: nil, message: "")]) == 182, "paper height")
        let failure = "Codex CLI not found. Install it or add it to your PATH."
        let withMessage = QuotaPanelEntry(id: "codex", model: normal, theme: .industrial, scheme: nil, message: failure)
        check(withMessage.height > 170 + 20 && withMessage.height < 170 + 80, "message height \(withMessage.height)")
        let long = QuotaPanelEntry(id: "codex", model: normal, theme: .industrial, scheme: nil, message: String(repeating: failure + " ", count: 6))
        check(long.messageHeight > withMessage.messageHeight * 2, "long message wraps")

        // Render every theme × mode × state to build/card-*.png; the files are compared with the Penpot boards by eye.
        let low = QuotaCardModel.make(provider: "Codex", five: 12, week: 8, fiveReset: five, weekReset: week, stale: false, updated: updated, threshold: 20, now: now)
        for theme in PanelTheme.allCases {
            for (modeName, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                for (state, model) in [("normal", normal), ("low", low), ("previous", previous), ("empty", empty)] {
                    let view = QuotaCardView(model: model, theme: theme, scheme: scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.cgImage else { fatalError("No image for \(theme) \(modeName) \(state)") }
                    check(image.width == 680 && image.height == Int(theme.cardHeight) * 2, "size \(image.width)x\(image.height)")
                    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/card-\(theme.rawValue)-\(modeName)-\(state).png"))
                }
            }
            // Popover with both providers, a failure under the first card.
            let claude = QuotaCardModel.make(provider: "Claude", five: 45, week: 84, fiveReset: five, weekReset: week, stale: false, updated: updated, threshold: 20, now: now)
            let entries = [QuotaPanelEntry(id: "codex", model: previous, theme: theme, scheme: .light, message: failure), QuotaPanelEntry(id: "claude", model: claude, theme: theme, scheme: .dark, message: "")]
            let panel = ImageRenderer(content: QuotaPanelView(entries: entries))
            panel.scale = 2
            try! NSBitmapImageRep(cgImage: panel.cgImage!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/card-panel-\(theme.rawValue).png"))
        }
        // Widget: the card scales to fit the family size (medium is about 364×170) instead of being cropped.
        for theme in PanelTheme.allCases {
            let fit = ImageRenderer(content: QuotaCardFit(model: normal, theme: theme, scheme: .light).frame(width: 364, height: 170).background(Color.white))
            fit.scale = 2
            guard let image = fit.cgImage else { fatalError("No widget image") }
            check(image.width == 728 && image.height == 340, "widget size")
            try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/widget-\(theme.rawValue).png"))
        }
        // Inactive desktop widget (vibrant rendering): macOS drops the container background and maps luminance to opacity,
        // so a card that paints its own light background turns into a plain white block. Only the ink may stay bright.
        for theme in PanelTheme.allCases {
            let fit = ImageRenderer(content: QuotaCardFit(model: normal, theme: theme, scheme: .light, vibrant: true).frame(width: 364, height: 170))
            fit.scale = 1
            guard let image = fit.cgImage else { fatalError("No vibrant widget image") }
            let coverage = vibrantCoverage(image)
            check(coverage < 0.3, "\(theme.rawValue) vibrant widget is a bright block (coverage \(coverage))")
            try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/widget-\(theme.rawValue)-vibrant.png"))
        }
        print("Card tests passed (model, footer, migration, layout; \(PanelTheme.allCases.count) themes rendered, VT323 \(CardFonts.terminalAvailable ? "loaded" : "missing"))")
    }
}
