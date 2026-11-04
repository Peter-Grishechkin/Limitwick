import AppKit
import UserNotifications

extension AppDelegate {
    func applyTheme() {
        popover.appearance = settings.providers == .both ? nil : appearanceMode.appearance
        content.appearance = settings.providers == .both ? nil : appearanceMode.appearance
        settingsWindow?.appearance = nil
        aboutWindow?.appearance = nil
        menuPopover?.appearance = nil
        desktopWindow?.appearance = settings.providers == .both ? nil : appearanceMode.appearance
        refreshSurfaces()
        resizeWindowToContent(settingsWindow)
        resizeWindowToContent(aboutWindow)
        layoutPanel()
    }
    func palette(for appearance: NSAppearance) -> ThemePalette {
        selectedTheme.palette(dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
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
                if view is MenuButton || view is MenuSeparator { view.needsDisplay = true }
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
        layoutPanel()
    }
}
