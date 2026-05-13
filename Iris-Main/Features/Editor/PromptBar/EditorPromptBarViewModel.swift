internal import Combine
import Foundation
import OSLog

enum EditorPromptBarPhase: Equatable {
    case idle
    case recording
    case typing
    case submitting(String)
    case clarification(String)
    case error(String)
}

@MainActor
final class EditorPromptBarViewModel: ObservableObject {
    typealias ContextProvider = @MainActor () -> IntentCompilerContext
    typealias ActionApplier = @MainActor ([Action]) -> Bool
    /// When transcript DB id is not ready yet for transcript-heavy prompts, await before starting the intent run. Returns true if a wait loop ran.
    typealias TranscriptReadinessWaiter = @MainActor (String) async throws -> Bool

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "EditorPromptBar"
    )

    @Published private(set) var phase: EditorPromptBarPhase = .idle
    @Published var promptDraft = ""
    @Published private(set) var voiceLevel: Float = 0
    @Published private(set) var liveTranscript: String = ""

    private let transcription: RealtimeTranscriptionViewModel
    private let remoteCompiler: RemoteIntentCompilerClient
    private let contextProvider: ContextProvider
    private let needsIntentTranscriptDatabaseWait: (@MainActor (String) -> Bool)?
    private let waitForTranscriptReadinessIfNeeded: TranscriptReadinessWaiter?
    private let applyActions: ActionApplier
    private var cancellables: Set<AnyCancellable> = []
    private var resetTask: Task<Void, Never>?
    /// Owns the in-flight intent compile so the user can cancel from the prompt bar.
    private var submitTask: Task<Void, Never>?
    private var micIsPressed = false

    var isTakingOver: Bool {
        phase != .idle
    }

    init(
        transcription: RealtimeTranscriptionViewModel? = nil,
        remoteCompiler: RemoteIntentCompilerClient? = nil,
        contextProvider: @escaping ContextProvider,
        needsIntentTranscriptDatabaseWait: (@MainActor (String) -> Bool)? = nil,
        waitForTranscriptReadinessIfNeeded: TranscriptReadinessWaiter? = nil,
        applyActions: @escaping ActionApplier
    ) {
        self.transcription = transcription ?? RealtimeTranscriptionViewModel()
        self.remoteCompiler = remoteCompiler ?? RemoteIntentCompilerClient()
        self.contextProvider = contextProvider
        self.needsIntentTranscriptDatabaseWait = needsIntentTranscriptDatabaseWait
        self.waitForTranscriptReadinessIfNeeded = waitForTranscriptReadinessIfNeeded
        self.applyActions = applyActions

        self.transcription.$inputLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.voiceLevel = level
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            self.transcription.$finalizedTranscript,
            self.transcription.$partialTranscript
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] finalized, partial in
            let pieces = [finalized, partial].filter { !$0.isEmpty }
            self?.liveTranscript = pieces.joined(separator: " ")
        }
        .store(in: &cancellables)
    }

    func beginVoicePrompt() async {
        guard phase != .recording, !isSubmitting else { return }
        resetTask?.cancel()
        micIsPressed = true
        phase = .recording
        Self.logger.info("[PromptBar] Voice prompt begin")

        await transcription.toggleRecording()
        if let errorMessage = transcription.errorMessage {
            micIsPressed = false
            Self.logger.error("[PromptBar] Voice prompt failed to start: \(errorMessage, privacy: .public)")
            showError(errorMessage)
            return
        }

        if !micIsPressed {
            await endVoicePrompt()
        }
    }

    func endVoicePrompt() async {
        micIsPressed = false
        guard phase == .recording else { return }
        Self.logger.info("[PromptBar] Voice prompt end requested")

        if transcription.isRecording {
            await transcription.toggleRecording()
        }

        if let errorMessage = transcription.errorMessage {
            Self.logger.error("[PromptBar] Voice prompt ended with transcription error: \(errorMessage, privacy: .public)")
            showError(errorMessage)
            return
        }

        let transcript = transcriptForSubmission()
        Self.logger.info(
            "[PromptBar] Voice transcript ready chars=\(transcript.count, privacy: .public) finalizedChars=\(self.transcription.finalizedTranscript.count, privacy: .public) partialChars=\(self.transcription.partialTranscript.count, privacy: .public)"
        )
        await submit(prompt: transcript, emptyMessage: "I did not catch any speech.")
    }

    func openTextPrompt() {
        guard !isSubmitting else { return }
        resetTask?.cancel()
        phase = .typing
    }

    func cancelTextPrompt() {
        promptDraft = ""
        phase = .idle
    }

    func cancelProcessing() {
        submitTask?.cancel()
    }

    func submitTextPrompt() async {
        let prompt = promptDraft
        promptDraft = ""
        await submit(prompt: prompt, emptyMessage: "Enter a prompt to compile.")
    }

    func tearDown() {
        submitTask?.cancel()
        resetTask?.cancel()
        transcription.tearDown()
        micIsPressed = false
        voiceLevel = 0
        liveTranscript = ""
        phase = .idle
    }

    private var isSubmitting: Bool {
        if case .submitting = phase {
            return true
        }
        return false
    }

    private func transcriptForSubmission() -> String {
        [transcription.finalizedTranscript, transcription.partialTranscript]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit(prompt: String, emptyMessage: String) async {
        submitTask?.cancel()

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            Self.logger.warning("[PromptBar] Submit skipped because prompt was empty")
            showError(emptyMessage)
            return
        }

        phase = .submitting("Starting backend intent run.")
        Self.logger.info("[PromptBar] Submit start promptChars=\(trimmedPrompt.count, privacy: .public)")

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSubmitting(trimmedPrompt: trimmedPrompt)
        }
        submitTask = task
        await task.value
        submitTask = nil
    }

    private func runSubmitting(trimmedPrompt: String) async {
        do {
            if let needsIntentTranscriptDatabaseWait,
               let waitForTranscriptReadinessIfNeeded,
               needsIntentTranscriptDatabaseWait(trimmedPrompt) {
                phase = .submitting("Processing clip")
                _ = try await waitForTranscriptReadinessIfNeeded(trimmedPrompt)
                phase = .submitting("Starting backend intent run.")
            }

            let context = contextProvider()
            Self.logger.info(
                "[PromptBar] Context timeline=\(context.timelineId, privacy: .public) project=\(context.projectId ?? "nil", privacy: .public) session=\(context.sessionId ?? "nil", privacy: .public) selectedClip=\(context.selectedClipId ?? "nil", privacy: .public) selectedTrack=\(context.selectedTrackId ?? "nil", privacy: .public) clips=\(context.clipsById.count, privacy: .public) tracks=\(context.orderedClipIdsByTrackId.count, privacy: .public) transcripts=\(context.transcriptContextsByClipId.count, privacy: .public)"
            )
            let result = try await remoteCompiler.compilePrompt(
                prompt: trimmedPrompt,
                context: context
            ) { [weak self] status in
                Self.logger.info("[PromptBar] Status update: \(status, privacy: .public)")
                self?.phase = .submitting(status)
            }

            try Task.checkCancellation()

            Self.logger.info(
                "[PromptBar] Result received actions=\(result.actions.count, privacy: .public) effects=\(result.experimentalEffectOperations.count, privacy: .public) warnings=\(result.warnings.map(\.rawValue).joined(separator: ","), privacy: .public) needsClarification=\(result.needsClarification, privacy: .public)"
            )
            if result.needsClarification {
                showClarification(result.unresolvedText ?? "I need a little more detail before I can apply that edit.")
                return
            }

            if !result.actions.isEmpty {
                Self.logger.info("[PromptBar] Applying actions count=\(result.actions.count, privacy: .public)")
                let didApply = applyActions(result.actions)
                guard didApply else {
                    Self.logger.error("[PromptBar] Returned actions did not change the current timeline")
                    showError("I got an edit back, but it could not be applied to the current timeline.")
                    return
                }
            } else {
                Self.logger.warning("[PromptBar] Result had no timeline actions to apply")
                if let unresolvedText = result.unresolvedText, !unresolvedText.isEmpty {
                    showClarification(unresolvedText)
                    return
                }
            }
            phase = .idle
        } catch is CancellationError {
            Self.logger.info("[PromptBar] Submit cancelled during transcript wait or compile")
            phase = .idle
        } catch let urlError as URLError where urlError.code == .cancelled {
            Self.logger.info("[PromptBar] Submit cancelled (URL session)")
            phase = .idle
        } catch let compilerError as RemoteIntentCompilerError {
            if case .cancelled = compilerError {
                Self.logger.info("[PromptBar] Submit cancelled (intent compiler websocket)")
                phase = .idle
            } else {
                Self.logger.error("[PromptBar] Submit failed: \(compilerError.localizedDescription, privacy: .public)")
                showError(compilerError.localizedDescription)
            }
        } catch {
            Self.logger.error("[PromptBar] Submit failed: \(error.localizedDescription, privacy: .public)")
            showError(error.localizedDescription)
        }
    }

    private func showClarification(_ message: String) {
        Self.logger.info("[PromptBar] Showing clarification: \(message, privacy: .public)")
        phase = .clarification(message)
        voiceLevel = 0
        resetTask?.cancel()
    }

    private func showError(_ message: String) {
        Self.logger.error("[PromptBar] Showing error: \(message, privacy: .public)")
        phase = .error(message)
        voiceLevel = 0
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard case .error = self?.phase else { return }
                self?.phase = .idle
            }
        }
    }
}
