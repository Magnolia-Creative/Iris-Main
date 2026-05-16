import Testing
@testable import Iris_Main

struct CaptionEditingTests {
    @Test func splitReassignsLeftCueToLeftClip() throws {
        var state = makeState(clips: [makeClip(id: "clip", source: 0...10_000_000, timeline: 0...10_000_000)])
        state.captionCues = [
            makeCue(
                id: "cue-left",
                clipId: "clip",
                text: "left cue",
                sourceStart: 1_000_000,
                sourceEnd: 2_000_000,
                timelineStart: 1_000_000,
                timelineEnd: 2_000_000
            )
        ]

        _ = state.apply([.splitClip(timelineId: "timeline", clipId: "clip", atTimeUs: 5_000_000)])

        let leftClip = try #require(state.clips.first { $0.sourceRange.end == 5_000_000 })
        #expect(state.captionCues.count == 1)
        #expect(state.captionCues.first?.clipId == leftClip.clipId)
        #expect(state.captionCues.first?.sourceStartUs == 1_000_000)
        #expect(state.captionCues.first?.sourceEndUs == 2_000_000)
    }

    @Test func splitCrossingCueCreatesOneCuePerHalf() throws {
        var state = makeState(clips: [makeClip(id: "clip", source: 0...10_000_000, timeline: 0...10_000_000)])
        state.captionCues = [
            makeCue(
                id: "cue-cross",
                clipId: "clip",
                text: "one two three four",
                sourceStart: 2_000_000,
                sourceEnd: 8_000_000,
                timelineStart: 2_000_000,
                timelineEnd: 8_000_000
            )
        ]

        _ = state.apply([.splitClip(timelineId: "timeline", clipId: "clip", atTimeUs: 5_000_000)])

        let leftClip = try #require(state.clips.first { $0.sourceRange.end == 5_000_000 })
        let rightClip = try #require(state.clips.first { $0.sourceRange.start == 5_000_000 })
        let cues = state.captionCues.sorted { ($0.sourceStartUs ?? 0) < ($1.sourceStartUs ?? 0) }

        #expect(cues.count == 2)
        #expect(cues[0].clipId == leftClip.clipId)
        #expect(cues[0].text == "one two")
        #expect(cues[0].sourceStartUs == 2_000_000)
        #expect(cues[0].sourceEndUs == 5_000_000)
        #expect(cues[1].clipId == rightClip.clipId)
        #expect(cues[1].text == "three four")
        #expect(cues[1].sourceStartUs == 5_000_000)
        #expect(cues[1].sourceEndUs == 8_000_000)
        #expect((cues[0].text + " " + cues[1].text) == "one two three four")
    }

    @Test func projectionTracksMovedClipTimelineRange() throws {
        let right = makeClip(id: "right", source: 5_000_000...10_000_000, timeline: 0...5_000_000)
        let left = makeClip(id: "left", source: 0...5_000_000, timeline: 5_000_000...10_000_000)
        var state = makeState(clips: [right, left])
        let cue = makeCue(
            id: "cue-right",
            clipId: "right",
            text: "right cue",
            sourceStart: 6_000_000,
            sourceEnd: 7_000_000,
            timelineStart: 1_000_000,
            timelineEnd: 2_000_000
        )
        state.captionCues = [cue]

        _ = state.apply([.moveClip(timelineId: "timeline", clipId: "right", orderedClipIds: ["left", "right"])])

        let clipsById = Dictionary(uniqueKeysWithValues: state.clips.map { ($0.clipId, $0) })
        let range = try #require(CaptionCueProjection.currentTimelineRange(for: cue, clips: clipsById))
        #expect(range.start == 6_000_000)
        #expect(range.end == 7_000_000)
    }

    @Test func deleteClipRemovesAnchoredCues() {
        var state = makeState(clips: [makeClip(id: "clip", source: 0...5_000_000, timeline: 0...5_000_000)])
        state.captionCues = [
            makeCue(
                id: "cue",
                clipId: "clip",
                text: "deleted cue",
                sourceStart: 1_000_000,
                sourceEnd: 2_000_000,
                timelineStart: 1_000_000,
                timelineEnd: 2_000_000
            )
        ]

        _ = state.apply([.removeClip(timelineId: "timeline", clipId: "clip")])

        #expect(state.captionCues.isEmpty)
    }
}

private func makeState(clips: [Clip]) -> TimelineState {
    var state = TimelineState(timelineId: "timeline")
    state.tracks = [Track(trackId: "track-video", timelineId: "timeline", kind: .video)]
    state.clips = clips
    return state
}

private func makeClip(id: String, source: ClosedRange<Int64>, timeline: ClosedRange<Int64>) -> Clip {
    Clip(
        clipId: id,
        trackId: "track-video",
        mediaId: "media",
        sourceRange: TimeRange(start: source.lowerBound, end: source.upperBound),
        timelineRange: TimeRange(start: timeline.lowerBound, end: timeline.upperBound)
    )
}

private func makeCue(
    id: String,
    clipId: String,
    text: String,
    sourceStart: Int64,
    sourceEnd: Int64,
    timelineStart: Int64,
    timelineEnd: Int64
) -> CaptionCue {
    CaptionCue(
        cueId: id,
        groupId: "group",
        clipId: clipId,
        text: text,
        timelineStartUs: timelineStart,
        timelineEndUs: timelineEnd,
        sourceStartUs: sourceStart,
        sourceEndUs: sourceEnd
    )
}
