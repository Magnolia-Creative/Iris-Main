import Foundation

final class IntentPromptActionCompiler {
    private let llmCompiler: IntentLLMCompiler
    private let effectCapabilityRetriever: IntentEffectCapabilityRetriever
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
        self.effectCapabilityRetriever = IntentEffectCapabilityRetriever()
        self.validator = validator
    }

    init(
        deterministicCompiler: IntentDeterministicCompiler = IntentDeterministicCompiler(),
        embeddingRetriever: IntentEmbeddingRetriever,
        llmCompiler: IntentLLMCompiler,
        effectCapabilityRetriever: IntentEffectCapabilityRetriever = IntentEffectCapabilityRetriever(),
        validator: IntentActionValidator = IntentActionValidator()
    ) {
        _ = deterministicCompiler
        _ = embeddingRetriever
        self.llmCompiler = llmCompiler
        self.effectCapabilityRetriever = effectCapabilityRetriever
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

        print("[IntentCompiler] Semantic planner mode: routing abstract effects through capability retrieval.")
        let llmResult = await compileWithAbstractEffectFlow(prompt: prompt, context: context)
        print("[IntentCompiler] LLM result actions=\(llmResult.actions.count) experimentalEffects=\(llmResult.experimentalEffectOperations.count) confidence=\(llmResult.confidence) needsClarification=\(llmResult.needsClarification) warnings=\(llmResult.warnings)")
        print("[IntentCompiler][LLM] Raw action result:\n\(IntentCompilerLog.json(llmResult))")
        let validatedLLMResult = validator.validatedResult(llmResult, context: context)
        print("[IntentCompiler][LLM] Validated final result:\n\(IntentCompilerLog.json(validatedLLMResult))")
        return validatedLLMResult
    }
}

private extension IntentPromptActionCompiler {
    func compileWithAbstractEffectFlow(
        prompt: String,
        context: IntentCompilerContext
    ) async -> IntentCompileResult {
        do {
            let semanticPlan = try await llmCompiler.makeSemanticPlan(
                prompt: prompt,
                context: context,
                deterministicResult: nil,
                embeddingCandidates: []
            )
            let effectResolution = await resolveExperimentalEffects(
                prompt: prompt,
                context: context,
                semanticPlan: semanticPlan
            )
            let mergedPlan = SemanticEditPlan(
                operations: semanticPlan.operations,
                effectRequests: semanticPlan.effectRequests,
                experimentalEffectOperations: effectResolution.operations,
                needsClarification: semanticPlan.needsClarification,
                clarificationQuestion: semanticPlan.clarificationQuestion
            )
            let result = IntentCompiler().compile(mergedPlan, originalPrompt: prompt, context: context)
            return result.withAdditionalWarnings(effectResolution.warnings)
        } catch IntentCompilerError.llmUnavailable {
            print("[IntentCompiler] Provider reported llmUnavailable for prompt='\(prompt)'")
            return IntentCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: prompt,
                warnings: [.llmUnavailable],
                needsClarification: true
            )
        } catch {
            print("[IntentCompiler] Abstract effect flow failed with error: \(error)")
            return IntentCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: prompt,
                warnings: [.invalidLLMResponse],
                needsClarification: true
            )
        }
    }

    func resolveExperimentalEffects(
        prompt: String,
        context: IntentCompilerContext,
        semanticPlan: SemanticEditPlan
    ) async -> (operations: [ExperimentalEffectOperation], warnings: [IntentCompileWarning]) {
        var operations: [ExperimentalEffectOperation] = []
        var warnings: [IntentCompileWarning] = []

        for effectRequest in semanticPlan.effectRequests {
            do {
                let relevantCapabilities = try await effectCapabilityRetriever.relevantCapabilities(for: effectRequest)
                guard relevantCapabilities.isEmpty == false else {
                    print("[IntentCompiler][EffectRAG] No capabilities matched request='\(effectRequest.intent)'")
                    warnings.append(.unsupportedIntent)
                    continue
                }

                let effectPlan = try await llmCompiler.planExperimentalEffects(
                    originalPrompt: prompt,
                    effectRequest: effectRequest,
                    relevantCapabilities: relevantCapabilities,
                    context: context
                )
                let validated = validate(
                    effectOperations: effectPlan.operations,
                    relevantCapabilities: relevantCapabilities
                )
                operations.append(contentsOf: validated.operations)
                warnings.append(contentsOf: validated.warnings)
            } catch IntentCompilerError.embeddingUnavailable {
                print("[IntentCompiler][EffectRAG] Embedding unavailable for request='\(effectRequest.intent)'")
                warnings.append(.embeddingUnavailable)
            } catch IntentCompilerError.llmUnavailable {
                print("[IntentCompiler][EffectRAG] LLM unavailable while planning effects request='\(effectRequest.intent)'")
                warnings.append(.llmUnavailable)
            } catch {
                print("[IntentCompiler][EffectRAG] Effect planning failed request='\(effectRequest.intent)' error=\(error)")
                warnings.append(.invalidLLMResponse)
            }
        }

        return (operations, warnings)
    }

    func validate(
        effectOperations: [ExperimentalEffectOperation],
        relevantCapabilities: [RelevantEffectCapability]
    ) -> (operations: [ExperimentalEffectOperation], warnings: [IntentCompileWarning]) {
        let capabilitiesByOperation = Dictionary(
            uniqueKeysWithValues: relevantCapabilities.map { ($0.capability.operation, $0.capability) }
        )
        var validOperations: [ExperimentalEffectOperation] = []
        var warnings: [IntentCompileWarning] = []

        for operation in effectOperations {
            guard let capability = capabilitiesByOperation[operation.operation] else {
                warnings.append(.unsupportedAction)
                continue
            }

            let clampedParameters = clampedParameters(
                operation.parameters,
                schema: capability.parameters
            )
            validOperations.append(
                ExperimentalEffectOperation(
                    operation: operation.operation,
                    sourceText: operation.sourceText,
                    intention: operation.intention,
                    target: operation.target,
                    confidence: operation.confidence,
                    parameters: clampedParameters
                )
            )
        }

        return (validOperations, warnings)
    }

    func clampedParameters(
        _ parameters: [String: JSONValue],
        schema: [EffectCapabilityParameter]
    ) -> [String: JSONValue] {
        var clamped = parameters
        for parameter in schema where parameter.valueType == "number" {
            guard let value = parameters[parameter.name]?.doubleValue else { continue }
            let minimum = parameter.minimum ?? value
            let maximum = parameter.maximum ?? value
            clamped[parameter.name] = .double(min(max(value, minimum), maximum))
        }
        return clamped
    }
}

private extension IntentCompileResult {
    func withAdditionalWarnings(_ additionalWarnings: [IntentCompileWarning]) -> IntentCompileResult {
        guard additionalWarnings.isEmpty == false else { return self }
        var seen = Set<IntentCompileWarning>()
        let mergedWarnings = (warnings + additionalWarnings).filter { seen.insert($0).inserted }
        return IntentCompileResult(
            actions: actions,
            confidence: confidence,
            source: source,
            unresolvedText: unresolvedText,
            warnings: mergedWarnings,
            needsClarification: needsClarification,
            experimentalEffectOperations: experimentalEffectOperations
        )
    }
}

func compilePromptToActions(
    prompt: String,
    context: IntentCompilerContext
) async throws -> IntentCompileResult {
    try await IntentPromptActionCompiler().compilePromptToActions(prompt: prompt, context: context)
}
