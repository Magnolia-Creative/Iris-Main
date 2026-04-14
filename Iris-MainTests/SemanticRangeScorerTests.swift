import Foundation
import Testing
@testable import Iris_Main

struct SemanticRangeScorerTests {
    @Test
    func mergeChunkHits_MergesNearbyChunksIntoSingleRange() {
        let hits: [VectorSearchHit<VideoChunkPoint>] = [
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-a",
                    videoName: "ClipA",
                    videoDuration: 20,
                    startTimeSeconds: 1.0,
                    endTimeSeconds: 2.0,
                    centerTimeSeconds: 1.5
                ),
                score: 0.81
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-a",
                    videoName: "ClipA",
                    videoDuration: 20,
                    startTimeSeconds: 2.3,
                    endTimeSeconds: 3.1,
                    centerTimeSeconds: 2.7
                ),
                score: 0.83
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-a",
                    videoName: "ClipA",
                    videoDuration: 20,
                    startTimeSeconds: 3.4,
                    endTimeSeconds: 4.0,
                    centerTimeSeconds: 3.7
                ),
                score: 0.9
            ),
        ]

        let merged = TemporalRangeScorer.mergeChunkHits(hits, maxGapSeconds: 0.6)
        #expect(merged.count == 1)
        #expect(merged[0].startTimeSeconds == 1.0)
        #expect(merged[0].endTimeSeconds == 4.0)
        #expect(merged[0].videoName == "ClipA")
    }

    @Test
    func mergeChunkHits_SplitsRangesWhenGapIsLarge() {
        let hits: [VectorSearchHit<VideoChunkPoint>] = [
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-b",
                    videoName: "ClipB",
                    videoDuration: 30,
                    startTimeSeconds: 2.0,
                    endTimeSeconds: 2.4,
                    centerTimeSeconds: 2.2
                ),
                score: 0.75
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-b",
                    videoName: "ClipB",
                    videoDuration: 30,
                    startTimeSeconds: 3.2,
                    endTimeSeconds: 3.6,
                    centerTimeSeconds: 3.4
                ),
                score: 0.76
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-b",
                    videoName: "ClipB",
                    videoDuration: 30,
                    startTimeSeconds: 8.0,
                    endTimeSeconds: 8.5,
                    centerTimeSeconds: 8.25
                ),
                score: 0.95
            ),
        ]

        let merged = TemporalRangeScorer.mergeChunkHits(hits, maxGapSeconds: 0.6)
        #expect(merged.count == 3)
        #expect(merged[0].startTimeSeconds == 2.0)
        #expect(merged[1].startTimeSeconds == 3.2)
        #expect(merged[2].startTimeSeconds == 8.0)
    }
}
