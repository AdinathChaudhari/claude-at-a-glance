import Foundation

/// The user's appearance preference for the popover.
public enum AppearanceChoice: String, CaseIterable, Sendable {
    case system, light, dark

    public static let defaultsKey = "appearance"

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Stored choice; missing or unknown values fall back to `.system`.
    public static func load(from defaults: UserDefaults = .standard) -> AppearanceChoice {
        defaults.string(forKey: defaultsKey).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
