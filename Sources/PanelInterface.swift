import AppKit
import UserNotifications

extension AppDelegate {
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
        let dual = settings.providers == .both
        multiPanel.isHidden = !dual
        stateLabel.isHidden = dual || message == nil
        additionalLabel.isHidden = dual
        themeView?.isHidden = dual
        fiveHourView.isHidden = dual || themeView != nil
        weeklyView.isHidden = dual || themeView != nil
        let bottom: CGFloat = themeView?.outerInset ?? 12
        let tileExtra = max(fiveHourView.extraResetHeight, weeklyView.extraResetHeight)
        fiveHourView.setExtraHeight(tileExtra); weeklyView.setExtraHeight(tileExtra)
        var dualHeight: CGFloat = 0
        if dual {
            dualHeight = providersPanel.configureSeparately(presentations, systemAppearance: content.effectiveAppearance) { provider in
                (theme(for: provider), mode(for: provider), settings.threshold(for: provider))
            }
            providersPanel.frame = NSRect(x: 0, y: 0, width: 340, height: dualHeight)
            if multiPanel.documentView !== providersPanel { multiPanel.documentView = providersPanel }
            multiPanel.drawsBackground = false; multiPanel.hasVerticalScroller = true; multiPanel.autohidesScrollers = true
        }
        let screenHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        let mainHeight = dual ? min(dualHeight, max(200, screenHeight)) : (themeView?.preferredContentHeight ?? (192 + tileExtra))
        let extraHeight = dual ? 0 : (stateHeight > 0 ? stateHeight + 12 : 0) + (additionalHeight > 0 ? additionalHeight + 12 : 0)
        let height: CGFloat = mainHeight + (dual ? 0 : bottom + extraHeight)
        // NSPopover positions its content view inside its own chrome. Preserve that origin.
        content.setFrameSize(NSSize(width: 340, height: height))
        popover.contentSize = content.frame.size
        themeView?.frame = content.bounds
        multiPanel.frame = NSRect(x: 0, y: 0, width: 340, height: mainHeight)
        fiveHourView.frame.origin = NSPoint(x: 12, y: bottom + extraHeight)
        weeklyView.frame.origin = NSPoint(x: 176, y: bottom + extraHeight)
        stateLabel.frame = NSRect(x: 14, y: bottom, width: 312, height: stateHeight)
        additionalLabel.frame = NSRect(x: 14, y: bottom + (stateHeight > 0 ? stateHeight + 12 : 0), width: 312, height: additionalHeight)
        updateThemeData()
        syncDesktop()
    }
}
