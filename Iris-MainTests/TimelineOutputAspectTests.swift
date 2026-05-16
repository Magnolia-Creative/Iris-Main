import CoreGraphics
import Testing
@testable import Iris_Main

struct TimelineOutputAspectTests {
    @Test func emptyTimelineHasNoDerivedAspect() {
        let aspect = TimelineState.computeDerivedOutputAspect(
            clips: [],
            tracks: [],
            mediaById: [:]
        )

        #expect(aspect == nil)
    }

    @Test func earliestVisualClipDrivesDerivedAspect() {
        let videoTrack = Track(trackId: "video-track", kind: .video)
        let audioTrack = Track(trackId: "audio-track", kind: .audio)
        let overlayTrack = Track(trackId: "overlay-track", kind: .overlay)
        let earlyAudio = makeClip(id: "audio", trackId: audioTrack.trackId, mediaId: "audio", start: 0)
        let laterVideo = makeClip(id: "video-b", trackId: videoTrack.trackId, mediaId: "video-b", start: 2_000_000)
        let earlierOverlay = makeClip(id: "overlay-a", trackId: overlayTrack.trackId, mediaId: "overlay-a", start: 1_000_000)

        let aspect = TimelineState.computeDerivedOutputAspect(
            clips: [laterVideo, earlyAudio, earlierOverlay],
            tracks: [videoTrack, audioTrack, overlayTrack],
            mediaById: [
                "audio": makeMedia(id: "audio", kind: .audio, width: 999, height: 999),
                "video-b": makeMedia(id: "video-b", kind: .video, width: 1920, height: 1080),
                "overlay-a": makeMedia(id: "overlay-a", kind: .photo, width: 1620, height: 1080),
            ]
        )

        #expect(aspect == OutputAspectRatio(width: 1620, height: 1080))
    }

    @Test func manualAspectOverridesDerivedAspect() {
        var state = TimelineState(timelineId: "timeline")
        state.derivedOutputAspect = OutputAspectRatio(width: 16, height: 9)

        #expect(state.effectiveOutputAspect == OutputAspectRatio(width: 16, height: 9))

        state.manualOutputAspect = OutputAspectRatio(width: 9, height: 16)

        #expect(state.effectiveOutputAspect == OutputAspectRatio(width: 9, height: 16))
    }

    @Test func portraitPixelSizeUsesLongSide() {
        let size = OutputAspectRatio(width: 9, height: 16).pixelSize(longSide: 1920)

        #expect(size == CGSize(width: 1080, height: 1920))
    }

    private func makeClip(id: String, trackId: String, mediaId: String, start: Int64) -> Clip {
        Clip(
            clipId: id,
            trackId: trackId,
            mediaId: mediaId,
            sourceRange: TimeRange(start: 0, end: 1_000_000),
            timelineRange: TimeRange(start: start, end: start + 1_000_000)
        )
    }

    private func makeMedia(id: String, kind: MediaKind, width: Int, height: Int) -> Media {
        var spec = MediaSpec()
        spec.duration = 1
        spec.width = width
        spec.height = height
        Media(
            mediaId: id,
            mediaLibraryId: "library",
            kind: kind,
            assetRefId: "asset-\(id)",
            spec: spec
        )
    }
}
