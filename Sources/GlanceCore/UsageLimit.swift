import Foundation

public enum Severity: String, Sendable, Equatable {
    case normal
    case warning
    case critical
}

public enum LimitKind: Sendable, Equatable {
    case session
    case weeklyAll
    case weeklyScoped
}

public struct UsageLimit: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: LimitKind
    /// "Current session", "Current week (all models)", or "Current week (<model display name>)".
    public let label: String
    /// Raw percent as reported. Values above 100 are kept; the UI clamps the bar.
    public let percent: Double
    public let resetsAt: Date?
    public let severity: Severity

    public init(id: String, kind: LimitKind, label: String, percent: Double, resetsAt: Date?, severity: Severity) {
        self.id = id
        self.kind = kind
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
        self.severity = severity
    }
}
