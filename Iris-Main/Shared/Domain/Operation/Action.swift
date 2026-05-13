import Foundation
import GRDB

// MARK: - Payload

enum ActionPayload: Equatable, Codable {
    case splitClip(clipId: String, atTimeUs: Int64)
    case removeClip(clipId: String)
    case addClip(clip: Clip)
    case trimClip(clipId: String, sourceRange: TimeRange)
    case removeClipRanges(clipId: String, sourceRanges: [TimeRange])
    case moveClip(clipId: String, orderedClipIds: [String])
    /// Restores the ordered clip list for a single track (used for undo/redo and inverse actions).
    case replaceTrackClips(trackId: String, clips: [Clip])

    /// Sparse update to a clip's color filter. Unset fields preserve the existing
    /// value so backend prompts like "make it warmer" only touch `temperature`.
    case updateClipColorFilter(clipId: String, adjustments: ClipColorFilterPatch)
    /// Replaces the clip's entire color filter with `filter` (used for inverse
    /// undo so we can restore the previous state precisely).
    case setClipColorFilter(clipId: String, filter: ClipColorFilter)
    /// Removes any color filter on the clip.
    case resetClipColorFilter(clipId: String)
}

// MARK: - Action

struct Action: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    let actionId: String
    let timelineId: String
    let createdAt: Date
    let type: ActionType
    let payload: ActionPayload
    let groupId: String?

    var id: String { actionId }

    init(
        actionId: String = UUID().uuidString,
        timelineId: String = "",
        createdAt: Date = Date(),
        type: ActionType,
        payload: ActionPayload,
        groupId: String? = nil
    ) {
        self.actionId = actionId
        self.timelineId = timelineId
        self.createdAt = createdAt
        self.type = type
        self.payload = payload
        self.groupId = groupId
    }

    init(
        actionId: String = UUID().uuidString,
        timelineId: String = "",
        createdAt: Date = Date(),
        payload: ActionPayload,
        groupId: String? = nil
    ) {
        self.init(
            actionId: actionId,
            timelineId: timelineId,
            createdAt: createdAt,
            type: Self.actionType(for: payload),
            payload: payload,
            groupId: groupId
        )
    }

    enum CodingKeys: String, CodingKey {
        case actionId = "action_id"
        case timelineId = "timeline_id"
        case createdAt = "created_at"
        case type
        case payload
        case groupId = "group_id"
    }

    static let databaseTableName = "timeline_actions"

    enum Columns: String, ColumnExpression {
        case actionId = "action_id"
        case timelineId = "timeline_id"
        case createdAt = "created_at"
        case type
        case targetId = "target_id"
        case parameters
        case groupId = "group_id"
        case payloadJson = "payload_json"
    }

    init(row: Row) throws {
        actionId = row[Columns.actionId]
        timelineId = row[Columns.timelineId]
        createdAt = row[Columns.createdAt]
        type = row[Columns.type]
        groupId = row[Columns.groupId]

        if let jsonString: String = row[Columns.payloadJson], !jsonString.isEmpty,
           let data = jsonString.data(using: .utf8) {
            payload = try Self.decodePayload(from: data)
        } else {
            // Legacy rows without `payload_json`: no-op when applied.
            payload = .removeClip(clipId: "")
        }
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.actionId] = actionId
        container[Columns.timelineId] = timelineId
        container[Columns.createdAt] = createdAt
        container[Columns.type] = type
        container[Columns.targetId] = nil
        container[Columns.parameters] = nil
        container[Columns.groupId] = groupId

        let data = try Self.encodePayloadData(payload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                payload,
                EncodingError.Context(codingPath: [], debugDescription: "payload JSON encoding failed")
            )
        }
        container[Columns.payloadJson] = jsonString
    }

    static func actionType(for payload: ActionPayload) -> ActionType {
        switch payload {
        case .splitClip: return .splitClip
        case .removeClip: return .removeClip
        case .addClip: return .addClip
        case .trimClip: return .trimClip
        case .removeClipRanges: return .removeClipRanges
        case .moveClip: return .moveClip
        case .replaceTrackClips: return .replaceTrackClips
        case .updateClipColorFilter: return .updateEffectParams
        case .setClipColorFilter: return .applyEffect
        case .resetClipColorFilter: return .removeEffect
        }
    }

    nonisolated private static func decodePayload(from data: Data) throws -> ActionPayload {
        try JSONDecoder().decode(ActionPayload.self, from: data)
    }

    nonisolated private static func encodePayloadData(_ payload: ActionPayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }
}

