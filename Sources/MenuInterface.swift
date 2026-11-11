import AppKit
import UserNotifications

extension AppDelegate {
    @objc func showAbout() {
        menuPopover?.performClose(nil); popover.performClose(nil)
        if aboutWindow == nil {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let title = heading("Limitwick")
            let versionLabel = NSTextField(labelWithString: "Version \(version)"); versionLabel.tag = 902
            let description = NSTextField(wrappingLabelWithString: "Codex and Claude Code limits in your menu bar."); description.widthAnchor.constraint(equalToConstant: 312).isActive = true
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
        let sessionsTitle = sessionsWindow?.isVisible == true ? "Hide Sessions" : "Show Sessions"
        var commands: [(String, Selector, String)] = [("Refresh", #selector(menuRefresh), "r"), (desktopTitle, #selector(toggleDesktopWindow), ""), (sessionsTitle, #selector(toggleSessionsWindow), ""), ("Settings…", #selector(showSettings), ","), ("About Limitwick", #selector(showAbout), "")]
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
        func separator() -> NSView {
            let line = MenuSeparator(); line.paletteProvider = view.items.first?.paletteProvider
            line.widthAnchor.constraint(equalToConstant: 250).isActive = true
            line.heightAnchor.constraint(equalToConstant: 9).isActive = true
            return line
        }
        // Lines set off Refresh and Quit from the other commands.
        let list = stack([buttons[0], separator()] + buttons[1..<(buttons.count - 1)] + [separator(), buttons[buttons.count - 1]], spacing: 2)
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
            desktopHost.sizingOptions = []
            desktopHost.autoresizingMask = [.width, .height]
            desktopContent.addSubview(desktopHost)
            window.contentView = desktopContent
            desktopWindow = window
            if !window.setFrameUsingName("DesktopWindow") { window.center() }
            window.setFrameAutosaveName("DesktopWindow")
        }
        syncDesktop()
        desktopWindow?.orderFrontRegardless()
        settings.desktopVisible = true
    }
    // MARK: Sessions window

    @objc func toggleSessionsWindow() {
        menuPopover?.performClose(nil)
        if sessionsWindow?.isVisible == true { hideSessionsWindow() } else { showSessionsWindow() }
    }
    func showSessionsWindow() {
        if sessionsWindow == nil {
            // Borderless like the Picture-in-Picture window: no title bar or close button; hide it from the menu or by right-click.
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: SessionGridLayout.size(limit: settings.sessionsLimit)),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.appearance = NSAppearance(named: .darkAqua)
            sessionsHost.sizingOptions = []
            sessionsHost.autoresizingMask = [.width, .height]
            window.contentView = sessionsHost
            sessionsWindow = window
            if !window.setFrameUsingName("SessionsWindow") { window.center() }
            window.setFrameAutosaveName("SessionsWindow")
        }
        applySessionsPlacement()
        settings.sessionsVisible = true
        updateMonitors()
        if sessionStore.tick() { sessionStore.save() }
        sessionsWindow?.orderFrontRegardless()
        syncSessions()
        refreshSessionHistory()
        if sessionsTimer == nil {
            // Finishes turns whose process exited, keeps the 24-hour limit current and rereads history every 5 minutes.
            sessionsTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if Date().timeIntervalSince1970 - self.sessionsHistoryScanned > 300 { self.refreshSessionHistory() }
                guard self.sessionStore.tick() else { return }
                self.sessionStore.save(); self.syncSessions()
            }
        }
    }
    func hideSessionsWindow() {
        sessionsWindow?.orderOut(nil)
        settings.sessionsVisible = false
        sessionsTimer?.invalidate(); sessionsTimer = nil
        updateMonitors()
    }
    /// Above all windows, or on the desktop: under every window, over the wallpaper and icons, and fixed in Mission Control.
    func applySessionsPlacement() {
        guard let window = sessionsWindow else { return }
        if settings.sessionsOnDesktop {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        } else {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
    }
    func syncSessions() {
        guard let window = sessionsWindow, window.isVisible else { return }
        let limit = settings.sessionsLimit
        sessionsHost.rootView = SessionGridView(sessions: sessionStore.ordered, limit: limit,
                                                open: { [weak self] session in self?.openSession(session) },
                                                hide: { [weak self] in self?.hideSessionsWindow() })
        let size = SessionGridLayout.size(limit: limit)
        if window.frame.size != size {
            // Grows and shrinks downward from the top edge, like the Picture-in-Picture window.
            let old = window.frame
            window.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
            window.invalidateShadow()
        }
    }
    /// Reads the last day's sessions from disk off the main thread, so tiles appear before each session sends a hook event.
    func refreshSessionHistory() {
        sessionsHistoryScanned = Date().timeIntervalSince1970
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = SessionHistory.scan()
            DispatchQueue.main.async {
                guard let self = self, self.sessionStore.merge(found) else { return }
                self.sessionStore.save(); self.syncSessions()
            }
        }
    }
    func sessionEvent(_ event: SessionEvent) {
        if sessionStore.apply(event) { sessionStore.save(); syncSessions() }
        // The Claude app names a session after its first turn and may rename it later: reread the title when a turn starts or ends.
        let key = "claude:" + event.session
        guard event.provider == .claude, event.event == "UserPromptSubmit" || event.event == "Stop",
              let host = sessionStore.sessions[key]?.host else { return }
        readSessionTitle(key: key, host: host, retries: event.event == "Stop" ? 2 : 0)
    }
    private func readSessionTitle(key: String, host: String, retries: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let title = SessionHistory.appTitle(host: host)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.sessionStore.retitle(key, title) { self.sessionStore.save(); self.syncSessions() }
                // Right after the first turn the app may not have written the title yet.
                guard title == nil, retries > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.readSessionTitle(key: key, host: host, retries: retries - 1)
                }
            }
        }
    }
    func openSession(_ session: Session) {
        switch SessionStore.target(for: session) {
        case .url(let url):
            NSWorkspace.shared.open(url)
        case .app(let bundleID):
            // Only an app that is still running: a closed terminal means the session is gone too.
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { NSSound.beep(); return }
            if #available(macOS 14, *) { app.activate() } else { app.activate(options: [.activateIgnoringOtherApps]) }
        case .none:
            NSSound.beep()
        }
    }
    /// The monitors run while their menu bar indicator is on or while the Sessions window is open.
    func updateMonitors() {
        let sessions = settings.sessionsVisible
        if activityEnabled || sessions { activity.start() } else { activity.stop() }
        if settings.activityEnabled(for: "claude") || sessions { claudeActivity.start() } else { claudeActivity.stop() }
    }

    func syncDesktop() {
        guard let window = desktopWindow else { return }
        desktopContent.appearance = settings.providers == .both ? nil : appearanceMode.appearance
        desktopContent.layer?.backgroundColor = palette(for: desktopContent.effectiveAppearance).background.cgColor
        let size = content.frame.size
        if window.contentView?.frame.size != size {
            let old = window.frame
            window.setFrame(NSRect(x: old.origin.x, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
        }
        desktopHost.frame = desktopContent.bounds
    }
}
