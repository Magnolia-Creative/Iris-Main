import Foundation

enum AgentSessionError: LocalizedError {
    case missingSessionData
    case invalidSessionEndpoint
    case disconnected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingSessionData:
            return "The upload response did not include the session data required to open the agent view."
        case .invalidSessionEndpoint:
            return "The websocket session URL could not be created from the current app configuration."
        case .disconnected:
            return "The live agent session is not connected."
        case .encodingFailed:
            return "The websocket message could not be encoded."
        }
    }
}

struct AgentSocketEnvelope: Decodable {
    let type: String
}

enum AgentSocketEvent {
    case sessionStarted(AgentSessionStartedEvent)
    case sessionResumed(AgentSessionResumedEvent)
    case sessionComplete(AgentSessionCompleteEvent)
    case sessionClosed(AgentSessionClosedEvent)
    case timelineUpdate(AgentTimelineUpdateEvent)
    case waitingForUser(AgentWaitingForUserEvent)
    case nodeStart(AgentNodeLifecycleEvent)
    case nodeComplete(AgentNodeLifecycleEvent)
    case statusUpdate(AgentStatusUpdateEvent)
    case stateSnapshot(AgentStateSnapshotEvent)
    case error(AgentErrorEvent)
    case unknown(String)

    static func decode(from data: Data, using decoder: JSONDecoder) throws -> AgentSocketEvent {
        let envelope = try decoder.decode(AgentSocketEnvelope.self, from: data)

        switch envelope.type {
        case "session_started":
            return .sessionStarted(try decoder.decode(AgentSessionStartedEvent.self, from: data))
        case "session_resumed":
            return .sessionResumed(try decoder.decode(AgentSessionResumedEvent.self, from: data))
        case "session_complete":
            return .sessionComplete(try decoder.decode(AgentSessionCompleteEvent.self, from: data))
        case "session_closed":
            return .sessionClosed(try decoder.decode(AgentSessionClosedEvent.self, from: data))
        case "timeline_update":
            return .timelineUpdate(try decoder.decode(AgentTimelineUpdateEvent.self, from: data))
        case "waiting_for_user":
            return .waitingForUser(try decoder.decode(AgentWaitingForUserEvent.self, from: data))
        case "node_start":
            return .nodeStart(try decoder.decode(AgentNodeLifecycleEvent.self, from: data))
        case "node_complete":
            return .nodeComplete(try decoder.decode(AgentNodeLifecycleEvent.self, from: data))
        case "status_update":
            return .statusUpdate(try decoder.decode(AgentStatusUpdateEvent.self, from: data))
        case "state_snapshot":
            return .stateSnapshot(try decoder.decode(AgentStateSnapshotEvent.self, from: data))
        case "error":
            return .error(try decoder.decode(AgentErrorEvent.self, from: data))
        default:
            return .unknown(envelope.type)
        }
    }
}

struct AgentSessionStartedEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?
    let uploadedCount: Int?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
        case uploadedCount = "uploaded_count"
    }
}

struct AgentSessionResumedEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let iterationCount: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case iterationCount = "iteration_count"
    }
}

struct AgentSessionCompleteEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?
    let timeline: [AgentTimelineEntry]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
        case timeline
    }
}

struct AgentSessionClosedEvent: Decodable {
    let sessionID: FlexibleIdentifier

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

struct AgentTimelineUpdateEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let timeline: [AgentTimelineEntry]
    let timelineNotes: [String]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case timeline
        case timelineNotes = "timeline_notes"
    }
}

struct AgentWaitingForUserEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
    }
}

struct AgentNodeLifecycleEvent: Decodable {
    let node: String
    let payload: AgentNodePayload?
}

struct AgentNodePayload: Decodable {
    let node: String?
    let statusMessage: String?
    let reasoningNotes: [String]?
    let inputClips: [AgentInputClip]?
    let inputClipIDs: [FlexibleIdentifier]?
    let clipIDs: [FlexibleIdentifier]?
    let selectedClipIDs: [FlexibleIdentifier]?
    let droppedClipIDs: [FlexibleIdentifier]?
    let clipRanges: [AgentClipRangePayload]?

    enum CodingKeys: String, CodingKey {
        case node
        case statusMessage = "status_message"
        case reasoningNotes = "reasoning_notes"
        case inputClips = "input_clips"
        case inputClipIDs = "input_clip_ids"
        case clipIDs = "clip_ids"
        case selectedClipIDs = "selected_clip_ids"
        case droppedClipIDs = "dropped_clip_ids"
        case clipRanges = "clip_ranges"
    }
}

