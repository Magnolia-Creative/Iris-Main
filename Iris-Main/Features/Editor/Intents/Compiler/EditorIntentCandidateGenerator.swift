import Foundation

struct EditorIntentCandidateGenerator {
    private let directMatcher: EditorIntentDirectRuleMatcher
    private let embeddingResolver: EditorIntentEmbeddingResolver?
    private let policy: EditorIntentResolutionPolicy

    init(
        directMatcher: EditorIntentDirectRuleMatcher = EditorIntentDirectRuleMatcher(),
        embeddingResolver: EditorIntentEmbeddingResolver? = EditorIntentEmbeddingResolver(),
        policy: EditorIntentResolutionPolicy = .default
    ) {
        self.directMatcher = directMatcher
        self.embeddingResolver = embeddingResolver
        self.policy = policy
    }

    func candidates(
        for prompt: NormalizedEditorIntentPrompt,
        context: EditorIntentCompilerContext
    ) async -> (candidates: [EditorIntentCandidate], embeddingWarnings: [EditorIntentEmbeddingResolverWarning]) {
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
