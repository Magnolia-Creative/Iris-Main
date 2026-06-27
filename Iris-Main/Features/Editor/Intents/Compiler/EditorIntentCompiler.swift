import Foundation

struct EditorIntentCompiler {
    private let candidateGenerator: EditorIntentCandidateGenerator
    private let ranker: EditorIntentCandidateRanker
    private let schemaBuilder: EditorIntentSchemaBuilder
    private let validator: EditorIntentCompilerValidator

    init(
        candidateGenerator: EditorIntentCandidateGenerator = EditorIntentCandidateGenerator(),
        ranker: EditorIntentCandidateRanker = EditorIntentCandidateRanker(),
        schemaBuilder: EditorIntentSchemaBuilder = EditorIntentSchemaBuilder(),
        validator: EditorIntentCompilerValidator = EditorIntentCompilerValidator()
    ) {
        self.candidateGenerator = candidateGenerator
        self.ranker = ranker
        self.schemaBuilder = schemaBuilder
        self.validator = validator
    }

    func compile(
        prompt: String,
        context: EditorIntentCompilerContext
    ) async -> EditorIntentCompilerResult {
        let normalized = EditorIntentPromptNormalizer.normalize(prompt)
        guard !normalized.normalizedText.isEmpty else {
            let report = makeReport(
                interpretation: "No prompt text was provided.",
                normalized: normalized,
                scoredCandidates: [],
                selected: nil,
                renderState: nil,
                validationWarnings: [],
                validationErrors: ["Enter a prompt to compile."]
            )
            return .unsupported(reason: "Enter a prompt to compile.", report: report)
        }

        let generation = await candidateGenerator.candidates(for: normalized, context: context)
        let ranked = ranker.rank(candidates: generation.candidates, context: context)

        switch ranked {
        case .selected(let scoredCandidate):
            return resolve(
                scoredCandidate: scoredCandidate,
                normalized: normalized,
                context: context,
                embeddingWarnings: generation.embeddingWarnings
            )
        case .ambiguous(let scoredCandidates):
            let options = scoredCandidates.map { scored in
                EditorIntentClarificationOption(
                    id: scored.candidate.id,
                    title: scored.candidate.target.displayName,
                    subtitle: "\(scored.candidate.operation.rawValue) · score \(String(format: "%.2f", scored.score))"
                )
            }
            let report = makeReport(
                interpretation: "Multiple UI interpretations are plausible.",
                normalized: normalized,
                scoredCandidates: scoredCandidates,
                selected: nil,
                renderState: nil,
                validationWarnings: generation.embeddingWarnings.map(\.rawValue),
                validationErrors: []
            )
            return .clarificationRequired(options: options, report: report)
        case .deferred(let reason, let scoredCandidates):
            let request = remoteRequest(
                prompt: prompt,
                normalized: normalized,
                candidates: scoredCandidates,
                context: context,
                reason: reason
            )
            let report = makeReport(
                interpretation: reason,
                normalized: normalized,
                scoredCandidates: scoredCandidates,
                selected: nil,
                renderState: nil,
                validationWarnings: generation.embeddingWarnings.map(\.rawValue),
                validationErrors: []
            )
            return .deferredToRemote(request: request, report: report)
        case .unsupported(let reason):
            if shouldDeferUnsupportedPrompt(normalized) {
                let request = remoteRequest(
                    prompt: prompt,
                    normalized: normalized,
                    candidates: [],
                    context: context,
                    reason: "No deterministic local UI capability matched the prompt."
                )
                let report = makeReport(
                    interpretation: request.reason,
                    normalized: normalized,
                    scoredCandidates: [],
                    selected: nil,
                    renderState: nil,
                    validationWarnings: generation.embeddingWarnings.map(\.rawValue),
                    validationErrors: []
                )
                return .deferredToRemote(request: request, report: report)
            }

            let report = makeReport(
                interpretation: reason,
                normalized: normalized,
                scoredCandidates: [],
                selected: nil,
                renderState: nil,
                validationWarnings: generation.embeddingWarnings.map(\.rawValue),
                validationErrors: [reason]
            )
            return .unsupported(reason: reason, report: report)
        }
    }
}

