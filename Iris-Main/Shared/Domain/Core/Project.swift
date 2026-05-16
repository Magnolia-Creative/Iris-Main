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
    var backendProjectId: String?
    var backendProjectName: String?
    /// When both are non-nil and positive, playback/export use this aspect instead of auto-from-first-clip.
    var manualOutputAspectWidth: Int?
    var manualOutputAspectHeight: Int?

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
        lastAccessedAt: Date? = Date(),
        backendProjectId: String? = nil,
        backendProjectName: String? = nil,
        manualOutputAspectWidth: Int? = nil,
        manualOutputAspectHeight: Int? = nil
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
        self.backendProjectId = backendProjectId
        self.backendProjectName = backendProjectName
        self.manualOutputAspectWidth = manualOutputAspectWidth
        self.manualOutputAspectHeight = manualOutputAspectHeight
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
        case backendProjectId = "backend_project_id"
        case backendProjectName = "backend_project_name"
        case manualOutputAspectWidth = "manual_output_aspect_w"
        case manualOutputAspectHeight = "manual_output_aspect_h"
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
        static let backendProjectId = Column(CodingKeys.backendProjectId)
        static let backendProjectName = Column(CodingKeys.backendProjectName)
        static let manualOutputAspectWidth = Column(CodingKeys.manualOutputAspectWidth)
        static let manualOutputAspectHeight = Column(CodingKeys.manualOutputAspectHeight)
    }

    /// Manual canvas aspect from persisted columns, if both dimensions are valid.
    var manualOutputAspect: OutputAspectRatio? {
        guard let w = manualOutputAspectWidth, let h = manualOutputAspectHeight, w > 0, h > 0 else {
            return nil
        }
        return OutputAspectRatio(width: w, height: h)
    }

    var resolutionLabel: String {
        if resolutionWidth >= 3840 { return "4K" }
        return "1080p"
    }

    var primaryTimestamp: Date {
        lastAccessedAt ?? updatedAt
    }
}
