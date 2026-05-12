internal import Combine
import Foundation

enum EditorPromptBarPhase: Equatable {
    case idle
    case recording
    case typing
    case submitting(String)
    case error(String)
}

@MainActor
final class EditorPromptBarViewModel: ObservableObject {
    typealias ContextProvider = @MainActor () -> IntentCompilerContext
    typealias ActionApplier = @MainActor ([Action]) -> Void

    @Published private(set) var phase: EditorPromptBarPhase = .idle
    @Published var promptDraft = ""
    @Published private(set) var voiceLevel: Float = 0

    private let transcription: RealtimeTranscriptionViewModel
    private let remoteCompiler: RemoteIntentCompilerClient
    private let contextProvider: ContextProvider
    private let applyActions: ActionApplier
    private var cancellables: Set<AnyCancellable> = []
    private var resetTask: Task<Void, Never>?
    private var micIsPressed = false

    var isTakingOver: Bool {
        phase != .idle
    }

    init(
        transcription: RealtimeTranscriptionViewModel? = nil,
        remoteCompiler: RemoteIntentCompilerClient? = nil,
        contextProvider: @escaping ContextProvider,
        applyActions: @escaping ActionApplier
    ) {
        self.transcription = transcription ?? RealtimeTranscriptionViewModel()
        self.remoteCompiler = remoteCompiler ?? RemoteIntentCompilerClient()
        self.contextProvider = contextProvider
        self.applyActions = applyActions

        transcription.$inputLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.voiceLevel = level
            }
            .store(in: &cancellables)
    }

    func beginVoicePrompt() async {
        guard phase != .recording, !isSubmitting else { return }
        resetTask?.cancel()
        micIsPressed = true
        phase = .recording

        await transcription.toggleRecording()
        if let errorMessage = transcription.errorMessage {
            micIsPressed = false
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

        if transcription.isRecording {
            await transcription.toggleRecording()
        }

        if let errorMessage = transcription.errorMessage {
            showError(errorMessage)
            return
        }

        let transcript = transcriptForSubmission()
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

    func submitTextPrompt() async {
        let prompt = promptDraft
        promptDraft = ""
        await submit(prompt: prompt, emptyMessage: "Enter a prompt to compile.")
    }

    func tearDown() {
        resetTask?.cancel()
        transcription.tearDown()
        micIsPressed = false
        voiceLevel = 0
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
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            showError(emptyMessage)
            return
        }

        phase = .submitting("Starting backend intent run.")

        do {
            let context = contextProvider()
            let result = try await remoteCompiler.compilePrompt(
                prompt: trimmedPrompt,
                context: context
            ) { [weak self] status in
                self?.phase = .submitting(status)
            }

            if !result.actions.isEmpty {
                applyActions(result.actions)
            }
            phase = .idle
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
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
