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

private enum TranscriptSearchScorer {
    static func candidates(
        for query: String,
        in videos: [SemanticImportedVideo]
    ) -> [SemanticRangeCandidate] {
        let normalizedQuery = normalizedText(query)
        let queryTerms = Set(normalizedQuery.split(separator: " ").map(String.init))
        guard !normalizedQuery.isEmpty, !queryTerms.isEmpty else { return [] }

        let transcriptVideoCount = videos.filter { !$0.transcriptSentences.isEmpty }.count
        let transcriptSentenceCount = videos.reduce(into: 0) { partialResult, video in
            partialResult += video.transcriptSentences.count
        }
        print(
            "[SemanticAudioSearch] scoring query=\"\(query)\" normalized=\"\(normalizedQuery)\" " +
            "videos=\(videos.count) transcriptVideos=\(transcriptVideoCount) transcriptSentences=\(transcriptSentenceCount)"
        )

        var matches: [SemanticRangeCandidate] = []
        for video in videos {
            if video.transcriptSentences.isEmpty {
                print("[SemanticAudioSearch] video has no transcript videoID=\(video.id) name=\(video.displayName)")
            }
            for sentence in video.transcriptSentences {
                let normalizedSentence = normalizedText(sentence.text)
                guard !normalizedSentence.isEmpty else { continue }

                let sentenceTerms = Set(normalizedSentence.split(separator: " ").map(String.init))
                let sharedTermCount = queryTerms.intersection(sentenceTerms).count
                guard sharedTermCount > 0 else { continue }

                var score = Double(sharedTermCount) / Double(max(queryTerms.count, 1))
                if normalizedSentence.contains(normalizedQuery) {
                    score += 1.0
                } else if queryTerms.isSubset(of: sentenceTerms) {
                    score += 0.55
                }
                if let confidence = sentence.confidence {
                    score += min(max(confidence, 0), 1) * 0.1
                }

                matches.append(
                    SemanticRangeCandidate(
                        videoID: video.id,
                        videoName: video.displayName,
                        startTimeSeconds: sentence.startTimeSeconds,
                        endTimeSeconds: sentence.endTimeSeconds,
                        confidence: score,
                        source: .audio,
                        matchText: sentence.text
                    )
                )
            }
        }

        print("[SemanticAudioSearch] produced audio candidates count=\(matches.count) query=\"\(query)\"")
        return matches.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.startTimeSeconds < rhs.startTimeSeconds
            }
            return lhs.confidence > rhs.confidence
        }
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private actor SemanticSearchCoordinator {
    private let frameSampler: any VideoFrameSampling
    private let pipeline: SemanticSearchPipeline
    private let thumbnailService: ThumbnailService

    init(
        frameSampler: any VideoFrameSampling = VideoFrameSampler(),
        pipeline: SemanticSearchPipeline = SemanticSearchPipeline(),
        thumbnailService: ThumbnailService = .shared
    ) {
        self.frameSampler = frameSampler
        self.pipeline = pipeline
        self.thumbnailService = thumbnailService
    }

    func resolveImportedVideos(_ importedVideos: [ImportedSemanticVideo]) async throws -> [SemanticImportedVideo] {
        var resolvedVideos: [SemanticImportedVideo] = []
        resolvedVideos.reserveCapacity(importedVideos.count)

        for imported in importedVideos {
            try Task.checkCancellation()
            let duration = try await frameSampler.loadDurationSeconds(videoURL: imported.localURL)
            resolvedVideos.append(
                SemanticImportedVideo(
                    localKey: imported.localKey,
                    fileURL: imported.localURL,
                    displayName: imported.displayName,
                    durationSeconds: duration,
                    transcriptSentences: [],
                    uploadLocalKey: nil,
                    visualContentSignature: imported.localKey,
                    transcriptContentSignature: "",
                    contentSignature: imported.localKey
                )
            )
        }

        return resolvedVideos
    }

    func resolveSearchableVideos(from media: [Media]) async throws -> [SemanticImportedVideo] {
        let candidateMedia = Media.deduplicatedForImportPresentation(media)
            .filter { $0.kind == .video }

        var importedVideos: [SemanticImportedVideo] = []
        importedVideos.reserveCapacity(candidateMedia.count)

        for item in candidateMedia {
            try Task.checkCancellation()
            guard let fileURL = try await thumbnailService.loadVideoURL(for: item.assetRefId) else { continue }

            let duration: Double
            if let existingDuration = item.spec.duration {
                duration = existingDuration
            } else {
                duration = (try? await frameSampler.loadDurationSeconds(videoURL: fileURL)) ?? 0
            }

            importedVideos.append(
                SemanticImportedVideo(
                    localKey: item.mediaId,
                    fileURL: fileURL,
                    displayName: fileURL.lastPathComponent,
                    durationSeconds: duration,
                    transcriptSentences: item.spec.transcriptSentences ?? [],
                    uploadLocalKey: item.spec.clipUploadLocalKey,
                    visualContentSignature: [
                        item.semanticSearchVisualSignature,
                        fileURL.path,
                        String(format: "%.3f", duration)
                    ].joined(separator: "::"),
                    transcriptContentSignature: item.semanticSearchTranscriptSignature,
                    contentSignature: item.semanticSearchContentSignature
                )
            )
        }

        return importedVideos
    }

    func reset() {
        pipeline.reset()
    }

    func buildIndex(
        videos: [SemanticImportedVideo],
        invalidatedVideoIDs: Set<String>,
        onProgress: @escaping @Sendable (String) async -> Void,
        options: SemanticIndexBuildOptions
    ) async throws -> SemanticVisualIndexState {
        try await pipeline.buildChunkIndex(
            videos: videos,
            invalidatedVideoIDs: invalidatedVideoIDs,
            onProgress: onProgress,
            options: options
        )
    }

    func search(query: String, videos: [SemanticImportedVideo]) async throws -> [SemanticRangeCandidate] {
        try await pipeline.search(query: query, videos: videos)
    }

    func prewarmEmbeddingServices() async {
        await pipeline.prewarmEmbeddingServices()
    }

    func indexedVideoSignatures() -> [String: String] {
        pipeline.indexedVideoSignatures
    }
}

