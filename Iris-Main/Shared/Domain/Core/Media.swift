import Foundation
import GRDB

struct Media: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let mediaId: String
    let mediaLibraryId: String
    let kind: MediaKind
    let assetRefId: String
    var spec: MediaSpec
    let createdAt: Date
    var updatedAt: Date

    var id: String { mediaId }

    init(
        mediaId: String = UUID().uuidString,
        mediaLibraryId: String,
        kind: MediaKind,
        assetRefId: String,
        spec: MediaSpec = MediaSpec(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.mediaId = mediaId
        self.mediaLibraryId = mediaLibraryId
        self.kind = kind
        self.assetRefId = assetRefId
        self.spec = spec
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case mediaId = "media_id"
        case mediaLibraryId = "media_library_id"
        case kind
        case assetRefId = "asset_ref_id"
        case spec
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "media"

    enum Columns: String, ColumnExpression {
        case mediaId = "media_id"
        case mediaLibraryId = "media_library_id"
        case kind
        case assetRefId = "asset_ref_id"
        case spec
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var importPresentationDeduplicationKey: String {
        "\(kind.rawValue)::\(assetRefId)"
    }

    var semanticSearchVisualSignature: String {
        [
            mediaId,
            kind.rawValue,
            assetRefId,
            spec.duration.map { String(format: "%.3f", $0) } ?? ""
        ].joined(separator: "::")
    }

    var semanticSearchTranscriptSignature: String {
        [
            spec.transcriptID ?? "",
            String(spec.transcriptSentences?.count ?? 0),
            spec.transcriptFullText ?? "",
            spec.clipUploadLocalKey ?? ""
        ].joined(separator: "::")
    }

    var semanticSearchContentSignature: String {
        [
            semanticSearchVisualSignature,
            semanticSearchTranscriptSignature
        ].joined(separator: "::")
    }

    static func deduplicatedForImportPresentation(_ media: [Media]) -> [Media] {
        var seenKeys: Set<String> = []

        return media
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.mediaId < rhs.mediaId
                }
                return lhs.createdAt < rhs.createdAt
            }
            .filter { seenKeys.insert($0.importPresentationDeduplicationKey).inserted }
    }
}

struct MediaSpec: Codable {
    var duration: Double?
    var width: Int?
    var height: Int?
    var thumbnailStripPath: String?
    var thumbnailStripHeight: Int?
    var thumbnailStripFrameCount: Int?
    var waveformPath: String?
    var waveformHeight: Int?
    var transcriptID: String?
    var transcriptFullText: String?
    var transcriptSentences: [MediaTranscriptSentence]?
    /// When set, matches `local_key` on backend clips for this timeline media (import-browser clip key).
    var clipUploadLocalKey: String?
}

struct MediaTranscriptSentence: Codable, Equatable {
    var text: String
    var startTimeSeconds: Double
    var endTimeSeconds: Double
    var confidence: Double?
    var speaker: String?
    var channel: String?
}

extension Notification.Name {
    /// Posted after `Media.spec` transcript fields are persisted (e.g. `persistTranscript`). `userInfo["mediaId"]` is the `media_id` string.
    static let irisMediaTranscriptDidPersist = Notification.Name("MagnoliaCreative.Iris.mediaTranscriptDidPersist")
}
