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

    @Test
    func mergeChunkHitGroups_TracksChunksUsedToBuildMergedRange() {
        let hits: [VectorSearchHit<VideoChunkPoint>] = [
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-c",
                    videoName: "ClipC",
                    videoDuration: 30,
                    startTimeSeconds: 10.0,
                    endTimeSeconds: 14.0,
                    centerTimeSeconds: 12.0
                ),
                score: 0.82
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-c",
                    videoName: "ClipC",
                    videoDuration: 30,
                    startTimeSeconds: 14.3,
                    endTimeSeconds: 18.3,
                    centerTimeSeconds: 16.3
                ),
                score: 0.87
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-c",
                    videoName: "ClipC",
                    videoDuration: 30,
                    startTimeSeconds: 23.0,
                    endTimeSeconds: 27.0,
                    centerTimeSeconds: 25.0
                ),
                score: 0.91
            ),
        ]

        let groups = TemporalRangeScorer.mergeChunkHitGroups(hits, maxGapSeconds: 0.6)

        #expect(groups.count == 2)
        #expect(groups[0].chunkHits.count == 2)
        #expect(groups[0].candidate.startTimeSeconds == 10.0)
        #expect(groups[0].candidate.endTimeSeconds == 18.3)
        #expect(abs(groups[0].averageScore - 0.845) < 0.0001)
        #expect(groups[0].peakScore == 0.87)
        #expect(groups[1].chunkHits.count == 1)
        #expect(groups[1].candidate.startTimeSeconds == 23.0)
        #expect(groups[1].candidate.endTimeSeconds == 27.0)
    }

    @Test
    func mergeChunkHitGroups_IgnoresChunksAtOrBelowMinimumScoreForStitching() {
        let hits: [VectorSearchHit<VideoChunkPoint>] = [
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-d",
                    videoName: "ClipD",
                    videoDuration: 30,
                    startTimeSeconds: 0.0,
                    endTimeSeconds: 4.0,
                    centerTimeSeconds: 2.0
                ),
                score: 0.21
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-d",
                    videoName: "ClipD",
                    videoDuration: 30,
                    startTimeSeconds: 3.5,
                    endTimeSeconds: 7.5,
                    centerTimeSeconds: 5.5
                ),
                score: 0.14
            ),
            VectorSearchHit(
                payload: VideoChunkPoint(
                    videoID: "clip-d",
                    videoName: "ClipD",
                    videoDuration: 30,
                    startTimeSeconds: 7.0,
                    endTimeSeconds: 11.0,
                    centerTimeSeconds: 9.0
                ),
                score: 0.22
            ),
        ]

        let groups = TemporalRangeScorer.mergeChunkHitGroups(
            hits,
            maxGapSeconds: 0.6,
            minimumScore: 0.15
        )

        #expect(groups.count == 2)
        #expect(groups[0].chunkHits.count == 1)
        #expect(groups[0].candidate.startTimeSeconds == 0.0)
        #expect(groups[0].candidate.endTimeSeconds == 4.0)
        #expect(groups[1].chunkHits.count == 1)
        #expect(groups[1].candidate.startTimeSeconds == 7.0)
        #expect(groups[1].candidate.endTimeSeconds == 11.0)
    }
}
