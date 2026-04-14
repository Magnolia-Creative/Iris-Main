import CoreGraphics
import Foundation

struct SemanticSearchConstants {
    static let chunkDurationSeconds = 4.0
    static let chunkOverlapSeconds = 0.5
    static let chunkTopK = 10
    static let chunkMergeMinimumScore = 0.15
    static let resultsLimit = 3
    static let rangeMergeGapSeconds = 0.6
    static let indexingFrameMaximumDimension: CGFloat = 320

    static var chunkStrideSeconds: Double {
        max(0.1, chunkDurationSeconds - chunkOverlapSeconds)
    }
}

struct SemanticIndexBuildOptions {
    let frameEmbeddingConcurrency: Int
    let embeddingPriority: TaskPriority

    static let interactive = SemanticIndexBuildOptions(
        frameEmbeddingConcurrency: 2,
        embeddingPriority: .utility
    )

    static let backgroundImport = SemanticIndexBuildOptions(
        frameEmbeddingConcurrency: 1,
        embeddingPriority: .background
    )
}

struct VideoChunkPoint: Hashable {
    let videoID: SemanticImportedVideo.ID
    let videoName: String
    let videoDuration: Double
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let centerTimeSeconds: Double
}

struct SemanticVisualIndexState {
    let indexedFrameCount: Int
    let indexedVideoSignatures: [String: String]
}

struct SemanticRangeCandidate {
    let videoID: SemanticImportedVideo.ID
    let videoName: String
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let confidence: Double
    let source: SemanticSearchResultSource
    let matchText: String?
}

struct MergedChunkDebugGroup {
    let candidate: SemanticRangeCandidate
    let chunkHits: [VectorSearchHit<VideoChunkPoint>]
    let averageScore: Double
    let peakScore: Double
}

final class SemanticSearchPipeline {
    private let embeddingService: MobileCLIPEmbeddingProviding
    private let frameSampler: any VideoFrameSampling

    private var chunkIndex = LocalVectorIndex<VideoChunkPoint>()
    private var indexedChunkCount = 0
    private var cachedVideoEntries: [String: CachedVideoChunkIndex] = [:]

    init(
        embeddingService: MobileCLIPEmbeddingProviding = MobileCLIPEmbeddingPool.shared,
        frameSampler: any VideoFrameSampling = VideoFrameSampler()
    ) {
        self.embeddingService = embeddingService
        self.frameSampler = frameSampler
    }

    var indexedFrameCount: Int {
        indexedChunkCount
    }

    var indexedVideoSignatures: [String: String] {
        cachedVideoEntries.mapValues(\.signature)
    }

    private struct CachedVideoChunkIndex {
        let signature: String
        let entries: [VectorEntry<VideoChunkPoint>]
    }

    private func chunkPoints(for video: SemanticImportedVideo) -> [VideoChunkPoint] {
        guard video.durationSeconds > 0 else { return [] }

        let chunkDuration = min(SemanticSearchConstants.chunkDurationSeconds, video.durationSeconds)
        guard chunkDuration > 0 else { return [] }

        if video.durationSeconds <= chunkDuration {
            return [
                VideoChunkPoint(
                    videoID: video.id,
                    videoName: video.displayName,
                    videoDuration: video.durationSeconds,
                    startTimeSeconds: 0,
                    endTimeSeconds: video.durationSeconds,
                    centerTimeSeconds: video.durationSeconds / 2
                )
            ]
        }

        let stride = SemanticSearchConstants.chunkStrideSeconds
        var starts: [Double] = []
        var currentStart = 0.0

        while currentStart + chunkDuration < video.durationSeconds {
            starts.append(currentStart)
            currentStart += stride
        }

        let finalStart = max(0, video.durationSeconds - chunkDuration)
        if let lastStart = starts.last {
            if abs(lastStart - finalStart) > 0.001 {
                starts.append(finalStart)
            }
        } else {
            starts.append(finalStart)
        }

        return starts.map { start in
            let end = min(start + chunkDuration, video.durationSeconds)
            let center = min(video.durationSeconds, start + ((end - start) / 2))
            return VideoChunkPoint(
                videoID: video.id,
                videoName: video.displayName,
                videoDuration: video.durationSeconds,
                startTimeSeconds: start,
                endTimeSeconds: end,
                centerTimeSeconds: center
            )
        }
    }

