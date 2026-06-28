import XCTest
@testable import Iris_Main

final class TimelineEditingServiceTests: XCTestCase {
    func testApplyActionsReturnsBeforeAfterSnapshotAndInverseActions() {
        var state = makeState()
        let service = TimelineEditingService()

        let application = service.applyActions(
            [Action.removeClip(timelineId: "timeline-1", clipId: "clip-1")],
            to: &state
        )

        XCTAssertEqual(application?.snapshot.beforeClips.map(\.clipId), ["clip-1"])
        XCTAssertTrue(application?.snapshot.afterClips.isEmpty == true)
        XCTAssertEqual(application?.inverseActions.count, 1)
        XCTAssertTrue(state.clips.isEmpty)
        XCTAssertTrue(state.canUndo)
    }

    func testUndoRedoReturnMutationSnapshots() {
        var state = makeState()
        let service = TimelineEditingService()
        _ = service.applyActions(
            [Action.removeClip(timelineId: "timeline-1", clipId: "clip-1")],
            to: &state
        )

        let undo = service.undoLastActionGroup(in: &state)
        XCTAssertTrue(undo?.snapshotRemovedAllClips == true)
        XCTAssertEqual(state.clips.map(\.clipId), ["clip-1"])
        XCTAssertTrue(state.canRedo)

        let redo = service.redoLastActionGroup(in: &state)
        XCTAssertEqual(redo?.beforeClips.map(\.clipId), ["clip-1"])
        XCTAssertTrue(redo?.afterClips.isEmpty == true)
        XCTAssertTrue(state.clips.isEmpty)
    }

    private func makeState() -> TimelineState {
        var state = TimelineState(timelineId: "timeline-1")
        state.tracks = [Track(trackId: "track-video", timelineId: "timeline-1", kind: .video)]
        state.clips = [
            Clip(
                clipId: "clip-1",
                trackId: "track-video",
                mediaId: "media-1",
                sourceRange: TimeRange(start: 0, end: 1_000_000),
                timelineRange: TimeRange(start: 0, end: 1_000_000)
            )
        ]
        return state
    }
}

private extension TimelineEditingService.MutationSnapshot {
    var snapshotRemovedAllClips: Bool {
        beforeClips.map(\.clipId) == [] && afterClips.map(\.clipId) == ["clip-1"]
    }
}
