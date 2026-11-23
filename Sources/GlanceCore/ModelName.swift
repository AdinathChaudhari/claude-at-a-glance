import Foundation

public enum ModelName {
    /// "claude-opus-5-5" -> "Opus 5.5". Unknown ids are returned unchanged.
    public static func display(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts[0] == "claude" else { return id }
        parts.removeFirst()
        let family = parts.removeFirst()
        guard family.allSatisfy({ $0.isLetter }) else { return id }
        var nums: [String] = []
        for p in parts {
            guard p.allSatisfy({ $0.isNumber }) else { return id }
            // A trailing date stamp (e.g. 20251001) is not part of the version.
            if p.count > 2 { break }
            nums.append(p)
        }
        guard !nums.isEmpty, nums.count <= 2 else { return id }
        return family.prefix(1).uppercased() + family.dropFirst() + " " + nums.joined(separator: ".")
    }
}

public enum TokenFormatter {
    /// 12345678 -> "12.3M", 752156 -> "752K", 999 -> "999".
    public static func string(_ n: Int) -> String {
        let v = max(n, 0)
        if v >= 1_000_000_000 { return scaled(Double(v) / 1_000_000_000, "B") }
        if v >= 999_500 { return scaled(Double(v) / 1_000_000, "M") }
        if v >= 1_000 { return "\(Int((Double(v) / 1_000).rounded()))K" }
        return "\(v)"
    }

    private static func scaled(_ x: Double, _ suffix: String) -> String {
        let r = (x * 10).rounded() / 10
        return (r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)) + suffix
    }
}
