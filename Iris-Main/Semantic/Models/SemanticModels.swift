import Foundation

struct SemanticImportedVideo: Identifiable, Equatable {
    let localKey: String
    let fileURL: URL
    let displayName: String
    let durationSeconds: Double

    var id: String { localKey }
}

struct SemanticMatchRange: Identifiable, Equatable {
    let id = UUID()
    let videoID: String
    let videoName: String
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let confidence: Double
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
    var results: [SemanticMatchRange] = []

    var hasVideos: Bool {
        !videos.isEmpty
    }

    var trimmedQuery: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canBuildIndex: Bool {
        hasVideos && !isImportingVideos && !isBuildingIndex && !isSearching
    }

    var canSearch: Bool {
        !trimmedQuery.isEmpty && indexedFrameCount > 0 && !isImportingVideos && !isBuildingIndex && !isSearching
    }
}

struct ImportedSemanticVideo: Equatable {
    let localURL: URL
    let displayName: String
    let localKey: String
}