@MainActor
final class SemanticSearchViewModel: ObservableObject {
    static let shared = SemanticSearchViewModel(resultSelectionMode: .bestClip)

    @Published private(set) var model = SemanticSearchModel()

    private struct PendingSyncRequest {
        let id: Int
        let media: [Media]
        let autoBuildIndex: Bool
    }

    private struct PendingBuildRequest {
        let id: Int
        let videos: [SemanticImportedVideo]
        let invalidatedVideoIDs: Set<String>
        let options: SemanticIndexBuildOptions
        let visualSignature: String
    }

    private let coordinator: SemanticSearchCoordinator
    private let resultSelectionMode: SemanticSearchResultSelectionMode
    private var liveSearchTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var buildTask: Task<Void, Never>?
    private var pendingSyncRequest: PendingSyncRequest?
    private var pendingBuildRequest: PendingBuildRequest?
    private var syncRequestCounter = 0
    private var buildRequestCounter = 0
    private var completedSyncRequestID = 0
    private var completedBuildRequestID = 0
    private var syncWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var buildWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var indexedVisualSignature: String?
    private var indexedVideoSignatures: [String: String] = [:]
    private var hasQueuedEmbeddingPrewarm = false
    private var importSearchTimelineId: String?

    init(
        frameSampler: (any VideoFrameSampling)? = nil,
        pipeline: SemanticSearchPipeline? = nil,
        thumbnailService: ThumbnailService? = nil
    ) {
        self.resultSelectionMode = .topRanges(limit: SemanticSearchConstants.resultsLimit)
        self.coordinator = SemanticSearchCoordinator(
            frameSampler: frameSampler ?? VideoFrameSampler(),
            pipeline: pipeline ?? SemanticSearchPipeline(),
            thumbnailService: thumbnailService ?? .shared
        )
    }

    private init(
        frameSampler: (any VideoFrameSampling)? = nil,
        pipeline: SemanticSearchPipeline? = nil,
        thumbnailService: ThumbnailService? = nil,
        resultSelectionMode: SemanticSearchResultSelectionMode
    ) {
        self.coordinator = SemanticSearchCoordinator(
            frameSampler: frameSampler ?? VideoFrameSampler(),
            pipeline: pipeline ?? SemanticSearchPipeline(),
            thumbnailService: thumbnailService ?? .shared
        )
        self.resultSelectionMode = resultSelectionMode
    }

    func prewarmEmbeddingServicesIfNeeded() {
        guard AppConfiguration.enablesLocalSemanticIndexing else { return }
        guard !hasQueuedEmbeddingPrewarm else { return }
        hasQueuedEmbeddingPrewarm = true
        print("[SemanticIndex] queueing embedding prewarm from editor open")
        Task(priority: .background) { [coordinator] in
            await coordinator.prewarmEmbeddingServices()
        }
    }

