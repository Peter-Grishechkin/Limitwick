import AppKit
import Sparkle
import Foundation
import UserNotifications
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, SPUUpdaterDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 34)
    let bars = Bars(frame: NSRect(x: 0, y: 0, width: 32, height: 20))
    let activity = ActivityMonitor()
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
        self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
    }, cancelTimer: { [weak self] in self?.refreshTimer?.invalidate(); self?.refreshTimer = nil })
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
    var running: Bool { refreshCoordinator.running }
    var lastUpdate: Date?
    var lastQuota: Quota?
    var state = "Loading…"
    var stale = false
    var lastFailure: String?
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
    lazy var selectedTheme: PanelTheme = PanelTheme(rawValue: settings.theme) ?? .classic
    lazy var appearanceMode: AppearanceMode = AppearanceMode(rawValue: settings.appearance) ?? .auto

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        bars.frame.origin = NSPoint(x: 1, y: (button.bounds.height - 20) / 2)
        bars.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(bars)
        activityIcon.isHidden = true
        activityIcon.frame.origin.y = (button.bounds.height - 19) / 2
        activityIcon.autoresizingMask = [.minYMargin, .maxYMargin]
        button.addSubview(activityIcon)
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
        for view in [fiveHourView, weeklyView, stateLabel, additionalLabel] as [NSView] { content.addSubview(view) }
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
        refreshNow()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.listener.run(findPath: { QuotaClient.findCLI() }) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.refreshCoordinator.changed()
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
        refreshCoordinator.changed()
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
        let activityDescription = activityState.map { ". \($0.label)" } ?? ""
        status.button?.setAccessibilityLabel("Codex. \(state). \(describe("5 hours", lastQuota?.fiveHour)). \(describe("Week", lastQuota?.weekly)). \(updatedLabel.stringValue)\(activityDescription)\(update)")
    }
    func showActivity(_ activityState: ActivityDisplay?) {
        self.activityState = activityState
        status.length = activityState == nil ? 34 : 56
        bars.frame.origin.x = activityState == nil ? 1 : 23
        activityIcon.show(activityState)
        updateStatusAccessibility()
    }
    @objc func accessibilityDisplayChanged(_ notification: Notification) { activityIcon.show(activityState) }
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
    @objc func refreshNow() { refreshCoordinator.refresh() }
    func refreshStarted() {
        refresh.isEnabled = false; menuRefreshButton?.isEnabled = false
        state = lastQuota == nil ? "Loading…" : (stale ? "Updating… Previous attempt: \(lastFailure ?? "failed") — showing previous data" : "Updating…")
        layoutPanel(message: state)
    }
    func finish(_ result: Result<Quota, Error>) {
        refresh.isEnabled = true; menuRefreshButton?.isEnabled = true
        var message: String?
        switch result {
        case .success(let quota):
            noticeService.process(quota)
            lastQuota = quota; lastUpdate = Date()
            state = "Up to date"
            stale = false
            lastFailure = nil

        case .failure(let error):
            stale = lastQuota != nil
            lastFailure = error.localizedDescription
            state = "\(error.localizedDescription)\(stale ? " — showing previous data (\(updatedLabel.stringValue.lowercased()))" : "")"
            message = state
        }
        if let quota = lastQuota {
            bars.values = [quota.fiveHour?.remaining, quota.weekly?.remaining]
            fiveHourView.update(quota.fiveHour, reset: resetDescription(quota.fiveHour))
            weeklyView.update(quota.weekly, reset: resetDescription(quota.weekly))
        }
        bars.stale = stale
        updateAge()
        layoutPanel(message: message)
        publishWidgetSnapshot(previousSnapshot: lastQuota == nil ? WidgetSnapshot.read() : nil)
        updateStatusAccessibility()
    }
    func publishWidgetSnapshot(previousSnapshot: WidgetSnapshot? = nil) {
        // Render specifically for the medium widget; the popup can grow independently.
        let five = lastQuota?.fiveHour ?? previousSnapshot?.five.map { QuotaWindow(durationMinutes: 300, remaining: $0, reset: previousSnapshot?.fiveReset) }
        let week = lastQuota?.weekly ?? previousSnapshot?.week.map { QuotaWindow(durationMinutes: 10080, remaining: $0, reset: previousSnapshot?.weekReset) }
        let summary = "\(describe("5 hours", five)). \(describe("Week", week)). \(state)"
        let widget = WidgetThemeView(theme: selectedTheme,
            data: ThemeData(fiveHour: five?.remaining, weekly: week?.remaining,
                            fiveReset: resetDescription(five), weekReset: resetDescription(week),
                            accessibility: summary, warningThreshold: noticeThreshold),
            previous: stale || lastQuota == nil, appearance: content.effectiveAppearance)
        let bounds = widget.bounds
        var image: Data?
        if let bitmap = widget.bitmapImageRepForCachingDisplay(in: bounds) {
            widget.cacheDisplay(in: bounds, to: bitmap)
            image = bitmap.representation(using: .png, properties: [:])
        }
        WidgetSnapshot(five: five?.remaining, week: week?.remaining,
                       fiveReset: five?.reset, weekReset: week?.reset,
                       updated: lastUpdate ?? previousSnapshot?.updated, stale: stale || lastQuota == nil, threshold: noticeThreshold,
                       panelImage: image, accessibility: summary, appVersion: installedVersion).write()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }
    func applicationWillTerminate(_ notification: Notification) {
        stopClickMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        refreshCoordinator.stop(); ageTimer?.invalidate(); updateCheckTimer?.invalidate()
        activity.stop()
        listener.cancel()
    }
    func updateAge() {
        if let date = lastUpdate {
            let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
            updatedLabel.stringValue = minutes == 0 ? "Updated just now" : "Updated \(minutes) min ago"
        } else { updatedLabel.stringValue = "Updated: —" }
        if stale, !running, let failure = lastFailure {
            let message = "\(failure) — showing previous data (\(updatedLabel.stringValue.lowercased()))"
            if state != message { state = message; layoutPanel(message: message) }
        }
        if let quota = lastQuota {
            fiveHourView.update(quota.fiveHour, reset: resetDescription(quota.fiveHour))
            weeklyView.update(quota.weekly, reset: resetDescription(quota.weekly))
            let conflicts = quota.conflictingDurations.map { "Conflicting \(durationName($0)) values; unavailable" }
            let extras = quota.additional.map { "\(durationName($0.durationMinutes)): \(Int($0.remaining.rounded()))% remaining · \(ResetText.describe($0.reset))" }
            let newText = (extras + conflicts).joined(separator: "\n")
            if additionalLabel.stringValue != newText { additionalLabel.stringValue = newText; layoutPanel(message: stateLabel.isHidden ? nil : stateLabel.stringValue) }
        }
        layoutPanel(message: stateLabel.isHidden ? nil : stateLabel.stringValue)
    }
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
