import Foundation

public enum UsageFetchError: Error, Equatable {
    case unauthorized
    case rateLimited
    case server(Int)
    case offline
    case other
}

/// GET https://api.anthropic.com/api/oauth/usage with the Claude Code bearer token.
public struct UsageClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw UsageFetchError.offline
            default:
                throw UsageFetchError.other
            }
        } catch {
            throw UsageFetchError.other
        }

        guard let http = response as? HTTPURLResponse else { throw UsageFetchError.other }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw UsageFetchError.unauthorized
        case 429: throw UsageFetchError.rateLimited
        case 500..<600: throw UsageFetchError.server(http.statusCode)
        default: throw UsageFetchError.other
        }
    }
}
