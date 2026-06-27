import Foundation
import Testing
@testable import Iris_Main

struct EditorIntentCompilerTests {
    @Test func normalizerCanonicalizesCommonPhrases() {
        let prompt = EditorIntentPromptNormalizer.normalize("  Make the timeline bigger!!  ")

        #expect(prompt.normalizedText == "make the timeline expanded")
        #expect(prompt.tokens.contains("timeline"))
        #expect(prompt.tokens.contains("expanded"))
        #expect(prompt.canonicalPhraseReplacements.contains(EditorIntentPhraseReplacement(source: "bigger", canonical: "expanded")))
    }

    @Test func lexiconMapsTimelineAliasToExistingComponent() {
        let prompt = EditorIntentPromptNormalizer.normalize("expand the tracks")
        let matches = EditorIntentLexicon.componentMatches(in: prompt)

        #expect(matches.contains { $0.value == "timeline.full" })
    }

    @Test func timelineBiggerResolvesToExpandedTimeline() async {
        let compiler = makeCompilerWithoutEmbeddings()
        let result = await compiler.compile(
            prompt: "Make the timeline bigger",
            context: EditorIntentCompilerDiagnosticsFixtures.defaultContext
        )

        guard case .resolved(let state, _, let report) = result else {
            Issue.record("Expected resolved result")
            return
        }

        #expect(state.timeline.componentId == "timeline.full")
        #expect(state.timeline.size == .expanded)
        #expect(state.timeline.isVisible)
        #expect(report.selectedCandidate?.ruleId == "timeline.expand")
    }

    @Test func hideParameterControlsResolvesToCompactChromeWithoutGroups() async {
        let compiler = makeCompilerWithoutEmbeddings()
        let result = await compiler.compile(
            prompt: "Hide the parameter controls",
            context: EditorIntentCompilerDiagnosticsFixtures.controlsContext
        )

        guard case .resolved(let state, _, _) = result else {
            Issue.record("Expected resolved result")
            return
        }

        #expect(state.chromePlan.density == .compact)
        #expect(state.chromePlan.parameterGroups.isEmpty)
        #expect(state.chromePlan.showsDock)
    }

    @Test func contextualThisUsesLastInteractedComponent() async {
        let compiler = makeCompilerWithoutEmbeddings()
        let result = await compiler.compile(
            prompt: "Make this bigger",
            context: EditorIntentCompilerDiagnosticsFixtures.previewContext
        )

        guard case .resolved(let state, _, let report) = result else {
            Issue.record("Expected resolved result")
            return
        }

        #expect(state.playback.componentId == "playback.section")
        #expect(state.playback.size == .expanded)
        #expect(report.selectedCandidate?.source == EditorIntentCandidateSource.contextual.rawValue)
    }

    @Test func missingContextDefersThisPrompt() async {
        let compiler = makeCompilerWithoutEmbeddings()
        let result = await compiler.compile(
            prompt: "Make this bigger",
            context: EditorIntentCompilerDiagnosticsFixtures.defaultContext
        )

        guard case .deferredToRemote(let request, _) = result else {
            Issue.record("Expected deferred result")
            return
        }

        #expect(request.normalizedPrompt == "make this expanded")
    }

    @Test func secondMonitorRequestIsUnsupported() async {
        let compiler = makeCompilerWithoutEmbeddings()
        let result = await compiler.compile(
            prompt: "Move the timeline onto a second monitor",
            context: EditorIntentCompilerDiagnosticsFixtures.defaultContext
        )

        guard case .unsupported(let reason, _) = result else {
            Issue.record("Expected unsupported result")
            return
        }

        #expect(reason.contains("No local UI component") || reason.contains("No deterministic"))
    }

    @Test func fakeEmbeddingProviderCanResolveSemanticWorkspacePrompt() async {
        let provider = TestUIEmbeddingProvider()
        let resolver = EditorIntentEmbeddingResolver(
            provider: provider,
            examples: [
                EditorIntentEmbeddingExample(
                    id: "clean",
                    text: "clean workspace example",
                    source: .embedding,
                    operation: .applyWorkspace,
                    target: .workspaceRecipe(EditorJITRecipeCatalog.lessCluttered.id),
                    requestedSize: nil,
                    assumptions: []
                )
            ],
            minimumScore: 0.5
        )
        let compiler = EditorIntentCompiler(
            candidateGenerator: EditorIntentCandidateGenerator(embeddingResolver: resolver)
        )

        let result = await compiler.compile(
            prompt: "arrange a tidy interface",
            context: EditorIntentCompilerDiagnosticsFixtures.defaultContext
        )

        guard case .resolved(let state, _, let report) = result else {
            Issue.record("Expected resolved result")
            return
        }

        #expect(state.id == EditorJITRecipeCatalog.lessCluttered.id)
        #expect(report.selectedCandidate?.source == EditorIntentCandidateSource.embedding.rawValue)
    }
}

private func makeCompilerWithoutEmbeddings() -> EditorIntentCompiler {
    EditorIntentCompiler(
        candidateGenerator: EditorIntentCandidateGenerator(embeddingResolver: nil)
    )
}

private final class TestUIEmbeddingProvider: EditorUITextEmbeddingProvider {
    func embedding(for text: String) async throws -> [Float] {
        if text.contains("clean") || text.contains("tidy") {
            return [1, 0, 0]
        }
        return [0, 1, 0]
    }
}
