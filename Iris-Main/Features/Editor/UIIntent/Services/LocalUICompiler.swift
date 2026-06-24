import Foundation

struct LocalUICompiler {
    private let candidateGenerator: UIIntentCandidateGenerator
    private let ranker: UIIntentCandidateRanker
    private let schemaBuilder: UIIntentSchemaBuilder
    private let validator: UIIntentValidator

    init(
        candidateGenerator: UIIntentCandidateGenerator = UIIntentCandidateGenerator(),
        ranker: UIIntentCandidateRanker = UIIntentCandidateRanker(),
        schemaBuilder: UIIntentSchemaBuilder = UIIntentSchemaBuilder(),
        validator: UIIntentValidator = UIIntentValidator()
    ) {
        self.candidateGenerator = candidateGenerator
        self.ranker = ranker
        self.schemaBuilder = schemaBuilder
        self.validator = validator
    }

    func compile(
        prompt: String,
        context: EditorUICompilerContext
    ) async -> EditorUICompilerResult {
        let normalized = UIPromptNormalizer.normalize(prompt)
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
                UIIntentClarificationOption(
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

private extension LocalUICompiler {
    func resolve(
        scoredCandidate: UIIntentScoredCandidate,
        normalized: NormalizedEditorUIPrompt,
        context: EditorUICompilerContext,
        embeddingWarnings: [UIEmbeddingResolverWarning]
    ) -> EditorUICompilerResult {
        let candidate = scoredCandidate.candidate
        guard let buildResult = schemaBuilder.build(from: candidate, context: context, prompt: normalized) else {
            let reason = "The selected UI intent could not be represented with existing editor schema."
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
        for candidate: EditorUIIntentCandidate,
        validation: UIIntentValidationOutput
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
        normalized: NormalizedEditorUIPrompt,
        scoredCandidates: [UIIntentScoredCandidate],
        selected: UIIntentScoredCandidate?,
        renderState: EditorJITRenderState?,
        validationWarnings: [String],
        validationErrors: [String]
    ) -> UIIntentCompilerReport {
        UIIntentCompilerReport(
            interpretation: interpretation,
            normalizedPrompt: normalized.normalizedText,
            selectedCandidate: selected.map { UIIntentCandidateDiagnostic(candidate: $0.candidate, score: $0.score) },
            candidates: scoredCandidates.map { UIIntentCandidateDiagnostic(candidate: $0.candidate, score: $0.score) },
            renderState: renderState.map(UIIntentRenderStateSnapshot.init),
            validationWarnings: validationWarnings,
            validationErrors: validationErrors
        )
    }

    func remoteRequest(
        prompt: String,
        normalized: NormalizedEditorUIPrompt,
        candidates: [UIIntentScoredCandidate],
        context: EditorUICompilerContext,
        reason: String
    ) -> EditorUIRemoteResolutionRequest {
        let supportedStates = Dictionary(
            uniqueKeysWithValues: EditorComponentRegistry.entries.map { entry in
                (entry.id.rawValue, entry.supportedSizes.map(\.rawValue).sorted())
            }
        )
        return EditorUIRemoteResolutionRequest(
            prompt: prompt,
            normalizedPrompt: normalized.normalizedText,
            activeSpace: context.activeSpace.rawValue,
            availableComponentIds: EditorComponentRegistry.entries.map(\.id.rawValue).sorted(),
            supportedStates: supportedStates,
            localCandidates: candidates.map { UIIntentCandidateDiagnostic(candidate: $0.candidate, score: $0.score) },
            reason: reason
        )
    }

    func shouldDeferUnsupportedPrompt(_ prompt: NormalizedEditorUIPrompt) -> Bool {
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
