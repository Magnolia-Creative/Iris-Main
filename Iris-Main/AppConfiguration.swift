import Foundation

enum AppConfiguration {
    static let backendBaseURL = URL(string: "http://127.0.0.1:8000")!
    static let ingestEndpoint = backendBaseURL.appending(path: "sessions/upload")
    static let agentSessionEndpoint = backendBaseURL.appending(path: "projects/agent-sessions")
    static let uploadFieldName = "videos"
    static let uploadLocalKeyFieldName = "local_key"
    static let simulateImportProcessing = false
    nonisolated static let semanticMobileCLIPEncoderURI = "s2:///Users/abdur-rahmanrana/Documents/Magnolia Creative/Dev/Models/mobileclip"

    static func projectClipProcessingEndpoint(projectID: String) -> URL {
        backendBaseURL
            .appending(path: "projects")
            .appending(path: projectID)
            .appending(path: "clips")
            .appending(path: "process")
    }

    static func projectClipCancelEndpoint(projectID: String, localKey: String, sessionID: String) -> URL {
        var components = URLComponents(
            url: backendBaseURL
                .appending(path: "projects")
                .appending(path: projectID)
                .appending(path: "clips")
                .appending(path: localKey),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "session_id", value: sessionID)]
        return components.url ?? backendBaseURL
    }

    static func agentWebSocketEndpoint(sessionID: String, basedOn baseURL: URL = ingestEndpoint) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/sessions/\(sessionID)"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
