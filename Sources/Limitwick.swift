import AppKit
import SwiftUI
import Sparkle
import Foundation
import UserNotifications
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, SPUUpdaterDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 34)
    let bars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let claudeBars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let codexMark = ProviderMark(frame: NSRect(x: 0, y: 0, width: 18, height: 20))
    let claudeMark = ProviderMark(frame: NSRect(x: 0, y: 0, width: 18, height: 20))
    let activity = ActivityMonitor()
    let claudeActivity = ClaudeActivityMonitor()
    let claudeActivityIcon = ActivityIcon(frame: NSRect(x: 0, y: 0, width: 19, height: 19))
    var claudeActivityState: ActivityDisplay?
    let activityIcon = ActivityIcon(frame: NSRect(x: 1, y: 0, width: 19, height: 19))
    var activityState: ActivityDisplay?
    let popover = NSPopover()
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 170))
    // The panel and the Picture-in-Picture window show the same SwiftUI cards.
    let panelHost = NSHostingView(rootView: QuotaPanelView(entries: []))
    let desktopHost = NSHostingView(rootView: QuotaPanelView(entries: []))
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
        guard self?.shouldRefresh(.codex) == true else { return }
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
        guard self?.shouldRefresh(.claude) == true else { return }
        self?.claudeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
    }, cancelTimer: { [weak self] in self?.claudeTimer?.invalidate(); self?.claudeTimer = nil })
    let settings: AppSettings = {
        AppSettings.importLegacy(UserDefaults.standard.persistentDomain(forName: AppSettings.legacyBundleID), into: .standard)
        return AppSettings()
    }()
    let notices = UNUserNotificationCenter.current()
    var noticeStatus = NSTextField(wrappingLabelWithString: "")
    var lowToggle: NSButton?
    var hookStatus: NSTextField?
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
    private var widgetDiscoveryTimer: Timer?
    private var installedWidgetKinds: Set<String> = []
    private var widgetSources: Set<WidgetSource> = []
    private var discoveringWidgets = false
    private var terminating = false
    var globalClickMonitor: Any?
    var localClickMonitor: Any?
    var desktopWindow: NSWindow?
    let desktopContent = NSView()
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var menuPopover: NSPopover?
    var menuRefreshButton: NSButton?
    var themeSurfaces: [ThemedSurface] = []
    var settingsProvider = "codex"
    var activeProvider: String { settings.providers == .claude ? "claude" : "codex" }
    var selectedTheme: PanelTheme { PanelTheme(stored: settings.theme(for: activeProvider)) }
    var appearanceMode: AppearanceMode { AppearanceMode(rawValue: settings.appearance(for: activeProvider)) ?? .auto }
    func theme(for provider: String) -> PanelTheme { PanelTheme(stored: settings.theme(for: provider)) }
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
        refreshClaudeHooks()
        removeLegacyCopies()
        activity.onChange = { [weak self] state in self?.showActivity(state) }
        if activityEnabled { activity.start() }
        updateBadge.frame = NSRect(x: button.bounds.width - 6, y: button.bounds.height - 6, width: 5, height: 5)
        updateBadge.autoresizingMask = [.minXMargin, .minYMargin]
        updateBadge.isHidden = true
        button.addSubview(updateBadge)
        let savedUpdate = settings.availableUpdate
        if savedUpdate?["installed"] == installedVersion { availableUpdate = savedUpdate?["available"] }
        updateUpdateUI()
        #if !LIMITWICK_DEVELOPMENT
        updaterController.updater.automaticallyChecksForUpdates = false
        updaterController.startUpdater()
        checkUpdateInformation()
        #endif
        button.toolTip = "Codex: top — 5 hours, bottom — week"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        refresh.target = self
        contextMenu.autoenablesItems = false
        contextMenu.addItem(refresh)
        contextMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)
        let about = NSMenuItem(title: "About Limitwick", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        contextMenu.addItem(about)
        #if !LIMITWICK_DEVELOPMENT
        checkUpdates.target = self
        contextMenu.addItem(checkUpdates)
        #endif
        contextMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        contextMenu.addItem(quit)
        panelHost.sizingOptions = []
        panelHost.autoresizingMask = [.width, .height]
        content.addSubview(panelHost)
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
        layoutPanel()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        if settings.desktopVisible { showDesktopWindow() }
        for source in WidgetSource.allCases {
            var snapshot = WidgetSnapshot.read(source) ?? WidgetSnapshot.migrate(source) ?? WidgetSnapshot()
            snapshot.state = snapshot.hasData ? .stale : .waiting
            snapshot.threshold = settings.threshold(for: source.rawValue)
            snapshot.write(source)
        }
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
                    if self.shouldRefresh(.codex) { self.refreshCoordinator.changed() }
                }
            }
        }
        if #available(macOS 14, *) {
            widgetDiscoveryTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
                self?.discoverWidgets()
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
            showPanel(relativeTo: button)
            if popover.isShown { startClickMonitoring() }
        }
    }
    /// On macOS 27 the system NSPopover show animation scales up, pauses for a frame and then keeps
    /// settling for ~0.25 s. Show without it and fade the window in with one ease-out instead.
    /// Closing and content-size changes keep the system animation.
    func showPanel(relativeTo button: NSView) {
        popover.animates = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.animates = true
        guard let window = popover.contentViewController?.view.window else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
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
    func popoverDidClose(_ notification: Notification) {
        stopClickMonitoring()
        popover.contentViewController?.view.window?.alphaValue = 1
    }
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
        discoverWidgets()
        if shouldRefresh(.codex) { refreshCoordinator.changed() }
        if shouldRefresh(.claude) { claudeCoordinator.changed() }
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
        hookStatus?.stringValue = hookStatusText
    }
    func showClaudeActivity(_ state: ActivityDisplay?) {
        claudeActivityState = state
        layoutStatusBars(); claudeActivityIcon.show(settings.providers.includesClaude ? state : nil); updateStatusAccessibility()
        hookStatus?.stringValue = hookStatusText
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
        discoverWidgets()
        for source in WidgetSource.allCases where shouldRefresh(source) {
            coordinator(for: source).refresh()
        }
    }

    func shouldRefresh(_ source: WidgetSource) -> Bool {
        let visible = source == .codex ? settings.providers.includesCodex : settings.providers.includesClaude
        return source.needsRefresh(menuVisible: visible, installed: widgetSources)
    }

    private func coordinator(for source: WidgetSource) -> RefreshCoordinator {
        source == .codex ? refreshCoordinator : claudeCoordinator
    }

    private func discoverWidgets() {
        guard #available(macOS 14, *), !discoveringWidgets else { return }
        discoveringWidgets = true
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.terminating else { return }
                self.discoveringWidgets = false
                guard case .success(let configurations) = result else { return }
                let variants = WidgetVariant.installed(in: Set(configurations.map(\.kind)))
                let previousSources = self.widgetSources
                let previousKinds = self.installedWidgetKinds
                self.installedWidgetKinds = Set(variants.map(\.kind))
                self.widgetSources = Set(variants.map(\.source))
                for kind in self.installedWidgetKinds.subtracting(previousKinds) {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
                self.stopUnusedRefreshTimers()
                for source in self.widgetSources.subtracting(previousSources) {
                    let visible = source == .codex ? self.settings.providers.includesCodex : self.settings.providers.includesClaude
                    if !visible { self.coordinator(for: source).refresh() }
                }
            }
        }
    }

    func stopUnusedRefreshTimers() {
        if !shouldRefresh(.codex) { refreshTimer?.invalidate(); refreshTimer = nil }
        if !shouldRefresh(.claude) { claudeTimer?.invalidate(); claudeTimer = nil }
    }

    func layoutStatusBars() {
        let dual = settings.providers == .both
        let layout = ActivityBarLayout(codex: settings.providers.includesCodex, claude: settings.providers.includesClaude,
                                       codexActive: activityState != nil, claudeActive: claudeActivityState != nil)
        let y = ((status.button?.bounds.height ?? 22) - 20) / 2
        activityIcon.isHidden = layout.codexIcon == nil; claudeActivityIcon.isHidden = layout.claudeIcon == nil
        if let x = layout.codexIcon { activityIcon.frame.origin = NSPoint(x: x, y: y) }
        if let x = layout.claudeIcon { claudeActivityIcon.frame.origin = NSPoint(x: x, y: y) }
        if let x = layout.codexMark { codexMark.frame = NSRect(x: x, y: y, width: 18, height: 20) }
        if let x = layout.claudeMark { claudeMark.frame = NSRect(x: x, y: y, width: 18, height: 20) }
        if let x = layout.codexBars ?? (dual ? nil : layout.claudeBars) { bars.frame = NSRect(x: x, y: y, width: 32, height: 20) }
        if dual, let x = layout.claudeBars { claudeBars.frame = NSRect(x: x, y: y, width: 32, height: 20) }
        status.length = layout.width
        codexMark.isHidden = !dual; claudeMark.isHidden = !dual; claudeBars.isHidden = !dual
    }
    func ageDescription(_ date: Date?) -> String {
        QuotaCardModel.age(date)
    }
    var presentations: [ProviderPresentation] {
        var result: [ProviderPresentation] = []
        func info(_ name: String, _ quota: Quota?, _ stale: Bool, _ failure: String?, _ date: Date?, _ running: Bool) -> ProviderPresentation {
            let status: String
            if let failure = failure { status = failure + (quota != nil ? " · Previous data · " + ageDescription(date) : "") }
            else if running { status = quota == nil ? "Loading…" : "Updating… · " + ageDescription(date) }
            else { status = ageDescription(date) }
            return ProviderPresentation(name: name, quota: quota, stale: stale, status: status, updated: date, failure: failure, running: running)
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
        publishWidgetSnapshot(.codex)
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
        publishWidgetSnapshot(.claude)
        updatePresentation()
    }
    func updatePresentation() {
        let first = presentations.first
        let quota = displayQuota
        bars.values = [quota?.fiveHour?.remaining, quota?.weekly?.remaining]
        bars.stale = displayStale
        claudeBars.values = [claudeQuota?.fiveHour?.remaining, claudeQuota?.weekly?.remaining]
        claudeBars.stale = claudeStale
        state = first?.status ?? "Loading…"
        refresh.isEnabled = !running; menuRefreshButton?.isEnabled = !running
        layoutStatusBars()
        activityIcon.show(settings.providers.includesCodex ? activityState : nil)
        claudeActivityIcon.show(settings.providers.includesClaude ? claudeActivityState : nil)
        layoutPanel()
    }

    func publishWidgetSnapshot(_ source: WidgetSource) {
        let quota = source == .codex ? lastQuota : claudeQuota
        let updated = source == .codex ? lastUpdate : claudeUpdate
        let failure = source == .codex ? lastFailure : claudeFailure
        var snapshot = WidgetSnapshot.read(source) ?? WidgetSnapshot()
        if let quota {
            snapshot.five = quota.fiveHour?.remaining
            snapshot.week = quota.weekly?.remaining
            snapshot.fiveReset = quota.fiveHour?.reset
            snapshot.weekReset = quota.weekly?.reset
            snapshot.updated = updated
        }
        if failure != nil {
            snapshot.state = snapshot.hasData ? .stale : .unavailable
        } else if quota != nil {
            snapshot.state = snapshot.hasData ? .current : .unavailable
        }
        snapshot.threshold = settings.threshold(for: source.rawValue)
        guard snapshot.write(source), #available(macOS 14, *) else { return }
        for variant in WidgetVariant.installed(in: installedWidgetKinds) where variant.source == source {
            WidgetCenter.shared.reloadTimelines(ofKind: variant.kind)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        stopClickMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        terminating = true
        widgetDiscoveryTimer?.invalidate()
        refreshCoordinator.stop(); claudeCoordinator.stop(); ageTimer?.invalidate(); updateCheckTimer?.invalidate()
        activity.stop(); claudeActivity.stop(); listener.cancel()
    }
    func updateAge() { updatePresentation() }
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
@main struct LimitwickMain {
    static func main() {
        let app = NSApplication.shared
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position Item-0": 120])
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
