import Foundation

struct SemanticSearchConstants {
    static let coarseStepSeconds = 2.0
    static let fineFramesPerSecond = 5.0
    static let coarseTopK = 10
    static let resultsLimit = 3
    static let coarseWindowHalfWidth = 2.0
    static let rangeMergeGapSeconds = 0.6
}

struct CoarseFramePoint: Hashable {
    let videoID: SemanticImportedVideo.ID
    let videoName: String
    let videoDuration: Double
    let timestampSeconds: Double
}

struct FineFrameScore {
    let point: CoarseFramePoint
    let score: Double
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

    private var coarseIndex = LocalVectorIndex<CoarseFramePoint>()
    private var coarseFrameCount = 0

    init(
        embeddingService: MobileCLIPEmbeddingProviding = MobileCLIPEmbeddingService(),
        frameSampler: VideoFrameSampler = VideoFrameSampler()
    ) {
        self.embeddingService = embeddingService
        self.frameSampler = frameSampler
    }

    var indexedFrameCount: Int {
        coarseFrameCount
    }

    func reset() {
        coarseIndex.reset()
        coarseFrameCount = 0
    }

    func buildCoarseIndex(
        videos: [SemanticImportedVideo],
        onProgress: @escaping @Sendable (String) async -> Void
    ) async throws {
        reset()
        guard !videos.isEmpty else { return }
        print("[SemanticIndex] buildCoarseIndex called with \(videos.count) video(s)")

        var index = LocalVectorIndex<CoarseFramePoint>()
        var totalFrames = 0

        for (videoIndex, video) in videos.enumerated() {
            print("[SemanticIndex] Sampling coarse frames for video \(videoIndex + 1)/\(videos.count): \(video.displayName), duration=\(video.durationSeconds)s")
            await onProgress("Indexing \(video.displayName) (\(videoIndex + 1)/\(videos.count))...")
            let frames = try await frameSampler.sampleFrames(
                videoURL: video.fileURL,
                startTime: 0,
                endTime: video.durationSeconds,
                stepSeconds: SemanticSearchConstants.coarseStepSeconds
            )
            print("[SemanticIndex] Sampled \(frames.count) coarse frame(s) for \(video.displayName)")

            for frame in frames {
                do {
                    let embedding = try await embeddingService.imageEmbedding(for: frame.image)
                    index.add(
                        vector: embedding,
                        payload: CoarseFramePoint(
                            videoID: video.id,
                            videoName: video.displayName,
                            videoDuration: video.durationSeconds,
                            timestampSeconds: frame.timestampSeconds
                        )
                    )
                    totalFrames += 1
                } catch {
                    print("[SemanticIndex] Embedding failed for video=\(video.displayName) timestamp=\(frame.timestampSeconds)s error=\(error)")
                    throw error
                }
            }
            print("[SemanticIndex] Finished video \(video.displayName). runningFrameTotal=\(totalFrames)")
        }

        coarseIndex = index
        coarseFrameCount = totalFrames
        print("[SemanticIndex] Coarse index finalized. totalFrames=\(totalFrames)")
        await onProgress("Coarse index ready with \(totalFrames) sampled frames.")
    }

    func search(query: String, videos: [SemanticImportedVideo]) async throws -> [SemanticRangeCandidate] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard !videos.isEmpty else { return [] }
        guard coarseFrameCount > 0 else { return [] }

        let queryVector = try await embeddingService.textEmbedding(for: query)
        let coarseHits = coarseIndex.topK(query: queryVector, limit: SemanticSearchConstants.coarseTopK)
        guard !coarseHits.isEmpty else { return [] }

        let videoLookup = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        var fineScores: [FineFrameScore] = []

        for hit in coarseHits {
            guard let video = videoLookup[hit.payload.videoID] else { continue }
            let windowStart = max(0, hit.payload.timestampSeconds - SemanticSearchConstants.coarseWindowHalfWidth)
            let windowEnd = min(video.durationSeconds, hit.payload.timestampSeconds + SemanticSearchConstants.coarseWindowHalfWidth)
            let fineStep = 1.0 / SemanticSearchConstants.fineFramesPerSecond

            let fineFrames = try await frameSampler.sampleFrames(
                videoURL: video.fileURL,
                startTime: windowStart,
                endTime: windowEnd,
                stepSeconds: fineStep
            )

            for frame in fineFrames {
                let imageVector = try await embeddingService.imageEmbedding(for: frame.image)
                let score = cosineSimilarity(queryVector, imageVector)
                fineScores.append(
                    FineFrameScore(
                        point: CoarseFramePoint(
                            videoID: video.id,
                            videoName: video.displayName,
                            videoDuration: video.durationSeconds,
                            timestampSeconds: frame.timestampSeconds
                        ),
                        score: score
                    )
                )
            }
        }

        let candidates = TemporalRangeScorer.mergeFineFrameScores(
            fineScores,
            maxGapSeconds: SemanticSearchConstants.rangeMergeGapSeconds
        )

        return candidates
            .sorted { $0.confidence > $1.confidence }
            .prefix(SemanticSearchConstants.resultsLimit)
            .map { $0 }
    }
}

enum TemporalRangeScorer {
    static func mergeFineFrameScores(
        _ scores: [FineFrameScore],
        maxGapSeconds: Double
    ) -> [SemanticRangeCandidate] {
        guard !scores.isEmpty else { return [] }

        let grouped = Dictionary(grouping: scores, by: { $0.point.videoID })
        var merged: [SemanticRangeCandidate] = []

        for videoScores in grouped.values {
            let sorted = videoScores.sorted { $0.point.timestampSeconds < $1.point.timestampSeconds }
            guard let first = sorted.first else { continue }

            var rangeStart = first.point.timestampSeconds
            var rangeEnd = first.point.timestampSeconds
            var scoreSum = first.score
            var scoreCount = 1
            var peak = first.score
            let videoName = first.point.videoName
            let videoID = first.point.videoID

            for current in sorted.dropFirst() {
                let gap = current.point.timestampSeconds - rangeEnd
                if gap <= maxGapSeconds {
                    rangeEnd = current.point.timestampSeconds
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
                    rangeStart = current.point.timestampSeconds
                    rangeEnd = current.point.timestampSeconds
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
