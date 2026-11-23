import Foundation

public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let url: URL
    public init(version: String, url: URL) {
        self.version = version
        self.url = url
    }
}

/// Looks for a newer GitHub release. Every failure (offline, 404 before the first release,
/// bad JSON) returns nil silently: an update check must never bother the user.
public enum UpdateChecker {
    public static let latestURL = URL(string: "https://api.github.com/repos/AdinathChaudhari/claude-at-a-glance/releases/latest")!

    /// Parses GitHub's `/releases/latest` JSON. Version has any leading "v" removed.
    public static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let html = obj["html_url"] as? String,
              let url = URL(string: html),
              url.scheme == "https",
              !tag.isEmpty
        else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return ReleaseInfo(version: version, url: url)
    }

    /// Numeric semver compare. Leading "v" tolerated, missing parts count as 0, a prerelease
    /// or build suffix ("-beta.1", "+5") is ignored. Unparseable input is never "newer".
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let r = components(remote), let l = components(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ s: String) -> [Int]? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        if let cut = t.firstIndex(where: { $0 == "-" || $0 == "+" }) { t = String(t[..<cut]) }
        guard !t.isEmpty else { return nil }
        var out: [Int] = []
        for part in t.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            out.append(n)
        }
        return out
    }

    public static func latest(session: URLSession = .shared) async -> ReleaseInfo? {
        var req = URLRequest(url: latestURL)
        req.setValue("claude-at-a-glance", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return parseLatest(data)
    }
}
