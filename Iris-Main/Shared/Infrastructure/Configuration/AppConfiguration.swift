import Foundation

enum AppConfiguration {
    static let backendBaseURL = URL(string: "http://127.0.0.1:8000")!
    static let ingestEndpoint = backendBaseURL.appending(path: "sessions/upload")
    static let transcriptSentencesEndpoint = backendBaseURL.appending(path: "transcriptions/sentences")
    static let agentSessionEndpoint = backendBaseURL.appending(path: "projects/agent-sessions")
    static let intentRunsEndpoint = backendBaseURL.appending(path: "intent-runs")
    static let uploadFieldName = "videos"
    static let uploadLocalKeyFieldName = "local_key"
    static let simulateImportProcessing = false

    nonisolated static var semanticMobileCLIPEncoderURI: String {
        guard let modelsDirectoryURL = semanticMobileCLIPModelsDirectoryURL else {
            return ""
        }

        var components = URLComponents()
        components.scheme = "s2"
        components.path = modelsDirectoryURL.path
        return components.string ?? ""
    }

    nonisolated private static var semanticMobileCLIPModelsDirectoryURL: URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let fileManager = FileManager.default
        let candidateDirectories = [
            resourceURL.appending(path: "MobileCLIP", directoryHint: .isDirectory),
            resourceURL.appending(path: "Resources/MobileCLIP", directoryHint: .isDirectory),
            resourceURL
        ]

        return candidateDirectories.first {
            containsBundledMobileCLIPModels(at: $0, fileManager: fileManager)
        }
    }

    private static func containsBundledMobileCLIPModels(at directoryURL: URL, fileManager: FileManager) -> Bool {
        let imageModelURL = directoryURL.appending(path: "mobileclip_s2_image.mlmodelc", directoryHint: .isDirectory)
        let textModelURL = directoryURL.appending(path: "mobileclip_s2_text.mlmodelc", directoryHint: .isDirectory)

        return directoryExists(at: imageModelURL, fileManager: fileManager)
            && directoryExists(at: textModelURL, fileManager: fileManager)
    }

    private static func directoryExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func projectClipProcessingEndpoint(projectID: String) -> URL {
        backendBaseURL
            .appending(path: "projects")
            .appending(path: projectID)
            .appending(path: "clips")
            .appending(path: "process")
    }

    static func sessionStatusEndpoint(sessionID: String) -> URL {
        backendBaseURL
            .appending(path: "sessions")
            .appending(path: sessionID)
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

    /// OpenAI Realtime transcription proxy (`stream_transcription`); client sends PCM16 mono @ 24 kHz as base64 JSON frames.
    static func transcriptionWebSocketEndpoint(
        model: String = "gpt-realtime-whisper",
        basedOn baseURL: URL = backendBaseURL
    ) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/transcribe"
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        components.fragment = nil
        return components.url
    }

    static func intentRunWebSocketEndpoint(runID: String, basedOn baseURL: URL = backendBaseURL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/intent-runs/\(runID)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func voiceIntentWebSocketEndpoint(
        model: String = "gpt-realtime-whisper",
        basedOn baseURL: URL = backendBaseURL
    ) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/intent/voice"
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        components.fragment = nil
        return components.url
    }
}
