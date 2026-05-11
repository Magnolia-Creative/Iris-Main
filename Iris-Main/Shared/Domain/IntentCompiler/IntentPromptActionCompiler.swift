import Foundation

final class IntentPromptActionCompiler {
    private let llmCompiler: IntentLLMCompiler
    private let validator: IntentActionValidator

    init(
        deterministicCompiler: IntentDeterministicCompiler = IntentDeterministicCompiler(),
        embeddingProvider: EmbeddingProvider = MobileCLIPTextEmbeddingProvider(),
        llmProvider: IntentLLMProvider = IntentLLMBackend.appleFoundation.makeProvider(),
        validator: IntentActionValidator = IntentActionValidator()
    ) {
        _ = deterministicCompiler
        _ = embeddingProvider
        self.llmCompiler = IntentLLMCompiler(provider: llmProvider)
        self.validator = validator
    }

    init(
        deterministicCompiler: IntentDeterministicCompiler = IntentDeterministicCompiler(),
        embeddingRetriever: IntentEmbeddingRetriever,
        llmCompiler: IntentLLMCompiler,
        validator: IntentActionValidator = IntentActionValidator()
    ) {
        _ = deterministicCompiler
        _ = embeddingRetriever
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

        print("[IntentCompiler] LLM-only mode: skipping deterministic and embedding stages.")
        let llmResult = await llmCompiler.compile(
            prompt: prompt,
            context: context,
            deterministicResult: nil,
            embeddingCandidates: []
        )
        print("[IntentCompiler] LLM result actions=\(llmResult.actions.count) confidence=\(llmResult.confidence) needsClarification=\(llmResult.needsClarification) warnings=\(llmResult.warnings)")
        print("[IntentCompiler][LLM] Raw action result:\n\(IntentCompilerLog.json(llmResult))")
        let validatedLLMResult = validator.validatedResult(llmResult, context: context)
        print("[IntentCompiler][LLM] Validated final result:\n\(IntentCompilerLog.json(validatedLLMResult))")
        return validatedLLMResult
    }
}

func compilePromptToActions(
    prompt: String,
    context: IntentCompilerContext
) async throws -> IntentCompileResult {
    try await IntentPromptActionCompiler().compilePromptToActions(prompt: prompt, context: context)
}
