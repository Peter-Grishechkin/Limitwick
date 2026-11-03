import AppKit

@main struct PanelThemeTests {
    static func main() {
        _ = NSApplication.shared
        let reset = Date().addingTimeInterval(3600)
        let quota = Quota(windows: [QuotaWindow(durationMinutes: 300, remaining: 72, reset: reset), QuotaWindow(durationMinutes: 10080, remaining: 31, reset: reset), QuotaWindow(durationMinutes: 60, remaining: 12, reset: reset)], conflictingDurations: [120], namedAdditional: [NamedQuotaWindow(name: "Extra", remaining: 22, reset: reset)])
        let claudeQuota = Quota(windows: [QuotaWindow(durationMinutes: 300, remaining: 45, reset: reset), QuotaWindow(durationMinutes: 10080, remaining: 84, reset: reset)], conflictingDurations: [])
        let error = String(repeating: "Long error message with recovery advice. ", count: 35)
        let providers = [ProviderPresentation(name: "Codex", quota: quota, stale: true, status: error, updated: nil), ProviderPresentation(name: "Claude", quota: claudeQuota, stale: false, status: "Updated just now", updated: nil)]
        for theme in PanelTheme.allCases {
            for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
                let view = ThemedProvidersView(frame: .zero)
                let appearance = NSAppearance(named: appearanceName)!
                view.appearance = appearance
                let height = view.configure(providers, theme: theme, appearance: appearance, threshold: 20)
                view.frame = NSRect(x: 0, y: 0, width: 340, height: height)
                let labels = view.subviews.compactMap { $0 as? NSTextField }
                precondition(labels.map(\.stringValue).contains("Codex") && labels.map(\.stringValue).contains("Claude"))
                precondition(!labels.contains { $0.stringValue == "Updated just now" })
                precondition(labels.contains { $0.stringValue == error && $0.frame.height > 100 })
                precondition(labels.contains { $0.stringValue.contains("Extra week: 22%") && $0.stringValue.contains("Conflicting") })
                precondition(view.subviews.allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY <= height })
                let themed = view.subviews.compactMap { $0 as? ThemeView }
                if theme == .classic {
                    let tiles = view.subviews.compactMap { $0 as? QuotaTile }
                    precondition(tiles.count == 4 && tiles[0].ring.value == 72 && tiles[3].ring.value == 84)
                }
                else {
                    precondition(themed.count == 2 && themed[0].data.fiveHour == 72 && themed[1].data.weekly == 84)
                    precondition(themed[0].data.providerName == "Codex" && themed[1].data.providerName == "Claude")
                }
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
                try! png.write(to: URL(fileURLWithPath: "build/panel-\(theme.rawValue)-\(appearanceName == .aqua ? "light" : "dark").png"))
            }
        }
        for theme in PanelTheme.allCases {
            let root = ThemedProvidersView(frame: .zero)
            let height = root.configureSeparately(providers, systemAppearance: NSAppearance(named: .aqua)!) { provider in
                provider == "codex" ? (theme, .light, 10) : (.terminal, .dark, 40)
            }
            root.frame = NSRect(x: 0, y: 0, width: 340, height: height)
            let blocks = root.subviews.compactMap { $0 as? ThemedProvidersView }
            precondition(blocks.count == 2 && blocks[0].frame.maxY <= blocks[1].frame.minY)
            precondition(blocks[0].effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
            precondition(blocks[1].effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            let claudeView = blocks[1].subviews.compactMap { $0 as? ThemeView }.first!
            precondition(claudeView is TerminalThemeView && claudeView.data.warningThreshold == 40 && claudeView.data.weekly == 84)
            precondition(!blocks[1].subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Updated just now" })
            guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { fatalError("No mixed bitmap") }
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/panel-mixed-\(theme.rawValue).png"))
        }
        print("Panel theme tests passed (six themes, light and dark, mixed blocks and long messages).")
    }
}
