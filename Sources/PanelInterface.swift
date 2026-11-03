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
}
