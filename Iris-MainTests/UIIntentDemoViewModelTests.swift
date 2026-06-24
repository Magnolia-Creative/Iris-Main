import Testing
@testable import Iris_Main

@MainActor
struct UIIntentDemoViewModelTests {
    @Test func compilePromptUpdatesOutputAndRenderState() async {
        let viewModel = UIIntentDemoViewModel(
            compiler: LocalUICompiler(
                candidateGenerator: UIIntentCandidateGenerator(embeddingResolver: nil)
            )
        )

        viewModel.prompt = "Make the timeline bigger"
        await viewModel.compilePrompt()

        #expect(viewModel.resultKind == "Resolved")
        #expect(viewModel.renderState.timeline.size == .expanded)
        #expect(viewModel.outputText.contains("\"selectedCandidate\""))
    }
}
