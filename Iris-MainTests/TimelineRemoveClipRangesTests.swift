import Foundation
import Testing
@testable import Iris_Main

struct TimelineRemoveClipRangesTests {
    @Test func appliesInteriorRangeRemovalAsPackedSurvivorClips() {
        var state = TimelineState(timelineId: "timeline-test")
        state.tracks = [Track(trackId: "track-video", timelineId: "timeline-test", kind: .video)]
        state.clips = [
            Clip(
                clipId: "clip-b",
                trackId: "track-video",
                mediaId: "media-b",
                sourceRange: TimeRange(start: 0, end: 10_000_000),
                timelineRange: TimeRange(start: 0, end: 10_000_000)
            )
        ]

        let inverse = state.apply([
            Action.removeClipRanges(
                timelineId: "timeline-test",
                clipId: "clip-b",
                sourceRanges: [TimeRange(start: 2_000_000, end: 3_000_000)]
            )
        ])

        let clips = state.orderedClips(for: "track-video")
        #expect(clips.map { [$0.sourceRange.start, $0.sourceRange.end] } == [
            [0, 2_000_000],
            [3_000_000, 10_000_000]
        ])
        #expect(clips.map { [$0.timelineRange.start, $0.timelineRange.end] } == [
            [0, 2_000_000],
            [2_000_000, 9_000_000]
        ])
        #expect(inverse.count == 1)
        guard case .replaceTrackClips(let trackId, let replacement) = inverse.first?.payload else {
            Issue.record("Expected replaceTrackClips inverse")
            return
        }
        #expect(trackId == "track-video")
        #expect(replacement.map(\.clipId) == ["clip-b"])
    }

    @Test func validatorRejectsOutOfSourceRemovalRange() {
        let clip = Clip(
            clipId: "clip-b",
            trackId: "track-video",
            mediaId: "media-b",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 0, end: 10_000_000)
        )
        let context = IntentCompilerContext(
            timelineId: "timeline-test",
            selectedClipId: "clip-b",
            selectedTrackId: "track-video",
            selectedRange: nil,
            playheadTimeUs: nil,
            clipsById: ["clip-b": clip],
            orderedClipIdsByTrackId: ["track-video": ["clip-b"]]
        )
        let result = IntentCompileResult(
            actions: [
                Action.removeClipRanges(
                    timelineId: "timeline-test",
                    clipId: "clip-b",
                    sourceRanges: [TimeRange(start: 9_000_000, end: 12_000_000)]
                )
            ],
            confidence: 0.9,
            source: .llm,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )

        #expect(IntentActionValidator().isExecutable(result, context: context) == false)
    }
}
