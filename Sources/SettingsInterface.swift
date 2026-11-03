import AppKit
import UserNotifications

extension AppDelegate {
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
        window.appearance = nil
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
            let providerPicker = NSPopUpButton(); providerPicker.addItems(withTitles: ProviderSelection.allCases.map(\.title))
            providerPicker.selectItem(at: ProviderSelection.allCases.firstIndex(of: settings.providers) ?? 0)
            providerPicker.target = self; providerPicker.action = #selector(providerChanged(_:)); providerPicker.setAccessibilityLabel("AI services")
            let claudeSetup = NSTextField(wrappingLabelWithString: "Claude requires Claude Code. Install it from code.claude.com, then run claude in Terminal and sign in to your Claude subscription.")
            claudeSetup.font = .systemFont(ofSize: 11); claudeSetup.tag = 902
            claudeSetup.widthAnchor.constraint(equalToConstant: 372).isActive = true
            let editPicker = NSPopUpButton(); editPicker.addItems(withTitles: ["Codex", "Claude"])
            editPicker.selectItem(at: settingsProvider == "codex" ? 0 : 1)
            editPicker.target = self; editPicker.action = #selector(settingsProviderChanged(_:))
            let themePicker = NSPopUpButton(); themePicker.addItems(withTitles: PanelTheme.allCases.map(\.title))
            themePicker.selectItem(at: PanelTheme.allCases.firstIndex(of: theme(for: settingsProvider)) ?? 0)
            themePicker.target = self; themePicker.action = #selector(themeChanged(_:)); themePicker.setAccessibilityLabel("Theme")
            let appearancePicker = NSPopUpButton(); appearancePicker.addItems(withTitles: AppearanceMode.allCases.map(\.title))
            appearancePicker.selectItem(at: AppearanceMode.allCases.firstIndex(of: mode(for: settingsProvider)) ?? 0)
            appearancePicker.target = self; appearancePicker.action = #selector(appearanceChanged(_:)); appearancePicker.setAccessibilityLabel("Appearance")
            func row(_ title: String, _ control: NSView) -> NSStackView {
                let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 110).isActive = true
                let row = NSStackView(views: [label, control]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
                control.widthAnchor.constraint(equalToConstant: 210).isActive = true
                return row
            }
            let low = NSButton(checkboxWithTitle: "Low remaining quota", target: self, action: #selector(noticeSettingChanged(_:)))
            low.state = settings.enabled("low", for: settingsProvider) ? .on : .off; low.identifier = NSUserInterfaceItemIdentifier("noticeLow"); lowToggle = low
            let reset = NSButton(checkboxWithTitle: "Confirmed quota reset", target: self, action: #selector(noticeSettingChanged(_:)))
            reset.state = settings.enabled("reset", for: settingsProvider) ? .on : .off; reset.identifier = NSUserInterfaceItemIdentifier("noticeReset"); resetToggle = reset
            let threshold = NSStepper(); threshold.minValue = 1; threshold.maxValue = 99; threshold.integerValue = settings.threshold(for: settingsProvider)
            threshold.target = self; threshold.action = #selector(thresholdChanged(_:)); threshold.setAccessibilityLabel("Low quota threshold percent")
            let field = NSTextField(labelWithString: "\(settings.threshold(for: settingsProvider))%"); field.tag = 501
            let thresholdRow = NSStackView(views: [NSTextField(labelWithString: "Low threshold:"), field, threshold]); thresholdRow.orientation = .horizontal; thresholdRow.spacing = 12
            noticeStatus.maximumNumberOfLines = 0; noticeStatus.font = .systemFont(ofSize: 11); noticeStatus.tag = 902
            noticeStatus.widthAnchor.constraint(equalToConstant: 372).isActive = true
            let openSettings = NSButton(title: "Notification Settings…", target: self, action: #selector(openNotificationSettings))
            let activityToggle = NSButton(checkboxWithTitle: "Show \(settingsProvider.capitalized) activity in menu bar", target: self, action: #selector(activitySettingChanged(_:)))
            activityToggle.state = settings.activityEnabled(for: settingsProvider) ? .on : .off
            var items = [heading("AI services"), row("Show limits", providerPicker), claudeSetup, heading("Provider settings"), row("Configure", editPicker), heading("Appearance"), row("Theme", themePicker), row("Mode", appearancePicker), activityToggle] as [NSView]
            if settingsProvider == "claude" {
                let help = NSTextField(wrappingLabelWithString: ClaudeActivityMonitor.hooksInstalled() ? "Claude Code hooks are installed. Restart Claude Code if activity does not appear." : "Claude Code activity requires hooks, which are not installed. Install them, then restart Claude Code.")
                help.font = .systemFont(ofSize: 11); help.tag = 902; help.widthAnchor.constraint(equalToConstant: 372).isActive = true
                let install = NSButton(title: "Install Claude hooks", target: self, action: #selector(installClaudeHooks))
                let remove = NSButton(title: "Remove Claude hooks", target: self, action: #selector(removeClaudeHooks))
                let buttons = NSStackView(views: [install, remove]); buttons.orientation = .horizontal; buttons.spacing = 8
                items += [help, buttons]
            }
            items += [heading("Notifications"), low, reset, thresholdRow, noticeStatus, openSettings]
            let content = stack(items, spacing: 12)
            content.setCustomSpacing(22, after: activityToggle)
            settingsWindow = makeWindow(title: "Settings", content: content, width: 420)
            settingsWindow?.initialFirstResponder = themePicker
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
        updateNoticeStatus()
        resizeWindowToContent(settingsWindow)
    }
    @objc func settingsProviderChanged(_ sender: NSPopUpButton) {
        settingsProvider = sender.indexOfSelectedItem == 0 ? "codex" : "claude"
        reloadSettingsWindow()
    }
    func reloadSettingsWindow() {
        if let surface = settingsWindow?.contentView { themeSurfaces.removeAll { $0 === surface } }
        settingsWindow?.close(); settingsWindow = nil; showSettings()
    }
    @objc func installClaudeHooks() { runClaudeHookSetup("install") }
    @objc func removeClaudeHooks() { runClaudeHookSetup("remove") }
    func runClaudeHookSetup(_ action: String) {
        guard let path = Bundle.main.path(forResource: "claude-activity-setup", ofType: "py", inDirectory: "useAnimations") else { return }
        let process = Process(); let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = [path, action]
        process.standardError = errors; process.standardOutput = Pipe()
        do {
            try process.run(); process.waitUntilExit()
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let alert = NSAlert()
            alert.messageText = process.terminationStatus == 0 ? "Claude hooks \(action == "install" ? "installed" : "removed")" : "Could not update Claude hooks"
            alert.informativeText = process.terminationStatus == 0 ? "Restart Claude Code to apply the change." : detail
            alert.runModal()
            if process.terminationStatus == 0 && action == "install" {
                settings.setActivityEnabled(true, for: "claude"); claudeActivity.start()
            }
            reloadSettingsWindow()
        } catch {
            let alert = NSAlert(error: error); alert.runModal()
        }
    }
    @objc func providerChanged(_ sender: NSPopUpButton) {
        guard ProviderSelection.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.providers = ProviderSelection.allCases[sender.indexOfSelectedItem]
        if !settings.providers.includesCodex { refreshTimer?.invalidate(); refreshTimer = nil }
        if !settings.providers.includesClaude { claudeTimer?.invalidate(); claudeTimer = nil }
        applyTheme()
        updateWarningThreshold()
        updatePresentation()
        refreshNow()
    }
    @objc func themeChanged(_ sender: NSPopUpButton) {
        guard PanelTheme.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.setTheme(PanelTheme.allCases[sender.indexOfSelectedItem].rawValue, for: settingsProvider)
        applyTheme()
        resizeWindowToContent(settingsWindow)
        publishWidgetSnapshot()
    }
    @objc func appearanceChanged(_ sender: NSPopUpButton) {
        guard AppearanceMode.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.setAppearance(AppearanceMode.allCases[sender.indexOfSelectedItem].rawValue, for: settingsProvider)
        applyTheme()
        resizeWindowToContent(settingsWindow)
        publishWidgetSnapshot()
    }
    var activityEnabled: Bool { settings.activityEnabled(for: "codex") }
    @objc func activitySettingChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        settings.setActivityEnabled(enabled, for: settingsProvider)
        if settingsProvider == "codex" {
            if enabled { activity.start() } else { activity.stop(); showActivity(nil) }
        } else {
            if enabled { claudeActivity.start() } else { claudeActivity.stop(); showClaudeActivity(nil) }
        }
    }
    var noticeThreshold: Int {
        settings.threshold(for: activeProvider)
    }
    @objc func thresholdChanged(_ sender: NSStepper) {
        settings.setThreshold(sender.integerValue, for: settingsProvider)
        updateWarningThreshold()
        layoutPanel(message: stateLabel.isHidden ? nil : stateLabel.stringValue)
        publishWidgetSnapshot()
        (settingsWindow?.contentView?.viewWithTag(501) as? NSTextField)?.stringValue = "\(sender.integerValue)%"
    }
    @objc func noticeSettingChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        settings.setEnabled(sender.state == .on, kind: key == "noticeLow" ? "low" : "reset", for: settingsProvider)
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
}
