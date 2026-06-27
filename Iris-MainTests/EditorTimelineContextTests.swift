import SwiftUI
import XCTest
@testable import Iris_Main

@MainActor
final class EditorTimelineContextTests: XCTestCase {
    func testTimelineSurfaceUsesCompressedLayoutOnlyForCompressedJITSize() {
        XCTAssertEqual(TimelineSurfaceComponent.timelineLayout(for: .compressed), .compressed)
        XCTAssertEqual(TimelineSurfaceComponent.timelineLayout(for: .standard), .expanded)
        XCTAssertEqual(TimelineSurfaceComponent.timelineLayout(for: .expanded), .expanded)
    }

    func testTimelineContextCarriesPromptActionPreview() {
        var currentTimeUs: Int64 = 0
        var scrollTargetTimeUs: Int64?
        var selectedClipId: String?
        var selectedCaptionCueId: String?
        var isAddMenuOpen = false

        let preview = TimelinePromptActionPreview(
            kind: .split,
            title: "Split clip",
            subtitle: nil,
            focusClipIds: ["clip-1"],
            overlayRanges: [],
            splitMarkerTimeUs: 2_000_000,
            scrollFocusTimeUs: 2_000_000
        )

        let context = EditorTimelineContext(
            tracks: [],
            clipsByTrackId: [:],
            mediaById: [:],
            captionGroups: [],
            captionCues: [],
            layoutSize: .standard,
            pixelsPerSecond: 100,
            timelineDurationUs: 4_000_000,
            scrollableDurationUs: 4_000_000,
            playbackState: .idle,
            reviewFocusedClipIds: [],
            isReviewInteractionDisabled: false,
            promptActionPreview: preview,
            captionHighlightRangeUs: nil,
            playheadTint: Color.ds.text,
            showAddButton: true,
            currentTimeAtCenter: Binding(get: { currentTimeUs }, set: { currentTimeUs = $0 }),
            scrollTargetTimeUs: Binding(get: { scrollTargetTimeUs }, set: { scrollTargetTimeUs = $0 }),
            selectedClipId: Binding(get: { selectedClipId }, set: { selectedClipId = $0 }),
            selectedCaptionCueId: Binding(get: { selectedCaptionCueId }, set: { selectedCaptionCueId = $0 }),
            isAddMenuOpen: Binding(get: { isAddMenuOpen }, set: { isAddMenuOpen = $0 })
        )

        XCTAssertEqual(context.promptActionPreview, preview)
    }
}
