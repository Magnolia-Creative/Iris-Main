import Foundation

enum SemanticSearchResultSource: String, Equatable {
    case visual
    case audio
}

struct SemanticImportedVideo: Identifiable, Equatable {
    let localKey: String
    let displayName: String
    /// Backend `local_key` from clip ingest, when known (see `MediaSpec.clipUploadLocalKey`).
    let uploadLocalKey: String?

    var id: String { localKey }
}

struct SemanticRangeCandidate {
    let videoID: String
    let videoName: String
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let confidence: Double
    let source: SemanticSearchResultSource
    let matchText: String?
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
    var isSearching = false
    var queryText = ""
    var statusMessage = "Import videos to search them."
    var searchErrorMessage: String?
    var visualResults: [SemanticMatchRange] = []
    var audioResults: [SemanticMatchRange] = []
    /// Backend Iris project id for cloud import-panel search (from local `Project.backendProjectId`).
    var cloudBackendProjectId: String?

    var results: [SemanticMatchRange] {
        visualResults + audioResults
    }

    var trimmedQuery: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSearch: Bool {
        !trimmedQuery.isEmpty
            && !isSearching
            && !videos.isEmpty
            && cloudBackendProjectId != nil
    }
}
