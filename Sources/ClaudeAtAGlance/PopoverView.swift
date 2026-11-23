import SwiftUI
import AppKit
import GlanceCore

/// Popover content: Limits / Stats tabs, footer with Updated / Refresh / Quit.
struct PopoverView: View {
    let store: UsageStore
    let statsStore: StatsStore
    @AppStorage("selectedTab") private var tab = "limits"
    @AppStorage(AppearanceChoice.defaultsKey) private var appearanceRaw = AppearanceChoice.system.rawValue

    private var appearance: AppearanceChoice { AppearanceChoice(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                Text("Limits").tag("limits")
                Text("Stats").tag("stats")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Both tabs stay in the layout so the popover never changes size on a switch;
            // the window is always as tall as the taller tab and only visibility swaps.
            ZStack(alignment: .topLeading) {
                limitsContent
                    .opacity(tab == "limits" ? 1 : 0)
                    .allowsHitTesting(tab == "limits")
                    .accessibilityHidden(tab != "limits")
                StatsView(store: statsStore, active: tab == "stats")
                    .opacity(tab == "stats" ? 1 : 0)
                    .allowsHitTesting(tab == "stats")
                    .accessibilityHidden(tab != "stats")
            }
            footer
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    @ViewBuilder private var limitsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = store.message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            if store.limits.isEmpty && store.message == nil {
                Text("Loading…").foregroundStyle(.secondary)
            }
            ForEach(store.limits) { limit in
                LimitRow(
                    limit: limit,
                    dimmed: store.isStale,
                    resetText: ResetFormatter.string(for: limit.resetsAt, now: Date(), timeZone: .current, locale: .current)
                )
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            if let update = store.availableUpdate {
                Button("Update available: v\(update.version)") { NSWorkspace.shared.open(update.url) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            HStack {
                // Version sits under the time so the row stays on one line at 320 pt.
                VStack(alignment: .leading, spacing: 0) {
                    Text(footerText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(versionText).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                appearanceMenu
                Button("Refresh") { Task { await store.manualRefresh() } }
                    .keyboardShortcut("r")
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }

    private var appearanceMenu: some View {
        Menu {
            ForEach(AppearanceChoice.allCases, id: \.self) { choice in
                Button {
                    appearanceRaw = choice.rawValue
                    applyAppearance(choice)
                } label: {
                    if choice == appearance {
                        Label(choice.title, systemImage: "checkmark")
                    } else {
                        Text(choice.title)
                    }
                }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24)
        .help("Appearance")
        .accessibilityLabel("Appearance, \(appearance.title)")
    }

    private var versionText: String {
        let v = AppVersion.current
        return v == "0.0.0" ? "dev" : "v\(v)"
    }

    private var footerText: String { store.footerText() }
}
