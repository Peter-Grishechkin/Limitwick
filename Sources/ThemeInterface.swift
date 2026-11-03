import AppKit
import UserNotifications

extension AppDelegate {
    func applyTheme() {
        themeView?.removeFromSuperview()
        themeView = selectedTheme.makeView()
        popover.appearance = settings.providers == .both ? nil : appearanceMode.appearance
        content.appearance = settings.providers == .both ? nil : appearanceMode.appearance
        settingsWindow?.appearance = nil
        aboutWindow?.appearance = nil
        menuPopover?.appearance = nil
        desktopWindow?.appearance = settings.providers == .both ? nil : appearanceMode.appearance
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
        let five = displayQuota?.fiveHour
        let week = displayQuota?.weekly
        let summary = "\(describe("5 hours", five)). \(describe("Week", week)). \(state). \(updatedLabel.stringValue). \(additionalLabel.stringValue)"
        themeView?.data = ThemeData(fiveHour: five?.remaining, weekly: week?.remaining,
                                    fiveReset: resetDescription(five), weekReset: resetDescription(week), accessibility: summary, warningThreshold: noticeThreshold, providerName: activeProvider.capitalized)
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
        bars.warningThreshold = settings.threshold(for: settings.providers == .claude ? "claude" : "codex")
        claudeBars.warningThreshold = settings.threshold(for: "claude")
        fiveHourView.ring.warningThreshold = noticeThreshold
        weeklyView.ring.warningThreshold = noticeThreshold
        updateThemeData()
    }
}
