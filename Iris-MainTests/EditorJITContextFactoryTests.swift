import XCTest
@testable import Iris_Main

@MainActor
final class EditorJITContextFactoryTests: XCTestCase {
    func testFocusedTimelinePresentationFiltersTracksAndClips() {
        let videoTrack = Track(trackId: "track-video", timelineId: "timeline-1", kind: .video)
        let audioTrack = Track(trackId: "track-audio", timelineId: "timeline-1", kind: .audio)
        var state = TimelineState(timelineId: "timeline-1")
        state.tracks = [videoTrack, audioTrack]
        state.clips = [
            Clip(
                clipId: "clip-keep",
                trackId: videoTrack.trackId,
                mediaId: "media-video",
                sourceRange: TimeRange(start: 0, end: 1_000_000),
                timelineRange: TimeRange(start: 0, end: 1_000_000)
            ),
            Clip(
                clipId: "clip-drop",
                trackId: videoTrack.trackId,
                mediaId: "media-video",
                sourceRange: TimeRange(start: 1_000_000, end: 2_000_000),
                timelineRange: TimeRange(start: 1_000_000, end: 2_000_000)
            ),
            Clip(
                clipId: "clip-audio",
                trackId: audioTrack.trackId,
                mediaId: "media-audio",
                sourceRange: TimeRange(start: 0, end: 1_000_000),
                timelineRange: TimeRange(start: 0, end: 1_000_000)
            )
        ]

        let factory = makeFactory(reviewFocusedClipIds: ["clip-keep"])
        let tracks = factory.displayTracks(state: state, presentation: .focusedClipStrip)
        let clipsByTrack = factory.clipsByTrackId(state: state, presentation: .focusedClipStrip)

        XCTAssertFalse(tracks.contains { $0.kind == .audio })
        XCTAssertTrue(tracks.contains { $0.kind == .video })
        XCTAssertTrue(tracks.contains { $0.kind == .captions })
        XCTAssertEqual(clipsByTrack[videoTrack.trackId]?.map(\.clipId), ["clip-keep"])
        XCTAssertNil(clipsByTrack[audioTrack.trackId])
    }

    func testPlaybackPreviewSizeFollowsActiveSpace() {
        XCTAssertEqual(makeFactory(activeSpace: .importMedia).previewComponentSize, .compressed)
        XCTAssertEqual(makeFactory(activeSpace: .edit).previewComponentSize, .standard)
        XCTAssertEqual(makeFactory(activeSpace: .export).previewComponentSize, .standard)
    }

    func testTimelineAddSelectionRequiresExpandedEditableTimeline() {
        let fallback: (TrackKind, ImportSource) -> Void = { _, _ in }

        XCTAssertNotNil(makeFactory(activeSpace: .edit).timelineAddSelection(layout: .expanded, fallback: fallback))
        XCTAssertNil(makeFactory(activeSpace: .edit).timelineAddSelection(layout: .compressed, fallback: fallback))
        XCTAssertNil(makeFactory(activeSpace: .importMedia).timelineAddSelection(layout: .expanded, fallback: fallback))
        XCTAssertNil(makeFactory(activeSpace: .edit, isReviewInteractionDisabled: true).timelineAddSelection(layout: .expanded, fallback: fallback))
    }

    private func makeFactory(
        activeSpace: EditorSpace = .edit,
        reviewFocusedClipIds: Set<String> = [],
        isReviewInteractionDisabled: Bool = false
    ) -> EditorJITContextFactory {
        EditorJITContextFactory(
            activeSpace: activeSpace,
            reviewFocusedClipIds: reviewFocusedClipIds,
            isReviewInteractionDisabled: isReviewInteractionDisabled,
            promptActionPreview: nil,
            onAddSelection: nil
        )
    }
}
