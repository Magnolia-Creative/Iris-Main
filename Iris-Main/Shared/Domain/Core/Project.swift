import Foundation
import GRDB

struct Project: Codable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    let projectId: String
    let name: String
    var description: String?
    var coverImagePath: String?
    let schemaVersion: String
    var resolutionWidth: Int
    var resolutionHeight: Int
    var frameRate: Int
    let createdAt: Date
    var updatedAt: Date
    var lastAccessedAt: Date?

    var id: String { projectId }

    init(
        projectId: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        coverImagePath: String? = nil,
        schemaVersion: String = "1.0",
        resolutionWidth: Int = 1920,
        resolutionHeight: Int = 1080,
        frameRate: Int = 30,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAccessedAt: Date? = Date()
    ) {
        self.projectId = projectId
        self.name = name
        self.description = description
        self.coverImagePath = coverImagePath
        self.schemaVersion = schemaVersion
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.frameRate = frameRate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
    }

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case name
        case description
        case coverImagePath = "cover_image_path"
        case schemaVersion = "schema_version"
        case resolutionWidth = "resolution_width"
        case resolutionHeight = "resolution_height"
        case frameRate = "frame_rate"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastAccessedAt = "last_accessed_at"
    }

    static let databaseTableName = "projects"

    enum Columns {
        static let projectID = Column(CodingKeys.projectId)
        static let name = Column(CodingKeys.name)
        static let description = Column(CodingKeys.description)
        static let coverImagePath = Column(CodingKeys.coverImagePath)
        static let schemaVersion = Column(CodingKeys.schemaVersion)
        static let resolutionWidth = Column(CodingKeys.resolutionWidth)
        static let resolutionHeight = Column(CodingKeys.resolutionHeight)
        static let frameRate = Column(CodingKeys.frameRate)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let lastAccessedAt = Column(CodingKeys.lastAccessedAt)
    }

    var resolutionLabel: String {
        if resolutionWidth >= 3840 { return "4K" }
        return "1080p"
    }

    var primaryTimestamp: Date {
        lastAccessedAt ?? updatedAt
    }
}
