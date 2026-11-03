import AppKit
import UserNotifications

extension AppDelegate {
    @objc func showAbout() {
        menuPopover?.performClose(nil); popover.performClose(nil)
        if aboutWindow == nil {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let title = heading("Limitwick")
            let versionLabel = NSTextField(labelWithString: "Version \(version)"); versionLabel.tag = 902
            let description = NSTextField(wrappingLabelWithString: "A menu bar app for Codex usage limits."); description.widthAnchor.constraint(equalToConstant: 312).isActive = true
            let github = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
            let close = NSButton(title: "Close", target: self, action: #selector(closeAbout))
            let buttons = NSStackView(views: [github, close]); buttons.orientation = .horizontal; buttons.spacing = 8
            aboutWindow = makeWindow(title: "About Limitwick", content: stack([title, versionLabel, description, buttons], spacing: 14), width: 360)
        }
        NSApp.activate(ignoringOtherApps: true); aboutWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/frankydzoro/Limitwick")!) }
    @objc func closeAbout() { aboutWindow?.performClose(nil) }

    func showContextMenu(relativeTo button: NSView) {
        if menuPopover?.isShown == true { menuPopover?.performClose(nil); return }
        if let old = menuPopover?.contentViewController?.view as? ThemedSurface { themeSurfaces.removeAll { $0 === old } }
        let menu = NSPopover(); menu.behavior = .transient; menu.appearance = nil
        let view = MenuView(); surface(view)
        let desktopTitle = desktopWindow?.isVisible == true ? "Hide Picture-in-Picture" : "Show Picture-in-Picture"
        var commands: [(String, Selector, String)] = [("Refresh", #selector(menuRefresh), "r"), (desktopTitle, #selector(toggleDesktopWindow), ""), ("Settings…", #selector(showSettings), ","), ("About Limitwick", #selector(showAbout), "")]
        #if !LIMITWICK_DEVELOPMENT
        commands.append((updateMenuTitle, #selector(menuUpdates), ""))
        #endif
        commands.append(("Quit", #selector(menuQuit), "q"))
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
            if action == #selector(menuUpdates) { item.highlightsUpdate = availableUpdate != nil; menuUpdateButton = item }
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
            settings.desktopVisible = false
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
            window.appearance = settings.providers == .both ? nil : appearanceMode.appearance
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
            for view in [desktopFive, desktopWeek, desktopState, desktopAdditional, multiDesktop] as [NSView] { desktopContent.addSubview(view) }
            window.contentView = desktopContent
            desktopWindow = window
            if !window.setFrameUsingName("DesktopWindow") { window.center() }
            window.setFrameAutosaveName("DesktopWindow")
        }
        syncDesktop()
        desktopWindow?.orderFrontRegardless()
        settings.desktopVisible = true
    }
    func syncDesktop() {
        guard let window = desktopWindow else { return }
        desktopContent.appearance = settings.providers == .both ? nil : appearanceMode.appearance
        desktopContent.layer?.backgroundColor = palette(for: desktopContent.effectiveAppearance).background.cgColor
        let dual = settings.providers == .both
        multiDesktop.isHidden = !dual
        multiDesktop.frame = multiPanel.frame
        if dual {
            let height = providersDesktop.configureSeparately(presentations, systemAppearance: desktopContent.effectiveAppearance) { provider in
                (theme(for: provider), mode(for: provider), settings.threshold(for: provider))
            }
            providersDesktop.frame = NSRect(x: 0, y: 0, width: 340, height: height)
            if multiDesktop.documentView !== providersDesktop { multiDesktop.documentView = providersDesktop }
            multiDesktop.drawsBackground = false; multiDesktop.hasVerticalScroller = true; multiDesktop.autohidesScrollers = true
        }
        desktopTheme?.isHidden = dual
        desktopFive.isHidden = dual || desktopTheme != nil; desktopWeek.isHidden = dual || desktopTheme != nil
        desktopFive.update(displayQuota?.fiveHour, reset: resetDescription(displayQuota?.fiveHour), stale: displayStale)
        desktopWeek.update(displayQuota?.weekly, reset: resetDescription(displayQuota?.weekly), stale: displayStale)
        desktopFive.ring.warningThreshold = noticeThreshold; desktopWeek.ring.warningThreshold = noticeThreshold
        desktopFive.frame = fiveHourView.frame; desktopWeek.frame = weeklyView.frame
        desktopState.stringValue = stateLabel.stringValue; desktopState.isHidden = dual || stateLabel.isHidden; desktopState.frame = stateLabel.frame
        desktopAdditional.stringValue = additionalLabel.stringValue; desktopAdditional.isHidden = dual; desktopAdditional.frame = additionalLabel.frame
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
}
