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

    @Test func backendProjectIdForUIPlanningUsesBackendIdNotLocalProjectUUID() {
        var state = TimelineState(timelineId: "tid-1")
        state.timeline = Timeline(
            timelineId: "tid-1",
            projectId: "AD330933-3098-4CE3-BD88-0CA3B272B2E3"
        )
        state.backendProjectId = "163"

        #expect(state.backendProjectIdForUIPlanning == "163")
        #expect(state.backendProjectIdForUIPlanning != state.timeline?.projectId)

        state.backendProjectId = nil
        #expect(state.backendProjectIdForUIPlanning == nil)
    }

    @Test func needsIntentTranscriptHydrationPrompt_detectsQuotedAndSilenceSignals() {
        let state = TimelineState(timelineId: "tid")
        #expect(state.needsIntentTranscriptHydrationPrompt("trim the silence") == true)
        #expect(state.needsIntentTranscriptHydrationPrompt("remove filler words") == true)
        #expect(state.needsIntentTranscriptHydrationPrompt(#"cut "hello" from the clip"#) == true)
        #expect(state.needsIntentTranscriptHydrationPrompt("where I say hello") == true)
        #expect(state.needsIntentTranscriptHydrationPrompt("remove the part where I pause") == true)
        #expect(state.needsIntentTranscriptHydrationPrompt("make it brighter") == false)
    }

    @Test func mediaIdAwaitingTranscriptDatabaseIDWhenPromptNeedsTranscriptAndIdMissing() {
        var state = TimelineState(timelineId: "tid-1")
        state.tracks = [Track(trackId: "tr-video", timelineId: "tid-1", kind: .video)]
        let media = Media(
            mediaLibraryId: "lib-1",
            kind: .video,
            assetRefId: "asset-a",
            spec: MediaSpec()
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
        #expect(state.mediaIdAwaitingTranscriptDatabaseIDForIntent(prompt: "remove silence") == media.mediaId)

        var spec2 = MediaSpec()
        spec2.transcriptID = "uuid-here"
        let media2 = Media(
            mediaLibraryId: "lib-1",
            kind: .video,
            assetRefId: "asset-b",
            spec: spec2
        )
        state.mediaById[media2.mediaId] = media2
        state.clips = [
            Clip(
                clipId: "clip-1",
                trackId: "tr-video",
                mediaId: media2.mediaId,
                sourceRange: TimeRange(start: 0, end: 8_000_000),
                timelineRange: TimeRange(start: 0, end: 8_000_000)
            )
        ]
        #expect(state.mediaIdAwaitingTranscriptDatabaseIDForIntent(prompt: "remove silence") == nil)
    }
}
