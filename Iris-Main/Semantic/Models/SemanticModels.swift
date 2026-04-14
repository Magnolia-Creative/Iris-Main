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
        hasVideos && !isImportingVideos && !isBuildingIndex && !isSearching
    }

    var canSearch: Bool {
        !trimmedQuery.isEmpty
            && (indexedFrameCount > 0 || hasTranscriptData)
            && !isImportingVideos
            && !isBuildingIndex
            && !isSearching
    }
}

struct ImportedSemanticVideo: Equatable {
    let localURL: URL
    let displayName: String
    let localKey: String
}
