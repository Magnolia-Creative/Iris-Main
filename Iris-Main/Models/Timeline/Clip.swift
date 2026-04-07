import Foundation
import GRDB

struct Clip: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let clipId: String
    let trackId: String
    let mediaId: String
    var sourceRange: TimeRange
    var timelineRange: TimeRange
    let createdAt: Date
    var updatedAt: Date

    var id: String { clipId }

    init(
        clipId: String = UUID().uuidString,
        trackId: String = "",
        mediaId: String,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.clipId = clipId
        self.trackId = trackId
        self.mediaId = mediaId
        self.sourceRange = sourceRange
        self.timelineRange = timelineRange
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var duration: Int64 {
        timelineRange.end - timelineRange.start
    }

    enum CodingKeys: String, CodingKey {
        case clipId = "clip_id"
        case trackId = "track_id"
        case mediaId = "media_id"
        case sourceRange = "source_range"
        case timelineRange = "timeline_range"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "clips"

    enum Columns: String, ColumnExpression {
        case clipId = "clip_id"
        case trackId = "track_id"
        case mediaId = "media_id"
        case sourceStartUs = "source_start_us"
        case sourceEndUs = "source_end_us"
        case timelineStartUs = "timeline_start_us"
        case timelineEndUs = "timeline_end_us"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(row: Row) {
        clipId = row[Columns.clipId]
        trackId = row[Columns.trackId]
        mediaId = row[Columns.mediaId]
        let sourceStart: Int64 = row[Columns.sourceStartUs]
        let sourceEnd: Int64 = row[Columns.sourceEndUs]
        let timelineStart: Int64 = row[Columns.timelineStartUs]
        let timelineEnd: Int64 = row[Columns.timelineEndUs]
        sourceRange = TimeRange(start: sourceStart, end: sourceEnd)
        timelineRange = TimeRange(start: timelineStart, end: timelineEnd)
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.clipId] = clipId
        container[Columns.trackId] = trackId
        container[Columns.mediaId] = mediaId
        container[Columns.sourceStartUs] = sourceRange.start
        container[Columns.sourceEndUs] = sourceRange.end
        container[Columns.timelineStartUs] = timelineRange.start
        container[Columns.timelineEndUs] = timelineRange.end
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

struct TimeRange: Codable {
    var start: Int64
    var end: Int64

    init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }

    var duration: Int64 {
        end - start
    }
}
