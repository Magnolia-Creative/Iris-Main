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
}
