import XCTest
@testable import Iris_Main

@MainActor
final class TimelineImportCoordinatorTests: XCTestCase {
    func testBeginAddSelectionUpdatesPendingImportAndRequestsPhotosAuthorizationOnlyForPhotos() {
        var state = TimelineState(timelineId: "timeline-1")
        let coordinator = TimelineImportCoordinator()

        XCTAssertTrue(coordinator.beginAddSelection(kind: .video, source: .photos, in: &state))
        XCTAssertEqual(state.pendingImport?.kind, .video)
        XCTAssertEqual(state.pendingImport?.source, .photos)

        XCTAssertFalse(coordinator.beginAddSelection(kind: .audio, source: .files, in: &state))
        XCTAssertEqual(state.pendingImport?.kind, .audio)
        XCTAssertEqual(state.pendingImport?.source, .files)
    }

    func testInsertClipSegmentAddsClipAndReturnsBeforeAfterMutation() {
        var state = TimelineState(timelineId: "timeline-1")
        state.tracks = [Track(trackId: "track-video", timelineId: "timeline-1", kind: .video)]
        let media = Media(
            mediaId: "media-1",
            mediaLibraryId: "library-1",
            kind: .video,
            assetRefId: "asset-1",
            spec: MediaSpec(duration: 4)
        )
        state.mediaById[media.mediaId] = media
        let coordinator = TimelineImportCoordinator()

        let mutation = coordinator.insertClipSegment(
            mediaId: media.mediaId,
            sourceRange: TimeRange(start: 1_000_000, end: 2_000_000),
            at: 3_000_000,
            kind: .video,
            in: &state
        )

        XCTAssertTrue(mutation?.beforeClips.isEmpty == true)
        XCTAssertEqual(mutation?.afterClips.count, 1)
        XCTAssertEqual(state.clips.first?.mediaId, media.mediaId)
        XCTAssertEqual(state.clips.first?.timelineRange.start, 3_000_000)
    }
}
