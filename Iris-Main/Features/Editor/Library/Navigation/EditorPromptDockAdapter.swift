import SwiftUI

struct EditorPromptDockAdapter: View {
    @ObservedObject var viewModel: EditorPromptBarViewModel
    @Binding var activeNavigationItemId: String
    let onVoicePromptSubmit: () -> Void
    let onTextPromptSubmit: () -> Void

    var body: some View {
        IntelligenceComponent(
            navigationItems: IntelligenceComponent.defaultShowcaseItems,
            activeNavigationItemId: $activeNavigationItemId,
            promptPhase: intelligencePromptPhase,
            promptDraft: $viewModel.promptDraft,
            liveTranscript: viewModel.liveTranscript,
            voiceLevel: viewModel.voiceLevel,
            onIntelligenceTap: {
                viewModel.openTextPrompt()
            },
            onVoiceHoldStart: {
                Task { await viewModel.beginVoicePrompt() }
            },
            onVoiceHoldEnd: onVoicePromptSubmit,
            onSubmitText: onTextPromptSubmit,
            onCancelText: {
                viewModel.cancelTextPrompt()
            },
            onCancelProcessing: {
                viewModel.cancelProcessing()
            }
        )
    }

    private var intelligencePromptPhase: Binding<IntelligencePromptPhase> {
        Binding(
            get: { viewModel.phase.intelligencePhase },
            set: { phase in
                switch phase {
                case .typing:
                    viewModel.openTextPrompt()
                case .idle:
                    viewModel.cancelTextPrompt()
                case .recording, .submitting, .clarification, .error:
                    break
                }
            }
        )
    }
}