    private func embedFrames(
        _ frames: [SampledVideoFrame],
        maxConcurrency: Int,
        priority: TaskPriority
    ) async throws -> [(frame: SampledVideoFrame, embedding: [Float])] {
        guard !frames.isEmpty else { return [] }
        try Task.checkCancellation()

        let boundedConcurrency = max(1, maxConcurrency)
        var frameIterator = frames.makeIterator()

        return try await withThrowingTaskGroup(of: (SampledVideoFrame, [Float]).self) { group in
            var results: [(frame: SampledVideoFrame, embedding: [Float])] = []

            let initialTaskCount = min(boundedConcurrency, frames.count)
            for _ in 0..<initialTaskCount {
                guard let frame = frameIterator.next() else { break }
                group.addTask(priority: priority) {
                    try Task.checkCancellation()
                    let embedding = try await self.embeddingService.imageEmbedding(for: frame.image)
                    return (frame, embedding)
                }
            }

            while let completed = try await group.next() {
                try Task.checkCancellation()
                results.append((frame: completed.0, embedding: completed.1))
                await Task.yield()

                if let frame = frameIterator.next() {
                    group.addTask(priority: priority) {
                        try Task.checkCancellation()
                        let embedding = try await self.embeddingService.imageEmbedding(for: frame.image)
                        return (frame, embedding)
                    }
                }
            }

            return results
        }
    }

    func reset() {
        chunkIndex.reset()
        indexedChunkCount = 0
        cachedVideoEntries.removeAll()
    }

    func prewarmEmbeddingServices() async {
        print("[SemanticIndex] prewarming embedding services")
        await embeddingService.prewarm()
    }

    func buildChunkIndex(
        videos: [SemanticImportedVideo],
        invalidatedVideoIDs: Set<String>,
        onProgress: @escaping @Sendable (String) async -> Void,
        options: SemanticIndexBuildOptions = .interactive
    ) async throws -> SemanticVisualIndexState {
        let buildStart = Date()
        guard !videos.isEmpty else {
            reset()
            return SemanticVisualIndexState(indexedFrameCount: 0, indexedVideoSignatures: [:])
        }
        print("[SemanticIndex] buildChunkIndex called with \(videos.count) video(s) invalidated=\(invalidatedVideoIDs.count)")

        let activeVideoIDs = Set(videos.map(\.id))
        cachedVideoEntries = cachedVideoEntries.filter { activeVideoIDs.contains($0.key) }

        let videosToRebuild = videos.filter { video in
            invalidatedVideoIDs.contains(video.id)
                || cachedVideoEntries[video.id]?.signature != video.visualContentSignature
        }

        for (videoIndex, video) in videosToRebuild.enumerated() {
            try Task.checkCancellation()
            let videoStart = Date()
            print("[SemanticIndex] Building chunks for video \(videoIndex + 1)/\(videosToRebuild.count): \(video.displayName), duration=\(video.durationSeconds)s")
            await onProgress("Indexing \(video.displayName) (\(videoIndex + 1)/\(max(videosToRebuild.count, 1)))...")
            let entries = try await buildChunkEntries(for: video, options: options)
            cachedVideoEntries[video.id] = CachedVideoChunkIndex(
                signature: video.visualContentSignature,
                entries: entries
            )
            let videoElapsed = Date().timeIntervalSince(videoStart)
            print("[SemanticIndex] Finished video \(video.displayName). cachedChunks=\(entries.count) elapsed=\(String(format: "%.2f", videoElapsed))s")
        }

        rebuildMergedIndex(for: videos)
        let buildElapsed = Date().timeIntervalSince(buildStart)
        print("[SemanticIndex] Chunk index finalized. totalChunks=\(indexedChunkCount) elapsed=\(String(format: "%.2f", buildElapsed))s")
        await onProgress("Chunk index ready with \(indexedChunkCount) chunks.")
        return SemanticVisualIndexState(
            indexedFrameCount: indexedChunkCount,
            indexedVideoSignatures: indexedVideoSignatures
        )
    }

