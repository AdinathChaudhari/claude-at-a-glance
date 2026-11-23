import AppKit
import SwiftUI
import GlanceCore

@main
struct ClaudeAtAGlanceApp: App {
    @State private var store = UsageStore()
    @State private var statsStore = StatsStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        applyAppearance(AppearanceChoice.load())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store, statsStore: statsStore)
        } label: {
            Text(store.menuBarTitle)
                .foregroundStyle(tint)
                .task {
                    store.start()
                    statsStore.start()
                    store.startUpdateChecks(localVersion: AppVersion.current)
                }
        }
        .menuBarExtraStyle(.window)
    }

    private var tint: Color {
        switch store.worstSeverity {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

enum AppVersion {
    /// Bundle version, or "0.0.0" when run via `swift run` (no Info.plist), which hides the update banner.
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

/// Sets the app-wide appearance so the MenuBarExtra panel material follows too.
@MainActor func applyAppearance(_ choice: AppearanceChoice) {
    switch choice {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