    func beginVideoImport() {
        model.isImportingVideos = true
        model.importErrorMessage = nil
    }

    func importSelection(from importedVideos: [ImportedSemanticVideo]) {
        guard !importedVideos.isEmpty else {
            liveSearchTask?.cancel()
            syncTask?.cancel()
            buildTask?.cancel()
            syncTask = nil
            buildTask = nil
            pendingSyncRequest = nil
            pendingBuildRequest = nil
            syncWaiters.removeAll()
            buildWaiters.removeAll()
            model.videos = []
            model.visualResults = []
            model.audioResults = []
            model.indexedFrameCount = 0
            model.statusMessage = "Import videos to build a chunk index."
            model.isImportingVideos = false
            model.importErrorMessage = nil
            indexedVisualSignature = nil
            indexedVideoSignatures = [:]
            Task(priority: .utility) { [coordinator] in
                await coordinator.reset()
            }
            return
        }

        Task(priority: .utility) { [weak self, coordinator] in
            guard let self else { return }
            do {
                let nextVideos = try await coordinator.resolveImportedVideos(importedVideos)
                guard !Task.isCancelled else { return }
                await coordinator.reset()
                buildTask?.cancel()
                buildTask = nil
                pendingBuildRequest = nil
                buildWaiters.removeAll()

                model.videos = nextVideos
                model.visualResults = []
                model.audioResults = []
                model.indexedFrameCount = 0
                model.statusMessage = "\(nextVideos.count) video(s) ready. Build index to search."
                model.importErrorMessage = nil
                model.searchErrorMessage = nil
                model.isImportingVideos = false
                indexedVisualSignature = nil
                indexedVideoSignatures = [:]
            } catch is CancellationError {
                return
            } catch {
                await coordinator.reset()
                buildTask?.cancel()
                buildTask = nil
                pendingBuildRequest = nil
                buildWaiters.removeAll()
                model.videos = []
                model.visualResults = []
                model.audioResults = []
                model.indexedFrameCount = 0
                model.importErrorMessage = error.localizedDescription
                model.statusMessage = "Could not load imported videos."
                model.isImportingVideos = false
                indexedVisualSignature = nil
                indexedVideoSignatures = [:]
            }
        }
    }

    func updateQuery(_ query: String) {
        model.queryText = query
    }

    func clearSearch() {
        liveSearchTask?.cancel()
        model.queryText = ""
        model.visualResults = []
        model.audioResults = []
        model.searchErrorMessage = nil
        model.statusMessage = readyStatusMessage()
    }

    func setImportSearchTimelineId(_ timelineId: String?) {
        importSearchTimelineId = timelineId
        refreshCloudBackendProjectIdFromDatabase()
    }

    func queueImportedMediaSync(_ media: [Media], autoBuildIndex: Bool) {
        let requestID = enqueueImportedMediaSyncRequest(media, autoBuildIndex: autoBuildIndex)
        let queuedVideoCount = Media.deduplicatedForImportPresentation(media).filter { $0.kind == .video }.count
        EditorDebugTrace.log(
            "SemanticSearchViewModel",
            "queue imported media sync requestID=\(requestID) videoCount=\(queuedVideoCount) autoBuildIndex=\(autoBuildIndex)"
        )
    }

    func syncImportedMediaAndWait(_ media: [Media], autoBuildIndex: Bool) async -> Set<String> {
        let requestID = enqueueImportedMediaSyncRequest(media, autoBuildIndex: autoBuildIndex)
        await waitForSyncRequest(id: requestID)
        return Set(indexedVideoSignatures.keys)
    }

