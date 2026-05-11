import Foundation

struct SemanticEditPlan: Codable, Equatable {
    let operations: [SemanticEditOperation]
    let needsClarification: Bool
    let clarificationQuestion: String?
}

struct SemanticEditOperation: Codable, Equatable {
    let type: TimelineEditIntentType
    let sourceText: String
    let target: SemanticEditTarget?
    let parameters: [String: JSONValue]
    let confidence: Double
}

enum SemanticEditTarget: Codable, Equatable {
    case clip(SemanticClipReference)
    case track(SemanticTrackReference)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            throw DecodingError.valueNotFound(
                SemanticEditTarget.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Semantic target is null")
            )
        }

        let object = try container.decode([String: JSONValue].self)
        guard let type = object["type"]?.stringValue else {
            throw DecodingError.keyNotFound(
                CodingKeys.type,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Semantic target is missing type")
            )
        }

        if SemanticTrackReference.Kind(rawValue: type) != nil {
            self = .track(try SemanticTrackReference(object: object))
        } else {
            self = .clip(try SemanticClipReference(object: object))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .clip(let reference):
            try reference.encode(to: encoder)
        case .track(let reference):
            try reference.encode(to: encoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}

struct SemanticClipReference: Codable, Equatable {
    enum Kind: String, Codable {
        case selectedClip
        case clipId
        case sameAsPrevious
        case ordinal
        case currentClipAtPlayhead
    }

    let type: Kind
    let clipId: String?
    let value: String?
    let track: SemanticTrackReference?

    init(type: Kind, clipId: String? = nil, value: String? = nil, track: SemanticTrackReference? = nil) {
        self.type = type
        self.clipId = clipId
        self.value = value
        self.track = track
    }

    init(object: [String: JSONValue]) throws {
        guard let typeValue = object["type"]?.stringValue,
              let type = Kind(rawValue: typeValue) else {
            throw TimelineCompilerError.invalidLLMResponse
        }

        self.type = type
        self.clipId = object["clipId"]?.stringValue
        self.value = object["value"]?.stringValue
        if case .object(let trackObject) = object["track"] {
            self.track = try SemanticTrackReference(object: trackObject)
        } else {
            self.track = nil
        }
    }
}

struct SemanticTrackReference: Codable, Equatable {
    enum Kind: String, Codable {
        case selectedTrack
        case trackId
    }

    let type: Kind
    let trackId: String?

    init(type: Kind, trackId: String? = nil) {
        self.type = type
        self.trackId = trackId
    }

    init(object: [String: JSONValue]) throws {
        guard let typeValue = object["type"]?.stringValue,
              let type = Kind(rawValue: typeValue) else {
            throw TimelineCompilerError.invalidLLMResponse
        }

        self.type = type
        self.trackId = object["trackId"]?.stringValue
    }
}

enum DurationExpression: Equatable {
    case duration(value: Double, unit: DurationUnit)
    case percentage(value: Double)
    case vague(phrase: String)
}

enum DurationUnit: String, Codable, Equatable {
    case microsecond
    case millisecond
    case second
    case minute
}

enum TimeExpression: Equatable {
    case playhead
    case absoluteTimelineTime(value: Double, unit: DurationUnit)
    case fractionOfClip(value: Double, relativeTo: ClipTimeReference)
    case afterStart(amount: DurationExpression)
    case beforeEnd(amount: DurationExpression)
}

enum ClipTimeReference: String, Codable, Equatable {
    case originalClip
    case postPreviousOperations
}
