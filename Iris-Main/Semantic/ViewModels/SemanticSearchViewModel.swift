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
                    durationSeconds: duration,
                    transcriptSentences: [],
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
    static let shared = SemanticSearchViewModel(resultSelectionMode: .bestClip)

    @Published private(set) var model = SemanticSearchModel()

    private let coordinator: SemanticSearchCoordinator
    private let resultSelectionMode: SemanticSearchResultSelectionMode
    private var liveSearchTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var indexedVideoKeys: [String] = []

    init(
        frameSampler: VideoFrameSampler? = nil,
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
        frameSampler: VideoFrameSampler? = nil,
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

    func beginVideoImport() {
        model.isImportingVideos = true
        model.importErrorMessage = nil
    }

    func importSelection(from importedVideos: [ImportedSemanticVideo]) {
        guard !importedVideos.isEmpty else {
            liveSearchTask?.cancel()
            syncTask?.cancel()
            model.videos = []
            model.visualResults = []
            model.audioResults = []
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
                model.visualResults = []
                model.audioResults = []
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
                model.visualResults = []
                model.audioResults = []
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
        model.visualResults = []
        model.audioResults = []
        model.searchErrorMessage = nil
        model.statusMessage = readyStatusMessage()
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
        let nextContentSignatures = candidateMedia.map(\.semanticSearchContentSignature)
        let currentKeys = model.videos.map(\.localKey)
        let currentContentSignatures = model.videos.map(\.contentSignature)

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
                await buildIndexIfNeeded(options: .backgroundImport)
                if !model.trimmedQuery.isEmpty {
                    await runSearch()
                }
            }
            return
        }

        let hasSameVideoKeys = nextKeys == currentKeys
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
            indexedVideoKeys = []
            model.statusMessage = "Could not prepare videos for semantic search."
            await coordinator.reset()
            return
        }

        liveSearchTask?.cancel()
        model.videos = importedVideos
        model.visualResults = []
        model.audioResults = []
        model.searchErrorMessage = nil
        model.importErrorMessage = nil
        if !hasSameVideoKeys {
            model.indexedFrameCount = 0
            indexedVideoKeys = []
            await coordinator.reset()
        }

        if importedVideos.isEmpty {
            model.statusMessage = "Import videos to search them semantically."
            EditorDebugTrace.log(
                "SemanticSearchViewModel",
                "sync completed with no imported videos \(EditorDebugTrace.elapsedMessage(since: syncStart))"
            )
            return
        }

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
        model.visualResults = []
        model.audioResults = []

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
        guard model.canSearch else {
            print(
                "[SemanticAudioSearch] run search skipped query=\"\(model.queryText)\" " +
                "trimmedEmpty=\(model.trimmedQuery.isEmpty) indexedFrames=\(model.indexedFrameCount) " +
                "hasTranscriptData=\(model.hasTranscriptData) videos=\(model.videos.count)"
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

    private func buildIndexIfNeeded() async {
        await buildIndexIfNeeded(options: .interactive)
    }

    private func buildIndexIfNeeded(options: SemanticIndexBuildOptions) async {
        guard !model.videos.isEmpty else { return }
        guard indexedVideoKeys != model.videos.map(\.localKey) || model.indexedFrameCount == 0 else { return }
        await buildIndex(options: options)
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
        if model.indexedFrameCount > 0 || model.hasTranscriptData {
            return "Search ready. Start typing to search clips."
        }
        return "Tap search to build an index for imported clips."
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
