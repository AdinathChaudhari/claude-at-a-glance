import Foundation
import Observation

public enum StoreStatus: Equatable, Sendable {
    case idle
    case ok
    case loginExpired
    case notSignedIn
    case offline
    case formatChanged
    case rateLimited
    case serverError
    case failed

    /// User-facing message, nil when healthy.
    public var message: String? {
        switch self {
        case .idle, .ok: return nil
        case .loginExpired: return "Login expired. Open Claude Code to refresh."
        case .notSignedIn: return "Claude Code not signed in."
        case .offline: return "Offline, retrying."
        case .formatChanged: return "Usage format changed. Update the app."
        case .rateLimited: return "Rate limited, retrying later."
        case .serverError: return "Server error, retrying later."
        case .failed: return "Could not read usage, retrying."
        }
    }
}

/// App-level owner of polling and state. Pure logic: credentials, network and clock are injected.
@MainActor
@Observable
public final class UsageStore {
    public static let pollInterval: TimeInterval = 60
    public static let openStaleAfter: TimeInterval = 15
    public static let manualDebounce: TimeInterval = 10
    public static let backoffSteps: [TimeInterval] = [300, 600, 1200]

    public private(set) var limits: [UsageLimit] = []
    public private(set) var status: StoreStatus = .idle
    public private(set) var lastUpdated: Date?
    /// Seconds to wait before the next poll.
    public private(set) var nextInterval: TimeInterval = UsageStore.pollInterval

    /// Set when a newer release exists on GitHub. Nil when up to date, offline, or run without a bundle version.
    public private(set) var availableUpdate: ReleaseInfo?
    public static let updateFirstDelay: TimeInterval = 10
    public static let updateInterval: TimeInterval = 24 * 60 * 60

    private var lastAttempt: Date?
    private var updateLoop: Task<Void, Never>?
    private var lastManual: Date?
    private var failureStreak = 0
    private var isRefreshing = false
    private var loop: Task<Void, Never>?

    private let readCredentials: @Sendable () throws -> Credentials
    private let fetch: @Sendable (String) async throws -> Data
    private let now: @Sendable () -> Date

    public init(
        readCredentials: @escaping @Sendable () throws -> Credentials = { try CredentialReader.read() },
        fetch: @escaping @Sendable (String) async throws -> Data = { try await UsageClient().fetch(token: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.readCredentials = readCredentials
        self.fetch = fetch
        self.now = now
    }

    public var message: String? { status.message }
    public var isErroring: Bool { status != .ok && status != .idle }

    /// Severity worst across rows, for tinting.
    public var worstSeverity: Severity {
        if limits.contains(where: { $0.severity == .critical }) { return .critical }
        if limits.contains(where: { $0.severity == .warning }) { return .warning }
        return .normal
    }

    public var menuBarTitle: String {
        guard let session = limits.first(where: { $0.kind == .session }) else {
            return isErroring ? "– ⚠" : "–"
        }
        let base = "\(Int(session.percent.rounded()))%"
        return isErroring ? base + " ⚠" : base
    }

    // MARK: - Polling

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Check a deadline every 5 s instead of sleeping the whole interval, so a
                // successful manual refresh during back-off brings 60 s polling back at once.
                let due = self.lastAttempt.map { self.now().timeIntervalSince($0) >= self.nextInterval } ?? true
                if due { await self.refresh() }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        updateLoop?.cancel()
        updateLoop = nil
    }

    /// First check after ~10 s, then every 24 h. Skipped when `localVersion` is "0.0.0" (swift run).
    public func startUpdateChecks(
        localVersion: String,
        firstDelay: TimeInterval = UsageStore.updateFirstDelay,
        interval: TimeInterval = UsageStore.updateInterval,
        check: @escaping @Sendable () async -> ReleaseInfo? = { await UpdateChecker.latest() }
    ) {
        guard updateLoop == nil, localVersion != "0.0.0" else { return }
        updateLoop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(firstDelay))
            while !Task.isCancelled {
                await self?.runUpdateCheck(localVersion: localVersion, check: check)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func runUpdateCheck(localVersion: String, check: @Sendable () async -> ReleaseInfo?) async {
        if let info = await check(), UpdateChecker.isNewer(info.version, than: localVersion) {
            availableUpdate = info
        } else {
            availableUpdate = nil
        }
    }

    /// Popover opened: refresh if data is older than 15 s and we are not backing off.
    public func refreshOnOpen() async {
        if failureStreak > 0, nextInterval > UsageStore.pollInterval { return }
        if let last = lastAttempt, now().timeIntervalSince(last) <= UsageStore.openStaleAfter { return }
        await refresh()
    }

    /// Manual Refresh button, debounced to once per 10 s.
    public func manualRefresh() async {
        let t = now()
        if let last = lastManual, t.timeIntervalSince(last) < UsageStore.manualDebounce { return }
        lastManual = t
        await refresh()
    }

    /// One fetch cycle. Updates state and `nextInterval`.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastAttempt = now()

        let creds: Credentials
        do {
            creds = try readCredentials()
        } catch CredentialError.notSignedIn {
            fail(.notSignedIn); return
        } catch {
            fail(.failed); return
        }
        if let exp = creds.expiresAt, exp <= now() {
            fail(.loginExpired); return
        }

        do {
            let data = try await fetch(creds.accessToken)
            let parsed = try UsageParser.parse(data)
            limits = parsed
            lastUpdated = now()
            status = .ok
            failureStreak = 0
            nextInterval = UsageStore.pollInterval
        } catch UsageFetchError.unauthorized {
            fail(.loginExpired)
        } catch UsageFetchError.rateLimited {
            fail(.rateLimited, backoff: true)
        } catch UsageFetchError.server {
            fail(.serverError, backoff: true)
        } catch UsageFetchError.offline {
            fail(.offline)
        } catch UsageParseError.formatChanged {
            fail(.formatChanged)
        } catch {
            fail(.failed)
        }
    }

    private func fail(_ s: StoreStatus, backoff: Bool = false) {
        status = s
        if backoff {
            let steps = UsageStore.backoffSteps
            nextInterval = steps[min(failureStreak, steps.count - 1)]
            failureStreak += 1
        } else {
            failureStreak = 0
            nextInterval = UsageStore.pollInterval
        }
    }
}
