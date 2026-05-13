import Foundation
import Testing
@testable import Iris_Main

struct TimelinePromptActionPreviewBuilderTests {
    @Test func splitPreviewIncludesMarkerAndFocusTime() {
        var state = TimelineState(timelineId: "t1")
        state.tracks = [Track(trackId: "track-v", timelineId: "t1", kind: .video)]
        let clip = Clip(
            clipId: "c1",
            trackId: "track-v",
            mediaId: "m1",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 0, end: 10_000_000)
        )
        state.clips = [clip]

        let action = Action.splitClip(timelineId: "t1", clipId: "c1", atTimeUs: 5_000_000)
        let preview = TimelinePromptActionPreviewBuilder.makePreview(state: state, action: action)

        #expect(preview?.kind == .split)
        #expect(preview?.splitMarkerTimeUs == 5_000_000)
        #expect(preview?.scrollFocusTimeUs == 5_000_000)
        #expect(preview?.focusClipIds == ["c1"])
    }

    @Test func trimPreviewMapsRemovedSourceToTimelineOverlays() {
        var state = TimelineState(timelineId: "t1")
        state.tracks = [Track(trackId: "track-v", timelineId: "t1", kind: .video)]
        let clip = Clip(
            clipId: "c1",
            trackId: "track-v",
            mediaId: "m1",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 1_000_000, end: 11_000_000)
        )
        state.clips = [clip]

        let action = Action.trimClip(
            timelineId: "t1",
            clipId: "c1",
            sourceRange: TimeRange(start: 3_000_000, end: 10_000_000)
        )
        let preview = TimelinePromptActionPreviewBuilder.makePreview(state: state, action: action)

        #expect(preview?.kind == .trim)
        #expect(preview?.overlayRanges.count == 1)
        let r = preview?.overlayRanges.first
        #expect(r?.timelineRange == TimeRange(start: 1_000_000, end: 4_000_000))
    }

    @Test func removeRangesPreviewMapsSourceRangesToTimeline() {
        var state = TimelineState(timelineId: "t1")
        state.tracks = [Track(trackId: "track-v", timelineId: "t1", kind: .video)]
        let clip = Clip(
            clipId: "c1",
            trackId: "track-v",
            mediaId: "m1",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 0, end: 10_000_000)
        )
        state.clips = [clip]

        let action = Action.removeClipRanges(
            timelineId: "t1",
            clipId: "c1",
            sourceRanges: [TimeRange(start: 2_000_000, end: 3_000_000)]
        )
        let preview = TimelinePromptActionPreviewBuilder.makePreview(state: state, action: action)

        #expect(preview?.kind == .removeRanges)
        #expect(preview?.overlayRanges.count == 1)
        #expect(preview?.overlayRanges.first?.timelineRange == TimeRange(start: 2_000_000, end: 3_000_000))
    }
}
