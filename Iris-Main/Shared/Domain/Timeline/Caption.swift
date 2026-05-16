import Foundation
import GRDB

enum CaptionStyle: String, Codable, CaseIterable, Sendable {
    case classic
    case modern
    case neo
}

struct CaptionGroup: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    let groupId: String
    let trackId: String
    let timelineId: String
    var style: CaptionStyle
    var hasBackground: Bool
    /// Stored as hex e.g. `#FFFFFF`
    var textColor: String
    var rangeStartUs: Int64?
    var rangeEndUs: Int64?
    let createdAt: Date
    var updatedAt: Date

    var id: String { groupId }

    init(
        groupId: String = UUID().uuidString,
        trackId: String,
        timelineId: String,
        style: CaptionStyle = .modern,
        hasBackground: Bool = false,
        textColor: String = "#FFFFFF",
        rangeStartUs: Int64? = nil,
        rangeEndUs: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.groupId = groupId
        self.trackId = trackId
        self.timelineId = timelineId
        self.style = style
        self.hasBackground = hasBackground
        self.textColor = textColor
        self.rangeStartUs = rangeStartUs
        self.rangeEndUs = rangeEndUs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case trackId = "track_id"
        case timelineId = "timeline_id"
        case style
        case hasBackground = "has_background"
        case textColor = "text_color"
        case rangeStartUs = "range_start_us"
        case rangeEndUs = "range_end_us"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "caption_groups"

    enum Columns: String, ColumnExpression {
        case groupId = "group_id"
        case trackId = "track_id"
        case timelineId = "timeline_id"
        case style
        case hasBackground = "has_background"
        case textColor = "text_color"
        case rangeStartUs = "range_start_us"
        case rangeEndUs = "range_end_us"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(row: Row) {
        groupId = row[Columns.groupId]
        trackId = row[Columns.trackId]
        timelineId = row[Columns.timelineId]
        style = CaptionStyle(rawValue: row[Columns.style]) ?? .modern
        hasBackground = row[Columns.hasBackground]
        textColor = row[Columns.textColor]
        rangeStartUs = row[Columns.rangeStartUs]
        rangeEndUs = row[Columns.rangeEndUs]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.groupId] = groupId
        container[Columns.trackId] = trackId
        container[Columns.timelineId] = timelineId
        container[Columns.style] = style.rawValue
        container[Columns.hasBackground] = hasBackground
        container[Columns.textColor] = textColor
        container[Columns.rangeStartUs] = rangeStartUs
        container[Columns.rangeEndUs] = rangeEndUs
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

extension CaptionStyle: DatabaseValueConvertible {}

struct CaptionCue: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    let cueId: String
    let groupId: String
    var clipId: String?
    var text: String
    var timelineStartUs: Int64
    var timelineEndUs: Int64
    var sourceStartUs: Int64?
    var sourceEndUs: Int64?
    let createdAt: Date
    var updatedAt: Date

    var id: String { cueId }

    init(
        cueId: String = UUID().uuidString,
        groupId: String,
        clipId: String? = nil,
        text: String,
        timelineStartUs: Int64,
        timelineEndUs: Int64,
        sourceStartUs: Int64? = nil,
        sourceEndUs: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.cueId = cueId
        self.groupId = groupId
        self.clipId = clipId
        self.text = text
        self.timelineStartUs = timelineStartUs
        self.timelineEndUs = timelineEndUs
        self.sourceStartUs = sourceStartUs
        self.sourceEndUs = sourceEndUs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case cueId = "cue_id"
        case groupId = "group_id"
        case clipId = "clip_id"
        case text
        case timelineStartUs = "timeline_start_us"
        case timelineEndUs = "timeline_end_us"
        case sourceStartUs = "source_start_us"
        case sourceEndUs = "source_end_us"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "caption_cues"

    enum Columns: String, ColumnExpression {
        case cueId = "cue_id"
        case groupId = "group_id"
        case clipId = "clip_id"
        case text
        case timelineStartUs = "timeline_start_us"
        case timelineEndUs = "timeline_end_us"
        case sourceStartUs = "source_start_us"
        case sourceEndUs = "source_end_us"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(row: Row) {
        cueId = row[Columns.cueId]
        groupId = row[Columns.groupId]
        clipId = row[Columns.clipId]
        text = row[Columns.text]
        timelineStartUs = row[Columns.timelineStartUs]
        timelineEndUs = row[Columns.timelineEndUs]
        sourceStartUs = row[Columns.sourceStartUs]
        sourceEndUs = row[Columns.sourceEndUs]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.cueId] = cueId
        container[Columns.groupId] = groupId
        container[Columns.clipId] = clipId
        container[Columns.text] = text
        container[Columns.timelineStartUs] = timelineStartUs
        container[Columns.timelineEndUs] = timelineEndUs
        container[Columns.sourceStartUs] = sourceStartUs
        container[Columns.sourceEndUs] = sourceEndUs
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}
