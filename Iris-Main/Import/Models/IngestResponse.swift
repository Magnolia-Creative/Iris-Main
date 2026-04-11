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
    let fileSizeBytes: Int?
    let processingStatus: String?
    let processingError: String?
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
        case localKey = "local_key"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileExtension = "extension"
        case fileSizeBytes = "file_size_bytes"
        case processingStatus = "processing_status"
        case processingError = "processing_error"
        case transcriptSegments = "transcript_segments"
        case transcriptFullText = "transcript_full_text"
        case videoReport = "video_report"
        case clipMeta = "clip_meta"
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
        fileSizeBytes = try container.decodeIfPresent(Int.self, forKey: .fileSizeBytes)
        processingStatus = try container.decodeIfPresent(String.self, forKey: .processingStatus)
        processingError = try container.decodeIfPresent(String.self, forKey: .processingError)
        transcriptSegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSegments)
        transcriptFullText = try container.decodeIfPresent(String.self, forKey: .transcriptFullText)
        videoReport = try container.decodeIfPresent(VideoReport.self, forKey: .videoReport)
        clipMeta = try container.decodeIfPresent(ClipMeta.self, forKey: .clipMeta)
    }
}

struct TranscriptSegment: Decodable, Identifiable {
    let start: Double
    let end: Double
    let text: String
    let words: [TranscriptWord]
    let averageLogProbability: Double?
    let confidence: Double?
    let speaker: String?
    let channel: String?

    var id: String { "\(start)-\(end)-\(text)" }
    var cleanedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case text
        case words
        case averageLogProbability = "avg_logprob"
        case confidence
        case speaker
        case channel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(Double.self, forKey: .start) ?? 0
        end = try container.decodeIfPresent(Double.self, forKey: .end) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        words = try container.decodeIfPresent([TranscriptWord].self, forKey: .words) ?? []
        averageLogProbability = try container.decodeIfPresent(Double.self, forKey: .averageLogProbability)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        speaker = try container.decodeFlexibleStringIfPresent(forKey: .speaker)
        channel = try container.decodeFlexibleStringIfPresent(forKey: .channel)
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
    let provider: String?
    let status: String?
    let durationSeconds: Double?
    let languageCode: String?
    let confidence: Double?
    let textLength: Int?
    let about: String?

    enum CodingKeys: String, CodingKey {
        case keywords
        case namedEntities = "named_entities"
        case salientSpans = "salient_spans"
        case transcriptStats = "transcript_stats"
        case candidateClipType = "candidate_clip_type"
        case clipTypeConfidence = "clip_type_confidence"
        case ambiguityIndicators = "ambiguity_indicators"
        case representativeSegments = "representative_segments"
        case provider
        case status
        case durationSeconds = "duration_seconds"
        case languageCode = "language_code"
        case confidence
        case textLength = "text_length"
        case about
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        namedEntities = try container.decodeIfPresent([NamedEntity].self, forKey: .namedEntities) ?? []
        salientSpans = try container.decodeIfPresent([SalientSpan].self, forKey: .salientSpans) ?? []
        transcriptStats = try container.decodeIfPresent(TranscriptStats.self, forKey: .transcriptStats)
        candidateClipType = try container.decodeIfPresent(String.self, forKey: .candidateClipType)
        clipTypeConfidence = try container.decodeIfPresent(Double.self, forKey: .clipTypeConfidence)
        ambiguityIndicators = try container.decodeIfPresent([String].self, forKey: .ambiguityIndicators) ?? []
        representativeSegments = try container.decodeIfPresent([RepresentativeSegment].self, forKey: .representativeSegments) ?? []
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        textLength = try container.decodeIfPresent(Int.self, forKey: .textLength)
        about = try container.decodeIfPresent(String.self, forKey: .about)
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
    let suffix: String?
    let provider: String?
    let audioBytes: Int?
    let assemblyAITranscriptID: String?

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case isSplit = "split"
        case durationSeconds = "duration_s"
        case durationSecondsAlt = "duration_seconds"
        case windowCount = "window_count"
        case wallSeconds = "wall_s"
        case suffix
        case provider
        case audioBytes = "audio_bytes"
        case assemblyAITranscriptID = "assemblyai_transcript_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipID = try container.decodeIfPresent(FlexibleIdentifier.self, forKey: .clipID)
        isSplit = try container.decodeIfPresent(Bool.self, forKey: .isSplit)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
            ?? container.decodeIfPresent(Double.self, forKey: .durationSecondsAlt)
        windowCount = try container.decodeIfPresent(Int.self, forKey: .windowCount)
        wallSeconds = try container.decodeIfPresent(Double.self, forKey: .wallSeconds)
        suffix = try container.decodeIfPresent(String.self, forKey: .suffix)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        audioBytes = try container.decodeIfPresent(Int.self, forKey: .audioBytes)
        assemblyAITranscriptID = try container.decodeIfPresent(String.self, forKey: .assemblyAITranscriptID)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }
        return nil
    }
}