struct AgentInputClip: Decodable {
    let clipID: FlexibleIdentifier
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case summary
    }
}

struct AgentClipRangePayload: Decodable {
    let clipID: FlexibleIdentifier
    let changed: Bool?
    let ranges: [AgentClipRangeEntry]

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case changed
        case ranges
    }
}

struct AgentClipRangeEntry: Decodable {
    let inSec: Double
    let outSec: Double
    let reason: String

    enum CodingKeys: String, CodingKey {
        case inSec = "in_sec"
        case outSec = "out_sec"
        case reason
    }
}

struct AgentTimelineEntry: Decodable {
    let clipID: FlexibleIdentifier
    let localKey: String?
    let inSec: Double
    let outSec: Double
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case localKey = "local_key"
        case inSec = "in_sec"
        case outSec = "out_sec"
        case rationale
    }
}

struct AgentStatusUpdateEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let node: String?
    let statusMessage: String
    let statusDetails: AgentNodePayload?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case node
        case statusMessage = "status_message"
        case statusDetails = "status_details"
    }
}

struct AgentStateSnapshotEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let state: [String: JSONValue]

    var projectID: FlexibleIdentifier? {
        if let raw = state["project_id"]?.stringValue {
            return FlexibleIdentifier(rawValue: raw)
        }
        if let raw = state["project_id"]?.intValue {
            return FlexibleIdentifier(rawValue: String(raw))
        }
        return nil
    }

    var statusMessage: String? {
        state["status_message"]?.stringValue
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case state
    }
}

struct AgentErrorEvent: Decodable {
    let sessionID: FlexibleIdentifier?
    let detail: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case detail
    }
}

struct AgentClientMessage: Encodable {
    let type: String
    let userPrompt: String?
    let prompt: String?

    static func startSession(prompt: String) -> AgentClientMessage {
        AgentClientMessage(type: "start_session", userPrompt: prompt, prompt: nil)
    }

    static func reprompt(prompt: String) -> AgentClientMessage {
        AgentClientMessage(type: "reprompt", userPrompt: nil, prompt: prompt)
    }

    static let done = AgentClientMessage(type: "done", userPrompt: nil, prompt: nil)

    enum CodingKeys: String, CodingKey {
        case type
        case userPrompt = "user_prompt"
        case prompt
    }
}

extension AgentSocketEvent {
    var logDescription: String {
        switch self {
        case .sessionStarted(let payload):
            return "session_started(session_id=\(payload.sessionID.rawValue))"
        case .sessionResumed(let payload):
            return "session_resumed(session_id=\(payload.sessionID.rawValue), iteration=\(payload.iterationCount))"
        case .sessionComplete(let payload):
            return "session_complete(session_id=\(payload.sessionID.rawValue), timeline_count=\(payload.timeline.count))"
        case .sessionClosed(let payload):
            return "session_closed(session_id=\(payload.sessionID.rawValue))"
        case .timelineUpdate(let payload):
            return "timeline_update(session_id=\(payload.sessionID.rawValue), timeline_count=\(payload.timeline.count), notes_count=\(payload.timelineNotes.count))"
        case .waitingForUser(let payload):
            return "waiting_for_user(session_id=\(payload.sessionID.rawValue))"
        case .nodeStart(let payload):
            return "node_start(node=\(payload.node))"
        case .nodeComplete(let payload):
            return "node_complete(node=\(payload.node))"
        case .statusUpdate(let payload):
            return "status_update(session_id=\(payload.sessionID.rawValue), node=\(payload.node ?? "nil"))"
        case .stateSnapshot(let payload):
            return "state_snapshot(session_id=\(payload.sessionID.rawValue), keys=\(payload.state.keys.sorted().joined(separator: ",")))"
        case .error(let payload):
            return "error(session_id=\(payload.sessionID?.rawValue ?? "nil"))"
        case .unknown(let type):
            return "unknown(type=\(type))"
        }
    }
}

extension AgentNodePayload {
    var containsInputClipReferences: Bool {
        inputClips != nil || inputClipIDs != nil
    }

    var containsCompletionDetails: Bool {
        clipIDs != nil || selectedClipIDs != nil || droppedClipIDs != nil || clipRanges != nil
    }
}