    private func buildChunkEntries(
        for video: SemanticImportedVideo,
        options: SemanticIndexBuildOptions
    ) async throws -> [VectorEntry<VideoChunkPoint>] {
        let chunks = chunkPoints(for: video)
        let centerTimestamps = chunks.map(\.centerTimeSeconds)
        let frames = try await frameSampler.sampleFrames(
            videoURL: video.fileURL,
            atTimestamps: centerTimestamps,
            maximumDimension: SemanticSearchConstants.indexingFrameMaximumDimension
        )
        print("[SemanticIndex] Sampled \(frames.count) chunk center frame(s) for \(video.displayName)")

        let frameByTimestamp = Dictionary(uniqueKeysWithValues: frames.map { ($0.timestampSeconds, $0) })
        let availableChunks = chunks.compactMap { chunk -> (chunk: VideoChunkPoint, frame: SampledVideoFrame)? in
            guard let frame = frameByTimestamp[chunk.centerTimeSeconds] else { return nil }
            return (chunk, frame)
        }

        let embeddedFrames = try await embedFrames(
            availableChunks.map(\.frame),
            maxConcurrency: options.frameEmbeddingConcurrency,
            priority: options.embeddingPriority
        )
        try Task.checkCancellation()
        await Task.yield()

        let chunkByCenter = Dictionary(uniqueKeysWithValues: availableChunks.map { ($0.chunk.centerTimeSeconds, $0.chunk) })
        return embeddedFrames.compactMap { item in
            guard let chunk = chunkByCenter[item.frame.timestampSeconds] else { return nil }
            return VectorEntry(vector: item.embedding, payload: chunk)
        }
    }

    private func rebuildMergedIndex(for videos: [SemanticImportedVideo]) {
        var index = LocalVectorIndex<VideoChunkPoint>()
        var totalChunks = 0

        for video in videos {
            guard let cachedVideo = cachedVideoEntries[video.id] else { continue }
            for entry in cachedVideo.entries {
                index.add(vector: entry.vector, payload: entry.payload)
                totalChunks += 1
            }
        }

        chunkIndex = index
        indexedChunkCount = totalChunks
    }

    func search(query: String, videos: [SemanticImportedVideo]) async throws -> [SemanticRangeCandidate] {
        let searchStart = Date()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard !videos.isEmpty else { return [] }
        guard indexedChunkCount > 0 else { return [] }

        let queryVector = try await embeddingService.textEmbedding(for: query)
        print(
            "[SemanticIndex] search start query=\"\(query)\" queryDimensions=\(queryVector.count) " +
            "videos=\(videos.count) indexedChunks=\(indexedChunkCount) chunkTopK=\(SemanticSearchConstants.chunkTopK) " +
            "mergeMinScore=\(String(format: "%.2f", SemanticSearchConstants.chunkMergeMinimumScore))"
        )
        let chunkHits = chunkIndex.topK(query: queryVector, limit: SemanticSearchConstants.chunkTopK)
        guard !chunkHits.isEmpty else {
            print("[SemanticIndex] search query=\"\(query)\" produced no chunk hits")
            return []
        }
        logChunkHits(chunkHits, query: query)

        let mergeEligibleChunkHits = chunkHits.filter { $0.score > SemanticSearchConstants.chunkMergeMinimumScore }
        if mergeEligibleChunkHits.count != chunkHits.count {
            print(
                "[SemanticIndex] merge eligibility query=\"\(query)\" eligible=\(mergeEligibleChunkHits.count) " +
                "excluded=\(chunkHits.count - mergeEligibleChunkHits.count) threshold=\(String(format: "%.2f", SemanticSearchConstants.chunkMergeMinimumScore))"
            )
        }
        guard !mergeEligibleChunkHits.isEmpty else {
            print(
                "[SemanticIndex] search query=\"\(query)\" produced no merge-eligible chunk hits " +
                "threshold=\(String(format: "%.2f", SemanticSearchConstants.chunkMergeMinimumScore))"
            )
            return []
        }

        let mergedGroups = TemporalRangeScorer.mergeChunkHitGroups(
            mergeEligibleChunkHits,
            maxGapSeconds: SemanticSearchConstants.rangeMergeGapSeconds,
            minimumScore: SemanticSearchConstants.chunkMergeMinimumScore
        )
        logMergedChunkGroups(
            mergedGroups,
            query: query,
            maxGapSeconds: SemanticSearchConstants.rangeMergeGapSeconds
        )
        let candidates = mergedGroups.map(\.candidate)

        let searchElapsed = Date().timeIntervalSince(searchStart)
        print("[SemanticIndex] Search completed. chunkHits=\(chunkHits.count) candidates=\(candidates.count) elapsed=\(String(format: "%.2f", searchElapsed))s")

        return candidates
            .sorted { $0.confidence > $1.confidence }
            .map { $0 }
    }

