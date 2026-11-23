import AppKit
import SwiftUI
import GlanceCore

@main
struct ClaudeAtAGlanceApp: App {
    @State private var store = UsageStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Text(store.menuBarTitle)
                .foregroundStyle(tint)
                .task {
                    store.start()
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
