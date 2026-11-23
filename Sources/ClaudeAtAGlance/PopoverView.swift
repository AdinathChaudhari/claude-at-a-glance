import SwiftUI
import AppKit
import GlanceCore

/// Popover content: one row per limit, footer with Updated / Refresh / Quit.
struct PopoverView: View {
    let store: UsageStore

    var body: some View {
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
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .task { await store.refreshOnOpen() }
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
