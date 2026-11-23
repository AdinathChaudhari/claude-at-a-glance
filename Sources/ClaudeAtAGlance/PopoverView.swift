import SwiftUI
import AppKit
import GlanceCore

/// Popover content: Limits / Stats tabs, footer with Updated / Refresh / Quit.
struct PopoverView: View {
    let store: UsageStore
    let statsStore: StatsStore
    @AppStorage("selectedTab") private var tab = "limits"

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
                    dimmed: store.isErroring,
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
                Text(footerText).font(.caption).foregroundStyle(.secondary)
                Text(versionText).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Refresh") { Task { await store.manualRefresh() } }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private var versionText: String {
        let v = AppVersion.current
        return v == "0.0.0" ? "dev" : "v\(v)"
    }

    private var footerText: String {
        guard let t = store.lastUpdated else { return "Not updated yet" }
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        return (store.isErroring ? "as of " : "Updated ") + f.string(from: t)
    }
}
