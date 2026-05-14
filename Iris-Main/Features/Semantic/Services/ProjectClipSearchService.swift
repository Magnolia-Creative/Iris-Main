import Foundation

/// Calls backend project-scoped semantic and transcript (sentence) search APIs.
struct ProjectClipSearchService: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
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

    func semanticSearch(projectID: String, query: String, limit: Int) async throws -> [Match] {
        try await postSearch(url: AppConfiguration.projectSemanticSearchEndpoint(projectID: projectID), query: query, limit: limit)
    }

    func transcriptSearch(projectID: String, query: String, limit: Int) async throws -> [Match] {
        try await postSearch(url: AppConfiguration.projectTranscriptSearchEndpoint(projectID: projectID), query: query, limit: limit)
    }

    private func postSearch(url: URL, query: String, limit: Int) async throws -> [Match] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "query": query,
            "limit": limit,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
            throw ProjectClipProcessingError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProjectClipProcessingError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
    }
}
