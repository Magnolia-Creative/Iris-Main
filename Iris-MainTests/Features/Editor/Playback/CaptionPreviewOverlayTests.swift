import CoreGraphics
import Testing
@testable import Iris_Main

struct CaptionPreviewOverlayTests {
    @Test func fitsLandscapeAspectInsidePreviewContainer() {
        let rect = PreviewAspectLayout.fittedRect(
            in: CGSize(width: 300, height: 220),
            aspect: 16.0 / 9.0
        )

        #expect(abs(rect.width - 300) < 0.001)
        #expect(abs(rect.height - 168.75) < 0.001)
        #expect(abs(rect.minX) < 0.001)
        #expect(abs(rect.minY - 25.625) < 0.001)
    }

    @Test func fitsPortraitAspectInsidePreviewContainer() {
        let rect = PreviewAspectLayout.fittedRect(
            in: CGSize(width: 300, height: 220),
            aspect: 9.0 / 16.0
        )

        #expect(abs(rect.width - 123.75) < 0.001)
        #expect(abs(rect.height - 220) < 0.001)
        #expect(abs(rect.minX - 88.125) < 0.001)
        #expect(abs(rect.minY) < 0.001)
    }

    @Test func fitsSquareAspectInsidePreviewContainer() {
        let rect = PreviewAspectLayout.fittedRect(
            in: CGSize(width: 300, height: 220),
            aspect: 1
        )

        #expect(abs(rect.width - 220) < 0.001)
        #expect(abs(rect.height - 220) < 0.001)
        #expect(abs(rect.minX - 40) < 0.001)
        #expect(abs(rect.minY) < 0.001)
    }

    @Test func resolvesActiveCueUsingProjectedClipRange() throws {
        let group = CaptionGroup(
            groupId: "group",
            trackId: "captions",
            timelineId: "timeline",
            style: .modern,
            hasBackground: true,
            textColor: "#FFFFFF"
        )
        let clip = Clip(
            clipId: "clip",
            trackId: "video",
            mediaId: "media",
            sourceRange: TimeRange(start: 5_000_000, end: 10_000_000),
            timelineRange: TimeRange(start: 0, end: 5_000_000)
        )
        let cue = CaptionCue(
            cueId: "cue",
            groupId: group.groupId,
            clipId: clip.clipId,
            text: "projected caption",
            timelineStartUs: 99_000_000,
            timelineEndUs: 100_000_000,
            sourceStartUs: 6_000_000,
            sourceEndUs: 7_000_000
        )

        let active = try #require(CaptionPreviewResolver.activeCue(
            at: 1_500_000,
            groups: [group],
            cues: [cue],
            clips: [clip]
        ))

        #expect(active.id == cue.cueId)
        #expect(active.text == "projected caption")
        #expect(active.position == CaptionPreviewResolver.defaultPosition)
        #expect(CaptionPreviewResolver.activeCue(
            at: 500_000,
            groups: [group],
            cues: [cue],
            clips: [clip]
        ) == nil)
    }
}
