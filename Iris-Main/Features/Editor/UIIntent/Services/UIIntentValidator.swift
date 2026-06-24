import Foundation

struct UIIntentValidationOutput: Equatable {
    let renderState: EditorJITRenderState
    let validationResult: EditorJITValidationResult
    let isNoOp: Bool
}

struct UIIntentValidator {
    func validate(
        buildResult: UIIntentSchemaBuildResult,
        candidate: EditorUIIntentCandidate,
        context: EditorUICompilerContext
    ) -> UIIntentValidationOutput {
        let supportErrors = supportErrors(for: candidate)
        let (validatedState, renderValidation) = EditorJITRenderValidator.validate(buildResult.renderState)
        let isNoOp = validatedState == context.currentRenderState

        var warnings = buildResult.warnings + renderValidation.warnings
        if isNoOp {
            warnings.append("Request does not change the current UI state.")
        }

        let result = EditorJITValidationResult(
            isValid: renderValidation.isValid && supportErrors.isEmpty,
            warnings: warnings,
            errors: renderValidation.errors + supportErrors
        )

        let state = EditorJITRenderState(
            id: validatedState.id,
            title: validatedState.title,
            promptExample: validatedState.promptExample,
            resolutionCategory: validatedState.resolutionCategory,
            playback: validatedState.playback,
            timeline: validatedState.timeline,
            chromePlan: validatedState.chromePlan,
            validationWarnings: warnings,
            isValid: result.isValid
        )

        return UIIntentValidationOutput(
            renderState: state,
            validationResult: result,
            isNoOp: isNoOp
        )
    }

    private func supportErrors(for candidate: EditorUIIntentCandidate) -> [String] {
        guard let capability = UIIntentLexicon.capability(for: candidate.target) else {
            return ["Unsupported UI target '\(candidate.target.displayName)'."]
        }

        var errors: [String] = []
        if !capability.supportedOperations.contains(candidate.operation) {
            errors.append("Operation '\(candidate.operation.rawValue)' is unsupported for '\(candidate.target.displayName)'.")
        }
        if let requestedSize = candidate.requestedSize,
           !capability.supportedSizes.contains(requestedSize) {
            errors.append("Size '\(requestedSize.rawValue)' is unsupported for '\(candidate.target.displayName)'.")
        }
        return errors
    }
}
