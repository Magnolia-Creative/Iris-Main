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

    func testTimelineOrganizerModelConvertsClipAndCaptionTracks() {
        let videoTrack = Track(trackId: "track-v", timelineId: "timeline-1", kind: .video)
        let captionTrack = Track(trackId: "track-c", timelineId: "timeline-1", kind: .captions)
        let media = Media(
            mediaId: "media-v",
            mediaLibraryId: "library-1",
            kind: .video,
            assetRefId: "asset-v",
            spec: MediaSpec(
                duration: 8,
                width: nil,
                height: nil,
                thumbnailStripPath: "thumbs/v.jpg",
                thumbnailStripHeight: nil,
                thumbnailStripFrameCount: nil,
                waveformPath: "waves/v.png",
                waveformHeight: nil,
                transcriptID: nil,
                transcriptFullText: nil,
                transcriptSentences: nil,
                clipUploadLocalKey: nil
            )
        )
        let laterClip = Clip(
            clipId: "clip-b",
            trackId: videoTrack.trackId,
            mediaId: media.mediaId,
            sourceRange: TimeRange(start: 4_000_000, end: 6_000_000),
            timelineRange: TimeRange(start: 3_000_000, end: 5_000_000)
        )
        let earlierClip = Clip(
            clipId: "clip-a",
            trackId: videoTrack.trackId,
            mediaId: media.mediaId,
            sourceRange: TimeRange(start: 0, end: 2_000_000),
            timelineRange: TimeRange(start: 1_000_000, end: 3_000_000)
        )
        let captionGroup = CaptionGroup(
            groupId: "caption-group",
            trackId: captionTrack.trackId,
            timelineId: "timeline-1"
        )
        let laterCue = CaptionCue(
            cueId: "cue-b",
            groupId: captionGroup.groupId,
            text: "world",
            timelineStartUs: 2_000_000,
            timelineEndUs: 3_000_000,
            sourceStartUs: 20_000,
            sourceEndUs: 30_000
        )
        let earlierCue = CaptionCue(
            cueId: "cue-a",
            groupId: captionGroup.groupId,
            text: "hello",
            timelineStartUs: 500_000,
            timelineEndUs: 1_500_000,
            sourceStartUs: 5_000,
            sourceEndUs: 15_000
        )
        let orphanCue = CaptionCue(
            cueId: "cue-orphan",
            groupId: "other-group",
            text: "ignored",
            timelineStartUs: 0,
            timelineEndUs: 100_000
        )

        let model = TimelineOrganizerModel(
            context: makeContext(
                tracks: [videoTrack, captionTrack],
                clipsByTrackId: [videoTrack.trackId: [laterClip, earlierClip]],
                mediaById: [media.mediaId: media],
                captionGroups: [captionGroup],
                captionCues: [laterCue, orphanCue, earlierCue],
                layoutSize: .expanded
            )
        )

        XCTAssertEqual(model.tracks.map(\.id), [videoTrack.trackId, captionTrack.trackId])
        XCTAssertEqual(model.tracks.map(\.kind), [.video, .caption])
        XCTAssertEqual(model.tracks.map(\.size), [.expanded, .expanded])

        let videoSegments = model.tracks[0].segments
        XCTAssertEqual(videoSegments.map(\.id), ["clip-a", "clip-b"])
        XCTAssertEqual(videoSegments[0].rangeUs, earlierClip.timelineRange)
        XCTAssertEqual(videoSegments[0].sourceRangeUs, earlierClip.sourceRange)
        XCTAssertEqual(videoSegments[0].mediaKind, .video)
        XCTAssertEqual(videoSegments[0].assetRefId, "asset-v")
        XCTAssertEqual(videoSegments[0].mediaDurationSeconds, 8)
        XCTAssertEqual(videoSegments[0].thumbnailStripPath, "thumbs/v.jpg")
        XCTAssertEqual(videoSegments[0].waveformPath, "waves/v.png")

        let captionSegments = model.tracks[1].segments
        XCTAssertEqual(captionSegments.map(\.id), ["cue-a", "cue-b"])
        XCTAssertEqual(captionSegments.map(\.captionText), ["hello", "world"])
        XCTAssertEqual(captionSegments[0].rangeUs, TimeRange(start: 500_000, end: 1_500_000))
        XCTAssertEqual(captionSegments[0].sourceRangeUs, TimeRange(start: 5_000, end: 15_000))
    }

    func testTimelineOrganizerModelPropagatesTimingAndScale() {
        let model = TimelineOrganizerModel(
            context: makeContext(
                pixelsPerSecond: 144,
                timelineDurationUs: 58_000_000,
                scrollableDurationUs: 61_000_000,
                currentTimeUs: 12_345_678
            )
        )

        XCTAssertEqual(model.durationUs, 58_000_000)
        XCTAssertEqual(model.scrollableDurationUs, 61_000_000)
        XCTAssertEqual(model.currentTimeUs, 12_345_678)
        XCTAssertEqual(model.pixelsPerSecond, 144)
    }

    func testTimelineContextBindingsBridgeJITSurfaceState() {
        var currentTimeUs: Int64 = 1_000_000
        var scrollTargetTimeUs: Int64?
        var selectedClipId: String?
        var selectedCaptionCueId: String?
        var isAddMenuOpen = false

        var context = makeContext(
            currentTimeAtCenter: Binding(
                get: { currentTimeUs },
                set: { currentTimeUs = $0 }
            ),
            scrollTargetTimeUs: Binding(
                get: { scrollTargetTimeUs },
                set: { scrollTargetTimeUs = $0 }
            ),
            selectedClipId: Binding(
                get: { selectedClipId },
                set: { selectedClipId = $0 }
            ),
            selectedCaptionCueId: Binding(
                get: { selectedCaptionCueId },
                set: { selectedCaptionCueId = $0 }
            ),
            isAddMenuOpen: Binding(
                get: { isAddMenuOpen },
                set: { isAddMenuOpen = $0 }
            )
        )

        context.currentTimeAtCenter = 2_500_000
        context.scrollTargetTimeUs = 3_000_000
        context.selectedClipId = "clip-a"
        context.selectedCaptionCueId = "cue-a"
        context.isAddMenuOpen = true

        XCTAssertEqual(currentTimeUs, 2_500_000)
        XCTAssertEqual(scrollTargetTimeUs, 3_000_000)
        XCTAssertEqual(selectedClipId, "clip-a")
        XCTAssertEqual(selectedCaptionCueId, "cue-a")
        XCTAssertTrue(isAddMenuOpen)
    }

    private func makeContext(
        tracks: [Track] = [Track(trackId: "track-v", timelineId: "timeline-1", kind: .video)],
        clipsByTrackId: [String: [Clip]] = [:],
        mediaById: [String: Media] = [:],
        captionGroups: [CaptionGroup] = [],
        captionCues: [CaptionCue] = [],
        layoutSize: EditorComponentSize = .standard,
        pixelsPerSecond: CGFloat = 100,
        timelineDurationUs: Int64 = 4_000_000,
        scrollableDurationUs: Int64 = 4_000_000,
        currentTimeUs: Int64 = 0,
        currentTimeAtCenter: Binding<Int64>? = nil,
        scrollTargetTimeUs: Binding<Int64?>? = nil,
        selectedClipId: Binding<String?>? = nil,
        selectedCaptionCueId: Binding<String?>? = nil,
        isAddMenuOpen: Binding<Bool>? = nil
    ) -> EditorTimelineContext {
        var currentTimeUs = currentTimeUs
        var localScrollTargetTimeUs: Int64?
        var localSelectedClipId: String?
        var localSelectedCaptionCueId: String?
        var localIsAddMenuOpen = false

        return EditorTimelineContext(
            tracks: tracks,
            clipsByTrackId: clipsByTrackId,
            mediaById: mediaById,
            captionGroups: captionGroups,
            captionCues: captionCues,
            layoutSize: layoutSize,
            pixelsPerSecond: pixelsPerSecond,
            timelineDurationUs: timelineDurationUs,
            scrollableDurationUs: scrollableDurationUs,
            playbackState: .idle,
            reviewFocusedClipIds: [],
            isReviewInteractionDisabled: false,
            captionHighlightRangeUs: nil,
            playheadTint: Color.ds.text,
            showAddButton: true,
            currentTimeAtCenter: currentTimeAtCenter ?? Binding(get: { currentTimeUs }, set: { currentTimeUs = $0 }),
            scrollTargetTimeUs: scrollTargetTimeUs ?? Binding(get: { localScrollTargetTimeUs }, set: { localScrollTargetTimeUs = $0 }),
            selectedClipId: selectedClipId ?? Binding(get: { localSelectedClipId }, set: { localSelectedClipId = $0 }),
            selectedCaptionCueId: selectedCaptionCueId ?? Binding(get: { localSelectedCaptionCueId }, set: { localSelectedCaptionCueId = $0 }),
            isAddMenuOpen: isAddMenuOpen ?? Binding(get: { localIsAddMenuOpen }, set: { localIsAddMenuOpen = $0 })
        )
    }
}
