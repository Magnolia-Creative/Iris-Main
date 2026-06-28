import Foundation
import OSLog

enum CaptionsServiceError: LocalizedError, Equatable {
    case invalidResponse
    case transcriptNotReady(statusCode: Int, body: String)
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The captions response could not be understood."
        case let .transcriptNotReady(statusCode, body):
            return body.isEmpty
                ? "Transcript not ready (status \(statusCode))."
                : "Transcript not ready: \(body)"
        case let .requestFailed(statusCode, body):
            return body.isEmpty ? "Request failed with status \(statusCode)." : "Request failed with status \(statusCode): \(body)"
        }
    }
}

/// Word timing from project source transcript sentence payloads.
struct RemoteCaptionWord: Decodable, Equatable, Sendable {
    let word: String
    let start: Double
    let end: Double
}

/// Sentence (segment) from project source transcript payloads.
struct RemoteCaptionSentence: Decodable, Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double?
    let words: [RemoteCaptionWord]?

    enum CodingKeys: String, CodingKey {
        case text, start, end, confidence, words
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        words = try c.decodeIfPresent([RemoteCaptionWord].self, forKey: .words)
    }
}

struct RemoteCaptionMeta: Decodable, Equatable, Sendable {
    let sourceFile: String?
    let mimeType: String?
    let fileExtension: String?

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case mimeType = "mime_type"
        case fileExtension = "extension"
    }
}

/// Decoded `GET /projects/{project_id}/sources/{local_key}/transcript` success body.
struct RemoteClipCaptions: Decodable, Equatable, Sendable {
    let projectId: Int
    let localKey: String
    let clipId: Int
    let transcriptId: Int?
    let processingStatus: String
    let fullText: String
    let sentences: [RemoteCaptionSentence]
    let meta: RemoteCaptionMeta?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case localKey = "local_key"
        case clipId = "clip_id"
        case transcriptId = "transcript_id"
        case processingStatus = "processing_status"
        case fullText = "full_text"
        case sentences
        case meta
    }
}

struct CaptionsService: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "CaptionsService"
    )
    private let session: URLSession
    private let authClient: AuthenticatedBackendClient
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, authClient: AuthenticatedBackendClient = AuthenticatedBackendClient()) {
        self.session = session
        self.authClient = authClient
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        self.decoder = d
    }

    func fetchCaptions(projectId: String, localKey: String) async throws -> RemoteClipCaptions {
        guard let projectInt = Int(projectId) else {
            Self.logger.error("[CaptionsService] invalid project id raw=\(projectId, privacy: .public) localKey=\(localKey, privacy: .public)")
            throw CaptionsServiceError.requestFailed(statusCode: 400, body: "Invalid project id")
        }
        let url = AppConfiguration.projectSourceTranscriptEndpoint(projectID: String(projectInt), localKey: localKey)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        request = try await authClient.authenticatedRequest(request)
        Self.logger.notice(
            "[CaptionsService] request projectId=\(projectInt, privacy: .public) localKey=\(localKey, privacy: .public) url=\(url.absoluteString, privacy: .public)"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("[CaptionsService] non-http response projectId=\(projectInt, privacy: .public) localKey=\(localKey, privacy: .public)")
            throw CaptionsServiceError.invalidResponse
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        Self.logger.notice(
            "[CaptionsService] response projectId=\(projectInt, privacy: .public) localKey=\(localKey, privacy: .public) status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)"
        )
        switch http.statusCode {
        case 200 ..< 300:
            do {
                let decoded = try decoder.decode(RemoteClipCaptions.self, from: data)
                Self.logger.notice(
                    """
                    [CaptionsService] decoded projectId=\(decoded.projectId, privacy: .public) \
                    localKey=\(decoded.localKey, privacy: .public) \
                    clipId=\(decoded.clipId, privacy: .public) \
                    transcriptId=\(decoded.transcriptId ?? -1, privacy: .public) \
                    status=\(decoded.processingStatus, privacy: .public) \
                    sentenceCount=\(decoded.sentences.count, privacy: .public)
                    """
                )
                return decoded
            } catch {
                Self.logger.error(
                    "[CaptionsService] decode failed projectId=\(projectInt, privacy: .public) localKey=\(localKey, privacy: .public) error=\(String(describing: error), privacy: .public) body=\(body, privacy: .public)"
                )
                throw error
            }
        case 409:
            Self.logger.error(
                "[CaptionsService] transcript not ready projectId=\(projectInt, privacy: .public) localKey=\(localKey, privacy: .public) body=\(body, privacy: .public)"
            )
            throw CaptionsServiceError.transcriptNotReady(statusCode: http.statusCode, body: body)
        default:
            Self.logger.error(
                "[CaptionsService] request failed projectId=\(projectInt, privacy: .public) localKey=\(localKey, privacy: .public) status=\(http.statusCode, privacy: .public) body=\(body, privacy: .public)"
            )
            throw CaptionsServiceError.requestFailed(statusCode: http.statusCode, body: body)
        }
    }
}
