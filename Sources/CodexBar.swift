import AppKit
import Sparkle
import Foundation
import UserNotifications
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, SPUUpdaterDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 34)
    let bars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let claudeBars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let codexMark = ProviderMark(frame: NSRect(x: 0, y: 0, width: 13, height: 13))
    let claudeMark = ProviderMark(frame: NSRect(x: 0, y: 0, width: 13, height: 13))
    let multiPanel = NSScrollView(frame: .zero)
    let multiDesktop = NSScrollView(frame: .zero)
    let providersPanel = ThemedProvidersView(frame: .zero)
    let providersDesktop = ThemedProvidersView(frame: .zero)
    let activity = ActivityMonitor()
    let claudeActivity = ClaudeActivityMonitor()
    let claudeActivityIcon = ActivityIcon(frame: NSRect(x: 0, y: 0, width: 19, height: 19))
    var claudeActivityState: ActivityDisplay?
    let activityIcon = ActivityIcon(frame: NSRect(x: 1, y: 0, width: 19, height: 19))
    var activityState: ActivityDisplay?
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
    let claudeClient = ClaudeClient()
    let listener = QuotaListener()
    lazy var updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    let updateBadge = UpdateBadge(frame: .zero)
    var updateCheckTimer: Timer?
    var menuUpdateButton: MenuButton?
    var availableUpdate: String?
    var installedVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    var refreshTimer: Timer?
    lazy var refreshCoordinator = RefreshCoordinator(fetch: { [weak self] completion in
        guard let self = self else { return }
        guard let path = QuotaClient.findCLI() else { completion(.failure(QuotaError.cliNotFound)); return }
        DispatchQueue.global(qos: .utility).async {
            let result = self.client.fetch(path: path)
            DispatchQueue.main.async { completion(result) }
        }
    }, cancelFetch: { [weak self] in self?.client.cancel() }, schedule: { [weak self] interval, action in
        guard self?.settings.providers.includesCodex == true else { return }
        self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
    }, cancelTimer: { [weak self] in self?.refreshTimer?.invalidate(); self?.refreshTimer = nil })
    var claudeTimer: Timer?
    lazy var claudeCoordinator = RefreshCoordinator(fetch: { [weak self] completion in
        guard let self = self else { return }
        guard let path = ClaudeClient.findCLI() else { completion(.failure(ClaudeError.notInstalled)); return }
        DispatchQueue.global(qos: .utility).async {
            let result = self.claudeClient.fetch(path: path)
            DispatchQueue.main.async { completion(result) }
        }
    }, cancelFetch: { [weak self] in self?.claudeClient.cancel() }, schedule: { [weak self] interval, action in
        guard self?.settings.providers.includesClaude == true else { return }
        self?.claudeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
    }, cancelTimer: { [weak self] in self?.claudeTimer?.invalidate(); self?.claudeTimer = nil })
    let settings = AppSettings()
    let notices = UNUserNotificationCenter.current()
    var noticeStatus = NSTextField(wrappingLabelWithString: "")
    var lowToggle: NSButton?
    var resetToggle: NSButton?
    lazy var noticeService = NoticeService(settings: settings, authorize: { [weak self] completion in
        self?.notices.getNotificationSettings { status in
            DispatchQueue.main.async { completion(status.authorizationStatus == .authorized || status.authorizationStatus == .provisional) }
        }
    }, deliver: { [weak self] key, notice, window, completion in
        let content = UNMutableNotificationContent()
        content.title = notice.kind == "low" ? "Codex quota running low" : "Codex quota reset"
        content.body = "\(durationName(notice.duration)) limit: \(Int(window.remaining.rounded()))% remaining."
        content.sound = .default
        self?.notices.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }, current: { [weak self] in (self?.lastQuota, self?.stale ?? true) })
    lazy var claudeNotices = NoticeService(settings: settings, authorize: { [weak self] completion in
        self?.notices.getNotificationSettings { status in
            DispatchQueue.main.async { completion(status.authorizationStatus == .authorized || status.authorizationStatus == .provisional) }
        }
    }, deliver: { [weak self] key, notice, window, completion in
        let content = UNMutableNotificationContent()
        content.title = notice.kind == "low" ? "Claude quota running low" : "Claude quota reset"
        content.body = "\(durationName(notice.duration)) limit: \(Int(window.remaining.rounded()))% remaining."
        content.sound = .default
        self?.notices.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }, current: { [weak self] in (self?.claudeQuota, self?.claudeStale ?? true) }, provider: "claude")
    var running: Bool { (settings.providers.includesCodex && refreshCoordinator.running) || (settings.providers.includesClaude && claudeCoordinator.running) }
    var lastUpdate: Date?
    var lastQuota: Quota?
    var state = "Loading…"
    var stale = false
    var lastFailure: String?
    var claudeQuota: Quota?
    var claudeUpdate: Date?
    var claudeStale = false
    var claudeFailure: String?
    var displayQuota: Quota? { settings.providers == .claude ? claudeQuota : lastQuota }
    var displayStale: Bool { settings.providers == .claude ? claudeStale : stale }
    var displayUpdate: Date? { settings.providers == .claude ? claudeUpdate : lastUpdate }
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
    var settingsProvider = "codex"
    var activeProvider: String { settings.providers == .claude ? "claude" : "codex" }
    var selectedTheme: PanelTheme { PanelTheme(rawValue: settings.theme(for: activeProvider)) ?? .classic }
    var appearanceMode: AppearanceMode { AppearanceMode(rawValue: settings.appearance(for: activeProvider)) ?? .auto }
    func theme(for provider: String) -> PanelTheme { PanelTheme(rawValue: settings.theme(for: provider)) ?? .classic }
    func mode(for provider: String) -> AppearanceMode { AppearanceMode(rawValue: settings.appearance(for: provider)) ?? .auto }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        bars.frame.origin = NSPoint(x: 1, y: (button.bounds.height - 20) / 2)
        bars.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(bars)
        button.addSubview(claudeBars)
        codexMark.provider = "Codex"; claudeMark.provider = "Claude"
        button.addSubview(codexMark); button.addSubview(claudeMark)
        activityIcon.isHidden = true
        activityIcon.frame.origin.y = (button.bounds.height - 19) / 2
        activityIcon.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(activityIcon)
        claudeActivityIcon.isHidden = true
        claudeActivityIcon.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(claudeActivityIcon)
        claudeActivity.onChange = { [weak self] state in self?.showClaudeActivity(state) }
        if settings.activityEnabled(for: "claude") { claudeActivity.start() }
        activity.onChange = { [weak self] state in self?.showActivity(state) }
        if activityEnabled { activity.start() }
        updateBadge.frame = NSRect(x: button.bounds.width - 6, y: button.bounds.height - 6, width: 5, height: 5)
        updateBadge.autoresizingMask = [.minXMargin, .minYMargin]
        updateBadge.isHidden = true
        button.addSubview(updateBadge)
        let savedUpdate = settings.availableUpdate
        if savedUpdate?["installed"] == installedVersion { availableUpdate = savedUpdate?["available"] }
        updateUpdateUI()
        #if !CODEXBAR_DEVELOPMENT
        updaterController.updater.automaticallyChecksForUpdates = false
        updaterController.startUpdater()
        checkUpdateInformation()
        #endif
        button.toolTip = "Codex: top — 5 hours, bottom — week"
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
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)
        let about = NSMenuItem(title: "About Codex Bar", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        contextMenu.addItem(about)
        #if !CODEXBAR_DEVELOPMENT
        checkUpdates.target = self
        contextMenu.addItem(checkUpdates)
        #endif
        contextMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        contextMenu.addItem(quit)
        for view in [fiveHourView, weeklyView, stateLabel, additionalLabel, multiPanel] as [NSView] { content.addSubview(view) }
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityDisplayChanged(_:)), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        layoutPanel(message: "Loading…")
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        if settings.desktopVisible { showDesktopWindow() }
        publishWidgetSnapshot(previousSnapshot: WidgetSnapshot.read())
        refreshCoordinator.onStart = { [weak self] in self?.refreshStarted() }
        refreshCoordinator.onFinish = { [weak self] result in self?.finish(result) }
        claudeCoordinator.onStart = { [weak self] in self?.refreshStarted() }
        claudeCoordinator.onFinish = { [weak self] result in self?.finishClaude(result) }
        refreshNow()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.listener.run(findPath: { QuotaClient.findCLI() }) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if self.settings.providers.includesCodex { self.refreshCoordinator.changed() }
                }
            }
        }
        ageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.updateAge() }
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
    @objc func didWake(_ notification: Notification) {
        updateAge()
        if settings.providers.includesCodex { refreshCoordinator.changed() }
        if settings.providers.includesClaude { claudeCoordinator.changed() }
    }
    var updateMenuTitle: String {
        availableUpdate.map { "Update to \($0)…" } ?? "Check for Updates…"
    }
    func updateUpdateUI() {
        updateBadge.isHidden = !(availableUpdate.map { isMajorUpdate($0, installedVersion: installedVersion) } ?? false)
        checkUpdates.title = updateMenuTitle
        menuUpdateButton?.title = updateMenuTitle
        menuUpdateButton?.setAccessibilityLabel(updateMenuTitle)
        menuUpdateButton?.highlightsUpdate = availableUpdate != nil
        updateStatusAccessibility()
    }
    func updateStatusAccessibility() {
        let update = availableUpdate.map { ". Update \($0) available" } ?? ""
        let activityDescription = (settings.providers.includesCodex ? (activityState.map { ". \($0.label)" } ?? "") : "") + (settings.providers.includesClaude ? (claudeActivityState.map { ". Claude \($0 == .tool ? "using a tool" : $0 == .working ? "working" : "finished")" } ?? "") : "")
        let descriptions = presentations.map { "\($0.name). \($0.status). \(describe("5 hours", $0.quota?.fiveHour)). \(describe("Week", $0.quota?.weekly))" }.joined(separator: ". ")
        status.button?.setAccessibilityLabel("\(descriptions)\(activityDescription)\(update)")
        status.button?.toolTip = presentations.map { "\($0.name): top — 5 hours, bottom — week" }.joined(separator: "\n")
    }
    func showActivity(_ activityState: ActivityDisplay?) {
        self.activityState = activityState
        layoutStatusBars()
        activityIcon.show(settings.providers.includesCodex ? activityState : nil)
        updateStatusAccessibility()
    }
    func showClaudeActivity(_ state: ActivityDisplay?) {
        claudeActivityState = state
        layoutStatusBars(); claudeActivityIcon.show(settings.providers.includesClaude ? state : nil); updateStatusAccessibility()
    }
    @objc func accessibilityDisplayChanged(_ notification: Notification) { activityIcon.show(activityState); claudeActivityIcon.show(claudeActivityState) }
    func checkUpdateInformation() {
        updateCheckTimer?.invalidate()
        let updater = updaterController.updater
        if updater.sessionInProgress {
            updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in self?.checkUpdateInformation() }
            return
        }
        updater.checkForUpdateInformation()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: false) { [weak self] _ in self?.checkUpdateInformation() }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableUpdate = item.displayVersionString
        settings.availableUpdate = ["installed": installedVersion, "available": item.displayVersionString]
        updateUpdateUI()
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableUpdate = nil
        settings.availableUpdate = nil
        updateUpdateUI()
    }
    @objc func menuRefresh() { menuPopover?.performClose(nil); refreshNow() }
    @objc func menuUpdates() { menuPopover?.performClose(nil); checkForUpdates() }
    @objc func menuQuit() { menuPopover?.performClose(nil); NSApp.terminate(nil) }
    @objc func checkForUpdates() {
        if !updaterController.updater.canCheckForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.checkForUpdates() }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }
    @objc func refreshNow() {
        if settings.providers.includesCodex { refreshCoordinator.refresh() }
        if settings.providers.includesClaude { claudeCoordinator.refresh() }
    }
    func layoutStatusBars() {
        let dual = settings.providers == .both
        let layout = ActivityBarLayout(codex: settings.providers.includesCodex, claude: settings.providers.includesClaude,
                                       codexActive: activityState != nil, claudeActive: claudeActivityState != nil)
        let y = ((status.button?.bounds.height ?? 22) - 20) / 2
        activityIcon.isHidden = layout.codexIcon == nil; claudeActivityIcon.isHidden = layout.claudeIcon == nil
        if let x = layout.codexIcon { activityIcon.frame.origin = NSPoint(x: x, y: y) }
        if let x = layout.claudeIcon { claudeActivityIcon.frame.origin = NSPoint(x: x, y: y) }
        if let x = layout.codexMark { codexMark.frame = NSRect(x: x, y: y + 3, width: 13, height: 13) }
        if let x = layout.claudeMark { claudeMark.frame = NSRect(x: x, y: y + 3, width: 13, height: 13) }
        if let x = layout.codexBars ?? (dual ? nil : layout.claudeBars) { bars.frame = NSRect(x: x, y: y, width: 32, height: 20) }
        if dual, let x = layout.claudeBars { claudeBars.frame = NSRect(x: x, y: y, width: 32, height: 20) }
        status.length = layout.width
        codexMark.isHidden = !dual; claudeMark.isHidden = !dual; claudeBars.isHidden = !dual
    }
    func ageDescription(_ date: Date?) -> String {
        guard let date = date else { return "No data yet" }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        return minutes == 0 ? "Updated just now" : "Updated \(minutes) min ago"
    }
    var presentations: [ProviderPresentation] {
        var result: [ProviderPresentation] = []
        func info(_ name: String, _ quota: Quota?, _ stale: Bool, _ failure: String?, _ date: Date?, _ running: Bool) -> ProviderPresentation {
            let status: String
            if let failure = failure { status = failure + (quota != nil ? " · Previous data · " + ageDescription(date) : "") }
            else if running { status = quota == nil ? "Loading…" : "Updating… · " + ageDescription(date) }
            else { status = ageDescription(date) }
            return ProviderPresentation(name: name, quota: quota, stale: stale, status: status, updated: date)
        }
        if settings.providers.includesCodex { result.append(info("Codex", lastQuota, stale, lastFailure, lastUpdate, refreshCoordinator.running)) }
        if settings.providers.includesClaude { result.append(info("Claude", claudeQuota, claudeStale, claudeFailure, claudeUpdate, claudeCoordinator.running)) }
        return result
    }
    func refreshStarted() { updatePresentation() }
    func finish(_ result: Result<Quota, Error>) {
        switch result {
        case .success(let quota):
            lastQuota = quota; lastUpdate = Date(); stale = false; lastFailure = nil
            if settings.providers.includesCodex { noticeService.process(quota) }
        case .failure(let error):
            stale = lastQuota != nil; lastFailure = error.localizedDescription
        }
        updatePresentation()
    }
    func finishClaude(_ result: Result<Quota, Error>) {
        switch result {
        case .success(let quota):
            claudeQuota = quota; claudeUpdate = Date(); claudeStale = false; claudeFailure = nil
            if settings.providers.includesClaude { claudeNotices.process(quota) }
        case .failure(let error):
            claudeStale = claudeQuota != nil; claudeFailure = error.localizedDescription
        }
        updatePresentation()
    }
    func updatePresentation(publishSnapshot: Bool = true) {
        let dual = settings.providers == .both
        let first = presentations.first
        let quota = displayQuota
        bars.values = [quota?.fiveHour?.remaining, quota?.weekly?.remaining]
        bars.stale = displayStale
        claudeBars.values = [claudeQuota?.fiveHour?.remaining, claudeQuota?.weekly?.remaining]
        claudeBars.stale = claudeStale
        fiveHourView.update(quota?.fiveHour, reset: resetDescription(quota?.fiveHour))
        weeklyView.update(quota?.weekly, reset: resetDescription(quota?.weekly))
        updatedLabel.stringValue = ageDescription(displayUpdate)
        state = first?.status ?? "Loading…"
        let messages = presentations.compactMap { item -> String? in
            guard item.status.contains("Previous data") || item.quota == nil else { return nil }
            return dual ? "\(item.name): \(item.status)" : item.status
        }
        let extras = presentations.flatMap { item -> [String] in
            let prefix = dual ? "\(item.name): " : ""
            let durations = item.quota?.additional.map { prefix + "\(durationName($0.durationMinutes)): \(Int($0.remaining.rounded()))% remaining · \(ResetText.describe($0.reset))" } ?? []
            let named = item.quota?.namedAdditional.map { prefix + "\($0.name) week: \(Int($0.remaining.rounded()))% remaining · \(ResetText.describe($0.reset))" } ?? []
            let conflicts = item.quota?.conflictingDurations.map { prefix + "Conflicting \(durationName($0)) values; unavailable" } ?? []
            return durations + named + conflicts
        }
        additionalLabel.stringValue = extras.joined(separator: "\n")
        refresh.isEnabled = !running; menuRefreshButton?.isEnabled = !running
        layoutStatusBars()
        activityIcon.show(settings.providers.includesCodex ? activityState : nil)
        claudeActivityIcon.show(settings.providers.includesClaude ? claudeActivityState : nil)
        layoutPanel(message: messages.isEmpty ? nil : messages.joined(separator: "\n"))
        if publishSnapshot { publishWidgetSnapshot() }
        updateStatusAccessibility()
    }
    func publishWidgetSnapshot(previousSnapshot: WidgetSnapshot? = WidgetSnapshot.read()) {
        let previous = previousSnapshot.flatMap { snapshot -> WidgetSnapshot? in
            let provider = snapshot.provider ?? "codex"
            return settings.providers != .both && settings.providers.rawValue == provider ? snapshot : nil
        }
        let five = displayQuota?.fiveHour ?? previous?.five.map { QuotaWindow(durationMinutes: 300, remaining: $0, reset: previous?.fiveReset) }
        let week = displayQuota?.weekly ?? previous?.week.map { QuotaWindow(durationMinutes: 10080, remaining: $0, reset: previous?.weekReset) }
        let summary = settings.providers != .both && displayQuota == nil && previous != nil
            ? "\(settings.providers.title). \(describe("5 hours", five)). \(describe("Week", week)). Previous data."
            : presentations.map { "\($0.name). \(describe("5 hours", $0.quota?.fiveHour)). \(describe("Week", $0.quota?.weekly)). \($0.status)" }.joined(separator: ". ")
        let widget: NSView
        if settings.providers == .both {
            let both = MultiProviderView(frame: NSRect(x: 0, y: 0, width: 340, height: 170))
            both.providers = presentations; both.colors = palette(for: content.effectiveAppearance); both.threshold = noticeThreshold; both.providerThresholds = ["codex": settings.threshold(for: "codex"), "claude": settings.threshold(for: "claude")]
            widget = both
        } else {
            widget = WidgetThemeView(theme: selectedTheme,
                data: ThemeData(fiveHour: five?.remaining, weekly: week?.remaining,
                                fiveReset: resetDescription(five), weekReset: resetDescription(week),
                                accessibility: summary, warningThreshold: noticeThreshold, providerName: activeProvider.capitalized),
                previous: displayStale || displayQuota == nil, appearance: content.effectiveAppearance)
        }
        var image: Data?
        if let bitmap = widget.bitmapImageRepForCachingDisplay(in: widget.bounds) {
            widget.cacheDisplay(in: widget.bounds, to: bitmap)
            image = bitmap.representation(using: .png, properties: [:])
        }
        var snapshot = WidgetSnapshot(five: five?.remaining, week: week?.remaining,
                       fiveReset: five?.reset, weekReset: week?.reset,
                       updated: displayUpdate ?? previous?.updated, stale: displayStale || displayQuota == nil, threshold: noticeThreshold,
                       panelImage: image, accessibility: summary, appVersion: installedVersion)
        snapshot.provider = settings.providers.rawValue
        if settings.providers == .both {
            snapshot.claudeFive = claudeQuota?.fiveHour?.remaining
            snapshot.claudeWeek = claudeQuota?.weekly?.remaining
            snapshot.claudeFiveReset = claudeQuota?.fiveHour?.reset
            snapshot.claudeWeekReset = claudeQuota?.weekly?.reset
        }
        snapshot.write()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }
    func applicationWillTerminate(_ notification: Notification) {
        stopClickMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        refreshCoordinator.stop(); claudeCoordinator.stop(); ageTimer?.invalidate(); updateCheckTimer?.invalidate()
        activity.stop(); claudeActivity.stop(); listener.cancel()
    }
    func updateAge() { updatePresentation(publishSnapshot: false) }
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
