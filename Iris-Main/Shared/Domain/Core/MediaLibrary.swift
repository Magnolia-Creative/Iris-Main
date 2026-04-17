import Foundation
import GRDB

struct MediaLibrary: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let mediaLibraryId: String
    let projectId: String
    let schemaVersion: String
    var settings: MediaLibrarySettings
    let createdAt: Date
    var updatedAt: Date

    var id: String { mediaLibraryId }

    init(
        mediaLibraryId: String = UUID().uuidString,
        projectId: String,
        schemaVersion: String = "1.0",
        settings: MediaLibrarySettings = MediaLibrarySettings(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.mediaLibraryId = mediaLibraryId
        self.projectId = projectId
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case mediaLibraryId = "media_library_id"
        case projectId = "project_id"
        case schemaVersion = "schema_version"
        case settings
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "media_libraries"

    enum Columns: String, ColumnExpression {
        case mediaLibraryId = "media_library_id"
        case projectId = "project_id"
        case schemaVersion = "schema_version"
        case settings
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MediaLibrarySettings: Codable {
    var normalizeOrientation: Bool
    var preserveOriginals: Bool
    var proxyPolicy: ProxyPolicy
    var preferredProxyResolution: String?
    var allowUnusedMedia: Bool
    var cleanupPolicy: CleanupPolicy

    init(
        normalizeOrientation: Bool = true,
        preserveOriginals: Bool = true,
        proxyPolicy: ProxyPolicy = .auto,
        preferredProxyResolution: String? = "720p",
        allowUnusedMedia: Bool = true,
        cleanupPolicy: CleanupPolicy = .never
    ) {
        self.normalizeOrientation = normalizeOrientation
        self.preserveOriginals = preserveOriginals
        self.proxyPolicy = proxyPolicy
        self.preferredProxyResolution = preferredProxyResolution
        self.allowUnusedMedia = allowUnusedMedia
        self.cleanupPolicy = cleanupPolicy
    }
}
