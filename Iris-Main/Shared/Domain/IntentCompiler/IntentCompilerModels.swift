import Foundation

struct IntentCompilerContext: Codable, Equatable {
    let timelineId: String
    let selectedClipId: String?
    let selectedTrackId: String?
    let selectedRange: TimeRange?
    let playheadTimeUs: Int64?
    let clipsById: [String: Clip]
    let orderedClipIdsByTrackId: [String: [String]]

    var selectedClip: Clip? {
        guard let selectedClipId else { return nil }
        return clipsById[selectedClipId]
    }

    func clip(withId clipId: String?) -> Clip? {
        guard let clipId else { return nil }
        return clipsById[clipId]
    }

    func orderedClipIds(for clip: Clip) -> [String] {
        orderedClipIdsByTrackId[clip.trackId] ?? []
    }

    func orderedClips(for trackId: String) -> [Clip] {
        (orderedClipIdsByTrackId[trackId] ?? []).compactMap { clipsById[$0] }
    }
}

struct IntentCompileResult: Codable, Equatable {
    let actions: [Action]
    let confidence: Double
    let source: CompileSource
    let unresolvedText: String?
    let warnings: [IntentCompileWarning]
    let needsClarification: Bool
    let experimentalEffectOperations: [ExperimentalEffectOperation]

    init(
        actions: [Action],
        confidence: Double,
        source: CompileSource,
        unresolvedText: String?,
        warnings: [IntentCompileWarning],
        needsClarification: Bool,
        experimentalEffectOperations: [ExperimentalEffectOperation] = []
    ) {
        self.actions = actions
        self.confidence = confidence
        self.source = source
        self.unresolvedText = unresolvedText
        self.warnings = warnings
        self.needsClarification = needsClarification
        self.experimentalEffectOperations = experimentalEffectOperations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.actions = try container.decode([Action].self, forKey: .actions)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.source = try container.decode(CompileSource.self, forKey: .source)
        self.unresolvedText = try container.decodeIfPresent(String.self, forKey: .unresolvedText)
        self.warnings = try container.decode([IntentCompileWarning].self, forKey: .warnings)
        self.needsClarification = try container.decode(Bool.self, forKey: .needsClarification)
        self.experimentalEffectOperations = try container.decodeIfPresent(
            [ExperimentalEffectOperation].self,
            forKey: .experimentalEffectOperations
        ) ?? []
    }

    static func unsupported(
        source: CompileSource,
        unresolvedText: String,
        warnings: [IntentCompileWarning] = [.unsupportedIntent]
    ) -> IntentCompileResult {
        IntentCompileResult(
            actions: [],
            confidence: 0,
            source: source,
            unresolvedText: unresolvedText,
            warnings: warnings,
            needsClarification: false
        )
    }
}

enum CompileSource: String, Codable, Equatable {
    case deterministic
    case embedding
    case llm
    case mixed
}

enum IntentCompileWarning: String, Codable, Equatable, Hashable {
    case missingSelectedClip
    case missingPlayhead
    case missingSelectedTrack
    case clipNotFound
    case trackNotFound
    case splitTimeOutsideClip
    case invalidTrimRange
    case invalidMoveOrder
    case unsupportedAction
    case unsupportedIntent
    case ambiguousTarget
    case noActionProduced
    case embeddingUnavailable
    case llmUnavailable
    case invalidLLMResponse
    case lowConfidence
    case destructiveActionNeedsClarification
}

enum IntentEditType: String, Codable, Equatable, Hashable, CaseIterable {
    case splitClip
    case removeClip
    case trimClip
    case moveClip
    case replaceTrackClips
    case unknown
}

struct IntentEmbeddingCandidate: Codable, Equatable {
    let type: IntentEditType
    let example: String
    let score: Double
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int64.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int64? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int64(value)
        case .string(let value):
            return Int64(value)
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }
}

protocol EmbeddingProvider {
    func embed(_ text: String) async throws -> [Float]
}

protocol IntentLLMProvider {
    func complete(prompt: String) async throws -> String
}

struct StubEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String) async throws -> [Float] {
        IntentKeywordEmbedding.vector(for: text)
    }
}

struct UnavailableIntentLLMProvider: IntentLLMProvider {
    func complete(prompt: String) async throws -> String {
        throw IntentCompilerError.llmUnavailable
    }
}

enum IntentCompilerError: Error, Equatable {
    case llmUnavailable
    case invalidLLMResponse
}

enum IntentKeywordEmbedding {
    static func vector(for text: String) -> [Float] {
        let normalized = text.lowercased()
        let keywordGroups = [
            ["split", "cut", "divide", "two clips", "half"],
            ["delete", "remove", "rid", "take out"],
            ["trim", "shorten", "beginning", "start", "end", "first", "last", "final"],
            ["move", "reorder", "beginning", "end", "first", "last", "before", "after"]
        ]

        return keywordGroups.map { keywords in
            keywords.reduce(Float(0)) { score, keyword in
                normalized.contains(keyword) ? score + 1 : score
            }
        }
    }
}

enum IntentCompilerLog {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func json<T: Encodable>(_ value: T) -> String {
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "<invalid utf8>"
        } catch {
            return "<failed to encode \(T.self): \(error)>"
        }
    }
}
