import Foundation

enum AppConfiguration {
    #if DEBUG
    /// Clerk publishable key (test instance: ethical-adder-19).
    static let clerkPublishableKey = "pk_test_ZXRoaWNhbC1hZGRlci0xOS5jbGVyay5hY2NvdW50cy5kZXYk"
    #else
    /// Clerk publishable key (production instance: clerk.irisvideo.app).
    static let clerkPublishableKey = "pk_live_Y2xlcmsuaXJpc3ZpZGVvLmFwcCQ"
    #endif

    #if DEBUG
    static let backendBaseURL = URL(string: "http://127.0.0.1:8000")!
    #else
    static let backendBaseURL = URL(string: "https://api.irisvideo.app")!
    #endif
    static let projectsCreateEndpoint = backendBaseURL.appending(path: "projects")
    static let transcriptSentencesEndpoint = backendBaseURL
        .appending(path: "agent")
        .appending(path: "transcriptions")
        .appending(path: "sentences")
    static let agentRunsEndpoint = backendBaseURL
        .appending(path: "agent")
        .appending(path: "runs")
    static let uploadFieldName = "videos"
    static let uploadLocalKeyFieldName = "local_key"
    static let visualFramesFieldName = "visual_frames"
    static let visualFrameManifestFieldName = "visual_frame_manifest"
    static let simulateImportProcessing = false
    /// When false, skips MobileCLIP prewarm and local chunk index rebuilds; import-panel search uses cloud project APIs instead.
    static let enablesLocalSemanticIndexing = false

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

    static func projectSourcesEndpoint(projectID: String) -> URL {
        backendBaseURL
            .appending(path: "projects")
            .appending(path: projectID)
            .appending(path: "sources")
    }

    static func projectSourceTranscriptEndpoint(projectID: String, localKey: String) -> URL {
        backendBaseURL
            .appending(path: "projects")
            .appending(path: projectID)
            .appending(path: "sources")
            .appending(path: localKey)
            .appending(path: "transcript")
    }

    static func projectSourceSearchEndpoint(projectID: String) -> URL {
        projectSourcesEndpoint(projectID: projectID).appending(path: "search")
    }

    static func agentRunStatusEndpoint(runID: String) -> URL {
        agentRunsEndpoint.appending(path: runID)
    }

    static func projectClipCancelEndpoint(projectID: String, localKey: String) -> URL {
        backendBaseURL
            .appending(path: "projects")
            .appending(path: projectID)
            .appending(path: "sources")
            .appending(path: localKey)
    }

    static func agentWebSocketEndpoint(sessionID: String, basedOn baseURL: URL = backendBaseURL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/agent/runs/\(sessionID)/stream"
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
        components.path = "/agent/voice/transcribe"
        components.queryItems = [URLQueryItem(name: "model", value: model)]
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
        components.path = "/agent/voice/intent"
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        components.fragment = nil
        return components.url
    }
}