    private func logChunkHits(_ hits: [VectorSearchHit<VideoChunkPoint>], query: String) {
        for (index, hit) in hits.enumerated() {
            let chunk = hit.payload
            print(
                "[SemanticIndex] Chunk hit \(index + 1)/\(hits.count) query=\"\(query)\" " +
                "video=\"\(chunk.videoName)\" window=\(formatSemanticTimestamp(chunk.startTimeSeconds))-\(formatSemanticTimestamp(chunk.endTimeSeconds)) " +
                "center=\(formatSemanticTimestamp(chunk.centerTimeSeconds)) score=\(String(format: "%.4f", hit.score)) " +
                "mergeEligible=\(hit.score > SemanticSearchConstants.chunkMergeMinimumScore)"
            )
        }
    }

    private func logMergedChunkGroups(
        _ groups: [MergedChunkDebugGroup],
        query: String,
        maxGapSeconds: Double
    ) {
        let rankedGroups = groups.sorted { lhs, rhs in
            if lhs.candidate.confidence == rhs.candidate.confidence {
                return lhs.candidate.startTimeSeconds < rhs.candidate.startTimeSeconds
            }
            return lhs.candidate.confidence > rhs.candidate.confidence
        }

        for (index, group) in rankedGroups.enumerated() {
            let candidate = group.candidate
            print(
                "[SemanticIndex] Merged range \(index + 1)/\(rankedGroups.count) query=\"\(query)\" " +
                "video=\"\(candidate.videoName)\" window=\(formatSemanticTimestamp(candidate.startTimeSeconds))-\(formatSemanticTimestamp(candidate.endTimeSeconds)) " +
                "confidence=\(String(format: "%.4f", candidate.confidence)) chunks=\(group.chunkHits.count) " +
                "avgScore=\(String(format: "%.4f", group.averageScore)) peakScore=\(String(format: "%.4f", group.peakScore)) " +
                "gapThreshold=\(String(format: "%.2f", maxGapSeconds))s"
            )

            let stitchPath = group.chunkHits.enumerated().map { memberIndex, hit in
                let gapDescription: String
                if memberIndex == 0 {
                    gapDescription = "seed"
                } else {
                    let previousHit = group.chunkHits[memberIndex - 1]
                    let gap = hit.payload.startTimeSeconds - previousHit.payload.endTimeSeconds
                    gapDescription = String(format: "gap=%+.2fs", gap)
                }

                return
                    "#\(memberIndex + 1) " +
                    "\(formatSemanticTimestamp(hit.payload.startTimeSeconds))-\(formatSemanticTimestamp(hit.payload.endTimeSeconds)) " +
                    "score=\(String(format: "%.4f", hit.score)) \(gapDescription)"
            }
            .joined(separator: " | ")

            print("[SemanticIndex] Merged range \(index + 1) stitch path: \(stitchPath)")
        }
    }
}

