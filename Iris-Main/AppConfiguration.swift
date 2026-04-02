import Foundation

enum AppConfiguration {
    static let ingestEndpoint = URL(string: "http://127.0.0.1:8000/sessions/upload")!
    static let uploadFieldName = "videos"
    static let uploadLocalKeyFieldName = "local_key"
    static let simulateImportProcessing = false
    static let semanticMobileCLIPEncoderURI = "s2:///Users/abdur-rahmanrana/Documents/Magnolia Creative/Dev/Models/mobileclip"

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
