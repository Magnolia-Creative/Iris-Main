import Foundation

struct FlexibleIdentifier: Codable, Hashable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            rawValue = stringValue
            return
        }

        if let intValue = try? container.decode(Int.self) {
            rawValue = String(intValue)
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            rawValue = String(doubleValue)
            return
        }

        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected a string or number identifier.")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        rawValue
    }

    var intValue: Int? {
        Int(rawValue)
    }
}

struct IngestResponse: Decodable {
    let sessionID: FlexibleIdentifier
    let sessionName: String
    let sessionStatus: String
    let projectID: FlexibleIdentifier?
    let projectName: String?
    let uploadedCount: Int
    let pendingClipCount: Int?
    let settledClipCount: Int?
    let readyForWebSocket: Bool?
    let videos: [IngestVideoResponse]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case sessionStatus = "session_status"
        case projectID = "project_id"
        case projectName = "project_name"
        case uploadedCount = "uploaded_count"
        case pendingClipCount = "pending_clip_count"
        case settledClipCount = "settled_clip_count"
        case readyForWebSocket = "ready_for_websocket"
        case videos
    }
}

struct IngestVideoResponse: Decodable, Identifiable {
    let index: Int
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?
    let clipID: FlexibleIdentifier
    let transcriptID: FlexibleIdentifier?
    let localKey: String?
    let fileName: String
    let mimeType: String
    let fileExtension: String?
    let processingStatus: String?
    let processingError: String?

    var id: String { clipID.rawValue }

    enum CodingKeys: String, CodingKey {
        case index
        case sessionID = "session_id"
        case projectID = "project_id"
        case clipID = "clip_id"
        case transcriptID = "transcript_id"
        case localKey = "local_key"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileExtension = "extension"
        case processingStatus = "processing_status"
        case processingError = "processing_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        sessionID = try container.decode(FlexibleIdentifier.self, forKey: .sessionID)
        projectID = try container.decodeIfPresent(FlexibleIdentifier.self, forKey: .projectID)
        clipID = try container.decode(FlexibleIdentifier.self, forKey: .clipID)
        transcriptID = try container.decodeIfPresent(FlexibleIdentifier.self, forKey: .transcriptID)
        localKey = try container.decodeIfPresent(String.self, forKey: .localKey)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? "Clip"
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream"
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
        processingStatus = try container.decodeIfPresent(String.self, forKey: .processingStatus)
        processingError = try container.decodeIfPresent(String.self, forKey: .processingError)
    }
}