enum TemporalRangeScorer {
    static func mergeChunkHits(
        _ hits: [VectorSearchHit<VideoChunkPoint>],
        maxGapSeconds: Double,
        minimumScore: Double = -.infinity
    ) -> [SemanticRangeCandidate] {
        mergeChunkHitGroups(hits, maxGapSeconds: maxGapSeconds, minimumScore: minimumScore).map(\.candidate)
    }

    static func mergeChunkHitGroups(
        _ hits: [VectorSearchHit<VideoChunkPoint>],
        maxGapSeconds: Double,
        minimumScore: Double = -.infinity
    ) -> [MergedChunkDebugGroup] {
        guard !hits.isEmpty else { return [] }

        let eligibleHits = hits.filter { $0.score > minimumScore }
        guard !eligibleHits.isEmpty else { return [] }

        let grouped = Dictionary(grouping: eligibleHits, by: { $0.payload.videoID })
        var merged: [MergedChunkDebugGroup] = []

        for videoHits in grouped.values {
            let sorted = videoHits.sorted { $0.payload.startTimeSeconds < $1.payload.startTimeSeconds }
            guard let first = sorted.first else { continue }

            var rangeStart = first.payload.startTimeSeconds
            var rangeEnd = first.payload.endTimeSeconds
            var scoreSum = first.score
            var scoreCount = 1
            var peak = first.score
            let videoName = first.payload.videoName
            let videoID = first.payload.videoID
            var chunkHits = [first]

            for current in sorted.dropFirst() {
                let gap = current.payload.startTimeSeconds - rangeEnd
                if gap <= maxGapSeconds {
                    rangeEnd = max(rangeEnd, current.payload.endTimeSeconds)
                    scoreSum += current.score
                    scoreCount += 1
                    peak = max(peak, current.score)
                    chunkHits.append(current)
                } else {
                    merged.append(
                        buildMergedChunkDebugGroup(
                            videoID: videoID,
                            videoName: videoName,
                            startTimeSeconds: rangeStart,
                            endTimeSeconds: rangeEnd,
                            chunkHits: chunkHits,
                            scoreSum: scoreSum,
                            scoreCount: scoreCount,
                            peakScore: peak
                        )
                    )
                    rangeStart = current.payload.startTimeSeconds
                    rangeEnd = current.payload.endTimeSeconds
                    scoreSum = current.score
                    scoreCount = 1
                    peak = current.score
                    chunkHits = [current]
                }
            }

            merged.append(
                buildMergedChunkDebugGroup(
                    videoID: videoID,
                    videoName: videoName,
                    startTimeSeconds: rangeStart,
                    endTimeSeconds: rangeEnd,
                    chunkHits: chunkHits,
                    scoreSum: scoreSum,
                    scoreCount: scoreCount,
                    peakScore: peak
                )
            )
        }

        return merged
    }

    private static func buildMergedChunkDebugGroup(
        videoID: SemanticImportedVideo.ID,
        videoName: String,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        chunkHits: [VectorSearchHit<VideoChunkPoint>],
        scoreSum: Double,
        scoreCount: Int,
        peakScore: Double
    ) -> MergedChunkDebugGroup {
        let averageScore = scoreSum / Double(max(scoreCount, 1))
        let confidence = (averageScore * 0.65) + (peakScore * 0.35)
        return MergedChunkDebugGroup(
            candidate: SemanticRangeCandidate(
                videoID: videoID,
                videoName: videoName,
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds,
                confidence: confidence,
                source: .visual,
                matchText: nil
            ),
            chunkHits: chunkHits,
            averageScore: averageScore,
            peakScore: peakScore
        )
    }
}

private func formatSemanticTimestamp(_ seconds: Double) -> String {
    let clampedSeconds = max(0.0, seconds)
    let totalMinutes = Int(clampedSeconds) / 60
    let remainingSeconds = clampedSeconds - Double(totalMinutes * 60)
    return String(format: "%02d:%05.2f", totalMinutes, remainingSeconds)
}