// MARK: - Factories

extension Action {
    static func splitClip(
        timelineId: String,
        clipId: String,
        atTimeUs: Int64,
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .splitClip(clipId: clipId, atTimeUs: atTimeUs),
            groupId: groupId
        )
    }

    static func removeClip(
        timelineId: String,
        clipId: String,
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .removeClip(clipId: clipId),
            groupId: groupId
        )
    }

    static func addClip(
        timelineId: String,
        clip: Clip,
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .addClip(clip: clip),
            groupId: groupId
        )
    }

    static func trimClip(
        timelineId: String,
        clipId: String,
        sourceRange: TimeRange,
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .trimClip(clipId: clipId, sourceRange: sourceRange),
            groupId: groupId
        )
    }

    static func removeClipRanges(
        timelineId: String,
        clipId: String,
        sourceRanges: [TimeRange],
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .removeClipRanges(clipId: clipId, sourceRanges: sourceRanges),
            groupId: groupId
        )
    }

    static func moveClip(
        timelineId: String,
        clipId: String,
        orderedClipIds: [String],
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .moveClip(clipId: clipId, orderedClipIds: orderedClipIds),
            groupId: groupId
        )
    }

    static func replaceTrackClips(
        timelineId: String,
        trackId: String,
        clips: [Clip],
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .replaceTrackClips(trackId: trackId, clips: clips),
            groupId: groupId
        )
    }

    static func updateClipColorFilter(
        timelineId: String,
        clipId: String,
        adjustments: ClipColorFilterPatch,
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .updateClipColorFilter(clipId: clipId, adjustments: adjustments),
            groupId: groupId
        )
    }

    static func setClipColorFilter(
        timelineId: String,
        clipId: String,
        filter: ClipColorFilter,
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .setClipColorFilter(clipId: clipId, filter: filter),
            groupId: groupId
        )
    }

    static func resetClipColorFilter(
        timelineId: String,
        clipId: String,
        groupId: String? = nil
    ) -> Action {
        Action(
            timelineId: timelineId,
            payload: .resetClipColorFilter(clipId: clipId),
            groupId: groupId
        )
    }
}

enum ActionType: String, Codable {
    case importMedia = "IMPORT_MEDIA"
    case addClip = "ADD_CLIP"
    case removeClip = "REMOVE_CLIP"
    case trimClip = "TRIM_CLIP"
    case removeClipRanges = "REMOVE_CLIP_RANGES"
    case splitClip = "SPLIT_CLIP"
    case moveClip = "MOVE_CLIP"
    case replaceTrackClips = "REPLACE_TRACK_CLIPS"
    case applyEffect = "APPLY_EFFECT"
    case removeEffect = "REMOVE_EFFECT"
    case updateEffectParams = "UPDATE_EFFECT_PARAMS"
    case reorderClips = "REORDER_CLIPS"
    case setProjectSettings = "SET_PROJECT_SETTINGS"
}

extension ActionType: DatabaseValueConvertible {}

// MARK: - AnyCodable (shared with analysis artifacts)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int: try container.encode(intValue)
        case let doubleValue as Double: try container.encode(doubleValue)
        case let boolValue as Bool: try container.encode(boolValue)
        case let stringValue as String: try container.encode(stringValue)
        case let arrayValue as [Any]: try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]: try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: container.codingPath, debugDescription: "Could not encode value")
            )
        }
    }
}
