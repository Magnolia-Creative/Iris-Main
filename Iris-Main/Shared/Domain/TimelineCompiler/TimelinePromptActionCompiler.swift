import Foundation

final class TimelinePromptActionCompiler {
    private let deterministicCompiler: TimelineDeterministicCompiler
    private let embeddingRetriever: TimelineEmbeddingIntentRetriever
    private let llmCompiler: TimelineLLMCompiler
    private let validator: TimelineActionValidator

    init(
        deterministicCompiler: TimelineDeterministicCompiler = TimelineDeterministicCompiler(),
        embeddingProvider: EmbeddingProvider = MobileCLIPTextEmbeddingProvider(),
        llmProvider: TimelineLLMProvider = ZeticGemmaTimelineLLMProvider(),
        validator: TimelineActionValidator = TimelineActionValidator()
    ) {
        self.deterministicCompiler = deterministicCompiler
        self.embeddingRetriever = TimelineEmbeddingIntentRetriever(embeddingProvider: embeddingProvider)
        self.llmCompiler = TimelineLLMCompiler(provider: llmProvider)
        self.validator = validator
    }

    init(
        deterministicCompiler: TimelineDeterministicCompiler = TimelineDeterministicCompiler(),
        embeddingRetriever: TimelineEmbeddingIntentRetriever,
        llmCompiler: TimelineLLMCompiler,
        validator: TimelineActionValidator = TimelineActionValidator()
    ) {
        self.deterministicCompiler = deterministicCompiler
        self.embeddingRetriever = embeddingRetriever
        self.llmCompiler = llmCompiler
        self.validator = validator
    }

    func compilePromptToActions(
        prompt: String,
        context: TimelineCompilerContext
    ) async throws -> TimelineCompileResult {
        let normalizedPrompt = TimelinePromptNormalizer.normalize(prompt)
        guard normalizedPrompt.isEmpty == false else {
            return TimelineCompileResult(
                actions: [],
                confidence: 0,
                source: .deterministic,
                unresolvedText: prompt,
                warnings: [.noActionProduced],
                needsClarification: true
            )
        }

        let deterministicResult = deterministicCompiler.compile(prompt: normalizedPrompt, context: context)
        if let deterministicResult {
            let validated = validator.validatedResult(deterministicResult, context: context)
            if shouldEarlyExit(validated, minimumConfidence: 0.95, context: context) {
                return validated
            }
            if validated.needsClarification {
                return validated
            }
        }

        let embeddingCandidates: [TimelineEmbeddingCandidate]
        do {
            embeddingCandidates = try await embeddingRetriever.candidates(for: normalizedPrompt)
        } catch {
            embeddingCandidates = []
        }

        if let highConfidenceCandidate = embeddingCandidates.first,
           let embeddingResult = embeddingRetriever.compileHighConfidenceCandidate(
               highConfidenceCandidate,
               prompt: normalizedPrompt,
               context: context
           ) {
            let validated = validator.validatedResult(embeddingResult, context: context)
            if shouldEarlyExit(validated, minimumConfidence: TimelineEmbeddingIntentRetriever.earlyExitThreshold, context: context) {
                return validated
            }
            if validated.needsClarification {
                return validated
            }
        }

        let llmResult = await llmCompiler.compile(
            prompt: prompt,
            context: context,
            deterministicResult: deterministicResult,
            embeddingCandidates: embeddingCandidates
        )
        return validator.validatedResult(llmResult, context: context)
    }
}

func compilePromptToActions(
    prompt: String,
    context: TimelineCompilerContext
) async throws -> TimelineCompileResult {
    try await TimelinePromptActionCompiler().compilePromptToActions(prompt: prompt, context: context)
}

private extension TimelinePromptActionCompiler {
    func shouldEarlyExit(
        _ result: TimelineCompileResult,
        minimumConfidence: Double,
        context: TimelineCompilerContext
    ) -> Bool {
        result.confidence >= minimumConfidence
            && result.actions.isEmpty == false
            && result.needsClarification == false
            && unresolvedTextIsEmptyOrConnectorOnly(result.unresolvedText)
            && validator.isExecutable(result, context: context)
    }

    func unresolvedTextIsEmptyOrConnectorOnly(_ text: String?) -> Bool {
        guard let text else { return true }
        let normalized = TimelinePromptNormalizer.normalize(text)
        return normalized.isEmpty
            || ["and", "then", "also", "and then"].contains(normalized)
    }
}
