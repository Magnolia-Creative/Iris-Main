import Foundation
import GRDB

struct Action: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let actionId: String
    let timelineId: String
    let createdAt: Date
    let type: ActionType
    let targetId: String?
    var parameters: [String: AnyCodable]?
    let groupId: String?

    var id: String { actionId }

    init(
        actionId: String = UUID().uuidString,
        timelineId: String = "",
        createdAt: Date = Date(),
        type: ActionType,
        targetId: String? = nil,
        parameters: [String: AnyCodable]? = nil,
        groupId: String? = nil
    ) {
        self.actionId = actionId
        self.timelineId = timelineId
        self.createdAt = createdAt
        self.type = type
        self.targetId = targetId
        self.parameters = parameters
        self.groupId = groupId
    }

    enum CodingKeys: String, CodingKey {
        case actionId = "action_id"
        case timelineId = "timeline_id"
        case createdAt = "created_at"
        case type
        case targetId = "target_id"
        case parameters
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
    }
}

enum ActionType: String, Codable {
    case importMedia = "IMPORT_MEDIA"
    case addClip = "ADD_CLIP"
    case removeClip = "REMOVE_CLIP"
    case trimClip = "TRIM_CLIP"
    case splitClip = "SPLIT_CLIP"
    case moveClip = "MOVE_CLIP"
    case applyEffect = "APPLY_EFFECT"
    case removeEffect = "REMOVE_EFFECT"
    case updateEffectParams = "UPDATE_EFFECT_PARAMS"
    case reorderClips = "REORDER_CLIPS"
    case setProjectSettings = "SET_PROJECT_SETTINGS"
}

extension ActionType: DatabaseValueConvertible {}

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
