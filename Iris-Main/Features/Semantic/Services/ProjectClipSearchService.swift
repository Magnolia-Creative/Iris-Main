import Foundation
import OSLog

/// Calls backend project-scoped semantic and transcript (sentence) search APIs.
struct ProjectClipSearchService: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "ProjectClipSearchService"
    )
    private let session: URLSession
    private let authClient: AuthenticatedBackendClient
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, authClient: AuthenticatedBackendClient = AuthenticatedBackendClient()) {
        self.session = session
        self.authClient = authClient
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    struct Match: Sendable {
        let clipId: Int?
        let localKey: String
        let fileName: String?
        let startTimeSeconds: Double
        let endTimeSeconds: Double
        let confidence: Double
        let source: String?
        let matchText: String?
    }

    private struct SearchResponseDTO: Decodable {
        let matches: [MatchDTO]
    }

    private struct MatchDTO: Decodable {
        let clipId: Int?
        let localKey: String
        let fileName: String?
        let startTimeSeconds: Double
        let endTimeSeconds: Double
        let confidence: Double
        let source: String?
        let matchText: String?
    }

    private enum SearchMode: String {
        case semantic
        case transcript
    }

    func semanticSearch(projectID: String, query: String, limit: Int) async throws -> [Match] {
        try await postSearch(projectID: projectID, mode: .semantic, query: query, limit: limit)
    }

    func transcriptSearch(projectID: String, query: String, limit: Int) async throws -> [Match] {
        try await postSearch(projectID: projectID, mode: .transcript, query: query, limit: limit)
    }

    private func postSearch(projectID: String, mode: SearchMode, query: String, limit: Int) async throws -> [Match] {
        let url = AppConfiguration.projectSourceSearchEndpoint(projectID: projectID)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "query": query,
            "limit": limit,
            "mode": mode.rawValue,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        request = try await authClient.authenticatedRequest(request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try decoder.decode(SearchResponseDTO.self, from: data)
        return decoded.matches.map {
            Match(
                clipId: $0.clipId,
                localKey: $0.localKey,
                fileName: $0.fileName,
                startTimeSeconds: $0.startTimeSeconds,
                endTimeSeconds: $0.endTimeSeconds,
                confidence: $0.confidence,
                source: $0.source,
                matchText: $0.matchText
            )
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("[ProjectClipSearchService] non-http response")
            throw ProjectClipProcessingError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            Self.logger.error(
                "[ProjectClipSearchService] search failed status=\(httpResponse.statusCode, privacy: .public) url=\(httpResponse.url?.absoluteString ?? "nil", privacy: .public) body=\(body, privacy: .public)"
            )
            throw ProjectClipProcessingError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
    }
}
