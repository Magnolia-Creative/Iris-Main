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
        guard !AppConfiguration.localAuthBypassEnabled else {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            Self.logger.warning(
                "[auth] LOCAL_AUTH_BYPASS enabled; sending backend request without Clerk bearer token method=\(request.httpMethod ?? "GET", privacy: .public) url=\(request.url?.redactedAuthLogURL ?? "nil", privacy: .public)"
            )
            return request
        }

        let token = try await sessionToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Self.logger.info(
            "[auth] Attached Clerk bearer token method=\(request.httpMethod ?? "GET", privacy: .public) url=\(request.url?.redactedAuthLogURL ?? "nil", privacy: .public) tokenChars=\(token.count, privacy: .public)"
        )
        return request
    }

    func authenticatedWebSocketURL(_ url: URL) async throws -> URL {
        guard !AppConfiguration.localAuthBypassEnabled else {
            Self.logger.warning(
                "[auth] LOCAL_AUTH_BYPASS enabled; opening backend WebSocket without Clerk token url=\(url.redactedAuthLogURL, privacy: .public)"
            )
            return url.removingAuthTokenQueryItem()
        }

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
        Self.logTokenDebugClaims(token)
        return token
    }

    private static func logTokenDebugClaims(_ token: String) {
        let claims = JWTDebugClaims(token: token)
        logger.info(
            """
            [auth] Clerk token debug \
            iss=\(claims.issuer ?? "nil", privacy: .public) \
            sub=\(claims.subject ?? "nil", privacy: .public) \
            sid=\(claims.sessionID ?? "nil", privacy: .public) \
            azp=\(claims.authorizedParty ?? "nil", privacy: .public) \
            exp=\(claims.expiresAt ?? "nil", privacy: .public) \
            tokenChars=\(token.count, privacy: .public) \
            tokenFingerprint=\(token.redactedTokenFingerprint, privacy: .public)
            """
        )
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

    func removingAuthTokenQueryItem() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        let filteredItems = components.queryItems?.filter { $0.name != "token" } ?? []
        components.queryItems = filteredItems.isEmpty ? nil : filteredItems
        return components.url ?? self
    }
}

private struct JWTDebugClaims {
    let issuer: String?
    let subject: String?
    let sessionID: String?
    let authorizedParty: String?
    let expiresAt: String?

    init(token: String) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let payloadData = Data(base64URLString: String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            issuer = nil
            subject = nil
            sessionID = nil
            authorizedParty = nil
            expiresAt = nil
            return
        }

        issuer = json["iss"] as? String
        subject = json["sub"] as? String
        sessionID = json["sid"] as? String
        authorizedParty = json["azp"] as? String
        if let exp = json["exp"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: exp).ISO8601Format()
        } else if let exp = json["exp"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(exp)).ISO8601Format()
        } else {
            expiresAt = nil
        }
    }
}

private extension Data {
    init?(base64URLString: String) {
        var base64 = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        self.init(base64Encoded: base64)
    }
}

private extension String {
    var redactedTokenFingerprint: String {
        guard count > 12 else {
            return "<short-token>"
        }
        return "\(prefix(6))...\(suffix(6))"
    }
}
