import Foundation
import Testing
@testable import Iris_Main

@MainActor
struct TimelinePromptActionReviewControllerTests {
    @Test func startReviewDoesNotMutateUntilApprove() async {
        let controller = TimelineController(timelineId: "t1")
        let clip = Clip(
            clipId: "c1",
            trackId: "track-v",
            mediaId: "m1",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 0, end: 10_000_000)
        )
        controller.replaceTimelineContentForTesting(
            tracks: [Track(trackId: "track-v", timelineId: "t1", kind: .video)],
            clips: [clip]
        )

        let actions = [
            Action.splitClip(timelineId: "t1", clipId: "c1", atTimeUs: 5_000_000)
        ]
        let started = controller.startPromptActionReview(actions: actions, prompt: "split")
        #expect(started)
        #expect(controller.promptActionReview != nil)
        #expect(controller.state.clips.count == 1)

        controller.approveCurrentPromptAction()
        #expect(controller.promptActionReview == nil)
        #expect(controller.state.clips.count == 2)
    }

    @Test func rejectSkipsWithoutApplying() async {
        let controller = TimelineController(timelineId: "t1")
        let clip = Clip(
            clipId: "c1",
            trackId: "track-v",
            mediaId: "m1",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 0, end: 10_000_000)
        )
        controller.replaceTimelineContentForTesting(
            tracks: [Track(trackId: "track-v", timelineId: "t1", kind: .video)],
            clips: [clip]
        )

        let actions = [
            Action.splitClip(timelineId: "t1", clipId: "c1", atTimeUs: 5_000_000)
        ]
        _ = controller.startPromptActionReview(actions: actions, prompt: "split")
        controller.rejectCurrentPromptAction()
        #expect(controller.promptActionReview == nil)
        #expect(controller.state.clips.count == 1)
    }

    @Test func discardReviewReturnsOriginalPrompt() async {
        let controller = TimelineController(timelineId: "t1")
        controller.replaceTimelineContentForTesting(
            tracks: [Track(trackId: "track-v", timelineId: "t1", kind: .video)],
            clips: [
                Clip(
                    clipId: "c1",
                    trackId: "track-v",
                    mediaId: "m1",
                    sourceRange: TimeRange(start: 0, end: 10_000_000),
                    timelineRange: TimeRange(start: 0, end: 10_000_000)
                )
            ]
        )
        _ = controller.startPromptActionReview(
            actions: [Action.splitClip(timelineId: "t1", clipId: "c1", atTimeUs: 5_000_000)],
            prompt: "hello"
        )
        let p = controller.discardPromptActionReviewReturningPrompt()
        #expect(p == "hello")
        #expect(controller.promptActionReview == nil)
        #expect(controller.state.clips.count == 1)
    }

    @Test func autoAppliesLeadingNonReviewableActions() async {
        let controller = TimelineController(timelineId: "t1")
        let clip = Clip(
            clipId: "c1",
            trackId: "track-v",
            mediaId: "m1",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 0, end: 10_000_000)
        )
        controller.replaceTimelineContentForTesting(
            tracks: [Track(trackId: "track-v", timelineId: "t1", kind: .video)],
            clips: [clip]
        )

        let colorAction = Action.updateClipColorFilter(
            timelineId: "t1",
            clipId: "c1",
            adjustments: ClipColorFilterPatch(temperature: 0.25)
        )
        let splitAction = Action.splitClip(timelineId: "t1", clipId: "c1", atTimeUs: 5_000_000)
        let started = controller.startPromptActionReview(actions: [colorAction, splitAction], prompt: "do things")
        #expect(started)
        // Color filter applied immediately; session should be waiting on split (still 1 clip until approve).
        #expect(controller.state.clips.count == 1)
        guard case .splitClip(let splitClipId, let atUs) = controller.promptActionReview?.currentAction?.payload else {
            Issue.record("Expected split to be current review action")
            return
        }
        #expect(splitClipId == "c1")
        #expect(atUs == 5_000_000)
    }
}
