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

// Compact text labels distinguish providers without changing the existing quota bars.
// Provider logos are not used: Anthropic declined permission for the Claude mark.
// The capital letters are as tall as `rect`, which the menu bar sets to the height of the two bars.
func drawProviderMark(_ provider: String, in rect: NSRect, color: NSColor) {
    func rounded(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .medium)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
    let probe = rounded(100)
    let font = rounded(rect.height * 100 / probe.capHeight)
    let label = NSAttributedString(string: provider == "Claude" ? "CL" : "CX",
                                   attributes: [.font: font, .foregroundColor: color, .kern: -0.2])
    let box = label.size()
    // Align the cap line, not the line box, so the glyphs match the bars' top and bottom edges.
    label.draw(at: NSPoint(x: rect.midX - box.width / 2, y: rect.midY - font.capHeight / 2 + font.descender))
}

final class ProviderMark: NSView {
    var provider = "Codex" { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { drawProviderMark(provider, in: bounds.insetBy(dx: 0, dy: 4), color: .labelColor) }
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
