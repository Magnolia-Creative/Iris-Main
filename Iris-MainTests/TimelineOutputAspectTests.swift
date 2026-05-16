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

        #expect(aspect?.width == 1620)
        #expect(aspect?.height == 1080)
    }

    @Test func manualAspectOverridesDerivedAspect() {
        var state = TimelineState(timelineId: "timeline")
        state.derivedOutputAspect = OutputAspectRatio(width: 16, height: 9)

        #expect(state.effectiveOutputAspect?.width == 16)
        #expect(state.effectiveOutputAspect?.height == 9)

        state.manualOutputAspect = OutputAspectRatio(width: 9, height: 16)

        #expect(state.effectiveOutputAspect?.width == 9)
        #expect(state.effectiveOutputAspect?.height == 16)
    }

    @Test func portraitPixelSizeUsesLongSide() {
        let size = OutputAspectRatio(width: 9, height: 16).pixelSize(longSide: 1920)

        #expect(size == CGSize(width: 1080, height: 1920))
    }

    @Test func renderInputOutputSizeFollowsManualAspectChanges() {
        var state = TimelineState(timelineId: "timeline")

        state.manualOutputAspect = OutputAspectRatio(width: 16, height: 9)
        #expect(state.makeRenderTimelineInput().outputSize == CGSize(width: 1920, height: 1080))

        state.manualOutputAspect = OutputAspectRatio(width: 9, height: 16)
        #expect(state.makeRenderTimelineInput().outputSize == CGSize(width: 1080, height: 1920))
    }

    @Test func derivedAspectRecoversAfterTimelineBecomesEmpty() {
        let timelineId = "timeline"
        let videoTrack = Track(trackId: "video-track", timelineId: timelineId, kind: .video)
        let firstClip = makeClip(id: "first", trackId: videoTrack.trackId, mediaId: "first-media", start: 0)
        let secondClip = makeClip(id: "second", trackId: videoTrack.trackId, mediaId: "second-media", start: 0)
        var state = TimelineState(timelineId: timelineId)
        state.tracks = [videoTrack]
        state.clips = [firstClip]
        state.mediaById = [
            "first-media": makeMedia(id: "first-media", kind: .video, width: 1620, height: 1080),
            "second-media": makeMedia(id: "second-media", kind: .video, width: 720, height: 1280),
        ]
        state.refreshDerivedOutputAspect()

        #expect(state.derivedOutputPixelSize?.width == 1620)
        #expect(state.derivedOutputPixelSize?.height == 1080)

        _ = state.apply([Action.removeClip(timelineId: timelineId, clipId: firstClip.clipId)])

        #expect(state.derivedOutputAspect == nil)
        #expect(state.derivedOutputPixelSize == nil)
        #expect(state.effectiveOutputPixelSize.width == 1920)
        #expect(state.effectiveOutputPixelSize.height == 1080)

        _ = state.apply([Action.addClip(timelineId: timelineId, clip: secondClip)])

        #expect(state.derivedOutputPixelSize?.width == 720)
        #expect(state.derivedOutputPixelSize?.height == 1280)
        #expect(state.effectiveOutputPixelSize.width == 720)
        #expect(state.effectiveOutputPixelSize.height == 1280)
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
        return Media(
            mediaId: id,
            mediaLibraryId: "library",
            kind: kind,
            assetRefId: "asset-\(id)",
            spec: spec
        )
    }
}
