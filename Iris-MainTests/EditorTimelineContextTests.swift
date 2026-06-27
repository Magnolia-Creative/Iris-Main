import SwiftUI
import XCTest
@testable import Iris_Main

@MainActor
final class EditorTimelineContextTests: XCTestCase {
    func testTimelineOrganizerModelUsesJITComponentSizeForNativeTracks() {
        let compressed = TimelineOrganizerModel(context: makeContext(layoutSize: .compressed))
        let standard = TimelineOrganizerModel(context: makeContext(layoutSize: .standard))
        let expanded = TimelineOrganizerModel(context: makeContext(layoutSize: .expanded))

        XCTAssertEqual(compressed.tracks.map(\.size), [.compressed])
        XCTAssertEqual(standard.tracks.map(\.size), [.standard])
        XCTAssertEqual(expanded.tracks.map(\.size), [.expanded])
    }

    private func makeContext(layoutSize: EditorComponentSize) -> EditorTimelineContext {
        var currentTimeUs: Int64 = 0
        var scrollTargetTimeUs: Int64?
        var selectedClipId: String?
        var selectedCaptionCueId: String?
        var isAddMenuOpen = false

        return EditorTimelineContext(
            tracks: [Track(trackId: "track-v", timelineId: "timeline-1", kind: .video)],
            clipsByTrackId: [:],
            mediaById: [:],
            captionGroups: [],
            captionCues: [],
            layoutSize: layoutSize,
            pixelsPerSecond: 100,
            timelineDurationUs: 4_000_000,
            scrollableDurationUs: 4_000_000,
            playbackState: .idle,
            reviewFocusedClipIds: [],
            isReviewInteractionDisabled: false,
            captionHighlightRangeUs: nil,
            playheadTint: Color.ds.text,
            showAddButton: true,
            currentTimeAtCenter: Binding(get: { currentTimeUs }, set: { currentTimeUs = $0 }),
            scrollTargetTimeUs: Binding(get: { scrollTargetTimeUs }, set: { scrollTargetTimeUs = $0 }),
            selectedClipId: Binding(get: { selectedClipId }, set: { selectedClipId = $0 }),
            selectedCaptionCueId: Binding(get: { selectedCaptionCueId }, set: { selectedCaptionCueId = $0 }),
            isAddMenuOpen: Binding(get: { isAddMenuOpen }, set: { isAddMenuOpen = $0 })
        )
    }
}
