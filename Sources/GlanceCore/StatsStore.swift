import Foundation
import Observation

public enum StatsReadError: Error, Sendable { case missing }

public enum StatsState: Equatable, Sendable {
    case idle
    case loaded(StatsSummary)
    case missing
    case formatChanged

    public var message: String? {
        switch self {
        case .missing: return "No stats yet. Run Claude Code once."
        case .formatChanged: return "Stats format changed."
        case .idle, .loaded: return nil
        }
    }
}

/// Reads Claude Code's local stats-cache.json. Local file only, no network.
@MainActor
@Observable
public final class StatsStore {
    public static let reloadInterval: TimeInterval = 300

    public private(set) var state: StatsState = .idle

    private var loop: Task<Void, Never>?
    private let read: @Sendable () throws -> Data
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        read: @escaping @Sendable () throws -> Data = { try StatsStore.readDefaultFile() },
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.read = read
        self.now = now
        self.calendar = calendar
    }

    public nonisolated static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/stats-cache.json")
    }

    public nonisolated static func readDefaultFile() throws -> Data {
        let url = defaultURL()
        guard FileManager.default.fileExists(atPath: url.path) else { throw StatsReadError.missing }
        return try Data(contentsOf: url)
    }

    /// Re-read the file now. Called when the Stats tab is shown and by the 5-minute loop.
    public func reload() {
        do {
            state = .loaded(try StatsParser.parse(try read(), today: now(), calendar: calendar))
        } catch StatsReadError.missing {
            state = .missing
        } catch {
            state = .formatChanged
        }
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.reload()
                try? await Task.sleep(for: .seconds(StatsStore.reloadInterval))
            }
        }
    }

    public func stop() { loop?.cancel(); loop = nil }
}
