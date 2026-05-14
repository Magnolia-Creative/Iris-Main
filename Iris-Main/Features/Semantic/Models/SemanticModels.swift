import Foundation

enum SemanticSearchResultSource: String, Equatable {
    case visual
    case audio
}

struct SemanticImportedVideo: Identifiable, Equatable {
    let localKey: String
    let fileURL: URL
    let displayName: String
    let durationSeconds: Double
    let transcriptSentences: [MediaTranscriptSentence]
    /// Backend `local_key` from clip ingest, when known (see `MediaSpec.clipUploadLocalKey`).
    let uploadLocalKey: String?
    let visualContentSignature: String
    let transcriptContentSignature: String
    let contentSignature: String

    var id: String { localKey }
}

struct SemanticMatchRange: Identifiable, Equatable {
    let id = UUID()
    let videoID: String
    let videoName: String
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let confidence: Double
    let source: SemanticSearchResultSource
    let matchText: String?
}

struct SemanticSearchModel {
    var videos: [SemanticImportedVideo] = []
    var isImportingVideos = false
    var isBuildingIndex = false
    var isSearching = false
    var queryText = ""
    var statusMessage = "Import videos to build a chunk index."
    var importErrorMessage: String?
    var searchErrorMessage: String?
    var indexedFrameCount = 0
    var visualResults: [SemanticMatchRange] = []
    var audioResults: [SemanticMatchRange] = []
    /// Backend Iris project id for cloud import-panel search (from local `Project.backendProjectId`).
    var cloudBackendProjectId: String?

    var results: [SemanticMatchRange] {
        visualResults + audioResults
    }

    var hasVideos: Bool {
        !videos.isEmpty
    }

    var hasTranscriptData: Bool {
        videos.contains { !$0.transcriptSentences.isEmpty }
    }

    var trimmedQuery: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canBuildIndex: Bool {
        hasVideos && !isImportingVideos && !isBuildingIndex
    }

    /// When local MobileCLIP indexing is off, import search uses the backend if `cloudBackendProjectId` is set.
    private var usesCloudImportSearch: Bool {
        !AppConfiguration.enablesLocalSemanticIndexing
    }

    var canSearch: Bool {
        !trimmedQuery.isEmpty
            && !isImportingVideos
            && !isBuildingIndex
            && !isSearching
            && (usesCloudImportSearch
                ? (!videos.isEmpty && cloudBackendProjectId != nil)
                : (indexedFrameCount > 0 || hasTranscriptData))
    }
}

struct ImportedSemanticVideo: Equatable {
    let localURL: URL
    let displayName: String
    let localKey: String
}
