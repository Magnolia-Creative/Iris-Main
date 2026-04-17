import Foundation
import GRDB

struct Timeline: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let timelineId: String
    let projectId: String
    var schemaVersion: String
    var timebase: String
    let createdAt: Date
    var updatedAt: Date

    var id: String { timelineId }

    init(
        timelineId: String = UUID().uuidString,
        projectId: String = "",
        schemaVersion: String = "1.0",
        timebase: String = "microseconds",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.timelineId = timelineId
        self.projectId = projectId
        self.schemaVersion = schemaVersion
        self.timebase = timebase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case timelineId = "timeline_id"
        case projectId = "project_id"
        case schemaVersion = "schema_version"
        case timebase
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "timelines"

    enum Columns: String, ColumnExpression {
        case timelineId = "timeline_id"
        case projectId = "project_id"
        case schemaVersion = "schema_version"
        case timebase
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(row: Row) {
        timelineId = row[Columns.timelineId]
        projectId = row[Columns.projectId]
        schemaVersion = row[Columns.schemaVersion]
        timebase = row[Columns.timebase]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.timelineId] = timelineId
        container[Columns.projectId] = projectId
        container[Columns.schemaVersion] = schemaVersion
        container[Columns.timebase] = timebase
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

struct Track: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let trackId: String
    let timelineId: String
    let kind: TrackKind
    var ordering: String
    var sortIndex: Int
    let createdAt: Date
    var updatedAt: Date

    var id: String { trackId }

    init(
        trackId: String = UUID().uuidString,
        timelineId: String = "",
        kind: TrackKind,
        ordering: String = "by_start_time",
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.trackId = trackId
        self.timelineId = timelineId
        self.kind = kind
        self.ordering = ordering
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case timelineId = "timeline_id"
        case kind
        case ordering
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "tracks"

    enum Columns: String, ColumnExpression {
        case trackId = "track_id"
        case timelineId = "timeline_id"
        case kind
        case ordering
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(row: Row) {
        trackId = row[Columns.trackId]
        timelineId = row[Columns.timelineId]
        kind = row[Columns.kind]
        ordering = row[Columns.ordering]
        sortIndex = row[Columns.sortIndex]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.trackId] = trackId
        container[Columns.timelineId] = timelineId
        container[Columns.kind] = kind
        container[Columns.ordering] = ordering
        container[Columns.sortIndex] = sortIndex
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

enum TrackKind: String, Codable {
    case video
    case audio
    case overlay
}

extension TrackKind: DatabaseValueConvertible {}
