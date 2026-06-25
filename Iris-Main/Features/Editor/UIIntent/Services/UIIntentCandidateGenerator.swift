import Foundation

struct UIIntentCandidateGenerator {
    private let directMatcher: UIDirectRuleMatcher
    private let embeddingResolver: UIEmbeddingResolver?
    private let policy: UIResolutionPolicy

    init(
        directMatcher: UIDirectRuleMatcher = UIDirectRuleMatcher(),
        embeddingResolver: UIEmbeddingResolver? = UIEmbeddingResolver(),
        policy: UIResolutionPolicy = .default
    ) {
        self.directMatcher = directMatcher
        self.embeddingResolver = embeddingResolver
        self.policy = policy
    }

    func candidates(
        for prompt: NormalizedEditorUIPrompt,
        context: EditorUICompilerContext
    ) async -> (candidates: [EditorUIIntentCandidate], embeddingWarnings: [UIEmbeddingResolverWarning]) {
        let directCandidates = directMatcher.candidates(for: prompt, context: context)
        let bestDirectScore = directCandidates.map(\.totalScore).max() ?? 0
        guard bestDirectScore < policy.decisiveDirectScore, let embeddingResolver else {
            return (directCandidates, [])
        }

        let embeddingResolution = await embeddingResolver.candidates(for: prompt)
        return (
            directCandidates + embeddingResolution.candidates,
            embeddingResolution.warnings
        )
    }
}
