import Foundation

enum ClipTranscriptServiceError: LocalizedError {
    case invalidResponse
    case emptyTranscript
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The transcript response could not be understood."
        case .emptyTranscript:
            return "The transcript response did not contain any sentence matches."
        case let .requestFailed(statusCode, body):
            return body.isEmpty ? "Request failed with status \(statusCode)." : "Request failed with status \(statusCode): \(body)"
        }
    }
}

struct ClipTranscriptSentenceResponse: Decodable, Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double?
    let speaker: String?
    let channel: String?
}

struct ClipTranscriptResponse: Decodable, Equatable, Sendable {
    let transcriptID: String
    let fullText: String
    let sentences: [ClipTranscriptSentenceResponse]
    let languageCode: String?
    let confidence: Double?
    let audioDuration: Double?

    enum CodingKeys: String, CodingKey {
        case transcriptID = "transcript_id"
        case fullText = "full_text"
        case sentences
        case languageCode = "language_code"
        case confidence
        case audioDuration = "audio_duration"
    }
}

struct ClipTranscriptService: Sendable {
    private let session: URLSession
    private let authClient: AuthenticatedBackendClient
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared, authClient: AuthenticatedBackendClient = AuthenticatedBackendClient()) {
        self.session = session
        self.authClient = authClient
    }

    func transcribe(_ asset: ProcessedAudioAsset) async throws -> ClipTranscriptResponse {
        let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: asset.audioURL.path)[.size] as? NSNumber)?.intValue
        print(
            "[ClipTranscriptService] starting request localKey=\(asset.localKey) file=\(asset.fileName) " +
            "mimeType=\(asset.mimeType) endpoint=\(AppConfiguration.transcriptSentencesEndpoint.absoluteString) " +
            "audioBytes=\(fileSizeBytes ?? -1)"
        )
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: AppConfiguration.transcriptSentencesEndpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let body = try makeMultipartBody(asset: asset, boundary: boundary)
        request = try await authClient.authenticatedRequest(request)
        let (data, response) = try await session.upload(for: request, from: body)
        if let httpResponse = response as? HTTPURLResponse {
            print(
                "[ClipTranscriptService] response received localKey=\(asset.localKey) " +
                "status=\(httpResponse.statusCode) bytes=\(data.count)"
            )
        } else {
            print("[ClipTranscriptService] non-http response localKey=\(asset.localKey) bytes=\(data.count)")
        }
        try validate(response: response, data: data)
        let transcript = try decoder.decode(ClipTranscriptResponse.self, from: data)
        print(
            "[ClipTranscriptService] decoded transcript localKey=\(asset.localKey) " +
            "transcriptID=\(transcript.transcriptID) sentences=\(transcript.sentences.count) " +
            "fullTextChars=\(transcript.fullText.count)"
        )
        if transcript.sentences.isEmpty {
            print("[ClipTranscriptService] transcript had no sentences localKey=\(asset.localKey)")
            throw ClipTranscriptServiceError.emptyTranscript
        }
        return transcript
    }

    private func makeMultipartBody(asset: ProcessedAudioAsset, boundary: String) throws -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(asset.fileName)\"\r\n")
        body.append("Content-Type: \(asset.mimeType)\r\n\r\n")
        body.append(try Data(contentsOf: asset.audioURL))
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClipTranscriptServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClipTranscriptServiceError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
