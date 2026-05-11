import Foundation

struct VoiceIntentStartMessage: Encodable {
    let type = "start"
    let context: IntentCompilerContext
}

struct VoiceIntentFinalizeMessage: Encodable {
    let type = "finalize"
}

enum VoiceIntentServerEvent {
    case sessionReady(model: String)
    case transcriptDelta(text: String)
    case transcriptCompleted(text: String)
    case status(type: String, message: String?)
    case intentResult(prompt: String?, result: IntentCompileResult)
    case speechStarted
    case speechStopped
    case error(detail: String)
    case unknown(type: String)

    static func decode(from data: Data, using decoder: JSONDecoder) throws -> VoiceIntentServerEvent {
        let envelope = try decoder.decode(VoiceIntentEnvelope.self, from: data)
        switch envelope.type {
        case "session_ready":
            let payload = try decoder.decode(VoiceIntentSessionReady.self, from: data)
            return .sessionReady(model: payload.model ?? "")
        case "transcript_delta":
            let payload = try decoder.decode(VoiceIntentTextPayload.self, from: data)
            return .transcriptDelta(text: payload.text ?? "")
        case "transcript_completed":
            let payload = try decoder.decode(VoiceIntentTextPayload.self, from: data)
            return .transcriptCompleted(text: payload.text ?? "")
        case "planner_started",
             "planner_completed",
             "effect_planner_started",
             "effect_planner_completed",
             "validation_completed":
            let payload = try decoder.decode(VoiceIntentStatusPayload.self, from: data)
            return .status(type: envelope.type, message: payload.status ?? payload.intent)
        case "intent_result":
            let payload = try decoder.decode(VoiceIntentResultPayload.self, from: data)
            return .intentResult(prompt: payload.prompt, result: payload.result)
        case "speech_started":
            return .speechStarted
        case "speech_stopped":
            return .speechStopped
        case "error":
            let payload = try decoder.decode(VoiceIntentErrorPayload.self, from: data)
            return .error(detail: payload.detail)
        default:
            return .unknown(type: envelope.type)
        }
    }
}

private struct VoiceIntentEnvelope: Decodable {
    let type: String
}

private struct VoiceIntentSessionReady: Decodable {
    let model: String?
}

private struct VoiceIntentTextPayload: Decodable {
    let text: String?
}

private struct VoiceIntentStatusPayload: Decodable {
    let status: String?
    let intent: String?
}

private struct VoiceIntentResultPayload: Decodable {
    let prompt: String?
    let result: IntentCompileResult
}

private struct VoiceIntentErrorPayload: Decodable {
    let detail: String
}

