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

    func testBuildsSelectedClipEditActions() {
        var state = makeState()
        state.selectedClipId = "clip-1"
        state.currentTimeAtCenter = 500_000
        let service = TimelineEditingService()

        XCTAssertEqual(service.deleteSelectedClipActions(in: state)?.count, 1)
        XCTAssertEqual(service.splitSelectedClipActions(in: state)?.count, 1)

        let colorActions = service.setClipColorFilterActions(
            clipId: "clip-1",
            filter: ClipColorFilter(temperature: 0.4),
            in: state
        )
        guard case .setClipColorFilter = colorActions?.first?.payload else {
            XCTFail("Expected setClipColorFilter action")
            return
        }

        let resetActions = service.setClipColorFilterActions(
            clipId: "clip-1",
            filter: .neutral,
            in: state
        )
        guard case .resetClipColorFilter = resetActions?.first?.payload else {
            XCTFail("Expected resetClipColorFilter action")
            return
        }
    }

    func testSetClipVolumeMutatesEffectsAndDeduplicatesExistingVolumeEffects() {
        var state = makeState()
        let service = TimelineEditingService()
        var older = Effect.clipVolume(
            timelineId: "timeline-1",
            clipId: "clip-1",
            volume: ClipVolume(gain: 0.8),
            effectId: "older",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        older.updatedAt = Date(timeIntervalSince1970: 1)
        var newer = Effect.clipVolume(
            timelineId: "timeline-1",
            clipId: "clip-1",
            volume: ClipVolume(gain: 0.9),
            effectId: "newer",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        state.effects = [older, newer]

        let mutation = service.setClipVolume(
            clipId: "clip-1",
            volume: ClipVolume(gain: 1.2),
            in: &state
        )

        XCTAssertEqual(state.effects.map(\.effectId), ["newer"])
        XCTAssertEqual(service.clipVolume(for: "clip-1", in: state), ClipVolume(gain: 1.2))
        XCTAssertEqual(mutation?.updated.map(\.effectId), ["newer"])
        XCTAssertEqual(mutation?.deletedIds, ["older"])
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
