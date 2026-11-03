import AppKit
import Sparkle
import Foundation
import UserNotifications
import WidgetKit

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
        symbolLabel.stringValue = symbol
        symbolLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        symbolLabel.alignment = .center
        symbolLabel.frame = NSRect(x: 31, y: 99, width: 90, height: 45)
        valueLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: 8, y: 46, width: 136, height: 28)
        resetLabel.font = .systemFont(ofSize: 10.5)
        resetLabel.textColor = .secondaryLabelColor
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
        symbolLabel.frame.origin.y = 99 + extra
        valueLabel.frame.origin.y = 46 + extra
    }
    func update(_ window: QuotaWindow?, reset: String) {
        ring.value = window?.remaining
        valueLabel.stringValue = window.map { "\(Int($0.remaining.rounded()))%" } ?? "—"
        resetLabel.stringValue = reset
        let period = symbol == "5" ? "5 hours" : "Week"
        setAccessibilityLabel("\(period), \(window == nil ? "unavailable" : valueLabel.stringValue + " remaining"), \(reset)")
    }
}

final class RingView: NSView {
    var value: Double? { didSet { needsDisplay = true } }
    var warningThreshold = 20 { didSet { needsDisplay = true } }
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
        (isLowQuota(value, threshold: warningThreshold) ? NSColor.systemRed : NSColor.systemBlue).setStroke()
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
        let background = p.background.blended(withFraction: selected ? 0.18 : 0.07, of: p.text) ?? p.surface
        background.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 34)
    let bars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let popover = NSPopover()
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 290))
    let fiveHourView = QuotaTile(symbol: "5")
    let weeklyView = QuotaTile(symbol: "W")
    let stateLabel = NSTextField(wrappingLabelWithString: "")
    let updatedLabel = NSTextField(labelWithString: "Last updated: —")
    let additionalLabel = NSTextField(wrappingLabelWithString: "")
    let contextMenu = NSMenu()
    let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    let client = QuotaClient()
    let listener = QuotaListener()
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    var timer: Timer?
    var schedule = RefreshSchedule()
    var wakePending = false
    var pendingNotices = Set<String>()
    let notices = UNUserNotificationCenter.current()
    var noticeStatus = NSTextField(wrappingLabelWithString: "")
    var lowToggle: NSButton?
    var resetToggle: NSButton?
    var tracker = NoticeTracker(resets: UserDefaults.standard.dictionary(forKey: "noticeResets") as? [String: Double] ?? [:], delivered: UserDefaults.standard.dictionary(forKey: "noticeDelivered") as? [String: Double] ?? [:])
    var running = false
    var lastUpdate: Date?
    var lastQuota: Quota?
    var state = "Loading…"
    var stale = false
    var lastFailure: String?
    var requestID = 0
    var ageTimer: Timer?
    var globalClickMonitor: Any?
    var localClickMonitor: Any?
    var themeView: ThemeView?
    var desktopWindow: NSWindow?
    let desktopContent = NSView()
    let desktopFive = QuotaTile(symbol: "5")
    let desktopWeek = QuotaTile(symbol: "W")
    let desktopState = NSTextField(wrappingLabelWithString: "")
    let desktopAdditional = NSTextField(wrappingLabelWithString: "")
    var desktopTheme: ThemeView?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var menuPopover: NSPopover?
    var menuRefreshButton: NSButton?
    var themeSurfaces: [ThemedSurface] = []
    var selectedTheme: PanelTheme = PanelTheme(rawValue: UserDefaults.standard.string(forKey: "panelTheme") ?? "") ?? .classic
    var appearanceMode: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .auto

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        bars.frame.origin = NSPoint(x: 1, y: (button.bounds.height - 20) / 2)
        bars.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(bars)
        button.toolTip = "Codex: top — 5 hours, bottom — week"
        button.setAccessibilityLabel("Codex usage limits, loading")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        stateLabel.font = .systemFont(ofSize: 12)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.maximumNumberOfLines = 0
        additionalLabel.font = .systemFont(ofSize: 12)
        additionalLabel.textColor = .secondaryLabelColor
        updatedLabel.font = .systemFont(ofSize: 12)
        updatedLabel.textColor = .secondaryLabelColor
        refresh.target = self
        contextMenu.autoenablesItems = false
        contextMenu.addItem(refresh)
        contextMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        contextMenu.addItem(settings)
        let about = NSMenuItem(title: "About Codex Bar", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        contextMenu.addItem(about)
        checkUpdates.target = self
        contextMenu.addItem(checkUpdates)
        contextMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        contextMenu.addItem(quit)
        for view in [fiveHourView, weeklyView, stateLabel, additionalLabel] as [NSView] { content.addSubview(view) }
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        // Handle dismissal ourselves so a status-item click cannot close the
        // popover on mouse-down and immediately reopen it on mouse-up.
        popover.behavior = .applicationDefined
        popover.delegate = self
        applyTheme()
        updateWarningThreshold()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        layoutPanel(message: "Loading…")
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        if UserDefaults.standard.bool(forKey: "desktopVisible") { showDesktopWindow() }
        refreshNow()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.listener.run(findPath: { QuotaClient.findCLI() }) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if self.running { self.wakePending = true } else { self.refreshNow() }
                }
            }
        }
        ageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.updateAge() }
    }
    func layoutPanel(message: String?) {
        func measured(_ text: String, font: NSFont) -> CGFloat {
            guard !text.isEmpty else { return 0 }
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
            return ceil((text as NSString).boundingRect(with: NSSize(width: 312, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: style]).height)
        }
        stateLabel.isHidden = message == nil
        stateLabel.stringValue = message ?? ""
        let stateHeight = measured(stateLabel.stringValue, font: stateLabel.font!)
        let additionalHeight = measured(additionalLabel.stringValue, font: additionalLabel.font!)
        updateThemeData()
        let bottom: CGFloat = themeView?.outerInset ?? 12
        let tileExtra = max(fiveHourView.extraResetHeight, weeklyView.extraResetHeight)
        fiveHourView.setExtraHeight(tileExtra); weeklyView.setExtraHeight(tileExtra)
        let mainHeight = themeView?.preferredContentHeight ?? (192 + tileExtra)
        let extraHeight = (stateHeight > 0 ? stateHeight + 12 : 0) + (additionalHeight > 0 ? additionalHeight + 12 : 0)
        let height: CGFloat = mainHeight + bottom + extraHeight
        // NSPopover positions its content view inside its own chrome. Preserve that origin.
        content.setFrameSize(NSSize(width: 340, height: height))
        popover.contentSize = content.frame.size
        themeView?.frame = content.bounds
        fiveHourView.frame.origin = NSPoint(x: 12, y: bottom + extraHeight)
        weeklyView.frame.origin = NSPoint(x: 176, y: bottom + extraHeight)
        stateLabel.frame = NSRect(x: 14, y: bottom, width: 312, height: stateHeight)
        additionalLabel.frame = NSRect(x: 14, y: bottom + (stateHeight > 0 ? stateHeight + 12 : 0), width: 312, height: additionalHeight)
        updateThemeData()
        syncDesktop()
    }
    @objc func statusItemClicked() {
        guard let button = status.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            showContextMenu(relativeTo: button)
            return
        }
        menuPopover?.performClose(nil)
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if popover.isShown { startClickMonitoring() }
        }
    }
    func startClickMonitoring() {
        stopClickMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            guard let self = self, self.settingsWindow?.isVisible != true else { return }
            self.popover.close()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [clicks, .keyDown]) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.popover.close(); return nil }
                return event
            }
            if self.settingsWindow?.isVisible != true && event.window !== self.content.window && event.window !== self.status.button?.window {
                self.popover.close()
            }
            return event
        }
    }
    func stopClickMonitoring() {
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor); globalClickMonitor = nil }
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor); localClickMonitor = nil }
    }
    func popoverDidClose(_ notification: Notification) { stopClickMonitoring() }
    @objc func activeApplicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              settingsWindow?.isVisible != true else { return }
        popover.close()
    }
    func applicationDidResignActive(_ notification: Notification) {
        if settingsWindow?.isVisible != true { popover.close() }
    }
    func applyTheme() {
        themeView?.removeFromSuperview()
        themeView = selectedTheme.makeView()
        popover.appearance = appearanceMode.appearance
        content.appearance = appearanceMode.appearance
        settingsWindow?.appearance = appearanceMode.appearance
        aboutWindow?.appearance = appearanceMode.appearance
        menuPopover?.appearance = appearanceMode.appearance
        desktopWindow?.appearance = appearanceMode.appearance
        desktopTheme?.removeFromSuperview()
        desktopTheme = selectedTheme.makeView()
        if let themed = desktopTheme { desktopContent.addSubview(themed, positioned: .below, relativeTo: nil) }
        refreshSurfaces()
        resizeWindowToContent(settingsWindow)
        resizeWindowToContent(aboutWindow)
        fiveHourView.isHidden = themeView != nil
        weeklyView.isHidden = themeView != nil
        if let themed = themeView {
            themed.frame = content.bounds
            themed.autoresizingMask = [.width, .height]
            themed.appearanceChanged = { [weak self] in self?.updateThemeColors() }
            content.addSubview(themed, positioned: .below, relativeTo: nil)
        }
        updateThemeColors()
        updateThemeData()
        layoutPanel(message: stateLabel.isHidden ? nil : stateLabel.stringValue)
    }
    func updateThemeColors() {
        let color = themeView?.palette.secondary ?? NSColor.secondaryLabelColor
        stateLabel.textColor = color
        updatedLabel.textColor = color
        additionalLabel.textColor = color
    }
    func updateThemeData() {
        let five = lastQuota?.fiveHour
        let week = lastQuota?.weekly
        let summary = "\(describe("5 hours", five)). \(describe("Week", week)). \(state). \(updatedLabel.stringValue). \(additionalLabel.stringValue)"
        themeView?.data = ThemeData(fiveHour: five?.remaining, weekly: week?.remaining,
                                    fiveReset: resetDescription(five), weekReset: resetDescription(week), accessibility: summary, warningThreshold: noticeThreshold)
    }
    func palette(for appearance: NSAppearance) -> ThemePalette {
        if let view = selectedTheme.makeView() {
            view.appearance = appearance
            return view.palette
        }
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return ThemePalette(background: dark ? .init(white: 0.12, alpha: 1) : .init(white: 0.96, alpha: 1), surface: dark ? .init(white: 0.18, alpha: 1) : .white, text: dark ? .white : .black, secondary: dark ? .lightGray : .darkGray, track: .gray, accent: .systemBlue, second: .systemBlue)
    }
    func surface(_ view: ThemedSurface) {
        view.paletteProvider = { [weak self] appearance in
            self?.palette(for: appearance) ?? ThemePalette(background: .windowBackgroundColor, surface: .controlBackgroundColor, text: .labelColor, secondary: .secondaryLabelColor, track: .separatorColor, accent: .controlAccentColor, second: .controlAccentColor)
        }
        view.onAppearanceChange = { [weak self] in self?.refreshSurfaces() }
        themeSurfaces.append(view)
    }
    func refreshSurfaces() {
        for surface in themeSurfaces {
            let colors = palette(for: surface.effectiveAppearance)
            surface.needsDisplay = true
            func apply(_ view: NSView) {
                if let item = view as? MenuButton { item.needsDisplay = true }
                if let text = view as? NSTextField {
                    text.textColor = text.tag == 902 ? colors.secondary : colors.text
                    if text.tag == 901 {
                        text.font = selectedTheme == .paper ? (NSFont(name: "Times New Roman", size: 18) ?? .boldSystemFont(ofSize: 18)) : ((selectedTheme == .terminal || selectedTheme == .industrial || selectedTheme == .dots) ? .monospacedSystemFont(ofSize: 14, weight: .semibold) : .systemFont(ofSize: 16, weight: .semibold))
                    }
                }
                for child in view.subviews { apply(child) }
            }
            apply(surface)
        }
    }
    func updateWarningThreshold() {
        bars.warningThreshold = noticeThreshold
        fiveHourView.ring.warningThreshold = noticeThreshold
        weeklyView.ring.warningThreshold = noticeThreshold
        updateThemeData()
    }
    func heading(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title); label.tag = 901
        return label
    }
    func stack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    func install(_ stack: NSStackView, in surface: NSView, width: CGFloat) {
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -22),
            surface.widthAnchor.constraint(equalToConstant: width)
        ])
    }
    func makeWindow(title: String, content stack: NSStackView, width: CGFloat) -> NSWindow {
        let surface = ThemedSurface(); surface.translatesAutoresizingMaskIntoConstraints = false
        self.surface(surface)
        install(stack, in: surface, width: width)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.contentView = surface
        window.appearance = appearanceMode.appearance
        surface.layoutSubtreeIfNeeded()
        let size = surface.fittingSize
        window.setContentSize(NSSize(width: width, height: max(1, size.height)))
        window.center()
        refreshSurfaces()
        return window
    }
    func resizeWindowToContent(_ window: NSWindow?) {
        guard let window = window, let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let height = view.fittingSize.height
        guard height > 0 else { return }
        let old = window.frame
        let frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: view.bounds.width, height: height))
        window.setFrame(NSRect(x: old.minX, y: old.maxY - frame.height, width: frame.width, height: frame.height), display: true)
    }
    @objc func showSettings() {
        popover.performClose(nil); menuPopover?.performClose(nil)
        if settingsWindow == nil {
            let themePicker = NSPopUpButton(); themePicker.addItems(withTitles: PanelTheme.allCases.map(\.title))
            themePicker.selectItem(at: PanelTheme.allCases.firstIndex(of: selectedTheme) ?? 0)
            themePicker.target = self; themePicker.action = #selector(themeChanged(_:)); themePicker.setAccessibilityLabel("Theme")
            let appearancePicker = NSPopUpButton(); appearancePicker.addItems(withTitles: AppearanceMode.allCases.map(\.title))
            appearancePicker.selectItem(at: AppearanceMode.allCases.firstIndex(of: appearanceMode) ?? 0)
            appearancePicker.target = self; appearancePicker.action = #selector(appearanceChanged(_:)); appearancePicker.setAccessibilityLabel("Appearance")
            func row(_ title: String, _ control: NSView) -> NSStackView {
                let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 110).isActive = true
                let row = NSStackView(views: [label, control]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
                control.widthAnchor.constraint(equalToConstant: 210).isActive = true
                return row
            }
            let low = NSButton(checkboxWithTitle: "Low remaining quota", target: self, action: #selector(noticeSettingChanged(_:)))
            low.state = UserDefaults.standard.bool(forKey: "noticeLow") ? .on : .off; low.identifier = NSUserInterfaceItemIdentifier("noticeLow"); lowToggle = low
            let reset = NSButton(checkboxWithTitle: "Confirmed quota reset", target: self, action: #selector(noticeSettingChanged(_:)))
            reset.state = UserDefaults.standard.bool(forKey: "noticeReset") ? .on : .off; reset.identifier = NSUserInterfaceItemIdentifier("noticeReset"); resetToggle = reset
            let threshold = NSStepper(); threshold.minValue = 1; threshold.maxValue = 99; threshold.integerValue = noticeThreshold
            threshold.target = self; threshold.action = #selector(thresholdChanged(_:)); threshold.setAccessibilityLabel("Low quota threshold percent")
            let field = NSTextField(labelWithString: "\(noticeThreshold)%"); field.tag = 501
            let thresholdRow = NSStackView(views: [NSTextField(labelWithString: "Low threshold:"), field, threshold]); thresholdRow.orientation = .horizontal; thresholdRow.spacing = 12
            noticeStatus.maximumNumberOfLines = 0; noticeStatus.font = .systemFont(ofSize: 11); noticeStatus.tag = 902
            noticeStatus.widthAnchor.constraint(equalToConstant: 372).isActive = true
            let openSettings = NSButton(title: "Notification Settings…", target: self, action: #selector(openNotificationSettings))
            let items = [heading("Appearance"), row("Theme", themePicker), row("Mode", appearancePicker), heading("Notifications"), low, reset, thresholdRow, noticeStatus, openSettings] as [NSView]
            let content = stack(items, spacing: 12)
            content.setCustomSpacing(22, after: items[2])
            settingsWindow = makeWindow(title: "Settings", content: content, width: 420)
            settingsWindow?.initialFirstResponder = themePicker
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
        updateNoticeStatus()
        resizeWindowToContent(settingsWindow)
    }
    @objc func themeChanged(_ sender: NSPopUpButton) {
        guard PanelTheme.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        selectedTheme = PanelTheme.allCases[sender.indexOfSelectedItem]
        UserDefaults.standard.set(selectedTheme.rawValue, forKey: "panelTheme")
        applyTheme()
        resizeWindowToContent(settingsWindow)
        publishWidgetSnapshot()
    }
    @objc func appearanceChanged(_ sender: NSPopUpButton) {
        guard AppearanceMode.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        appearanceMode = AppearanceMode.allCases[sender.indexOfSelectedItem]
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        applyTheme()
        resizeWindowToContent(settingsWindow)
        publishWidgetSnapshot()
    }
    var noticeThreshold: Int {
        let value = UserDefaults.standard.integer(forKey: "noticeThreshold")
        return value == 0 ? 20 : min(99, max(1, value))
    }
    @objc func thresholdChanged(_ sender: NSStepper) {
        UserDefaults.standard.set(sender.integerValue, forKey: "noticeThreshold")
        updateWarningThreshold()
        layoutPanel(message: stateLabel.isHidden ? nil : stateLabel.stringValue)
        publishWidgetSnapshot()
        (settingsWindow?.contentView?.viewWithTag(501) as? NSTextField)?.stringValue = "\(sender.integerValue)%"
    }
    @objc func noticeSettingChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
        if sender.state == .on {
            notices.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in DispatchQueue.main.async { self?.updateNoticeStatus() } }
        } else { updateNoticeStatus() }
    }
    func updateNoticeStatus() {
        notices.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch settings.authorizationStatus {
                case .denied: self.noticeStatus.stringValue = "Notifications are blocked by macOS. Enable Codex Bar in System Settings → Notifications."
                case .authorized, .provisional, .ephemeral: self.noticeStatus.stringValue = "Notifications are allowed. Reset alerts require a successful refresh."
                default: self.noticeStatus.stringValue = "Enable an alert above to request notification permission."
                }
                self.resizeWindowToContent(self.settingsWindow)
            }
        }
    }
    @objc func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func processNotices(_ quota: Quota) {
        let defaults = UserDefaults.standard
        let candidates = tracker.evaluate(quota.windows, now: Date(), low: defaults.bool(forKey: "noticeLow"), reset: defaults.bool(forKey: "noticeReset"), threshold: noticeThreshold)
        defaults.set(tracker.resets, forKey: "noticeResets")
        // Commit delivery only after macOS accepts each request, so denied permission does not consume an alert.
        for notice in candidates {
            let key = "\(notice.kind):\(notice.duration):\(Int64(notice.reset))"
            tracker.delivered.removeValue(forKey: key)
            guard pendingNotices.insert(key).inserted else { continue }
            notices.getNotificationSettings { [weak self] settings in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let keyEnabled = notice.kind == "low" ? "noticeLow" : "noticeReset"
                    guard (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional),
                          UserDefaults.standard.bool(forKey: keyEnabled), !self.stale,
                          let current = self.lastQuota?.windows.first(where: { $0.durationMinutes == notice.duration }),
                          current.reset?.timeIntervalSince1970 == notice.reset, notice.reset > Date().timeIntervalSince1970,
                          notice.kind != "low" || current.remaining <= Double(self.noticeThreshold) else {
                        self.pendingNotices.remove(key)
                        return
                    }
                    let content = UNMutableNotificationContent()
                    content.title = notice.kind == "low" ? "Codex quota running low" : "Codex quota reset"
                    content.body = "\(durationName(notice.duration)) limit: \(Int(current.remaining.rounded()))% remaining."
                    content.sound = .default
                    self.notices.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) { error in
                        DispatchQueue.main.async {
                            self.pendingNotices.remove(key)
                            guard error == nil else { return }
                            self.tracker.delivered[key] = Date().timeIntervalSince1970
                            UserDefaults.standard.set(self.tracker.delivered, forKey: "noticeDelivered")
                        }
                    }
                }
            }
        }
        defaults.set(tracker.delivered, forKey: "noticeDelivered")
    }
    @objc func didWake(_ notification: Notification) {
        updateAge()
        if running { wakePending = true } else { refreshNow() }
    }
    func scheduleRefresh(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in self?.refreshNow() }
    }
    @objc func showAbout() {
        menuPopover?.performClose(nil); popover.performClose(nil)
        if aboutWindow == nil {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let title = heading("Codex Bar")
            let versionLabel = NSTextField(labelWithString: "Version \(version)"); versionLabel.tag = 902
            let description = NSTextField(wrappingLabelWithString: "A menu bar app for Codex usage limits."); description.widthAnchor.constraint(equalToConstant: 312).isActive = true
            let github = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
            let close = NSButton(title: "Close", target: self, action: #selector(closeAbout))
            let buttons = NSStackView(views: [github, close]); buttons.orientation = .horizontal; buttons.spacing = 8
            aboutWindow = makeWindow(title: "About Codex Bar", content: stack([title, versionLabel, description, buttons], spacing: 14), width: 360)
        }
        NSApp.activate(ignoringOtherApps: true); aboutWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/frankydzoro/codex-bar")!) }
    @objc func closeAbout() { aboutWindow?.performClose(nil) }

    func showContextMenu(relativeTo button: NSView) {
        if menuPopover?.isShown == true { menuPopover?.performClose(nil); return }
        if let old = menuPopover?.contentViewController?.view as? ThemedSurface { themeSurfaces.removeAll { $0 === old } }
        let menu = NSPopover(); menu.behavior = .transient; menu.appearance = appearanceMode.appearance
        let view = MenuView(); surface(view)
        let desktopTitle = desktopWindow?.isVisible == true ? "Hide Picture-in-Picture" : "Show Picture-in-Picture"
        let commands: [(String, Selector, String)] = [("Refresh", #selector(menuRefresh), "r"), (desktopTitle, #selector(toggleDesktopWindow), ""), ("Settings…", #selector(showSettings), ","), ("About Codex Bar", #selector(showAbout), ""), ("Check for Updates…", #selector(menuUpdates), ""), ("Quit", #selector(menuQuit), "q")]
        var buttons: [NSView] = []
        for (title, action, key) in commands {
            let item = MenuButton(title: title, target: self, action: action)
            item.isBordered = false; item.setAccessibilityLabel(title)
            item.shortcut = key.isEmpty ? "" : "⌘\(key.uppercased())"
            item.dismiss = { [weak menu] in menu?.performClose(nil) }
            item.fontProvider = { [weak self] in
                guard let self = self else { return .systemFont(ofSize: 13) }
                switch self.selectedTheme {
                case .industrial, .dots, .terminal: return .monospacedSystemFont(ofSize: 12, weight: .regular)
                case .paper: return NSFont(name: "Times New Roman", size: 14) ?? .systemFont(ofSize: 13)
                default: return .systemFont(ofSize: 13)
                }
            }
            item.paletteProvider = { [weak self, weak view] in
                guard let self = self, let view = view else { return ThemePalette(background: .windowBackgroundColor, surface: .controlBackgroundColor, text: .labelColor, secondary: .secondaryLabelColor, track: .separatorColor, accent: .controlAccentColor, second: .controlAccentColor) }
                return self.palette(for: view.effectiveAppearance)
            }
            item.keyEquivalent = key; if !key.isEmpty { item.keyEquivalentModifierMask = .command }
            item.widthAnchor.constraint(equalToConstant: 250).isActive = true
            item.heightAnchor.constraint(equalToConstant: 30).isActive = true
            if title == "Refresh" { item.isEnabled = !running; menuRefreshButton = item }
            buttons.append(item)
        }
        view.items = buttons.compactMap { $0 as? MenuButton }
        let list = stack(buttons, spacing: 2)
        list.setCustomSpacing(10, after: buttons[0])
        list.setCustomSpacing(10, after: buttons[4])
        install(list, in: view, width: 298)
        let controller = NSViewController(); controller.view = view; menu.contentViewController = controller
        view.dismiss = { [weak menu] in menu?.performClose(nil) }
        menuPopover = menu; refreshSurfaces()
        view.layoutSubtreeIfNeeded(); menu.contentSize = NSSize(width: 298, height: max(1, view.fittingSize.height))
        NSApp.activate(ignoringOtherApps: true)
        menu.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        menu.contentViewController?.view.window?.makeFirstResponder(view)
    }
    @objc func toggleDesktopWindow() {
        menuPopover?.performClose(nil)
        if desktopWindow?.isVisible == true {
            desktopWindow?.orderOut(nil)
            UserDefaults.standard.set(false, forKey: "desktopVisible")
        } else {
            showDesktopWindow()
        }
    }
    func showDesktopWindow() {
        if desktopWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 220), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.appearance = appearanceMode.appearance
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            desktopContent.wantsLayer = true
            desktopContent.layer?.cornerRadius = 12
            desktopContent.layer?.masksToBounds = true
            for label in [desktopState, desktopAdditional] {
                label.font = .systemFont(ofSize: 12)
                label.maximumNumberOfLines = 0
            }
            for view in [desktopFive, desktopWeek, desktopState, desktopAdditional] as [NSView] { desktopContent.addSubview(view) }
            window.contentView = desktopContent
            desktopWindow = window
            if !window.setFrameUsingName("DesktopWindow") { window.center() }
            window.setFrameAutosaveName("DesktopWindow")
        }
        syncDesktop()
        desktopWindow?.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "desktopVisible")
    }
    func syncDesktop() {
        guard let window = desktopWindow else { return }
        desktopContent.appearance = appearanceMode.appearance
        desktopContent.layer?.backgroundColor = palette(for: desktopContent.effectiveAppearance).background.cgColor
        desktopFive.isHidden = desktopTheme != nil; desktopWeek.isHidden = desktopTheme != nil
        desktopFive.update(lastQuota?.fiveHour, reset: resetDescription(lastQuota?.fiveHour))
        desktopWeek.update(lastQuota?.weekly, reset: resetDescription(lastQuota?.weekly))
        desktopFive.ring.warningThreshold = noticeThreshold; desktopWeek.ring.warningThreshold = noticeThreshold
        desktopFive.frame = fiveHourView.frame; desktopWeek.frame = weeklyView.frame
        desktopState.stringValue = stateLabel.stringValue; desktopState.isHidden = stateLabel.isHidden; desktopState.frame = stateLabel.frame
        desktopAdditional.stringValue = additionalLabel.stringValue; desktopAdditional.frame = additionalLabel.frame
        let secondary = desktopTheme?.palette.secondary ?? NSColor.secondaryLabelColor
        desktopState.textColor = secondary; desktopAdditional.textColor = secondary
        if let theme = desktopTheme {
            theme.frame = content.bounds
            theme.data = themeView?.data ?? ThemeData(fiveHour: nil, weekly: nil, fiveReset: "—", weekReset: "—", accessibility: "Limits unavailable")
        }
        let size = content.frame.size
        if window.contentView?.frame.size != size {
            let old = window.frame
            window.setFrame(NSRect(x: old.origin.x, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
        }
    }
    @objc func menuRefresh() { menuPopover?.performClose(nil); refreshNow() }
    @objc func menuUpdates() { menuPopover?.performClose(nil); checkForUpdates() }
    @objc func menuQuit() { menuPopover?.performClose(nil); NSApp.terminate(nil) }
    @objc func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }
    @objc func refreshNow() {
        guard !running else { return }
        timer?.invalidate()
        running = true; refresh.isEnabled = false; menuRefreshButton?.isEnabled = false
        requestID += 1
        let currentRequest = requestID
        state = lastQuota == nil ? "Loading…" : (stale ? "Updating… Previous attempt: \(lastFailure ?? "failed") — showing previous data" : "Updating…")
        layoutPanel(message: state)
        guard let path = QuotaClient.findCLI() else { finish(.failure(QuotaError.cliNotFound)); return }
        DispatchQueue.global(qos: .utility).async {
            let result = self.client.fetch(path: path)
            DispatchQueue.main.async { if self.requestID == currentRequest { self.finish(result) } }
        }
    }
    func finish(_ result: Result<Quota, Error>) {
        running = false; refresh.isEnabled = true; menuRefreshButton?.isEnabled = true
        var message: String?
        switch result {
        case .success(let quota):
            processNotices(quota)
            lastQuota = quota; lastUpdate = Date()
            state = "Up to date"
            stale = false
            lastFailure = nil

        case .failure(let error):
            stale = lastQuota != nil
            lastFailure = error.localizedDescription
            state = "\(error.localizedDescription)\(stale ? " — showing previous data (\(updatedLabel.stringValue.lowercased()))" : "")"
            message = state
        }
        if let quota = lastQuota {
            bars.values = [quota.fiveHour?.remaining, quota.weekly?.remaining]
            fiveHourView.update(quota.fiveHour, reset: resetDescription(quota.fiveHour))
            weeklyView.update(quota.weekly, reset: resetDescription(quota.weekly))
        }
        bars.stale = stale
        updateAge()
        layoutPanel(message: message)
        publishWidgetSnapshot()
        status.button?.setAccessibilityLabel("Codex. \(state). \(describe("5 hours", lastQuota?.fiveHour)). \(describe("Week", lastQuota?.weekly)). \(updatedLabel.stringValue)")
        let interval: TimeInterval
        switch result { case .success: interval = schedule.record(success: true); case .failure: interval = schedule.record(success: false) }
        if wakePending { wakePending = false; refreshNow() } else { scheduleRefresh(after: interval) }
    }
    func publishWidgetSnapshot() {
        // Render the same views used by the popup, so every theme stays in sync.
        content.layoutSubtreeIfNeeded()
        let bounds = content.bounds
        var image: Data?
        if bounds.width > 0, bounds.height > 0,
           let bitmap = content.bitmapImageRepForCachingDisplay(in: bounds) {
            content.cacheDisplay(in: bounds, to: bitmap)
            image = bitmap.representation(using: .png, properties: [:])
        }
        let summary = "\(describe("5 hours", lastQuota?.fiveHour)). \(describe("Week", lastQuota?.weekly)). \(state)"
        WidgetSnapshot(five: lastQuota?.fiveHour?.remaining, week: lastQuota?.weekly?.remaining,
                       fiveReset: lastQuota?.fiveHour?.reset, weekReset: lastQuota?.weekly?.reset,
                       updated: lastUpdate, stale: stale || lastQuota == nil, threshold: noticeThreshold,
                       panelImage: image, accessibility: summary).write()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }
    func applicationWillTerminate(_ notification: Notification) {
        requestID += 1
        stopClickMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate(); ageTimer?.invalidate()
        client.cancel()
        listener.cancel()
    }
    func updateAge() {
        if let date = lastUpdate {
            let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
            updatedLabel.stringValue = minutes == 0 ? "Updated just now" : "Updated \(minutes) min ago"
        } else { updatedLabel.stringValue = "Updated: —" }
        if stale, !running, let failure = lastFailure {
            let message = "\(failure) — showing previous data (\(updatedLabel.stringValue.lowercased()))"
            if state != message { state = message; layoutPanel(message: message) }
        }
        if let quota = lastQuota {
            fiveHourView.update(quota.fiveHour, reset: resetDescription(quota.fiveHour))
            weeklyView.update(quota.weekly, reset: resetDescription(quota.weekly))
            let conflicts = quota.conflictingDurations.map { "Conflicting \(durationName($0)) values; unavailable" }
            let extras = quota.additional.map { "\(durationName($0.durationMinutes)): \(Int($0.remaining.rounded()))% remaining · \(ResetText.describe($0.reset))" }
            let newText = (extras + conflicts).joined(separator: "\n")
            if additionalLabel.stringValue != newText { additionalLabel.stringValue = newText; layoutPanel(message: stateLabel.isHidden ? nil : stateLabel.stringValue) }
        }
        layoutPanel(message: stateLabel.isHidden ? nil : stateLabel.stringValue)
    }
    func resetDescription(_ window: QuotaWindow?) -> String {
        ResetText.describe(window?.reset)
    }
    func describe(_ name: String, _ window: QuotaWindow?) -> String {
        guard let window = window else { return "\(name): unavailable" }
        let reset = " · \(ResetText.describe(window.reset))"
        return "\(name): \(Int(window.remaining.rounded()))% remaining\(reset)"
    }
    func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    func shortReset(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    func format(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
@main struct CodexBarMain {
    static func main() {
        let app = NSApplication.shared
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position Item-0": 120])
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
