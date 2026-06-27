import Testing
@testable import Iris_Main

@MainActor
struct EditorIntentCompilerDiagnosticsViewModelTests {
    @Test func compilePromptUpdatesOutputAndRenderState() async {
        let viewModel = EditorIntentCompilerDiagnosticsViewModel(
            compiler: EditorIntentCompiler(
                candidateGenerator: EditorIntentCandidateGenerator(embeddingResolver: nil)
            )
        )

        viewModel.prompt = "Make the timeline bigger"
        await viewModel.compilePrompt()

        #expect(viewModel.resultKind == "Resolved")
        #expect(viewModel.renderState.timeline.size == .expanded)
        #expect(viewModel.outputText.contains("\"selectedCandidate\""))
    }
}
