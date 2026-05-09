import Foundation

// MARK: - Client → server

struct RealtimeTranscriptionClientAudioMessage: Encodable {
    let type: String
    let audio: String

    init(audio: String) {
        self.type = "audio"
        self.audio = audio
    }
}

struct RealtimeTranscriptionClientStopMessage: Encodable {
    let type: String

    init() {
        self.type = "stop"
    }
}

// MARK: - Server → client (envelope)

enum RealtimeTranscriptionServerEvent: Equatable {
    case sessionReady(model: String)
    case delta(text: String)
    case completed(text: String)
    case speechStarted
    case speechStopped
    case error(detail: String)
    case unknown(type: String)

    var displayType: String {
        switch self {
        case .sessionReady:
            return "session_ready"
        case .delta:
            return "delta"
        case .completed:
            return "completed"
        case .speechStarted:
            return "speech_started"
        case .speechStopped:
            return "speech_stopped"
        case .error:
            return "error"
        case .unknown(let type):
            return type
        }
    }

    static func decode(from data: Data, using decoder: JSONDecoder) throws -> RealtimeTranscriptionServerEvent {
        let envelope = try decoder.decode(RealtimeTranscriptionEnvelope.self, from: data)
        switch envelope.type {
        case "session_ready":
            let payload = try decoder.decode(RealtimeTranscriptionSessionReady.self, from: data)
            return .sessionReady(model: payload.model ?? "")
        case "delta":
            let payload = try decoder.decode(RealtimeTranscriptionDelta.self, from: data)
            return .delta(text: payload.text ?? "")
        case "completed":
            let payload = try decoder.decode(RealtimeTranscriptionCompleted.self, from: data)
            return .completed(text: payload.text ?? "")
        case "speech_started":
            return .speechStarted
        case "speech_stopped":
            return .speechStopped
        case "error":
            let payload = try decoder.decode(RealtimeTranscriptionErrorPayload.self, from: data)
            return .error(detail: payload.detail ?? "Unknown error")
        default:
            return .unknown(type: envelope.type)
        }
    }
}

private struct RealtimeTranscriptionEnvelope: Decodable {
    let type: String
}

private struct RealtimeTranscriptionSessionReady: Decodable {
    let model: String?
}

private struct RealtimeTranscriptionDelta: Decodable {
    let text: String?
}

private struct RealtimeTranscriptionCompleted: Decodable {
    let text: String?
}

private struct RealtimeTranscriptionErrorPayload: Decodable {
    let detail: String?
}
