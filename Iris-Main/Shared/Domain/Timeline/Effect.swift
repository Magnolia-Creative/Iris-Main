import Foundation
import GRDB

struct Effect: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let effectId: String
    let timelineId: String
    let type: String
    let appliesTo: AppliesTo
    let targetId: String
    var parameters: [String: EffectParameterValue]
    var constraints: [String: EffectConstraints]?
    let createdAt: Date
    var updatedAt: Date

    var id: String { effectId }

    init(
        effectId: String = UUID().uuidString,
        timelineId: String = "",
        type: String,
        appliesTo: AppliesTo,
        targetId: String,
        parameters: [String: EffectParameterValue] = [:],
        constraints: [String: EffectConstraints]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.effectId = effectId
        self.timelineId = timelineId
        self.type = type
        self.appliesTo = appliesTo
        self.targetId = targetId
        self.parameters = parameters
        self.constraints = constraints
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func updateParameter(key: String, value: EffectParameterValue) {
        parameters[key] = value
    }

    enum CodingKeys: String, CodingKey {
        case effectId = "effect_id"
        case timelineId = "timeline_id"
        case type
        case appliesTo = "applies_to"
        case targetId = "target_id"
        case parameters
        case constraints
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static let databaseTableName = "effects"

    enum Columns: String, ColumnExpression {
        case effectId = "effect_id"
        case timelineId = "timeline_id"
        case type
        case appliesTo = "applies_to"
        case targetId = "target_id"
        case parameters
        case constraints
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum AppliesTo: String, Codable {
    case clip
    case track
}

extension AppliesTo: DatabaseValueConvertible {}

enum EffectParameterValue: Codable {
    case number(Double)
    case boolean(Bool)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .boolean(boolValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not decode effect parameter value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

struct EffectConstraints: Codable {
    var min: Double?
    var max: Double?

    init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }
}
