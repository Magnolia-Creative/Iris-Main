import Foundation
import Testing
@testable import Iris_Main

struct ClipColorFilterActionTests {
    private static let timelineId = "timeline-color-actions"
    private static let trackId = "track-color-actions"
    private static let clipId = "clip-color-actions"

    @Test func updatePayloadAppliesPatchOverNeutralAndReturnsResetInverse() {
        var state = makeState()

        let inverse = state.apply([
            Action.updateClipColorFilter(
                timelineId: Self.timelineId,
                clipId: Self.clipId,
                adjustments: ClipColorFilterPatch(temperature: 0.4)
            )
        ])

        #expect(state.effects.count == 1)
        #expect(state.effects.first?.clipColorFilter == ClipColorFilter(temperature: 0.4))
        #expect(inverse.count == 1)
        guard case .resetClipColorFilter(let inverseClipId) = inverse.first?.payload else {
            Issue.record("Expected resetClipColorFilter inverse")
            return
        }
        #expect(inverseClipId == Self.clipId)
    }

    @Test func updatePayloadComposesWithExistingFilterAndReturnsSetInverse() {
        var state = makeState()
        _ = state.apply([
            Action.setClipColorFilter(
                timelineId: Self.timelineId,
                clipId: Self.clipId,
                filter: ClipColorFilter(temperature: 0.2, saturation: 0.5)
            )
        ])

        let inverse = state.apply([
            Action.updateClipColorFilter(
                timelineId: Self.timelineId,
                clipId: Self.clipId,
                adjustments: ClipColorFilterPatch(contrast: 0.3)
            )
        ])

        #expect(state.effects.count == 1)
        #expect(
            state.effects.first?.clipColorFilter == ClipColorFilter(
                temperature: 0.2,
                contrast: 0.3,
                saturation: 0.5
            )
        )
        #expect(inverse.count == 1)
        guard case .setClipColorFilter(_, let inverseFilter) = inverse.first?.payload else {
            Issue.record("Expected setClipColorFilter inverse")
            return
        }
        #expect(inverseFilter == ClipColorFilter(temperature: 0.2, saturation: 0.5))
    }

    @Test func resetPayloadRemovesAllColorFilterEffectsForClip() {
        var state = makeState()
        _ = state.apply([
            Action.setClipColorFilter(
                timelineId: Self.timelineId,
                clipId: Self.clipId,
                filter: ClipColorFilter(highlights: 0.5)
            )
        ])

        let inverse = state.apply([
            Action.resetClipColorFilter(timelineId: Self.timelineId, clipId: Self.clipId)
        ])

        #expect(state.effects.isEmpty)
        guard case .setClipColorFilter(_, let restored) = inverse.first?.payload else {
            Issue.record("Expected setClipColorFilter inverse")
            return
        }
        #expect(restored == ClipColorFilter(highlights: 0.5))
    }

    @Test func updatePayloadIsNoopWhenClipMissing() {
        var state = makeState()

        let inverse = state.apply([
            Action.updateClipColorFilter(
                timelineId: Self.timelineId,
                clipId: "missing-clip",
                adjustments: ClipColorFilterPatch(temperature: 0.5)
            )
        ])

        #expect(state.effects.isEmpty)
        #expect(inverse.isEmpty)
    }

    @Test func updateActionRoundTripsThroughCodable() throws {
        let action = Action.updateClipColorFilter(
            timelineId: Self.timelineId,
            clipId: Self.clipId,
            adjustments: ClipColorFilterPatch(temperature: -0.4, saturation: 0.6)
        )

        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(Action.self, from: data)

        #expect(decoded.type == .updateEffectParams)
        guard case .updateClipColorFilter(let clipId, let adjustments) = decoded.payload else {
            Issue.record("Expected updateClipColorFilter payload after decode")
            return
        }
        #expect(clipId == Self.clipId)
        #expect(adjustments.temperature == -0.4)
        #expect(adjustments.saturation == 0.6)
        #expect(adjustments.contrast == nil)
    }

    @Test func updateNeutralPatchOverNeutralIsNoop() {
        var state = makeState()
        let inverse = state.apply([
            Action.updateClipColorFilter(
                timelineId: Self.timelineId,
                clipId: Self.clipId,
                adjustments: ClipColorFilterPatch()
            )
        ])
        #expect(state.effects.isEmpty)
        #expect(inverse.isEmpty)
    }

    private func makeState() -> TimelineState {
        var state = TimelineState(timelineId: Self.timelineId)
        state.tracks = [Track(trackId: Self.trackId, timelineId: Self.timelineId, kind: .video)]
        state.clips = [
            Clip(
                clipId: Self.clipId,
                trackId: Self.trackId,
                mediaId: "media-color-actions",
                sourceRange: TimeRange(start: 0, end: 5_000_000),
                timelineRange: TimeRange(start: 0, end: 5_000_000)
            )
        ]
        return state
    }
}
