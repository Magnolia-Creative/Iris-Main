internal import Combine
import Foundation

@MainActor
final class TimelineReviewCoordinator: ObservableObject {
    @Published var cutReview: TimelineCutReviewSession?
    @Published var promptActionReview: TimelinePromptActionReviewSession?
    @Published var promptActionReviewMessage: String?
}
