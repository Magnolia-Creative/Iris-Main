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
        print("[TimelineCompiler] Compile start prompt='\(prompt)' normalized='\(normalizedPrompt)'")
        guard normalizedPrompt.isEmpty == false else {
            print("[TimelineCompiler] Empty prompt after normalization.")
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
            print("[TimelineCompiler] Deterministic result actions=\(validated.actions.count) confidence=\(validated.confidence) needsClarification=\(validated.needsClarification) warnings=\(validated.warnings)")
            if shouldEarlyExit(validated, minimumConfidence: 0.95, context: context) {
                print("[TimelineCompiler] Early exit with deterministic result.")
                return validated
            }
            if validated.needsClarification {
                print("[TimelineCompiler] Returning deterministic clarification.")
                return validated
            }
        } else {
            print("[TimelineCompiler] Deterministic compiler produced no result.")
        }

        let embeddingCandidates: [TimelineEmbeddingCandidate]
        do {
            embeddingCandidates = try await embeddingRetriever.candidates(for: normalizedPrompt)
            print("[TimelineCompiler] Embedding candidates count=\(embeddingCandidates.count) topScore=\(embeddingCandidates.first?.score.description ?? "nil") topType=\(embeddingCandidates.first?.type.rawValue ?? "nil")")
        } catch {
            print("[TimelineCompiler] Embedding retrieval failed: \(error)")
            embeddingCandidates = []
        }

        if let highConfidenceCandidate = embeddingCandidates.first,
           let embeddingResult = embeddingRetriever.compileHighConfidenceCandidate(
               highConfidenceCandidate,
               prompt: normalizedPrompt,
               context: context
           ) {
            let validated = validator.validatedResult(embeddingResult, context: context)
            print("[TimelineCompiler] Embedding result actions=\(validated.actions.count) confidence=\(validated.confidence) needsClarification=\(validated.needsClarification) warnings=\(validated.warnings)")
            if shouldEarlyExit(validated, minimumConfidence: TimelineEmbeddingIntentRetriever.earlyExitThreshold, context: context) {
                print("[TimelineCompiler] Early exit with embedding result.")
                return validated
            }
            if validated.needsClarification {
                print("[TimelineCompiler] Returning embedding clarification.")
                return validated
            }
        } else {
            print("[TimelineCompiler] No high-confidence embedding action resolved; falling back to LLM.")
        }

        let llmResult = await llmCompiler.compile(
            prompt: prompt,
            context: context,
            deterministicResult: deterministicResult,
            embeddingCandidates: embeddingCandidates
        )
        print("[TimelineCompiler] LLM result actions=\(llmResult.actions.count) confidence=\(llmResult.confidence) needsClarification=\(llmResult.needsClarification) warnings=\(llmResult.warnings)")
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
