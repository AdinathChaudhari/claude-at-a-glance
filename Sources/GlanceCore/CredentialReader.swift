import Foundation

public struct Credentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

public enum CredentialError: Error, Equatable {
    case notSignedIn
    case unreadable
}

/// Reads Claude Code's OAuth login from the macOS Keychain by shelling out to
/// /usr/bin/security. Never logs the token, never writes the Keychain, never refreshes.
public enum CredentialReader {
    public static func read() throws -> Credentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch { throw CredentialError.unreadable }
        let raw = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // 44 = errSecItemNotFound; anything else non-zero means unreadable (denied, locked, ...).
        guard process.terminationStatus == 0 else {
            throw process.terminationStatus == 44 ? CredentialError.notSignedIn : CredentialError.unreadable
        }
        return try parse(raw)
    }

    /// Parses the keychain payload. Exposed internally for tests (no Keychain access).
    static func parse(_ raw: Data) throws -> Credentials {
        var data = raw
        if let text = String(data: raw, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // `security -w` hex-encodes payloads it considers non-printable.
            if !trimmed.hasPrefix("{"), let decoded = hexDecode(trimmed) { data = decoded }
            else { data = Data(trimmed.utf8) }
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw CredentialError.unreadable
        }
        var expiry: Date?
        if let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue {
            expiry = Date(timeIntervalSince1970: ms / 1000)
        }
        return Credentials(accessToken: token, expiresAt: expiry)
    }

    private static func hexDecode(_ s: String) -> Data? {
        guard s.count >= 2, s.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return Data(bytes)
    }
}
