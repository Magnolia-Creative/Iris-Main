import CoreGraphics
import Foundation

struct SemanticSearchConstants {
    static let chunkDurationSeconds = 4.0
    static let chunkOverlapSeconds = 0.5
    static let chunkTopK = 10
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

struct SemanticRangeCandidate {
    let videoID: SemanticImportedVideo.ID
    let videoName: String
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let confidence: Double
}

final class SemanticSearchPipeline {
    private let embeddingService: MobileCLIPEmbeddingProviding
    private let frameSampler: VideoFrameSampler

    private var chunkIndex = LocalVectorIndex<VideoChunkPoint>()
    private var indexedChunkCount = 0

    init(
        embeddingService: MobileCLIPEmbeddingProviding = MobileCLIPEmbeddingPool.shared,
        frameSampler: VideoFrameSampler = VideoFrameSampler()
    ) {
        self.embeddingService = embeddingService
        self.frameSampler = frameSampler
    }

    var indexedFrameCount: Int {
        indexedChunkCount
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
    }

    func buildChunkIndex(
        videos: [SemanticImportedVideo],
        onProgress: @escaping @Sendable (String) async -> Void,
        options: SemanticIndexBuildOptions = .interactive
    ) async throws {
        let buildStart = Date()
        reset()
        guard !videos.isEmpty else { return }
        print("[SemanticIndex] buildChunkIndex called with \(videos.count) video(s)")

        var index = LocalVectorIndex<VideoChunkPoint>()
        var totalChunks = 0

        for (videoIndex, video) in videos.enumerated() {
            try Task.checkCancellation()
            let videoStart = Date()
            print("[SemanticIndex] Building chunks for video \(videoIndex + 1)/\(videos.count): \(video.displayName), duration=\(video.durationSeconds)s")
            await onProgress("Indexing \(video.displayName) (\(videoIndex + 1)/\(videos.count))...")

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
            for item in embeddedFrames {
                guard let chunk = chunkByCenter[item.frame.timestampSeconds] else { continue }
                index.add(
                    vector: item.embedding,
                    payload: chunk
                )
                totalChunks += 1
            }
            let videoElapsed = Date().timeIntervalSince(videoStart)
            print("[SemanticIndex] Finished video \(video.displayName). runningChunkTotal=\(totalChunks) elapsed=\(String(format: "%.2f", videoElapsed))s")
        }

        chunkIndex = index
        indexedChunkCount = totalChunks
        let buildElapsed = Date().timeIntervalSince(buildStart)
        print("[SemanticIndex] Chunk index finalized. totalChunks=\(totalChunks) elapsed=\(String(format: "%.2f", buildElapsed))s")
        await onProgress("Chunk index ready with \(totalChunks) chunks.")
    }

    func search(query: String, videos: [SemanticImportedVideo]) async throws -> [SemanticRangeCandidate] {
        let searchStart = Date()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard !videos.isEmpty else { return [] }
        guard indexedChunkCount > 0 else { return [] }

        let queryVector = try await embeddingService.textEmbedding(for: query)
        let chunkHits = chunkIndex.topK(query: queryVector, limit: SemanticSearchConstants.chunkTopK)
        guard !chunkHits.isEmpty else { return [] }

        let candidates = TemporalRangeScorer.mergeChunkHits(
            chunkHits,
            maxGapSeconds: SemanticSearchConstants.rangeMergeGapSeconds
        )

        let searchElapsed = Date().timeIntervalSince(searchStart)
        print("[SemanticIndex] Search completed. chunkHits=\(chunkHits.count) candidates=\(candidates.count) elapsed=\(String(format: "%.2f", searchElapsed))s")

        return candidates
            .sorted { $0.confidence > $1.confidence }
            .map { $0 }
    }
}

enum TemporalRangeScorer {
    static func mergeChunkHits(
        _ hits: [VectorSearchHit<VideoChunkPoint>],
        maxGapSeconds: Double
    ) -> [SemanticRangeCandidate] {
        guard !hits.isEmpty else { return [] }

        let grouped = Dictionary(grouping: hits, by: { $0.payload.videoID })
        var merged: [SemanticRangeCandidate] = []

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

            for current in sorted.dropFirst() {
                let gap = current.payload.startTimeSeconds - rangeEnd
                if gap <= maxGapSeconds {
                    rangeEnd = max(rangeEnd, current.payload.endTimeSeconds)
                    scoreSum += current.score
                    scoreCount += 1
                    peak = max(peak, current.score)
                } else {
                    let confidence = ((scoreSum / Double(scoreCount)) * 0.65) + (peak * 0.35)
                    merged.append(
                        SemanticRangeCandidate(
                            videoID: videoID,
                            videoName: videoName,
                            startTimeSeconds: rangeStart,
                            endTimeSeconds: rangeEnd,
                            confidence: confidence
                        )
                    )
                    rangeStart = current.payload.startTimeSeconds
                    rangeEnd = current.payload.endTimeSeconds
                    scoreSum = current.score
                    scoreCount = 1
                    peak = current.score
                }
            }

            let lastConfidence = ((scoreSum / Double(scoreCount)) * 0.65) + (peak * 0.35)
            merged.append(
                SemanticRangeCandidate(
                    videoID: videoID,
                    videoName: videoName,
                    startTimeSeconds: rangeStart,
                    endTimeSeconds: rangeEnd,
                    confidence: lastConfidence
                )
            )
        }

        return merged
    }
}
