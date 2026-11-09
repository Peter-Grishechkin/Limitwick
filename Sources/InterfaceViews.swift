import AppKit

final class Bars: NSView {
    var values: [Double?] = [nil, nil] { didSet { needsDisplay = true } }
    var stale = false { didSet { needsDisplay = true } }
    var warningThreshold = 20 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<2 {
            let rect = NSRect(x: 1, y: 4 + CGFloat(i) * 8, width: 30, height: 4)
            NSColor.labelColor.withAlphaComponent(stale ? 0.12 : 0.25).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            if let value = values[i] {
                let width = rect.width * max(0, min(1, value / 100))
                if width > 0 {
                    (isLowQuota(value, threshold: warningThreshold) ? NSColor.systemRed : NSColor.labelColor).withAlphaComponent(stale ? 0.35 : 1).setFill()
                    NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: max(2, width), height: rect.height), xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }
}

// A shared surface lets each window follow the panel's palette and appearance.
class ThemedSurface: NSView {
    var paletteProvider: ((NSAppearance) -> ThemePalette)?
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        onAppearanceChange?()
    }
    override func draw(_ dirtyRect: NSRect) {
        (paletteProvider?(effectiveAppearance).background ?? .windowBackgroundColor).setFill()
        bounds.fill()
    }
}

final class MenuButton: NSButton {
    var paletteProvider: (() -> ThemePalette)?
    var shortcut = ""
    var dismiss: (() -> Void)?
    var fontProvider: (() -> NSFont)?
    var highlightsUpdate = false { didSet { needsDisplay = true } }
    var keyboardSelected = false { didSet { needsDisplay = true } }
    private var hovered = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func draw(_ dirtyRect: NSRect) {
        guard let p = paletteProvider?() else { return }
        let selected = isEnabled && (hovered || keyboardSelected)
        // Rows stay clear at rest like a native menu; only the selected row and an update offer are filled.
        let background = highlightsUpdate
            ? (p.background.blended(withFraction: selected ? 0.36 : 0.24, of: .systemBlue) ?? p.surface)
            : selected ? (p.background.blended(withFraction: 0.14, of: p.text) ?? p.surface) : nil
        if let background = background {
            background.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        let foreground = isEnabled ? p.text : p.secondary.withAlphaComponent(0.55)
        let font = fontProvider?() ?? NSFont.systemFont(ofSize: 13, weight: .regular)
        let shortcutFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 12, y: (bounds.height - 17) / 2, width: bounds.width - (shortcut.isEmpty ? 24 : 75), height: 18), withAttributes: [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph])
        let right = NSMutableParagraphStyle(); right.alignment = .right
        (shortcut as NSString).draw(in: NSRect(x: bounds.width - 60, y: (bounds.height - 16) / 2, width: 48, height: 17), withAttributes: [.font: shortcutFont, .foregroundColor: p.secondary, .paragraphStyle: right])
    }
    override func keyDown(with event: NSEvent) {
        guard let siblings = superview?.subviews.compactMap({ $0 as? MenuButton }), let index = siblings.firstIndex(of: self) else { super.keyDown(with: event); return }
        if event.keyCode == 53 { dismiss?(); return }
        if event.keyCode == 125 || event.keyCode == 126 {
            let step = event.keyCode == 125 ? 1 : -1
            for offset in 1...siblings.count {
                let next = siblings[(index + step * offset + siblings.count * 2) % siblings.count]
                if next.isEnabled {
                    siblings.forEach { $0.keyboardSelected = false }
                    next.keyboardSelected = true; window?.makeFirstResponder(next); return
                }
            }
        }
        if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 { performClick(nil); return }
        super.keyDown(with: event)
    }
}

final class MenuSeparator: NSView {
    var paletteProvider: (() -> ThemePalette)?
    override func draw(_ dirtyRect: NSRect) {
        guard let p = paletteProvider?() else { return }
        p.text.withAlphaComponent(0.14).setFill()
        NSRect(x: 12, y: floor(bounds.midY), width: bounds.width - 24, height: 1).fill()
    }
}

final class MenuView: ThemedSurface {
    override var acceptsFirstResponder: Bool { true }
    var dismiss: (() -> Void)?
    var items: [MenuButton] = []
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss?(); return }
        if event.keyCode == 125 || event.keyCode == 126 {
            let candidates = event.keyCode == 125 ? items : items.reversed()
            if let first = candidates.first(where: { $0.isEnabled }) {
                first.keyboardSelected = true; window?.makeFirstResponder(first)
            }
            return
        }
        super.keyDown(with: event)
    }
}

final class UpdateBadge: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

// Menu bar provider marks in the bar's own colour: a cloud with a prompt for Codex, Claude Code's pixel mascot for Claude.
// Drawn in an unflipped 20 pt tall view; the glyphs span y 4…16 like the bars.
func drawProviderMark(_ provider: String, in rect: NSRect, color: NSColor) {
    let image = NSImage(size: rect.size, flipped: false) { bounds in
        color.setFill()
        let midX = bounds.midX.rounded(.down), midY = bounds.midY
        if provider == "Claude" {
            // Claude Code's terminal art: 16 × 5 cells, body, arms, eyes and legs. Cells are 1 pt wide and 2.5 pt
            // tall (2 pt for the legs) so the mascot fills the bars' 12 pt like the cloud and stays crisp on Retina.
            let rows: [[ClosedRange<Int>]] = [[2...13], [2...3, 5...10, 12...13], [0...15], [2...13], [3...3, 5...5, 10...10, 12...12]]
            let heights: [CGFloat] = [2.5, 2.5, 2.5, 2.5, 2]
            var top = midY + 6
            let left = midX - 8
            for (row, spans) in rows.enumerated() {
                top -= heights[row]
                for span in spans {
                    NSRect(x: left + CGFloat(span.lowerBound), y: top, width: CGFloat(span.count), height: heights[row]).fill()
                }
            }
        } else {
            let x = bounds.midX - 8.5, y = midY - 6
            let cloud = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 9, height: 9))
            cloud.append(NSBezierPath(ovalIn: NSRect(x: x + 3.5, y: y + 2, width: 10, height: 10)))
            cloud.append(NSBezierPath(ovalIn: NSRect(x: x + 9, y: y, width: 8, height: 8)))
            cloud.append(NSBezierPath(roundedRect: NSRect(x: x + 3, y: y, width: 11, height: 5), xRadius: 2, yRadius: 2))
            cloud.fill()
            let prompt = NSBezierPath()
            prompt.move(to: NSPoint(x: x + 5.5, y: y + 7.5)); prompt.line(to: NSPoint(x: x + 7.75, y: y + 5.5)); prompt.line(to: NSPoint(x: x + 5.5, y: y + 3.5))
            prompt.move(to: NSPoint(x: x + 9.25, y: y + 3.5)); prompt.line(to: NSPoint(x: x + 12, y: y + 3.5))
            prompt.lineWidth = 1.5; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round
            NSGraphicsContext.current?.compositingOperation = .clear
            prompt.stroke()
        }
        return true
    }
    image.draw(in: rect)
}

final class ProviderMark: NSView {
    var provider = "Codex" { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { drawProviderMark(provider, in: bounds, color: .labelColor) }
}

struct ProviderPresentation {
    let name: String
    let quota: Quota?
    let stale: Bool
    let status: String
    let updated: Date?
    /// Raw refresh failure ("Codex CLI not found…"); nil when the last refresh worked.
    var failure: String? = nil
    var running = false
}
