import ClerkKit
import Foundation
import OSLog

enum AuthenticatedBackendClientError: LocalizedError {
    case missingSessionToken
    case invalidWebSocketURL

    var errorDescription: String? {
        switch self {
        case .missingSessionToken:
            return "No active Clerk session token is available."
        case .invalidWebSocketURL:
            return "The authenticated WebSocket URL could not be built."
        }
    }
}

struct AuthenticatedBackendClient: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "AuthenticatedBackendClient"
    )

    func authenticatedRequest(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        let token = try await sessionToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Self.logger.info(
            "[auth] Attached Clerk bearer token method=\(request.httpMethod ?? "GET", privacy: .public) url=\(request.url?.redactedAuthLogURL ?? "nil", privacy: .public) tokenChars=\(token.count, privacy: .public)"
        )
        return request
    }

    func authenticatedWebSocketURL(_ url: URL) async throws -> URL {
        let token = try await sessionToken()
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthenticatedBackendClientError.invalidWebSocketURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "token" }
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems
        guard let authenticatedURL = components.url else {
            throw AuthenticatedBackendClientError.invalidWebSocketURL
        }
        Self.logger.info(
            "[auth] Attached Clerk WebSocket token url=\(url.redactedAuthLogURL, privacy: .public) tokenChars=\(token.count, privacy: .public)"
        )
        return authenticatedURL
    }

    private func sessionToken() async throws -> String {
        guard Clerk.shared.session != nil else {
            Self.logger.error("[auth] Missing active Clerk session while preparing backend request.")
            throw AuthenticatedBackendClientError.missingSessionToken
        }
        guard let token = try await Clerk.shared.session?.getToken(), !token.isEmpty else {
            Self.logger.error("[auth] Clerk session returned an empty backend token.")
            throw AuthenticatedBackendClientError.missingSessionToken
        }
        Self.logger.info("[auth] Retrieved Clerk session token tokenChars=\(token.count, privacy: .public)")
        return token
    }
}

private extension URL {
    var redactedAuthLogURL: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            item.name == "token" ? URLQueryItem(name: item.name, value: "<redacted>") : item
        }
        return components.string ?? absoluteString
    }
}
