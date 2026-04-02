import Foundation
import Testing
@testable import Iris_Main

struct SemanticRangeScorerTests {
    @Test
    func mergeFineFrameScores_MergesNearbyFramesIntoSingleRange() {
        let videoID = UUID()
        let points: [FineFrameScore] = [
            FineFrameScore(
                point: CoarseFramePoint(
                    videoID: videoID,
                    videoName: "ClipA",
                    videoDuration: 20,
                    timestampSeconds: 1.0
                ),
                score: 0.81
            ),
            FineFrameScore(
                point: CoarseFramePoint(
                    videoID: videoID,
                    videoName: "ClipA",
                    videoDuration: 20,
                    timestampSeconds: 1.4
                ),
                score: 0.83
            ),
            FineFrameScore(
                point: CoarseFramePoint(
                    videoID: videoID,
                    videoName: "ClipA",
                    videoDuration: 20,
                    timestampSeconds: 1.9
                ),
                score: 0.9
            ),
        ]

        let merged = TemporalRangeScorer.mergeFineFrameScores(points, maxGapSeconds: 0.6)
        #expect(merged.count == 1)
        #expect(merged[0].startTimeSeconds == 1.0)
        #expect(merged[0].endTimeSeconds == 1.9)
        #expect(merged[0].videoName == "ClipA")
    }

    @Test
    func mergeFineFrameScores_SplitsRangesWhenGapIsLarge() {
        let videoID = UUID()
        let points: [FineFrameScore] = [
            FineFrameScore(
                point: CoarseFramePoint(
                    videoID: videoID,
                    videoName: "ClipB",
                    videoDuration: 30,
                    timestampSeconds: 2.0
                ),
                score: 0.75
            ),
            FineFrameScore(
                point: CoarseFramePoint(
                    videoID: videoID,
                    videoName: "ClipB",
                    videoDuration: 30,
                    timestampSeconds: 3.0
                ),
                score: 0.76
            ),
            FineFrameScore(
                point: CoarseFramePoint(
                    videoID: videoID,
                    videoName: "ClipB",
                    videoDuration: 30,
                    timestampSeconds: 8.0
                ),
                score: 0.95
            ),
        ]

        let merged = TemporalRangeScorer.mergeFineFrameScores(points, maxGapSeconds: 0.6)
        #expect(merged.count == 3)
        #expect(merged[0].startTimeSeconds == 2.0)
        #expect(merged[1].startTimeSeconds == 3.0)
        #expect(merged[2].startTimeSeconds == 8.0)
    }
}
