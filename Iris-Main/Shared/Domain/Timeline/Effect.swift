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

struct ClipColorFilter: Codable, Equatable {
    var temperature: Float
    var tint: Float
    var exposure: Float
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var highlights: Float
    var shadows: Float

    static let neutral = ClipColorFilter(
        temperature: 0,
        tint: 0,
        exposure: 0,
        brightness: 0,
        contrast: 0,
        saturation: 0,
        highlights: 0,
        shadows: 0
    )

    init(
        temperature: Float = 0,
        tint: Float = 0,
        exposure: Float = 0,
        brightness: Float = 0,
        contrast: Float = 0,
        saturation: Float = 0,
        highlights: Float = 0,
        shadows: Float = 0
    ) {
        self.temperature = Self.clamp(temperature, to: Self.normalizedRange)
        self.tint = Self.clamp(tint, to: Self.normalizedRange)
        self.exposure = Self.clamp(exposure, to: Self.exposureRange)
        self.brightness = Self.clamp(brightness, to: Self.normalizedRange)
        self.contrast = Self.clamp(contrast, to: Self.normalizedRange)
        self.saturation = Self.clamp(saturation, to: Self.normalizedRange)
        self.highlights = Self.clamp(highlights, to: Self.normalizedRange)
        self.shadows = Self.clamp(shadows, to: Self.normalizedRange)
    }
}

extension ClipColorFilter {
    static let effectType = "clip_color_filter"
    static let normalizedRange: ClosedRange<Float> = -1...1
    static let exposureRange: ClosedRange<Float> = -4...4

    var isNeutral: Bool {
        self == .neutral
    }

    var effectParameters: [String: EffectParameterValue] {
        [
            "temperature": .number(Double(temperature)),
            "tint": .number(Double(tint)),
            "exposure": .number(Double(exposure)),
            "brightness": .number(Double(brightness)),
            "contrast": .number(Double(contrast)),
            "saturation": .number(Double(saturation)),
            "highlights": .number(Double(highlights)),
            "shadows": .number(Double(shadows)),
        ]
    }

    init(parameters: [String: EffectParameterValue]) {
        self.init(
            temperature: parameters.floatValue(for: "temperature"),
            tint: parameters.floatValue(for: "tint"),
            exposure: parameters.floatValue(for: "exposure"),
            brightness: parameters.floatValue(for: "brightness"),
            contrast: parameters.floatValue(for: "contrast"),
            saturation: parameters.floatValue(for: "saturation"),
            highlights: parameters.floatValue(for: "highlights"),
            shadows: parameters.floatValue(for: "shadows")
        )
    }

    /// Returns a copy of this filter with non-nil patch fields applied. Missing
    /// keys leave existing values unchanged so partial updates compose.
    func applying(_ patch: ClipColorFilterPatch) -> ClipColorFilter {
        ClipColorFilter(
            temperature: patch.temperature ?? temperature,
            tint: patch.tint ?? tint,
            exposure: patch.exposure ?? exposure,
            brightness: patch.brightness ?? brightness,
            contrast: patch.contrast ?? contrast,
            saturation: patch.saturation ?? saturation,
            highlights: patch.highlights ?? highlights,
            shadows: patch.shadows ?? shadows
        )
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension Effect {
    var clipColorFilter: ClipColorFilter? {
        guard type == ClipColorFilter.effectType, appliesTo == .clip else { return nil }
        return ClipColorFilter(parameters: parameters)
    }

    static func clipColorFilter(
        timelineId: String,
        clipId: String,
        filter: ClipColorFilter,
        effectId: String = UUID().uuidString,
        createdAt: Date = Date()
    ) -> Effect {
        Effect(
            effectId: effectId,
            timelineId: timelineId,
            type: ClipColorFilter.effectType,
            appliesTo: .clip,
            targetId: clipId,
            parameters: filter.effectParameters,
            constraints: ClipColorFilter.effectConstraints,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

private extension ClipColorFilter {
    static var effectConstraints: [String: EffectConstraints] {
        let normalized = EffectConstraints(min: Double(normalizedRange.lowerBound), max: Double(normalizedRange.upperBound))
        return [
            "temperature": normalized,
            "tint": normalized,
            "exposure": EffectConstraints(min: Double(exposureRange.lowerBound), max: Double(exposureRange.upperBound)),
            "brightness": normalized,
            "contrast": normalized,
            "saturation": normalized,
            "highlights": normalized,
            "shadows": normalized,
        ]
    }
}

// MARK: - ClipColorFilterPatch

/// Sparse update to a `ClipColorFilter`. Each `nil` field keeps the existing
/// value when applied, making it the natural payload for backend prompts that
/// only intend to adjust one parameter (e.g. "make it warmer").
struct ClipColorFilterPatch: Codable, Equatable {
    var temperature: Float?
    var tint: Float?
    var exposure: Float?
    var brightness: Float?
    var contrast: Float?
    var saturation: Float?
    var highlights: Float?
    var shadows: Float?

    init(
        temperature: Float? = nil,
        tint: Float? = nil,
        exposure: Float? = nil,
        brightness: Float? = nil,
        contrast: Float? = nil,
        saturation: Float? = nil,
        highlights: Float? = nil,
        shadows: Float? = nil
    ) {
        self.temperature = temperature
        self.tint = tint
        self.exposure = exposure
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.highlights = highlights
        self.shadows = shadows
    }

    var isEmpty: Bool {
        temperature == nil && tint == nil && exposure == nil && brightness == nil
            && contrast == nil && saturation == nil && highlights == nil && shadows == nil
    }
}

private extension Dictionary where Key == String, Value == EffectParameterValue {
    func floatValue(for key: String) -> Float {
        guard let value = self[key] else { return 0 }
        switch value {
        case .number(let number):
            return Float(number)
        case .boolean:
            return 0
        case .string(let string):
            return Float(string) ?? 0
        }
    }
}
