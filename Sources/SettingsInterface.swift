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
            let claudeInstalled = ClaudeClient.findCLI() != nil
            let claudeSetup = NSTextField(wrappingLabelWithString: claudeInstalled
                ? "Claude limits not loading? Click Sign in, then type /login in Terminal."
                : "Claude needs Claude Code. Click Install and sign in when Terminal asks.")
            let claudeButton = NSButton(title: claudeInstalled ? "Sign in to Claude…" : "Install Claude Code…", target: self, action: #selector(setUpClaude))
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
            var items = [heading("AI services"), row("Show limits", providerPicker), claudeSetup, claudeButton, heading("Provider settings"), row("Configure", editPicker), heading("Appearance"), row("Theme", themePicker), row("Mode", appearancePicker), activityToggle] as [NSView]
            let copies = otherCopies
            if !copies.isEmpty {
                let paths = copies.map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n")
                let warning = NSTextField(wrappingLabelWithString: "Another copy of Limitwick is on this Mac, so the widget gallery may show its old widgets. Move it to the Trash, empty the Trash, and log out and back in.\n\(paths)")
                warning.font = .systemFont(ofSize: 11); warning.tag = 902; warning.widthAnchor.constraint(equalToConstant: 372).isActive = true
                items = [heading("Other copies"), warning, NSButton(title: "Show in Finder", target: self, action: #selector(revealOtherCopies))] + items
            }
            if settingsProvider == "claude" {
                let help = NSTextField(wrappingLabelWithString: claudeHookStatusText)
                help.font = .systemFont(ofSize: 11); help.tag = 902; help.widthAnchor.constraint(equalToConstant: 372).isActive = true
                claudeHookStatus = help
                let button = ClaudeActivityMonitor.hooksInstalled()
                    ? NSButton(title: "Remove Claude hooks", target: self, action: #selector(removeClaudeHooks))
                    : NSButton(title: "Install Claude hooks", target: self, action: #selector(installClaudeHooks))
                items += [help, button]
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
        settingsWindow?.close(); settingsWindow = nil; claudeHookStatus = nil; showSettings()
    }
    var otherCopies: [URL] {
        // Copies under the pre-2.0 bundle ID still add their widgets to the gallery.
        let ids = [Bundle.main.bundleIdentifier, AppSettings.legacyBundleID].compactMap { $0 }
        return otherAppCopies(ids.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }, running: Bundle.main.bundleURL)
    }
    // Version 2.0 replaces apps under the pre-2.0 bundle ID: they are quit and moved to the Trash at launch.
    func removeLegacyCopies() {
        let copies = otherAppCopies(NSWorkspace.shared.urlsForApplications(withBundleIdentifier: AppSettings.legacyBundleID), running: Bundle.main.bundleURL).filter { !isInTrash($0) }
        guard !copies.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: AppSettings.legacyBundleID)
            running.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(5)
            while running.contains(where: { !$0.isTerminated }) && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
            // Hooks are moved off the old bundles first, so open sessions do not call a missing script.
            if ClaudeActivityMonitor.hooksInstalled() { _ = self.claudeHookSetup("refresh") }
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            let codexHooks = (try? String(contentsOf: codexHome.appendingPathComponent("hooks.json"), encoding: .utf8)) ?? ""
            let codexMoved = hooksUseBundles(codexHooks, copies, script: "activity-hook.py") && self.runHookScript("activity-setup.py", "install") == nil
            var removed: [URL] = []
            for url in copies {
                // Unregistering keeps the old widgets out of the gallery before the Trash is emptied.
                let plugins = (try? FileManager.default.contentsOfDirectory(at: url.appendingPathComponent("Contents/PlugIns"), includingPropertiesForKeys: nil)) ?? []
                plugins.forEach { self.runTool("/usr/bin/pluginkit", ["-r", $0.path]) }
                self.runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-u", url.path])
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { removed.append(url) }
            }
            DispatchQueue.main.async {
                let failed = copies.filter { !removed.contains($0) }
                let list = { (urls: [URL]) in urls.map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n") }
                var text = removed.isEmpty ? "" : "Moved to the Trash:\n\(list(removed))"
                if !failed.isEmpty { text += (text.isEmpty ? "" : "\n\n") + "Could not move, remove manually:\n\(list(failed))" }
                if codexMoved { text += "\n\nCodex activity hooks now use this app. Review and trust them in Codex Settings → Hooks." }
                let alert = NSAlert()
                alert.messageText = "Previous versions of Limitwick removed"
                alert.informativeText = text + "\n\nRemove old widgets from the desktop and add new ones from the widget gallery."
                NSApp.activate(ignoringOtherApps: true); alert.runModal()
            }
        }
    }
    func runTool(_ path: String, _ arguments: [String]) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil { process.waitUntilExit() }
    }
    @objc func revealOtherCopies() { NSWorkspace.shared.activateFileViewerSelecting(otherCopies) }
    var claudeHookStatusText: String {
        guard ClaudeActivityMonitor.hooksInstalled() else { return "Claude Code hooks are not installed. Install them to show Claude Code activity in the menu bar." }
        if !settings.activityEnabled(for: "claude") { return "Claude Code hooks are installed. Turn on activity above to show it in the menu bar." }
        if claudeActivity.lastEvent != nil { return "Claude Code hooks are installed. Receiving activity from Claude Code." }
        return "Claude Code hooks are installed. Waiting for activity: it appears in Claude Code sessions started after installation."
    }
    // Opens Terminal with the official installer when needed, then starts Claude Code to sign in.
    @objc func setUpClaude() {
        let claude = ClaudeClient.findCLI().map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
        let command = claude ?? "curl -fsSL https://claude.ai/install.sh | bash && \"$HOME/.local/bin/claude\""
        let script = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Limitwick/claude-setup.command")
        do {
            try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/zsh -l\nclear\n\(command)\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch { NSWorkspace.shared.open(URL(string: "https://code.claude.com")!) }
    }
    @objc func installClaudeHooks() { runClaudeHookSetup("install") }
    @objc func removeClaudeHooks() { runClaudeHookSetup("remove") }
    // Returns an error description, or nil on success.
    func claudeHookSetup(_ action: String) -> String? { runHookScript("claude-activity-setup.py", action) }
    func runHookScript(_ script: String, _ action: String) -> String? {
        guard let path = Bundle.main.path(forResource: script, ofType: nil, inDirectory: "useAnimations") else { return "The hook installer is missing from the app." }
        let process = Process(); let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = [path, action]
        process.standardError = errors; process.standardOutput = Pipe()
        do { try process.run() } catch { return error.localizedDescription }
        process.waitUntilExit()
        let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return process.terminationStatus == 0 ? nil : (detail.isEmpty ? "The hook installer failed." : detail)
    }
    // Keeps installed hooks pointing at the current helper script; never installs them on its own.
    func refreshClaudeHooks() {
        guard ClaudeActivityMonitor.hooksInstalled() else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in _ = self?.claudeHookSetup("refresh") }
    }
    @discardableResult func runClaudeHookSetup(_ action: String) -> Bool {
        let failure = claudeHookSetup(action)
        let alert = NSAlert()
        if let failure = failure {
            alert.messageText = "Could not update Claude hooks"; alert.informativeText = failure
        } else if action == "install" {
            alert.messageText = "Claude hooks installed"
            alert.informativeText = "Activity appears in Claude Code sessions started from now on. To include a session that is already open, type /exit in it, then run claude --continue to resume the conversation."
            settings.setActivityEnabled(true, for: "claude"); claudeActivity.start()
        } else {
            alert.messageText = "Claude hooks removed"
            alert.informativeText = "New Claude Code sessions no longer send activity. Sessions that are already open stop after they are restarted."
        }
        alert.runModal()
        reloadSettingsWindow()
        return failure == nil
    }
    @objc func providerChanged(_ sender: NSPopUpButton) {
        guard ProviderSelection.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.providers = ProviderSelection.allCases[sender.indexOfSelectedItem]
        stopUnusedRefreshTimers()
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
    }
    @objc func appearanceChanged(_ sender: NSPopUpButton) {
        guard AppearanceMode.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.setAppearance(AppearanceMode.allCases[sender.indexOfSelectedItem].rawValue, for: settingsProvider)
        applyTheme()
        resizeWindowToContent(settingsWindow)
    }
    var activityEnabled: Bool { settings.activityEnabled(for: "codex") }
    @objc func activitySettingChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        settings.setActivityEnabled(enabled, for: settingsProvider)
        if settingsProvider == "codex" {
            if enabled { activity.start() } else { activity.stop(); showActivity(nil) }
        } else {
            if enabled && !ClaudeActivityMonitor.hooksInstalled() {
                // Installing here means hooks exist before the next Claude Code session starts.
                guard runClaudeHookSetup("install") else { settings.setActivityEnabled(false, for: "claude"); reloadSettingsWindow(); return }
            }
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
        if let source = WidgetSource(rawValue: settingsProvider) { publishWidgetSnapshot(source) }
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
                case .denied: self.noticeStatus.stringValue = "Notifications are blocked by macOS. Enable Limitwick in System Settings → Notifications."
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
