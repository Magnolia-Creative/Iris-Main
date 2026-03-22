import Foundation

struct IngestResponse: Decodable {
    let projectID: Int
    let projectName: String
    let uploadedCount: Int
    let videos: [IngestVideoResponse]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case projectName = "project_name"
        case uploadedCount = "uploaded_count"
        case videos
    }
}

struct IngestVideoResponse: Decodable, Identifiable {
    let index: Int
    let projectID: Int
    let clipID: Int
    let transcriptID: Int
    let fileName: String
    let mimeType: String
    let fileExtension: String
    let fileSizeBytes: Int
    let transcriptSegments: [TranscriptSegment]

    var id: Int { clipID }

    enum CodingKeys: String, CodingKey {
        case index
        case projectID = "project_id"
        case clipID = "clip_id"
        case transcriptID = "transcript_id"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileExtension = "extension"
        case fileSizeBytes = "file_size_bytes"
        case transcriptSegments = "transcript_segments"
    }
}

struct TranscriptSegment: Decodable, Identifiable {
    let start: Double
    let end: Double
    let text: String
    let words: [TranscriptWord]
    let averageLogProbability: Double

    var id: String { "\(start)-\(end)-\(text)" }
    var cleanedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case text
        case words
        case averageLogProbability = "avg_logprob"
    }
}

struct TranscriptWord: Decodable, Identifiable, Hashable {
    let word: String
    let start: Double?
    let end: Double?
    let score: Double?

    var id: String {
        "\(word)-\(start ?? -1)-\(end ?? -1)"
    }
}
