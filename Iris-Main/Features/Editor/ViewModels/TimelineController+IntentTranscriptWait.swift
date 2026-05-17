import Foundation
import OSLog

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
    private static let intentTranscriptWaitLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "IntentTranscriptWait"
    )

    /// When the prompt needs backend transcript hydration and the target clip’s media has no `transcriptID` yet, polls until it appears or times out. Returns true after a successful wait (the caller should already have gated with `needsIntentTranscriptDatabaseWait`).
    @MainActor
    func waitForIntentTranscriptReadinessIfNeeded(prompt: String) async throws -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let mediaId = state.mediaIdAwaitingTranscriptDatabaseIDForIntent(prompt: trimmed) else { return false }
        let promptPreview = String(trimmed.prefix(80))

        let timeout: Duration = .seconds(120)
        let poll: Duration = .milliseconds(250)
        let deadline = ContinuousClock.now + timeout
        var attempt = 0

        Self.intentTranscriptWaitLogger.warning(
            "[intent-transcript-wait] starting mediaId=\(mediaId, privacy: .public) promptChars=\(trimmed.count, privacy: .public) promptPreview=\(promptPreview, privacy: .public)"
        )

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            attempt += 1

            // Poll the local database as well as in-memory state. The transcript persistence
            // notification can be missed if it fires before the editor view subscribes.
            refreshMediaFromDatabaseIfOnTimeline(mediaId: mediaId)

            let media = state.mediaById[mediaId]
            let tid = media?.spec.transcriptID?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sentenceCount = media?.spec.transcriptSentences?.count ?? 0
            let hasFullText = !(media?.spec.transcriptFullText?.isEmpty ?? true)
            if !tid.isEmpty {
                Self.intentTranscriptWaitLogger.info(
                    "[intent-transcript-wait] ready mediaId=\(mediaId, privacy: .public) transcriptID=\(tid, privacy: .public) attempts=\(attempt, privacy: .public) sentences=\(sentenceCount, privacy: .public) hasFullText=\(hasFullText, privacy: .public)"
                )
                return true
            }
            if attempt == 1 || attempt % 20 == 0 {
                Self.intentTranscriptWaitLogger.warning(
                    "[intent-transcript-wait] still waiting mediaId=\(mediaId, privacy: .public) attempts=\(attempt, privacy: .public) sentences=\(sentenceCount, privacy: .public) hasFullText=\(hasFullText, privacy: .public)"
                )
            }
            try await Task.sleep(for: poll)
        }
        Self.intentTranscriptWaitLogger.error(
            "[intent-transcript-wait] timed out mediaId=\(mediaId, privacy: .public) attempts=\(attempt, privacy: .public)"
        )
        throw IntentTranscriptReadinessError.timedOutWaitingForTranscriptID
    }

    @MainActor
    func needsIntentTranscriptDatabaseWait(for prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaId = state.mediaIdAwaitingTranscriptDatabaseIDForIntent(prompt: trimmed)
        if let mediaId {
            Self.intentTranscriptWaitLogger.warning(
                "[intent-transcript-wait] required mediaId=\(mediaId, privacy: .public) promptChars=\(trimmed.count, privacy: .public)"
            )
        } else {
            Self.intentTranscriptWaitLogger.info(
                "[intent-transcript-wait] not required promptChars=\(trimmed.count, privacy: .public)"
            )
        }
        return mediaId != nil
    }
}
