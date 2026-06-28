import Testing
@testable import Iris_Main

@MainActor
struct TimelineReviewCoordinatorTests {
    @Test func startsAndDiscardsPromptActionReview() {
        let coordinator = TimelineReviewCoordinator()
        let action = Action.splitClip(timelineId: "timeline-1", clipId: "clip-1", atTimeUs: 500_000)

        #expect(coordinator.startPromptActionReview(actions: [action], prompt: "split", timelineId: "timeline-1"))
        #expect(coordinator.promptActionReview?.originalPrompt == "split")

        #expect(coordinator.discardPromptActionReviewReturningPrompt() == "split")
        #expect(coordinator.promptActionReview == nil)
        #expect(coordinator.promptActionReviewMessage == nil)
    }

    @Test func rejectsPromptReviewForMismatchedTimeline() {
        let coordinator = TimelineReviewCoordinator()
        let action = Action.splitClip(timelineId: "other", clipId: "clip-1", atTimeUs: 500_000)

        #expect(!coordinator.startPromptActionReview(actions: [action], prompt: "split", timelineId: "timeline-1"))
        #expect(coordinator.promptActionReview == nil)
    }

    @Test func updatesCutReviewRepromptComposerState() {
        let coordinator = TimelineReviewCoordinator()
        coordinator.cutReview = TimelineCutReviewSession(
            items: [
                TimelineCutReviewItem(
                    leftClipId: "left",
                    rightClipId: "right",
                    leftMediaId: "media",
                    rightMediaId: "media",
                    startTimeUs: 0,
                    cutTimeUs: 1_000_000,
                    endTimeUs: 2_000_000
                )
            ],
            currentIndex: 0
        )

        coordinator.showCutReviewRepromptComposer()
        coordinator.updateCutReviewRepromptDraft("try again")
        #expect(coordinator.cutReview?.isRepromptComposerPresented == true)
        #expect(coordinator.cutReview?.repromptDraft == "try again")

        coordinator.hideCutReviewRepromptComposer()
        #expect(coordinator.cutReview?.isRepromptComposerPresented == false)
        #expect(coordinator.cutReview?.repromptDraft == "")
    }
}
