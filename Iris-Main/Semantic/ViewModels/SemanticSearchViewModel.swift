internal import Combine
import Foundation

@MainActor
final class SemanticSearchViewModel: ObservableObject {
    static let shared = SemanticSearchViewModel()

    @Published private(set) var model = SemanticSearchModel()

    private let frameSampler: VideoFrameSampler
    private let pipeline: SemanticSearchPipeline
    private let thumbnailService: ThumbnailService
    private var liveSearchTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var indexedVideoKeys: [String] = []

    init(
        frameSampler: VideoFrameSampler? = nil,
        pipeline: SemanticSearchPipeline? = nil,
        thumbnailService: ThumbnailService? = nil
    ) {
        self.frameSampler = frameSampler ?? VideoFrameSampler()
        self.pipeline = pipeline ?? SemanticSearchPipeline()
        self.thumbnailService = thumbnailService ?? .shared
    }

    func beginVideoImport() {
        model.isImportingVideos = true
        model.importErrorMessage = nil
    }

    func importSelection(from importedVideos: [ImportedSemanticVideo]) {
        guard !importedVideos.isEmpty else {
            model.videos = []
            model.results = []
            model.indexedFrameCount = 0
            model.statusMessage = "Import videos to build a chunk index."
            model.isImportingVideos = false
            model.importErrorMessage = nil
            pipeline.reset()
            return
        }

        Task {
            do {
                var nextVideos: [SemanticImportedVideo] = []
                for imported in importedVideos {
                    let duration = try await frameSampler.loadDurationSeconds(videoURL: imported.localURL)
                    nextVideos.append(
                        SemanticImportedVideo(
                            localKey: imported.localKey,
                            fileURL: imported.localURL,
                            displayName: imported.displayName,
                            durationSeconds: duration
                        )
                    )
                }

                model.videos = nextVideos
                model.results = []
                model.indexedFrameCount = 0
                model.statusMessage = "\(nextVideos.count) video(s) ready. Build index to search."
                model.importErrorMessage = nil
                model.searchErrorMessage = nil
                model.isImportingVideos = false
                pipeline.reset()
            } catch {
                model.videos = []
                model.results = []
                model.indexedFrameCount = 0
                model.importErrorMessage = error.localizedDescription
                model.statusMessage = "Could not load imported videos."
                model.isImportingVideos = false
                pipeline.reset()
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
        syncTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.syncImportedMedia(media, autoBuildIndex: autoBuildIndex)
        }
    }

    func syncImportedMedia(_ media: [Media], autoBuildIndex: Bool) async {
        let syncStart = EditorDebugTrace.mark()
        let candidateMedia = media
            .filter { $0.kind == .video }
            .sorted { $0.createdAt < $1.createdAt }
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
                await buildIndexIfNeeded()
                if !model.trimmedQuery.isEmpty {
                    await runSearch()
                }
            }
            return
        }

        var importedVideos: [SemanticImportedVideo] = []
        importedVideos.reserveCapacity(candidateMedia.count)

        for item in candidateMedia {
            guard let fileURL = try? await thumbnailService.loadVideoURL(for: item.assetRefId) else { continue }
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

        liveSearchTask?.cancel()
        model.videos = importedVideos
        model.results = []
        model.searchErrorMessage = nil
        model.importErrorMessage = nil
        model.indexedFrameCount = 0
        indexedVideoKeys = []
        pipeline.reset()

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
            await buildIndexIfNeeded()
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
            await self.buildIndexIfNeeded()
            guard !Task.isCancelled else { return }
            await self.runSearch()
        }
    }

    func buildIndex() async {
        guard model.canBuildIndex else { return }
        print("[SemanticIndex] Starting chunk index build for \(model.videos.count) video(s)")
        model.isBuildingIndex = true
        model.searchErrorMessage = nil
        model.results = []

        do {
            try await pipeline.buildChunkIndex(videos: model.videos) { message in
                await MainActor.run {
                    self.model.statusMessage = message
                }
            }
            model.indexedFrameCount = pipeline.indexedFrameCount
            indexedVideoKeys = model.videos.map(\.localKey)
            model.statusMessage = "Index built. Enter a query to find clip ranges."
            print("[SemanticIndex] Index build succeeded. indexedFrameCount=\(model.indexedFrameCount)")
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
        model.isSearching = true
        model.searchErrorMessage = nil
        model.results = []
        model.statusMessage = "Searching likely ranges..."

        do {
            let ranges = try await pipeline.search(query: model.trimmedQuery, videos: model.videos)
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
        } catch {
            model.searchErrorMessage = error.localizedDescription
            model.statusMessage = "Search failed."
        }

        model.isSearching = false
    }

    private func buildIndexIfNeeded() async {
        guard !model.videos.isEmpty else { return }
        guard indexedVideoKeys != model.videos.map(\.localKey) || model.indexedFrameCount == 0 else { return }
        await buildIndex()
    }
}
