import Foundation

struct RemoteIntentRunCreatePayload: Encodable {
    let kind = "intent"
    let prompt: String
    let context: IntentCompilerContext
    let editorContext: RemoteIntentEditorContext?
    let currentWorkspaceId: String?

    init(
        prompt: String,
        context: IntentCompilerContext,
        editorContext: RemoteIntentEditorContext? = nil,
        currentWorkspaceId: String? = nil
    ) {
        self.prompt = prompt
        self.context = context
        self.editorContext = editorContext
        self.currentWorkspaceId = currentWorkspaceId
    }
}

struct RemoteIntentEditorContext: Codable, Equatable {
    let activeSpace: String?
    let hasSelectedClip: Bool
}

struct RemoteIntentAgentResponse: Decodable, Equatable {
    let edit: IntentCompileResult
    let ui: RemoteIntentUIPlan
    let meta: RemoteIntentAgentMeta
}

struct RemoteIntentAgentMeta: Decodable, Equatable {
    let hydration: [String: JSONValue]
    let editEvents: [[String: JSONValue]]
    let uiEvents: [[String: JSONValue]]
    let timings: [RemoteIntentTiming]

    enum CodingKeys: String, CodingKey {
        case hydration
        case editEvents = "edit_events"
        case uiEvents = "ui_events"
        case timings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hydration = try container.decodeIfPresent([String: JSONValue].self, forKey: .hydration) ?? [:]
        editEvents = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .editEvents) ?? []
        uiEvents = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .uiEvents) ?? []
        timings = try container.decodeIfPresent([RemoteIntentTiming].self, forKey: .timings) ?? []
    }
}

struct RemoteIntentTiming: Decodable, Equatable {
    let branch: String
    let elapsedMs: Int

    enum CodingKeys: String, CodingKey {
        case branch
        case elapsedMs = "elapsed_ms"
    }
}

struct RemoteIntentUIPlan: Decodable, Equatable {
    let catalogVersion: String
    let workspaceId: String
    let intentSummary: String
    let intentSlices: [[String: JSONValue]]
    let currentSliceId: String?
    let currentSliceIndex: Int
    let layout: [String: JSONValue]
    let toolbar: [String: JSONValue]
    let transitions: [[String: JSONValue]]
    let hiddenBecauseIrrelevant: [String]
    let warnings: [String]
    let isDefaultWorkspace: Bool
    let restoreDefaultOnComplete: Bool

    enum CodingKeys: String, CodingKey {
        case catalogVersion
        case workspaceId
        case intentSummary
        case intentSlices
        case currentSliceId
        case currentSliceIndex
        case layout
        case toolbar
        case transitions
        case hiddenBecauseIrrelevant
        case warnings
        case isDefaultWorkspace
        case restoreDefaultOnComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogVersion = try container.decodeIfPresent(String.self, forKey: .catalogVersion) ?? "1"
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        intentSummary = try container.decodeIfPresent(String.self, forKey: .intentSummary) ?? ""
        intentSlices = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .intentSlices) ?? []
        currentSliceId = try container.decodeIfPresent(String.self, forKey: .currentSliceId)
        currentSliceIndex = try container.decodeIfPresent(Int.self, forKey: .currentSliceIndex) ?? 0
        layout = try container.decodeIfPresent([String: JSONValue].self, forKey: .layout) ?? [:]
        toolbar = try container.decodeIfPresent([String: JSONValue].self, forKey: .toolbar) ?? [:]
        transitions = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .transitions) ?? []
        hiddenBecauseIrrelevant = try container.decodeIfPresent([String].self, forKey: .hiddenBecauseIrrelevant) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        isDefaultWorkspace = try container.decodeIfPresent(Bool.self, forKey: .isDefaultWorkspace) ?? false
        restoreDefaultOnComplete = try container.decodeIfPresent(Bool.self, forKey: .restoreDefaultOnComplete) ?? true
    }
}

enum RemoteIntentCompilerEvent {
    case runStarted(prompt: String?)
    case status(type: String, message: String?)
    case intentResult(prompt: String?, result: IntentCompileResult)
    case error(detail: String)
    case unknown(type: String)

    static func decode(from data: Data, using decoder: JSONDecoder) throws -> RemoteIntentCompilerEvent {
        let envelope = try decoder.decode(RemoteIntentCompilerEnvelope.self, from: data)
        switch envelope.type {
        case "run_started":
            let payload = try decoder.decode(RemoteIntentRunStartedEvent.self, from: data)
            return .runStarted(prompt: payload.prompt)
        case "planner_started",
             "planner_completed",
             "effect_planner_started",
             "effect_planner_completed",
             "validation_completed":
            let payload = try decoder.decode(RemoteIntentStatusEvent.self, from: data)
            return .status(type: envelope.type, message: payload.status ?? payload.intent)
        case "intent_result":
            let payload = try decoder.decode(RemoteIntentResultEvent.self, from: data)
            return .intentResult(prompt: payload.prompt, result: payload.result)
        case "error":
            let payload = try decoder.decode(RemoteIntentErrorEvent.self, from: data)
            return .error(detail: payload.detail)
        default:
            return .unknown(type: envelope.type)
        }
    }
}

private struct RemoteIntentCompilerEnvelope: Decodable {
    let type: String
}

private struct RemoteIntentRunStartedEvent: Decodable {
    let prompt: String?
}

private struct RemoteIntentStatusEvent: Decodable {
    let status: String?
    let intent: String?
}

private struct RemoteIntentResultEvent: Decodable {
    let prompt: String?
    let result: IntentCompileResult
}

private struct RemoteIntentErrorEvent: Decodable {
    let detail: String
}

