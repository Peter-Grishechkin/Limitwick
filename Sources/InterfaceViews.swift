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

final class QuotaTile: NSView {
    let symbol: String
    let ring = RingView()
    let symbolLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "—")
    let resetLabel = NSTextField(wrappingLabelWithString: "Reset unavailable")

    init(symbol: String) {
        self.symbol = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: 152, height: 180))
        ring.frame = NSRect(x: 31, y: 77, width: 90, height: 90)
        // The percentage is the reading; the period letter inside the ring only labels it.
        symbolLabel.stringValue = symbol
        symbolLabel.font = .systemFont(ofSize: 22, weight: .medium)
        symbolLabel.textColor = .secondaryLabelColor
        symbolLabel.alignment = .center
        symbolLabel.frame = NSRect(x: 31, y: 107, width: 90, height: 30)
        valueLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: 8, y: 43, width: 136, height: 33)
        resetLabel.font = .systemFont(ofSize: 11)
        // The system secondary gray is 3.9:1 on the light tile; a darker gray keeps 4.5:1.
        resetLabel.textColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .secondaryLabelColor : NSColor(white: 0.40, alpha: 1) }
        resetLabel.alignment = .center
        resetLabel.maximumNumberOfLines = 0
        resetLabel.frame = NSRect(x: 6, y: 8, width: 140, height: 34)
        for view in [ring, symbolLabel, valueLabel, resetLabel] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        update(nil, reset: "Reset unavailable")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.56).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }
    var extraResetHeight: CGFloat {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        return max(0, ceil((resetLabel.stringValue as NSString).boundingRect(with: NSSize(width: 140, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: resetLabel.font!, .paragraphStyle: style]).height) - 34)
    }
    func setExtraHeight(_ extra: CGFloat) {
        frame.size.height = 180 + extra
        resetLabel.frame.size.height = 34 + extra
        ring.frame.origin.y = 77 + extra
        symbolLabel.frame.origin.y = 107 + extra
        valueLabel.frame.origin.y = 43 + extra
    }
    func update(_ window: QuotaWindow?, reset: String, stale: Bool = false) {
        ring.value = window?.remaining
        ring.stale = stale
        valueLabel.stringValue = window.map { "\(Int($0.remaining.rounded()))%" } ?? "—"
        resetLabel.stringValue = reset
        let period = symbol == "5" ? "5 hours" : "Week"
        setAccessibilityLabel("\(period), \(window == nil ? "unavailable" : valueLabel.stringValue + " remaining"), \(reset)")
    }
}

final class RingView: NSView {
    var value: Double? { didSet { needsDisplay = true } }
    var warningThreshold = 20 { didSet { needsDisplay = true } }
    var stale = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 6)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = 8
        NSColor.tertiaryLabelColor.withAlphaComponent(0.32).setStroke()
        track.stroke()
        guard let value = value, value > 0 else { return }
        let fraction = max(0, min(1, value / 100))
        let path = NSBezierPath()
        path.lineWidth = 8
        path.lineCapStyle = .round
        if fraction >= 1 { path.appendOval(in: rect) }
        else {
            path.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: rect.width / 2,
                           startAngle: 90, endAngle: 90 - CGFloat(360 * fraction), clockwise: true)
        }
        (isLowQuota(value, threshold: warningThreshold) ? NSColor.systemRed : NSColor.systemBlue).withAlphaComponent(stale ? 0.4 : 1).setStroke()
        path.stroke()
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
func drawProviderMark(_ provider: String, in rect: NSRect, color: NSColor) {
    let size = min(rect.width, rect.height) * 0.66
    let heavy = NSFont.systemFont(ofSize: size, weight: .heavy)
    let font = heavy.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? heavy
    let label = NSAttributedString(string: provider == "Claude" ? "CL" : "CX",
                                   attributes: [.font: font, .foregroundColor: color, .kern: -0.2])
    let box = label.size()
    label.draw(at: NSPoint(x: rect.midX - box.width / 2, y: rect.midY - box.height / 2 + size * 0.035))
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
}

// The dual panel reuses the same theme and quota tiles as a single-provider panel.
final class ThemedProvidersView: NSView {
    override var isFlipped: Bool { true }
    var backgroundColor = NSColor.windowBackgroundColor
    private var currentTheme: PanelTheme = .classic
    override func draw(_ dirtyRect: NSRect) { backgroundColor.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let sample = currentTheme.makeView()
        sample?.appearance = effectiveAppearance
        backgroundColor = sample?.palette.background ?? .windowBackgroundColor
        for label in subviews.compactMap({ $0 as? NSTextField }) {
            label.textColor = label.tag == 1 ? (sample?.palette.text ?? .labelColor) : (sample?.palette.secondary ?? .secondaryLabelColor)
        }
        needsDisplay = true
    }

