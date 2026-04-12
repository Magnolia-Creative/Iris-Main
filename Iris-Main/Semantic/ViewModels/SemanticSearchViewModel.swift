internal import Combine
import Foundation

private actor SemanticSearchCoordinator {
    private let frameSampler: VideoFrameSampler
    private let pipeline: SemanticSearchPipeline
    private let thumbnailService: ThumbnailService

    init(
        frameSampler: VideoFrameSampler = VideoFrameSampler(),
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
                    durationSeconds: duration
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
                    durationSeconds: duration
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
        onProgress: @escaping @Sendable (String) async -> Void,
        options: SemanticIndexBuildOptions
    ) async throws -> Int {
        try await pipeline.buildChunkIndex(videos: videos, onProgress: onProgress, options: options)
        return pipeline.indexedFrameCount
    }

    func search(query: String, videos: [SemanticImportedVideo]) async throws -> [SemanticRangeCandidate] {
        try await pipeline.search(query: query, videos: videos)
    }
}

@MainActor
final class SemanticSearchViewModel: ObservableObject {
    static let shared = SemanticSearchViewModel()

    @Published private(set) var model = SemanticSearchModel()

    private let coordinator: SemanticSearchCoordinator
    private var liveSearchTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var indexedVideoKeys: [String] = []

    init(
        frameSampler: VideoFrameSampler? = nil,
        pipeline: SemanticSearchPipeline? = nil,
        thumbnailService: ThumbnailService? = nil
    ) {
        self.coordinator = SemanticSearchCoordinator(
            frameSampler: frameSampler ?? VideoFrameSampler(),
            pipeline: pipeline ?? SemanticSearchPipeline(),
            thumbnailService: thumbnailService ?? .shared
        )
    }

    func beginVideoImport() {
        model.isImportingVideos = true
        model.importErrorMessage = nil
    }

