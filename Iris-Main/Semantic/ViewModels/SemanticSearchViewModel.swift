import Combine
import Foundation

@MainActor
final class SemanticSearchViewModel: ObservableObject {
    @Published private(set) var model = SemanticSearchModel()

    private let frameSampler: VideoFrameSampler
    private let pipeline: SemanticSearchPipeline

    init(
        frameSampler: VideoFrameSampler = VideoFrameSampler(),
        pipeline: SemanticSearchPipeline = SemanticSearchPipeline()
    ) {
        self.frameSampler = frameSampler
        self.pipeline = pipeline
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

    func buildIndex() async {
        guard model.canBuildIndex else { return }
        print("[SemanticIndex] Starting chunk index build for \(model.videos.count) video(s)")
        model.isBuildingIndex = true
        model.searchErrorMessage = nil
        model.results = []

        do {
            try await pipeline.buildChunkIndex(videos: model.videos) { [weak self] message in
                await MainActor.run {
                    self?.model.statusMessage = message
                }
            }
            model.indexedFrameCount = pipeline.indexedFrameCount
            model.statusMessage = "Index built. Enter a query to find clip ranges."
            print("[SemanticIndex] Index build succeeded. indexedFrameCount=\(model.indexedFrameCount)")
        } catch {
            print("[SemanticIndex] Index build failed with error: \(error)")
            print("[SemanticIndex] Error description: \(error.localizedDescription)")
            model.searchErrorMessage = error.localizedDescription
            model.statusMessage = "Index build failed."
            model.indexedFrameCount = 0
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
}
