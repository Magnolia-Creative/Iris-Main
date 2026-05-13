import Foundation

enum IntentTranscriptReadinessError: LocalizedError {
    case timedOutWaitingForTranscriptID

    var errorDescription: String? {
        switch self {
        case .timedOutWaitingForTranscriptID:
            return "The clip transcript is still preparing or could not be saved. Try again in a moment."
        }
    }
}

extension TimelineController {
    /// When the prompt needs backend transcript hydration and the target clip’s media has no `transcriptID` yet, polls until it appears or times out. Returns true after a successful wait (the caller should already have gated with `needsIntentTranscriptDatabaseWait`).
    @MainActor
    func waitForIntentTranscriptReadinessIfNeeded(prompt: String) async throws -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let mediaId = state.mediaIdAwaitingTranscriptDatabaseIDForIntent(prompt: trimmed) else { return false }

        let timeout: Duration = .seconds(120)
        let poll: Duration = .milliseconds(250)
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let tid = state.mediaById[mediaId]?.spec.transcriptID?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !tid.isEmpty { return true }
            try await Task.sleep(for: poll)
        }
        throw IntentTranscriptReadinessError.timedOutWaitingForTranscriptID
    }

    @MainActor
    func needsIntentTranscriptDatabaseWait(for prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.mediaIdAwaitingTranscriptDatabaseIDForIntent(prompt: trimmed) != nil
    }
}
