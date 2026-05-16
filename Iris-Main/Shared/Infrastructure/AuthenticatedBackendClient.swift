import ClerkKit
import Foundation

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
    func authenticatedRequest(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        let token = try await sessionToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
        return authenticatedURL
    }

    private func sessionToken() async throws -> String {
        guard let token = try await Clerk.shared.session?.getToken(), !token.isEmpty else {
            throw AuthenticatedBackendClientError.missingSessionToken
        }
        return token
    }
}
