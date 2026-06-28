internal import Combine
import Foundation

@MainActor
final class TimelineReviewCoordinator: ObservableObject {
    @Published var cutReview: TimelineCutReviewSession?
    @Published var promptActionReview: TimelinePromptActionReviewSession?
    @Published var promptActionReviewMessage: String?

    func promptActionPreview(state: TimelineState) -> TimelinePromptActionPreview? {
        guard let session = promptActionReview,
              let action = session.currentAction,
              action.isPromptSequenceReviewable
        else { return nil }
        return TimelinePromptActionPreviewBuilder.makePreview(state: state, action: action)
    }

    func finishCutReview() {
        cutReview = nil
    }

    func showCutReviewRepromptComposer() {
        guard var review = cutReview else { return }
        review.isRepromptComposerPresented = true
        cutReview = review
    }

    func hideCutReviewRepromptComposer() {
        guard var review = cutReview else { return }
        review.isRepromptComposerPresented = false
        review.repromptDraft = ""
        cutReview = review
    }

    func updateCutReviewRepromptDraft(_ draft: String) {
        guard var review = cutReview else { return }
        review.repromptDraft = draft
        cutReview = review
    }

    func startPromptActionReview(actions: [Action], prompt: String, timelineId: String) -> Bool {
        guard actions.contains(where: \.isPromptSequenceReviewable)
            || actions.contains(where: \.isPromptColorReviewable) else { return false }
        guard actions.allSatisfy({ $0.timelineId == timelineId }) else { return false }

        promptActionReviewMessage = nil
        promptActionReview = TimelinePromptActionReviewSession(
            originalPrompt: prompt,
            actions: actions,
            currentIndex: 0
        )
        return true
    }

    func finishPromptActionReview() {
        promptActionReview = nil
        promptActionReviewMessage = nil
    }

    func discardPromptActionReviewReturningPrompt() -> String? {
        let prompt = promptActionReview?.originalPrompt
        finishPromptActionReview()
        return prompt
    }
}
