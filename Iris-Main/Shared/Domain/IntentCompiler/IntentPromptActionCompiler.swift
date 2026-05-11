import Foundation

final class IntentPromptActionCompiler {
    private let deterministicCompiler: IntentDeterministicCompiler
    private let embeddingRetriever: IntentEmbeddingRetriever
    private let llmCompiler: IntentLLMCompiler
    private let validator: IntentActionValidator

    init(
        deterministicCompiler: IntentDeterministicCompiler = IntentDeterministicCompiler(),
        embeddingProvider: EmbeddingProvider = MobileCLIPTextEmbeddingProvider(),
        llmProvider: IntentLLMProvider = IntentLLMBackend.appleFoundation.makeProvider(),
        validator: IntentActionValidator = IntentActionValidator()
    ) {
        self.deterministicCompiler = deterministicCompiler
        self.embeddingRetriever = IntentEmbeddingRetriever(embeddingProvider: embeddingProvider)
        self.llmCompiler = IntentLLMCompiler(provider: llmProvider)
        self.validator = validator
    }

    init(
        deterministicCompiler: IntentDeterministicCompiler = IntentDeterministicCompiler(),
        embeddingRetriever: IntentEmbeddingRetriever,
        llmCompiler: IntentLLMCompiler,
        validator: IntentActionValidator = IntentActionValidator()
    ) {
        self.deterministicCompiler = deterministicCompiler
        self.embeddingRetriever = embeddingRetriever
        self.llmCompiler = llmCompiler
        self.validator = validator
    }

    func compilePromptToActions(
        prompt: String,
        context: IntentCompilerContext
    ) async throws -> IntentCompileResult {
        let normalizedPrompt = IntentPromptNormalizer.normalize(prompt)
        print("[IntentCompiler] Compile start prompt='\(prompt)' normalized='\(normalizedPrompt)'")
        guard normalizedPrompt.isEmpty == false else {
            print("[IntentCompiler] Empty prompt after normalization.")
            return IntentCompileResult(
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
            print("[IntentCompiler] Deterministic result actions=\(validated.actions.count) confidence=\(validated.confidence) needsClarification=\(validated.needsClarification) warnings=\(validated.warnings)")
            if shouldEarlyExit(validated, minimumConfidence: 0.95, context: context) {
                print("[IntentCompiler] Early exit with deterministic result.")
                return validated
            }
            if validated.needsClarification {
                print("[IntentCompiler] Returning deterministic clarification.")
                return validated
            }
        } else {
            print("[IntentCompiler] Deterministic compiler produced no result.")
        }

        let embeddingCandidates: [IntentEmbeddingCandidate]
        do {
            embeddingCandidates = try await embeddingRetriever.candidates(for: normalizedPrompt)
            print("[IntentCompiler] Embedding candidates count=\(embeddingCandidates.count) topScore=\(embeddingCandidates.first?.score.description ?? "nil") topType=\(embeddingCandidates.first?.type.rawValue ?? "nil")")
        } catch {
            print("[IntentCompiler] Embedding retrieval failed: \(error)")
            embeddingCandidates = []
        }

        if let highConfidenceCandidate = embeddingCandidates.first,
           let embeddingResult = embeddingRetriever.compileHighConfidenceCandidate(
               highConfidenceCandidate,
               prompt: normalizedPrompt,
               context: context
           ) {
            let validated = validator.validatedResult(embeddingResult, context: context)
            print("[IntentCompiler] Embedding result actions=\(validated.actions.count) confidence=\(validated.confidence) needsClarification=\(validated.needsClarification) warnings=\(validated.warnings)")
            if shouldEarlyExit(validated, minimumConfidence: IntentEmbeddingRetriever.earlyExitThreshold, context: context) {
                print("[IntentCompiler] Early exit with embedding result.")
                return validated
            }
            if validated.needsClarification {
                print("[IntentCompiler] Returning embedding clarification.")
                return validated
            }
        } else {
            print("[IntentCompiler] No high-confidence embedding action resolved; falling back to LLM.")
        }

        let llmResult = await llmCompiler.compile(
            prompt: prompt,
            context: context,
            deterministicResult: deterministicResult,
            embeddingCandidates: embeddingCandidates
        )
        print("[IntentCompiler] LLM result actions=\(llmResult.actions.count) confidence=\(llmResult.confidence) needsClarification=\(llmResult.needsClarification) warnings=\(llmResult.warnings)")
        return validator.validatedResult(llmResult, context: context)
    }
}

func compilePromptToActions(
    prompt: String,
    context: IntentCompilerContext
) async throws -> IntentCompileResult {
    try await IntentPromptActionCompiler().compilePromptToActions(prompt: prompt, context: context)
}

private extension IntentPromptActionCompiler {
    func shouldEarlyExit(
        _ result: IntentCompileResult,
        minimumConfidence: Double,
        context: IntentCompilerContext
    ) -> Bool {
        result.confidence >= minimumConfidence
            && result.actions.isEmpty == false
            && result.needsClarification == false
            && unresolvedTextIsEmptyOrConnectorOnly(result.unresolvedText)
            && validator.isExecutable(result, context: context)
    }

    func unresolvedTextIsEmptyOrConnectorOnly(_ text: String?) -> Bool {
        guard let text else { return true }
        let normalized = IntentPromptNormalizer.normalize(text)
        return normalized.isEmpty
            || ["and", "then", "also", "and then"].contains(normalized)
    }
}
