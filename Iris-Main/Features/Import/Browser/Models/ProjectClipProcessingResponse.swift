import Foundation

struct RemoteImportSessionResponse: Decodable {
    let sessionID: FlexibleIdentifier
    let sessionName: String
    let sessionStatus: String
    let projectID: FlexibleIdentifier
    let projectName: String
    let uploadedCount: Int
    let pendingClipCount: Int?
    let settledClipCount: Int?
    let readyForWebSocket: Bool?
    let videos: [IngestVideoResponse]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case sessionStatus = "session_status"
        case projectID = "project_id"
        case projectName = "project_name"
        case uploadedCount = "uploaded_count"
        case pendingClipCount = "pending_clip_count"
        case settledClipCount = "settled_clip_count"
        case readyForWebSocket = "ready_for_websocket"
        case videos
    }
}

struct CancelClipResponse: Decodable {
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier
    let localKey: String
    let taskCancelled: Bool
    let deletedClipID: FlexibleIdentifier?
    let sessionStatus: String
    let readyForWebSocket: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
        case localKey = "local_key"
        case taskCancelled = "task_cancelled"
        case deletedClipID = "deleted_clip_id"
        case sessionStatus = "session_status"
        case readyForWebSocket = "ready_for_websocket"
    }
}