    func syncImportedMedia(_ media: [Media], autoBuildIndex: Bool) async {
        let syncStart = EditorDebugTrace.mark()
        let candidateMedia = Media.deduplicatedForImportPresentation(media)
            .filter { $0.kind == .video }
        let nextContentSignatures = candidateMedia.map(\.semanticSearchContentSignature)
        let currentContentSignatures = model.videos.map(\.contentSignature)
        let previousVideosByLocalKey = Dictionary(uniqueKeysWithValues: model.videos.map { ($0.localKey, $0) })

        EditorDebugTrace.log(
            "SemanticSearchViewModel",
            "sync start candidateVideos=\(candidateMedia.count) autoBuildIndex=\(autoBuildIndex)"
        )

        guard nextContentSignatures != currentContentSignatures else {
            EditorDebugTrace.log(
                "SemanticSearchViewModel",
                "sync skipped unchangedVideos count=\(candidateMedia.count) \(EditorDebugTrace.elapsedMessage(since: syncStart))"
            )
            if autoBuildIndex {
                await buildIndexIfNeeded(options: .backgroundImport, invalidatedVideoIDs: [])
                if !model.trimmedQuery.isEmpty {
                    await runSearch()
                }
            }
            refreshCloudBackendProjectIdFromDatabase()
            return
        }

        let importedVideos: [SemanticImportedVideo]
        do {
            importedVideos = try await coordinator.resolveSearchableVideos(from: candidateMedia)
        } catch is CancellationError {
            return
        } catch {
            model.videos = []
            model.visualResults = []
            model.audioResults = []
            model.searchErrorMessage = error.localizedDescription
            model.importErrorMessage = error.localizedDescription
            model.indexedFrameCount = 0
            indexedVisualSignature = nil
            indexedVideoSignatures = [:]
            model.statusMessage = "Could not prepare videos for semantic search."
            await coordinator.reset()
            return
        }

        let invalidatedVideoIDs = Set(importedVideos.compactMap { video -> String? in
            guard let previousVideo = previousVideosByLocalKey[video.localKey] else { return video.localKey }
            return previousVideo.visualContentSignature == video.visualContentSignature ? nil : video.localKey
        })
        let nextVisualSignature = visualIndexSignature(for: importedVideos)

        liveSearchTask?.cancel()
        model.videos = importedVideos
        model.visualResults = []
        model.audioResults = []
        model.searchErrorMessage = nil
        model.importErrorMessage = nil

        if importedVideos.isEmpty {
            model.statusMessage = "Import videos to search them semantically."
            indexedVisualSignature = nil
            indexedVideoSignatures = [:]
            model.indexedFrameCount = 0
            await coordinator.reset()
            EditorDebugTrace.log(
                "SemanticSearchViewModel",
                "sync completed with no imported videos \(EditorDebugTrace.elapsedMessage(since: syncStart))"
            )
            refreshCloudBackendProjectIdFromDatabase()
            return
        }

        print(
            "[SemanticIndex] visual signature updated next=\(nextVisualSignature) invalidatedVideoIDs=\(invalidatedVideoIDs.sorted())"
        )

        model.statusMessage = autoBuildIndex
            ? "Preparing search data..."
            : readyStatusMessage()

        let transcriptVideoCount = importedVideos.filter { !$0.transcriptSentences.isEmpty }.count
        let transcriptSentenceCount = importedVideos.reduce(into: 0) { partialResult, video in
            partialResult += video.transcriptSentences.count
        }
        print(
            "[SemanticAudioSearch] sync prepared videos=\(importedVideos.count) transcriptVideos=\(transcriptVideoCount) " +
            "transcriptSentences=\(transcriptSentenceCount) autoBuildIndex=\(autoBuildIndex)"
        )

        if autoBuildIndex {
            await buildIndexIfNeeded(options: .backgroundImport, invalidatedVideoIDs: invalidatedVideoIDs)
            if !model.trimmedQuery.isEmpty {
                await runSearch()
            }
        }

        EditorDebugTrace.log(
            "SemanticSearchViewModel",
            "sync completed importedVideos=\(importedVideos.count) indexedFrames=\(model.indexedFrameCount) \(EditorDebugTrace.elapsedMessage(since: syncStart))"
        )
        refreshCloudBackendProjectIdFromDatabase()
    }