    func importSelection(from importedVideos: [ImportedSemanticVideo]) {
        guard !importedVideos.isEmpty else {
            liveSearchTask?.cancel()
            syncTask?.cancel()
            model.videos = []
            model.results = []
            model.indexedFrameCount = 0
            model.statusMessage = "Import videos to build a chunk index."
            model.isImportingVideos = false
            model.importErrorMessage = nil
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

                model.videos = nextVideos
                model.results = []
                model.indexedFrameCount = 0
                model.statusMessage = "\(nextVideos.count) video(s) ready. Build index to search."
                model.importErrorMessage = nil
                model.searchErrorMessage = nil
                model.isImportingVideos = false
            } catch is CancellationError {
                return
            } catch {
                await coordinator.reset()
                model.videos = []
                model.results = []
                model.indexedFrameCount = 0
                model.importErrorMessage = error.localizedDescription
                model.statusMessage = "Could not load imported videos."
                model.isImportingVideos = false
            }
        }
    }

    func updateQuery(_ query: String) {
        model.queryText = query
    }

    func clearSearch() {
        liveSearchTask?.cancel()
        model.queryText = ""
        model.results = []
        model.searchErrorMessage = nil
        if model.indexedFrameCount > 0 {
            model.statusMessage = model.videos.isEmpty
                ? "Import videos to build a chunk index."
                : "Index ready. Start typing to search clips."
        }
    }

    func queueImportedMediaSync(_ media: [Media], autoBuildIndex: Bool) {
        syncTask?.cancel()
        let queuedVideoCount = media.filter { $0.kind == .video }.count
        EditorDebugTrace.log(
            "SemanticSearchViewModel",
            "queue imported media sync videoCount=\(queuedVideoCount) autoBuildIndex=\(autoBuildIndex)"
        )
        syncTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.syncImportedMedia(media, autoBuildIndex: autoBuildIndex)
        }
    }

    func syncImportedMedia(_ media: [Media], autoBuildIndex: Bool) async {
        let syncStart = EditorDebugTrace.mark()
        let candidateMedia = Media.deduplicatedForImportPresentation(media)
            .filter { $0.kind == .video }
        let nextKeys = candidateMedia.map(\.mediaId)
        let currentKeys = model.videos.map(\.localKey)

        EditorDebugTrace.log(
            "SemanticSearchViewModel",
            "sync start candidateVideos=\(candidateMedia.count) autoBuildIndex=\(autoBuildIndex)"
        )

        guard nextKeys != currentKeys else {
            EditorDebugTrace.log(
                "SemanticSearchViewModel",
                "sync skipped unchangedVideos count=\(candidateMedia.count) \(EditorDebugTrace.elapsedMessage(since: syncStart))"
            )
            if autoBuildIndex {
                await buildIndexIfNeeded(options: .backgroundImport)
                if !model.trimmedQuery.isEmpty {
                    await runSearch()
                }
            }
            return
        }

        let importedVideos: [SemanticImportedVideo]
        do {
            importedVideos = try await coordinator.resolveSearchableVideos(from: candidateMedia)
        } catch is CancellationError {
            return
        } catch {
            model.videos = []
            model.results = []
            model.searchErrorMessage = error.localizedDescription
            model.importErrorMessage = error.localizedDescription
            model.indexedFrameCount = 0
            indexedVideoKeys = []
            model.statusMessage = "Could not prepare videos for semantic search."
            await coordinator.reset()
            return
        }

        liveSearchTask?.cancel()
        model.videos = importedVideos
        model.results = []
        model.searchErrorMessage = nil
        model.importErrorMessage = nil
        model.indexedFrameCount = 0
        indexedVideoKeys = []
        await coordinator.reset()

        if importedVideos.isEmpty {
            model.statusMessage = "Import videos to search them semantically."
            EditorDebugTrace.log(
                "SemanticSearchViewModel",
                "sync completed with no imported videos \(EditorDebugTrace.elapsedMessage(since: syncStart))"
            )
            return
        }

        model.statusMessage = autoBuildIndex
            ? "Preparing semantic index..."
            : "Tap search to build an index for imported clips."

        if autoBuildIndex {
            await buildIndexIfNeeded(options: .backgroundImport)
            if !model.trimmedQuery.isEmpty {
                await runSearch()
            }
        }

        EditorDebugTrace.log(
            "SemanticSearchViewModel",
            "sync completed importedVideos=\(importedVideos.count) indexedFrames=\(model.indexedFrameCount) \(EditorDebugTrace.elapsedMessage(since: syncStart))"
        )
    }

    func queueLiveSearch() {
        liveSearchTask?.cancel()
        model.searchErrorMessage = nil

        guard !model.trimmedQuery.isEmpty else {
            model.results = []
            if model.videos.isEmpty {
                model.statusMessage = "Import videos to search them semantically."
            } else if model.indexedFrameCount > 0 {
                model.statusMessage = "Index ready. Start typing to search clips."
            }
            return
        }

        liveSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.buildIndexIfNeeded(options: .interactive)
            guard !Task.isCancelled else { return }
            await self.runSearch()
        }
    }

    func buildIndex() async {
        await buildIndex(options: .interactive)
    }

    private func buildIndex(options: SemanticIndexBuildOptions) async {
        guard model.canBuildIndex else { return }
        let videos = model.videos
        let requestedVideoKeys = videos.map(\.localKey)
        print("[SemanticIndex] Starting chunk index build for \(videos.count) video(s)")
        model.isBuildingIndex = true
        model.searchErrorMessage = nil
        model.results = []

        do {
            let indexedFrameCount = try await coordinator.buildIndex(videos: videos, onProgress: { message in
                await MainActor.run {
                    self.model.statusMessage = message
                }
            }, options: options)
            guard requestedVideoKeys == model.videos.map(\.localKey) else {
                model.isBuildingIndex = false
                return
            }
            model.indexedFrameCount = indexedFrameCount
            indexedVideoKeys = requestedVideoKeys
            model.statusMessage = "Index built. Enter a query to find clip ranges."
            print("[SemanticIndex] Index build succeeded. indexedFrameCount=\(model.indexedFrameCount)")
        } catch is CancellationError {
            model.isBuildingIndex = false
            return
        } catch {
            print("[SemanticIndex] Index build failed with error: \(error)")
            print("[SemanticIndex] Error description: \(error.localizedDescription)")
            model.searchErrorMessage = error.localizedDescription
            model.statusMessage = "Index build failed."
            model.indexedFrameCount = 0
            indexedVideoKeys = []
        }

        model.isBuildingIndex = false
    }

    func runSearch() async {
        guard model.canSearch else { return }
        let query = model.trimmedQuery
        let videos = model.videos
        let requestedVideoKeys = videos.map(\.localKey)
        model.isSearching = true
        model.searchErrorMessage = nil
        model.results = []
        model.statusMessage = "Searching likely ranges..."

        do {
            let ranges = try await coordinator.search(query: query, videos: videos)
            guard query == model.trimmedQuery, requestedVideoKeys == model.videos.map(\.localKey) else {
                model.isSearching = false
                return
            }
            logSearchResults(ranges, query: query)
            model.results = ranges.map {
                SemanticMatchRange(
                    videoID: $0.videoID,
                    videoName: $0.videoName,
                    startTimeSeconds: $0.startTimeSeconds,
                    endTimeSeconds: $0.endTimeSeconds,
                    confidence: $0.confidence
                )
            }
            model.statusMessage = ranges.isEmpty ? "No matching ranges found." : "Found \(ranges.count) likely range(s)."
        } catch is CancellationError {
            model.isSearching = false
            return
        } catch {
            model.searchErrorMessage = error.localizedDescription
            model.statusMessage = "Search failed."
        }

        model.isSearching = false
    }

    private func buildIndexIfNeeded() async {
        await buildIndexIfNeeded(options: .interactive)
    }

    private func buildIndexIfNeeded(options: SemanticIndexBuildOptions) async {
        guard !model.videos.isEmpty else { return }
        guard indexedVideoKeys != model.videos.map(\.localKey) || model.indexedFrameCount == 0 else { return }
        await buildIndex(options: options)
    }

    private func logSearchResults(_ ranges: [SemanticRangeCandidate], query: String) {
        if ranges.isEmpty {
            print("[SemanticIndex] No results found for query=\"\(query)\"")
            return
        }

        for (index, range) in ranges.enumerated() {
            print(
                "[SemanticIndex] Result \(index + 1): video=\"\(range.videoName)\" start=\(formatTime(range.startTimeSeconds)) end=\(formatTime(range.endTimeSeconds)) confidence=\(String(format: "%.4f", range.confidence))"
            )
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
