import Foundation
import Testing
@testable import Iris_Main

@MainActor
struct TimelineStateIntentCompilerContextTests {
    @Test func makeIntentCompilerContextIncludesProjectIdAndTranscriptRefs() throws {
        var state = TimelineState(timelineId: "tid-1")
        state.timeline = Timeline(timelineId: "tid-1", projectId: "proj-42")
        state.tracks = [Track(trackId: "tr-video", timelineId: "tid-1", kind: .video)]
        var spec = MediaSpec()
        spec.transcriptID = "501"
        let media = Media(
            mediaLibraryId: "lib-1",
            kind: .video,
            assetRefId: "asset-a",
            spec: spec
        )
        state.mediaById[media.mediaId] = media
        state.clips = [
            Clip(
                clipId: "clip-1",
                trackId: "tr-video",
                mediaId: media.mediaId,
                sourceRange: TimeRange(start: 0, end: 8_000_000),
                timelineRange: TimeRange(start: 0, end: 8_000_000)
            )
        ]
        state.selectedClipId = "clip-1"

        let context = state.makeIntentCompilerContext()

        #expect(context.projectId == "proj-42")
        #expect(context.sessionId == nil)
        #expect(context.transcriptContextsByClipId["clip-1"]?.transcriptId == "501")
        #expect(context.transcriptContextsByClipId["clip-1"]?.words.isEmpty == true)
        #expect(context.transcriptContextsByClipId["clip-1"]?.fullText == nil)

        let data = try JSONEncoder().encode(context)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] as? String == "proj-42")
        let transcripts = json?["transcriptContextsByClipId"] as? [String: Any]
        let clipPayload = transcripts?["clip-1"] as? [String: Any]
        #expect(clipPayload?["transcriptId"] as? String == "501")
        #expect(clipPayload?["fullText"] == nil)
    }
}
