internal import Combine
import Foundation

private enum SemanticSearchResultSelectionMode {
    case topRanges(limit: Int)
    case bestClip

    func select(from candidates: [SemanticRangeCandidate]) -> [SemanticRangeCandidate] {
        let sortedCandidates = candidates.sorted { $0.confidence > $1.confidence }
        switch self {
        case .topRanges(let limit):
            return Array(sortedCandidates.prefix(limit))
        case .bestClip:
            guard let bestMatch = sortedCandidates.first else { return [] }
            return sortedCandidates.filter { $0.videoID == bestMatch.videoID }
        }
    }
}

@MainActor
final class SemanticSearchViewModel: ObservableObject {
    static let shared = SemanticSearchViewModel(selectionMode: .bestClip)

    @Published private(set) var model = SemanticSearchModel()

    private let selectionMode: SemanticSearchResultSelectionMode
    private var liveSearchTask: Task<Void, Never>?
    private var importSearchTimelineID: String?

    init() {
        selectionMode = .topRanges(limit: 3)
    }

    private init(selectionMode: SemanticSearchResultSelectionMode) {
        self.selectionMode = selectionMode
    }

    func setImportSearchTimelineId(_ timelineID: String?) {
        importSearchTimelineID = timelineID
        refreshCloudBackendProjectIDFromDatabase()
    }

    func queueImportedMediaSync(_ media: [Media]) {
        let searchableMedia = Media.deduplicatedForImportPresentation(media)
            .filter { $0.kind == .video }
        let nextVideos = searchableMedia.map { item in
            SemanticImportedVideo(
                localKey: item.mediaId,
                displayName: item.spec.clipUploadLocalKey ?? item.mediaId,
                uploadLocalKey: item.spec.clipUploadLocalKey
            )
        }

        guard nextVideos != model.videos else { return }
        model.videos = nextVideos
        model.visualResults = []
        model.audioResults = []
        refreshCloudBackendProjectIDFromDatabase()
        model.statusMessage = readyStatusMessage()
        if !model.trimmedQuery.isEmpty {
            queueLiveSearch()
        }
    }

    func updateQuery(_ query: String) {
        model.queryText = query
    }

    func clearSearch() {
        liveSearchTask?.cancel()
        liveSearchTask = nil
        model.queryText = ""
        model.visualResults = []
        model.audioResults = []
        model.searchErrorMessage = nil
        model.statusMessage = readyStatusMessage()
    }

    func queueLiveSearch() {
        liveSearchTask?.cancel()
        model.isSearching = false
        model.searchErrorMessage = nil

        guard !model.trimmedQuery.isEmpty else {
            model.visualResults = []
            model.audioResults = []
            model.statusMessage = readyStatusMessage()
            return
        }

        liveSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.runSearch()
        }
    }

    func runSearch() async {
        refreshCloudBackendProjectIDFromDatabase()
        guard model.canSearch, let projectID = model.cloudBackendProjectId else {
            model.statusMessage = readyStatusMessage()
            return
        }

        let query = model.trimmedQuery
        let requestedVideoKeys = model.videos.map(\.localKey)
        model.isSearching = true
        model.searchErrorMessage = nil
        model.visualResults = []
        model.audioResults = []
        model.statusMessage = "Searching clips..."

        do {
            let service = ProjectClipSearchService()
            async let semanticMatches = service.semanticSearch(
                projectID: projectID,
                query: query,
                limit: 3
            )
            async let transcriptMatches = service.transcriptSearch(
                projectID: projectID,
                query: query,
                limit: 3
            )

            let semanticRows = try await semanticMatches
            let transcriptRows = try await transcriptMatches
            var visualCandidates: [SemanticRangeCandidate] = []
            var audioCandidates: [SemanticRangeCandidate] = []

            for row in semanticRows {
                guard let candidate = mapProjectSearchMatch(row) else { continue }
                if candidate.source == .audio {
                    audioCandidates.append(candidate)
                } else {
                    visualCandidates.append(candidate)
                }
            }
            audioCandidates.append(contentsOf: transcriptRows.compactMap(mapProjectSearchMatch))

            guard query == model.trimmedQuery,
                  requestedVideoKeys == model.videos.map(\.localKey) else {
                model.isSearching = false
                return
            }

            model.visualResults = selectionMode.select(from: visualCandidates).map(makeMatchRange)
            model.audioResults = selectionMode.select(from: audioCandidates).map(makeMatchRange)
            let resultCount = model.results.count
            model.statusMessage = resultCount == 0
                ? "No matching ranges found."
                : "Found \(resultCount) likely range(s)."
        } catch is CancellationError {
            model.isSearching = false
            return
        } catch {
            model.searchErrorMessage = error.localizedDescription
            model.statusMessage = "Search failed."
        }

        model.isSearching = false
    }

    private func mapProjectSearchMatch(
        _ match: ProjectClipSearchService.Match
    ) -> SemanticRangeCandidate? {
        guard let video = model.videos.first(where: { video in
            let backendKey = match.localKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !backendKey.isEmpty else { return false }
            return video.uploadLocalKey?.caseInsensitiveCompare(backendKey) == .orderedSame
                || video.localKey.caseInsensitiveCompare(backendKey) == .orderedSame
        }) else {
            return nil
        }

        let source: SemanticSearchResultSource = (match.source ?? "").lowercased().hasPrefix("audio")
            ? .audio
            : .visual
        return SemanticRangeCandidate(
            videoID: video.localKey,
            videoName: match.fileName ?? video.displayName,
            startTimeSeconds: match.startTimeSeconds,
            endTimeSeconds: match.endTimeSeconds,
            confidence: match.confidence,
            source: source,
            matchText: match.matchText
        )
    }

    private func makeMatchRange(_ candidate: SemanticRangeCandidate) -> SemanticMatchRange {
        SemanticMatchRange(
            videoID: candidate.videoID,
            videoName: candidate.videoName,
            startTimeSeconds: candidate.startTimeSeconds,
            endTimeSeconds: candidate.endTimeSeconds,
            confidence: candidate.confidence,
            source: candidate.source,
            matchText: candidate.matchText
        )
    }

    private func refreshCloudBackendProjectIDFromDatabase() {
        guard let timelineID = importSearchTimelineID,
              let timeline = try? DatabaseManager.shared.get(Timeline.self, id: timelineID, keyColumn: "timeline_id"),
              let project = try? DatabaseManager.shared.get(Project.self, id: timeline.projectId, keyColumn: "project_id"),
              let projectID = project.backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectID.isEmpty else {
            model.cloudBackendProjectId = nil
            return
        }
        model.cloudBackendProjectId = projectID
    }

    private func readyStatusMessage() -> String {
        if model.videos.isEmpty {
            return "Import videos to search them."
        }
        if model.cloudBackendProjectId == nil {
            return "Upload clips to your Iris project to search them in the cloud."
        }
        return "Search ready. Start typing to search clips."
    }
}