    func configureSeparately(_ providers: [ProviderPresentation], systemAppearance: NSAppearance, configuration: (String) -> (PanelTheme, AppearanceMode, Int)) -> CGFloat {
        subviews.forEach { $0.removeFromSuperview() }
        backgroundColor = .windowBackgroundColor
        var y: CGFloat = 0
        for item in providers {
            let (theme, mode, threshold) = configuration(item.name.lowercased())
            let block = ThemedProvidersView(frame: .zero)
            block.appearance = mode.appearance
            let height = block.configure([item], theme: theme, appearance: mode.appearance ?? systemAppearance, threshold: threshold)
            block.frame = NSRect(x: 0, y: y, width: 340, height: height)
            addSubview(block); y += height
        }
        needsDisplay = true
        return y
    }

    func configure(_ providers: [ProviderPresentation], theme: PanelTheme, appearance: NSAppearance, threshold: Int) -> CGFloat {
        subviews.forEach { $0.removeFromSuperview() }
        currentTheme = theme
        let sample = theme.makeView()
        sample?.appearance = appearance
        let palette = sample?.palette
        backgroundColor = palette?.background ?? .windowBackgroundColor
        let foreground = palette?.text ?? NSColor.labelColor
        let secondary = palette?.secondary ?? NSColor.secondaryLabelColor
        var y: CGFloat = 12
        func addLabel(_ value: String, font: NSFont, color: NSColor, spacing: CGFloat, heading: Bool = false) {
            guard !value.isEmpty else { return }
            let label = NSTextField(wrappingLabelWithString: value)
            label.font = font; label.textColor = color; label.maximumNumberOfLines = 0; label.tag = heading ? 1 : 0
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
            let height = ceil((value as NSString).boundingRect(with: NSSize(width: 312, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: style]).height)
            label.frame = NSRect(x: 14, y: y, width: 312, height: height + 2)
            addSubview(label); y += height + spacing
        }
        for item in providers {
            // A failure or previous-data note sits under the provider name, next to the values it qualifies.
            // Terminal prints the name in its own "> NAME / LIMITS" header, so its note follows the readout.
            let note = item.status.hasPrefix("Updated ") ? "" : item.status
            let ownHeader = theme == .terminal
            if !ownHeader {
                addLabel(item.name, font: .systemFont(ofSize: 14, weight: .semibold), color: foreground, spacing: note.isEmpty ? 8 : 2, heading: true)
                addLabel(note, font: .systemFont(ofSize: 12), color: secondary, spacing: 8)
            }
            let five = item.quota?.fiveHour, week = item.quota?.weekly
            let fiveReset = five?.reset.map { ResetText.describe($0) } ?? "Reset unavailable"
            let weekReset = week?.reset.map { ResetText.describe($0) } ?? "Reset unavailable"
            if let view = theme.makeView() {
                func description(_ name: String, _ window: QuotaWindow?, _ reset: String) -> String {
                    guard let window = window else { return "\(name): unavailable" }
                    return "\(name): \(Int(window.remaining.rounded())) percent remaining, \(reset)"
                }
                let summary = "\(item.name). \(description("5 hours", five, fiveReset)). \(description("Week", week, weekReset)). \(item.status)"
                view.data = ThemeData(fiveHour: five?.remaining, weekly: week?.remaining, fiveReset: fiveReset, weekReset: weekReset, accessibility: summary, warningThreshold: threshold, providerName: item.name, stale: item.stale)
                let height = view.preferredContentHeight + view.outerInset
                view.frame = NSRect(x: 0, y: y, width: 340, height: height)
                addSubview(view); y += height
                if ownHeader { addLabel(note, font: .systemFont(ofSize: 12), color: secondary, spacing: 10) }
            } else {
                let first = QuotaTile(symbol: "5"), second = QuotaTile(symbol: "W")
                first.update(five, reset: fiveReset, stale: item.stale); second.update(week, reset: weekReset, stale: item.stale)
                first.ring.warningThreshold = threshold; second.ring.warningThreshold = threshold
                let extra = max(first.extraResetHeight, second.extraResetHeight)
                first.setExtraHeight(extra); second.setExtraHeight(extra)
                first.frame.origin = NSPoint(x: 12, y: y); second.frame.origin = NSPoint(x: 176, y: y)
                addSubview(first); addSubview(second); y += 192 + extra
            }
            var extras = item.quota?.additional.map { "\(durationName($0.durationMinutes)): \(Int($0.remaining.rounded()))% remaining · \(ResetText.describe($0.reset))" } ?? []
            extras += item.quota?.namedAdditional.map { "\($0.name) week: \(Int($0.remaining.rounded()))% remaining · \(ResetText.describe($0.reset))" } ?? []
            extras += item.quota?.conflictingDurations.map { "Conflicting \(durationName($0)) values; unavailable" } ?? []
            addLabel(extras.joined(separator: "\n"), font: .systemFont(ofSize: 12), color: secondary, spacing: 10)
        }
        needsDisplay = true
        return y
    }
}