private extension EditorIntentCompiler {
    func resolve(
        scoredCandidate: EditorIntentScoredCandidate,
        normalized: NormalizedEditorIntentPrompt,
        context: EditorIntentCompilerContext,
        embeddingWarnings: [EditorIntentEmbeddingResolverWarning]
    ) -> EditorIntentCompilerResult {
        let candidate = scoredCandidate.candidate
        guard let buildResult = schemaBuilder.build(from: candidate, context: context, prompt: normalized) else {
            let reason = "The selected editor intent could not be represented with existing editor schema."
            let report = makeReport(
                interpretation: reason,
                normalized: normalized,
                scoredCandidates: [scoredCandidate],
                selected: scoredCandidate,
                renderState: nil,
                validationWarnings: embeddingWarnings.map(\.rawValue),
                validationErrors: [reason]
            )
            return .unsupported(reason: reason, report: report)
        }

        let validation = validator.validate(
            buildResult: buildResult,
            candidate: candidate,
            context: context
        )
        let warnings = embeddingWarnings.map(\.rawValue) + validation.validationResult.warnings
        let interpretation = interpretation(for: candidate, validation: validation)
        let report = makeReport(
            interpretation: interpretation,
            normalized: normalized,
            scoredCandidates: [scoredCandidate],
            selected: scoredCandidate,
            renderState: validation.renderState,
            validationWarnings: warnings,
            validationErrors: validation.validationResult.errors
        )

        guard validation.validationResult.isValid else {
            let reason = validation.validationResult.errors.first ?? "The requested UI state is invalid."
            return .unsupported(reason: reason, report: report)
        }

        return .resolved(
            renderState: validation.renderState,
            interpretation: interpretation,
            report: report
        )
    }

    func interpretation(
        for candidate: EditorIntentCandidate,
        validation: EditorIntentValidationOutput
    ) -> String {
        var text = "\(candidate.operation.rawValue) \(candidate.target.displayName)"
        if let requestedSize = candidate.requestedSize {
            text += " as \(requestedSize.rawValue)"
        }
        if validation.isNoOp {
            text += " (already current)"
        }
        return text
    }

    func makeReport(
        interpretation: String,
        normalized: NormalizedEditorIntentPrompt,
        scoredCandidates: [EditorIntentScoredCandidate],
        selected: EditorIntentScoredCandidate?,
        renderState: EditorJITRenderState?,
        validationWarnings: [String],
        validationErrors: [String]
    ) -> EditorIntentCompilerReport {
        EditorIntentCompilerReport(
            interpretation: interpretation,
            normalizedPrompt: normalized.normalizedText,
            selectedCandidate: selected.map { EditorIntentCandidateDiagnostic(candidate: $0.candidate, score: $0.score) },
            candidates: scoredCandidates.map { EditorIntentCandidateDiagnostic(candidate: $0.candidate, score: $0.score) },
            renderState: renderState.map(EditorIntentRenderStateSnapshot.init),
            validationWarnings: validationWarnings,
            validationErrors: validationErrors
        )
    }

    func remoteRequest(
        prompt: String,
        normalized: NormalizedEditorIntentPrompt,
        candidates: [EditorIntentScoredCandidate],
        context: EditorIntentCompilerContext,
        reason: String
    ) -> EditorIntentRemoteResolutionRequest {
        let supportedStates = Dictionary(
            uniqueKeysWithValues: EditorComponentRegistry.entries.map { entry in
                (entry.id.rawValue, entry.supportedSizes.map(\.rawValue).sorted())
            }
        )
        return EditorIntentRemoteResolutionRequest(
            prompt: prompt,
            normalizedPrompt: normalized.normalizedText,
            activeSpace: context.activeSpace.rawValue,
            availableComponentIds: EditorComponentRegistry.entries.map(\.id.rawValue).sorted(),
            supportedStates: supportedStates,
            localCandidates: candidates.map { EditorIntentCandidateDiagnostic(candidate: $0.candidate, score: $0.score) },
            reason: reason
        )
    }

    func shouldDeferUnsupportedPrompt(_ prompt: NormalizedEditorIntentPrompt) -> Bool {
        let unsupportedTerms = [
            "second monitor",
            "external display",
            "floating window",
            "new panel",
            "separate window"
        ]
        if unsupportedTerms.contains(where: { prompt.normalizedText.contains($0) }) {
            return false
        }
        return true
    }
}