    func queueLiveSearch() {
        liveSearchTask?.cancel()
        model.searchErrorMessage = nil
        print(
            "[SemanticAudioSearch] queue live search query=\"\(model.queryText)\" " +
            "trimmed=\"\(model.trimmedQuery)\" indexedFrames=\(model.indexedFrameCount) hasTranscriptData=\(model.hasTranscriptData)"
        )

        guard !model.trimmedQuery.isEmpty else {
            model.visualResults = []
            model.audioResults = []
            if model.videos.isEmpty {
                model.statusMessage = "Import videos to search them semantically."
            } else {
                model.statusMessage = readyStatusMessage()
            }
            return
        }

        liveSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            if AppConfiguration.enablesLocalSemanticIndexing {
                await self.buildIndexIfNeeded(options: .interactive, invalidatedVideoIDs: [])
                guard !Task.isCancelled else { return }
            }
            await self.runSearch()
        }
    }

    func buildIndex() async {
        await buildIndexIfNeeded(options: .interactive, invalidatedVideoIDs: [])
    }

    func runSearch() async {
        guard model.canSearch else {
            print(
                "[SemanticAudioSearch] run search skipped query=\"\(model.queryText)\" " +
                "trimmedEmpty=\(model.trimmedQuery.isEmpty) indexedFrames=\(model.indexedFrameCount) " +
                "hasTranscriptData=\(model.hasTranscriptData) cloudProject=\(model.cloudBackendProjectId ?? "nil") " +
                "videos=\(model.videos.count)"
            )
            return
        }
        let query = model.trimmedQuery
        let videos = model.videos
        let requestedVideoKeys = videos.map(\.localKey)
        model.isSearching = true
        model.searchErrorMessage = nil
        model.visualResults = []
        model.audioResults = []
        model.statusMessage = "Searching clips..."
        let transcriptVideoCount = videos.filter { !$0.transcriptSentences.isEmpty }.count
        let transcriptSentenceCount = videos.reduce(into: 0) { partialResult, video in
            partialResult += video.transcriptSentences.count
        }
        print(
            "[SemanticAudioSearch] run search query=\"\(query)\" videos=\(videos.count) indexedFrames=\(model.indexedFrameCount) " +
            "transcriptVideos=\(transcriptVideoCount) transcriptSentences=\(transcriptSentenceCount)"
        )

        do {
            if !AppConfiguration.enablesLocalSemanticIndexing {
                try await performCloudImportPanelSearch(
                    query: query,
                    videos: videos,
                    requestedVideoKeys: requestedVideoKeys
                )
            } else {
                let visualCandidateRanges = model.indexedFrameCount > 0
                    ? try await coordinator.search(query: query, videos: videos)
                    : []
                let audioCandidateRanges = TranscriptSearchScorer.candidates(for: query, in: videos)
                let visualRanges = resultSelectionMode.select(from: visualCandidateRanges)
                let audioRanges = resultSelectionMode.select(from: audioCandidateRanges)
                guard query == model.trimmedQuery, requestedVideoKeys == model.videos.map(\.localKey) else {
                    model.isSearching = false
                    return
                }
                logSearchResults(visualRanges, query: query, source: .visual)
                logSearchResults(audioRanges, query: query, source: .audio)
                model.visualResults = visualRanges.map {
                    SemanticMatchRange(
                        videoID: $0.videoID,
                        videoName: $0.videoName,
                        startTimeSeconds: $0.startTimeSeconds,
                        endTimeSeconds: $0.endTimeSeconds,
                        confidence: $0.confidence,
                        source: $0.source,
                        matchText: $0.matchText
                    )
                }
                model.audioResults = audioRanges.map {
                    SemanticMatchRange(
                        videoID: $0.videoID,
                        videoName: $0.videoName,
                        startTimeSeconds: $0.startTimeSeconds,
                        endTimeSeconds: $0.endTimeSeconds,
                        confidence: $0.confidence,
                        source: $0.source,
                        matchText: $0.matchText
                    )
                }
                let totalRangeCount = model.visualResults.count + model.audioResults.count
                model.statusMessage = totalRangeCount == 0
                    ? "No matching ranges found."
                    : "Found \(totalRangeCount) likely range(s)."
                print(
                    "[SemanticAudioSearch] search complete query=\"\(query)\" visualCandidates=\(visualCandidateRanges.count) " +
                    "visualResults=\(visualRanges.count) audioCandidates=\(audioCandidateRanges.count) audioResults=\(audioRanges.count)"
                )
            }
        } catch is CancellationError {
            print("[SemanticAudioSearch] search cancelled query=\"\(query)\"")
            model.isSearching = false
            return
        } catch {
            print("[SemanticAudioSearch] search failed query=\"\(query)\" error=\(error)")
            model.searchErrorMessage = error.localizedDescription
            model.statusMessage = "Search failed."
        }

        model.isSearching = false
    }

    private func performCloudImportPanelSearch(
        query: String,
        videos: [SemanticImportedVideo],
        requestedVideoKeys: [String]
    ) async throws {
        refreshCloudBackendProjectIdFromDatabase()
        guard let projectId = model.cloudBackendProjectId else {
            throw ProjectClipProcessingError.missingProjectInformation
        }

        let limit = SemanticSearchConstants.resultsLimit
        let service = ProjectClipSearchService()
        async let semanticMatches = service.semanticSearch(projectID: projectId, query: query, limit: limit)
        async let transcriptMatches = service.transcriptSearch(projectID: projectId, query: query, limit: limit)
        let semanticRows = try await semanticMatches
        let transcriptRows = try await transcriptMatches

        var visualPool: [SemanticRangeCandidate] = []
        var audioPool: [SemanticRangeCandidate] = []
        for row in semanticRows {
            guard let candidate = mapProjectSearchMatch(row, videos: videos) else { continue }
            if candidate.source == .audio {
                audioPool.append(candidate)
            } else {
                visualPool.append(candidate)
            }
        }
        for row in transcriptRows {
            guard let candidate = mapProjectSearchMatch(row, videos: videos) else { continue }
            audioPool.append(candidate)
        }

        let visualRanges = resultSelectionMode.select(from: visualPool)
        let audioRanges = resultSelectionMode.select(from: audioPool)
        guard query == model.trimmedQuery, requestedVideoKeys == model.videos.map(\.localKey) else {
            model.isSearching = false
            return
        }
        logSearchResults(visualRanges, query: query, source: .visual)
        logSearchResults(audioRanges, query: query, source: .audio)
        model.visualResults = visualRanges.map {
            SemanticMatchRange(
                videoID: $0.videoID,
                videoName: $0.videoName,
                startTimeSeconds: $0.startTimeSeconds,
                endTimeSeconds: $0.endTimeSeconds,
                confidence: $0.confidence,
                source: $0.source,
                matchText: $0.matchText
            )
        }
        model.audioResults = audioRanges.map {
            SemanticMatchRange(
                videoID: $0.videoID,
                videoName: $0.videoName,
                startTimeSeconds: $0.startTimeSeconds,
                endTimeSeconds: $0.endTimeSeconds,
                confidence: $0.confidence,
                source: $0.source,
                matchText: $0.matchText
            )
        }
        let totalRangeCount = model.visualResults.count + model.audioResults.count
        model.statusMessage = totalRangeCount == 0
            ? "No matching ranges found."
            : "Found \(totalRangeCount) likely range(s)."
        print(
            "[SemanticCloudSearch] search complete query=\"\(query)\" semanticRows=\(semanticRows.count) " +
            "transcriptRows=\(transcriptRows.count) visualResults=\(visualRanges.count) audioResults=\(audioRanges.count)"
        )
    }

    private func mapProjectSearchMatch(
        _ match: ProjectClipSearchService.Match,
        videos: [SemanticImportedVideo]
    ) -> SemanticRangeCandidate? {
        guard let (videoID, displayName) = resolveVideoForBackendLocalKey(match.localKey, in: videos) else {
            return nil
        }
        let rawSource = (match.source ?? "").lowercased()
        let source: SemanticSearchResultSource = (rawSource == "audio") ? .audio : .visual
        return SemanticRangeCandidate(
            videoID: videoID,
            videoName: displayName,
            startTimeSeconds: match.startTimeSeconds,
            endTimeSeconds: match.endTimeSeconds,
            confidence: match.confidence,
            source: source,
            matchText: match.matchText
        )
    }

    private func resolveVideoForBackendLocalKey(
        _ backendKey: String,
        in videos: [SemanticImportedVideo]
    ) -> (String, String)? {
        if let hit = videos.first(where: { $0.uploadLocalKey == backendKey }) {
            return (hit.localKey, hit.displayName)
        }
        if let hit = videos.first(where: { $0.localKey == backendKey }) {
            return (hit.localKey, hit.displayName)
        }
        return nil
    }

    private func refreshCloudBackendProjectIdFromDatabase() {
        guard !AppConfiguration.enablesLocalSemanticIndexing else {
            model.cloudBackendProjectId = nil
            return
        }
        guard let timelineId = importSearchTimelineId,
              let timeline = try? DatabaseManager.shared.get(Timeline.self, id: timelineId, keyColumn: "timeline_id"),
              let project = try? DatabaseManager.shared.get(Project.self, id: timeline.projectId, keyColumn: "project_id"),
              let raw = project.backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            model.cloudBackendProjectId = nil
            return
        }
        model.cloudBackendProjectId = raw
    }

    private func buildIndexIfNeeded() async {
        await buildIndexIfNeeded(options: .interactive, invalidatedVideoIDs: [])
    }

    private func buildIndexIfNeeded(options: SemanticIndexBuildOptions, invalidatedVideoIDs: Set<String>) async {
        guard AppConfiguration.enablesLocalSemanticIndexing else { return }
        guard !model.videos.isEmpty else { return }
        let requestedVisualSignature = visualIndexSignature(for: model.videos)
        guard !requestedVisualSignature.isEmpty else { return }
        if indexedVisualSignature == requestedVisualSignature, model.indexedFrameCount > 0 {
            print("[SemanticIndex] Skipping rebuild; index already available signature=\(requestedVisualSignature)")
            return
        }
        let requestID = enqueueBuildRequest(
            videos: model.videos,
            invalidatedVideoIDs: invalidatedVideoIDs,
            options: options,
            visualSignature: requestedVisualSignature
        )
        await waitForBuildRequest(id: requestID)
    }

    private func enqueueImportedMediaSyncRequest(_ media: [Media], autoBuildIndex: Bool) -> Int {
        syncRequestCounter += 1
        let requestID = syncRequestCounter
        if let existingPendingSyncRequest = pendingSyncRequest {
            pendingSyncRequest = PendingSyncRequest(
                id: requestID,
                media: media,
                autoBuildIndex: existingPendingSyncRequest.autoBuildIndex || autoBuildIndex
            )
        } else {
            pendingSyncRequest = PendingSyncRequest(id: requestID, media: media, autoBuildIndex: autoBuildIndex)
        }
        startNextSyncIfNeeded()
        return requestID
    }

    private func startNextSyncIfNeeded() {
        guard syncTask == nil, let request = pendingSyncRequest else { return }
        pendingSyncRequest = nil
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSyncLoop(startingWith: request)
        }
    }

    private func performSyncLoop(startingWith initialRequest: PendingSyncRequest) async {
        var request = initialRequest

        while true {
            await syncImportedMedia(request.media, autoBuildIndex: request.autoBuildIndex)
            completedSyncRequestID = max(completedSyncRequestID, request.id)
            resumeSyncWaiters(for: request.id)

            guard let nextRequest = pendingSyncRequest else { break }
            pendingSyncRequest = nil
            request = nextRequest
        }

        syncTask = nil
        startNextSyncIfNeeded()
    }

    private func waitForSyncRequest(id: Int) async {
        if completedSyncRequestID >= id { return }
        await withCheckedContinuation { continuation in
            syncWaiters[id, default: []].append(continuation)
        }
    }

    private func resumeSyncWaiters(for completedID: Int) {
        let waiterIDs = syncWaiters.keys.filter { $0 <= completedID }.sorted()
        for waiterID in waiterIDs {
            let waiters = syncWaiters.removeValue(forKey: waiterID) ?? []
            waiters.forEach { $0.resume() }
        }
    }

    private func enqueueBuildRequest(
        videos: [SemanticImportedVideo],
        invalidatedVideoIDs: Set<String>,
        options: SemanticIndexBuildOptions,
        visualSignature: String
    ) -> Int {
        buildRequestCounter += 1
        let requestID = buildRequestCounter
        let request = PendingBuildRequest(
            id: requestID,
            videos: videos,
            invalidatedVideoIDs: invalidatedVideoIDs,
            options: options,
            visualSignature: visualSignature
        )
        if let existingPendingBuildRequest = pendingBuildRequest {
            let mergedInvalidatedVideoIDs = existingPendingBuildRequest.invalidatedVideoIDs.union(invalidatedVideoIDs)
            let preferredOptions = mergedBuildOptions(existingPendingBuildRequest.options, options)
            self.pendingBuildRequest = PendingBuildRequest(
                id: requestID,
                videos: videos,
                invalidatedVideoIDs: mergedInvalidatedVideoIDs,
                options: preferredOptions,
                visualSignature: visualSignature
            )
        } else {
            pendingBuildRequest = request
        }
        startNextBuildIfNeeded()
        return requestID
    }

    private func startNextBuildIfNeeded() {
        guard buildTask == nil, let request = pendingBuildRequest else { return }
        pendingBuildRequest = nil
        buildTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performBuildLoop(startingWith: request)
        }
    }

    private func performBuildLoop(startingWith initialRequest: PendingBuildRequest) async {
        var request = initialRequest

        while true {
            await executeBuild(request)
            completedBuildRequestID = max(completedBuildRequestID, request.id)
            resumeBuildWaiters(for: request.id)

            guard let nextRequest = pendingBuildRequest else { break }
            pendingBuildRequest = nil
            request = nextRequest
        }

        buildTask = nil
        startNextBuildIfNeeded()
    }

    private func waitForBuildRequest(id: Int) async {
        if completedBuildRequestID >= id { return }
        await withCheckedContinuation { continuation in
            buildWaiters[id, default: []].append(continuation)
        }
    }

    private func resumeBuildWaiters(for completedID: Int) {
        let waiterIDs = buildWaiters.keys.filter { $0 <= completedID }.sorted()
        for waiterID in waiterIDs {
            let waiters = buildWaiters.removeValue(forKey: waiterID) ?? []
            waiters.forEach { $0.resume() }
        }
    }

    private func executeBuild(_ request: PendingBuildRequest) async {
        guard AppConfiguration.enablesLocalSemanticIndexing else { return }
        guard !request.videos.isEmpty else { return }
        if indexedVisualSignature == request.visualSignature, model.indexedFrameCount > 0 {
            return
        }

        print("[SemanticIndex] Starting chunk index build for \(request.videos.count) video(s)")
        model.isBuildingIndex = true
        model.searchErrorMessage = nil
        model.visualResults = []
        model.audioResults = []

        do {
            let buildState = try await coordinator.buildIndex(
                videos: request.videos,
                invalidatedVideoIDs: request.invalidatedVideoIDs,
                onProgress: { message in
                    await MainActor.run {
                        self.model.statusMessage = message
                    }
                },
                options: request.options
            )
            model.indexedFrameCount = buildState.indexedFrameCount
            indexedVideoSignatures = buildState.indexedVideoSignatures

            if request.visualSignature == visualIndexSignature(for: model.videos) {
                indexedVisualSignature = request.visualSignature
            }

            model.statusMessage = "Index built. Enter a query to find clip ranges."
            print(
                "[SemanticIndex] Index build succeeded. indexedFrameCount=\(model.indexedFrameCount) signature=\(request.visualSignature)"
            )
        } catch is CancellationError {
            return
        } catch {
            print("[SemanticIndex] Index build failed with error: \(error)")
            print("[SemanticIndex] Error description: \(error.localizedDescription)")
            model.searchErrorMessage = error.localizedDescription
            model.statusMessage = "Index build failed."
            model.indexedFrameCount = 0
            indexedVisualSignature = nil
            indexedVideoSignatures = [:]
        }

        model.isBuildingIndex = false
    }

    private func mergedBuildOptions(
        _ lhs: SemanticIndexBuildOptions,
        _ rhs: SemanticIndexBuildOptions
    ) -> SemanticIndexBuildOptions {
        SemanticIndexBuildOptions(
            frameEmbeddingConcurrency: max(lhs.frameEmbeddingConcurrency, rhs.frameEmbeddingConcurrency),
            embeddingPriority: lhs.embeddingPriority == .utility || rhs.embeddingPriority == .utility ? .utility : .background
        )
    }

    private func logSearchResults(
        _ ranges: [SemanticRangeCandidate],
        query: String,
        source: SemanticSearchResultSource
    ) {
        if ranges.isEmpty {
            print("[SemanticIndex] No \(source.rawValue) results found for query=\"\(query)\"")
            return
        }

        for (index, range) in ranges.enumerated() {
            print(
                "[SemanticIndex] \(source.rawValue.capitalized) result \(index + 1): video=\"\(range.videoName)\" start=\(formatTime(range.startTimeSeconds)) end=\(formatTime(range.endTimeSeconds)) confidence=\(String(format: "%.4f", range.confidence))"
            )
        }
    }

    private func readyStatusMessage() -> String {
        if model.videos.isEmpty {
            return "Import videos to build a chunk index."
        }
        if !AppConfiguration.enablesLocalSemanticIndexing {
            if model.cloudBackendProjectId == nil {
                return "Upload clips to your Iris project to search them in the cloud."
            }
            return "Search ready. Start typing to search clips."
        }
        if model.indexedFrameCount > 0 || model.hasTranscriptData {
            return "Search ready. Start typing to search clips."
        }
        return "Tap search to build an index for imported clips."
    }

    private func visualIndexSignature(for videos: [SemanticImportedVideo]) -> String {
        videos
            .map(\.visualContentSignature)
            .joined(separator: "|")
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
