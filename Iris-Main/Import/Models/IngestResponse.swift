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
    let uploadedCount: Int
    let videos: [IngestVideoResponse]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case sessionStatus = "session_status"
        case uploadedCount = "uploaded_count"
        case videos
    }
}

struct IngestVideoResponse: Decodable, Identifiable {
    let index: Int
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?
    let clipID: FlexibleIdentifier
    let transcriptID: FlexibleIdentifier?
    let fileName: String
    let mimeType: String
    let fileExtension: String
    let fileSizeBytes: Int?
    let transcriptSegments: [TranscriptSegment]?
    let transcriptFullText: String?
    let videoReport: VideoReport?
    let clipMeta: ClipMeta?

    var id: String { clipID.rawValue }

    enum CodingKeys: String, CodingKey {
        case index
        case sessionID = "session_id"
        case projectID = "project_id"
        case clipID = "clip_id"
        case transcriptID = "transcript_id"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileExtension = "extension"
        case fileSizeBytes = "file_size_bytes"
        case transcriptSegments = "transcript_segments"
        case transcriptFullText = "transcript_full_text"
        case videoReport = "video_report"
        case clipMeta = "clip_meta"
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

struct VideoReport: Decodable {
    let keywords: [String]
    let namedEntities: [NamedEntity]
    let salientSpans: [SalientSpan]
    let transcriptStats: TranscriptStats?
    let candidateClipType: String?
    let clipTypeConfidence: Double?
    let ambiguityIndicators: [String]
    let representativeSegments: [RepresentativeSegment]

    enum CodingKeys: String, CodingKey {
        case keywords
        case namedEntities = "named_entities"
        case salientSpans = "salient_spans"
        case transcriptStats = "transcript_stats"
        case candidateClipType = "candidate_clip_type"
        case clipTypeConfidence = "clip_type_confidence"
        case ambiguityIndicators = "ambiguity_indicators"
        case representativeSegments = "representative_segments"
    }
}

struct NamedEntity: Decodable, Identifiable {
    let text: String
    let label: String
    let count: Int

    var id: String { "\(label)-\(text)" }
}

struct SalientSpan: Decodable, Identifiable {
    let start: Double
    let end: Double
    let text: String
    let score: Double

    var id: String { "\(start)-\(end)-\(text)" }
}

struct RepresentativeSegment: Decodable, Identifiable {
    let start: Double
    let end: Double
    let text: String

    var id: String { "\(start)-\(end)-\(text)" }
}

struct TranscriptStats: Decodable {
    let wordCount: Int
    let segmentCount: Int
    let speakerCount: Int
    let durationSec: Double
    let wordsPerMinute: Double
    let averageSegmentLengthSec: Double
    let silenceRatio: Double

    enum CodingKeys: String, CodingKey {
        case wordCount = "word_count"
        case segmentCount = "segment_count"
        case speakerCount = "speaker_count"
        case durationSec = "duration_sec"
        case wordsPerMinute = "words_per_minute"
        case averageSegmentLengthSec = "avg_segment_len_sec"
        case silenceRatio = "silence_ratio"
    }
}

struct ClipMeta: Decodable {
    let clipID: FlexibleIdentifier?
    let isSplit: Bool?
    let durationSeconds: Double?
    let windowCount: Int?
    let wallSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case isSplit = "split"
        case durationSeconds = "duration_s"
        case windowCount = "window_count"
        case wallSeconds = "wall_s"
    }
}
