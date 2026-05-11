import Foundation

struct RemoteIntentRunCreatePayload: Encodable {
    let prompt: String
    let context: IntentCompilerContext
}

struct RemoteIntentRunCreateResponse: Decodable {
    let runID: String
    let websocketURL: URL

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case websocketURL = "websocket_url"
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

