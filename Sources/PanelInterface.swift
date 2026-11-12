import AppKit
import SwiftUI
import UserNotifications

extension AppearanceMode {
    /// Explicit scheme for a card; Auto follows the system.
    var scheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The Picture-in-Picture card. The hosting view keeps clicks to itself, so isMovableByWindowBackground alone
/// does not move the borderless window; drag it explicitly, like the Sessions window.
final class PiPHostingView: NSHostingView<QuotaPanelView> {
    override var mouseDownCanMoveWindow: Bool { true }
    // Limitwick is a menu bar app and the window is usually not key: the first click must start the drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

extension AppDelegate {
    /// One entry per tracked provider: its card, its own theme and mode, and the refresh failure shown under the card.
    var panelEntries: [QuotaPanelEntry] {
        presentations.map { item in
            let provider = item.name.lowercased()
            let model = QuotaCardModel.make(provider: item.name, quota: item.quota, stale: item.stale, loading: item.running,
                                            updated: item.updated, threshold: settings.threshold(for: provider))
            return QuotaPanelEntry(id: provider, model: model, theme: theme(for: provider), scheme: mode(for: provider).scheme, message: item.failure ?? "")
        }
    }

    func layoutPanel() {
        let entries = panelEntries
        // Cards have fixed heights per theme; only a refresh failure under a card adds height.
        let screenHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        let height = min(QuotaPanelLayout.height(entries), max(200, screenHeight))
        let root = QuotaPanelView(entries: entries, maxHeight: height)
        panelHost.rootView = root
        desktopHost.rootView = root
        let size = NSSize(width: QuotaPanelLayout.width, height: height)
        // NSPopover positions its content view inside its own chrome. Preserve that origin.
        if content.frame.size != size { content.setFrameSize(size); popover.contentSize = size }
        panelHost.frame = content.bounds
        syncDesktop()
    }
}
