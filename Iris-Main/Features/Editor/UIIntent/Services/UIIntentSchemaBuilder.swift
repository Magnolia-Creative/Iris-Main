import Foundation

struct UIIntentSchemaBuildResult: Equatable {
    let renderState: EditorJITRenderState
    let warnings: [String]
}

struct UIIntentSchemaBuilder {
    func build(
        from candidate: EditorUIIntentCandidate,
        context: EditorUICompilerContext,
        prompt: NormalizedEditorUIPrompt
    ) -> UIIntentSchemaBuildResult? {
        switch candidate.target {
        case .workspaceRecipe(let recipeId):
            guard let recipe = EditorJITRecipeCatalog.recipe(id: recipeId) else { return nil }
            return UIIntentSchemaBuildResult(renderState: recipe.makeRawState(), warnings: [])
        case .component:
            return buildComponentState(from: candidate, context: context, prompt: prompt)
        case .chromeControls:
            return buildChromeControlsState(from: candidate, context: context, prompt: prompt)
        }
    }
}

private extension UIIntentSchemaBuilder {
    func buildComponentState(
        from candidate: EditorUIIntentCandidate,
        context: EditorUICompilerContext,
        prompt: NormalizedEditorUIPrompt
    ) -> UIIntentSchemaBuildResult? {
        guard case .component(let componentId) = candidate.target else { return nil }

        var playback = context.currentRenderState.playback
        var timeline = context.currentRenderState.timeline
        var chromePlan = context.currentRenderState.chromePlan
        var warnings: [String] = []

        let nextState = componentState(
            componentId: componentId,
            operation: candidate.operation,
            requestedSize: candidate.requestedSize
        )

        if componentId.rawValue.hasPrefix("playback.") {
            playback = nextState
            if playback.isVisible && playback.size == .expanded && timeline.isVisible && timeline.size == .expanded {
                timeline.size = .compressed
                warnings.append("Compressed timeline because preview was expanded.")
            }
        } else if componentId.rawValue.hasPrefix("timeline.") {
            timeline = nextState
            if timeline.isVisible && timeline.size == .expanded && playback.isVisible && playback.size == .expanded {
                playback.size = .compressed
                warnings.append("Compressed preview because timeline was expanded.")
            }
        } else if componentId.rawValue.hasPrefix("toolbar.") || componentId.rawValue.hasPrefix("chrome.") {
            chromePlan = chromePlan(for: candidate.operation, requestedSize: candidate.requestedSize)
        } else {
            return nil
        }

        return UIIntentSchemaBuildResult(
            renderState: renderState(
                prompt: prompt,
                candidate: candidate,
                playback: playback,
                timeline: timeline,
                chromePlan: chromePlan,
                warnings: warnings
            ),
            warnings: warnings
        )
    }

    func buildChromeControlsState(
        from candidate: EditorUIIntentCandidate,
        context: EditorUICompilerContext,
        prompt: NormalizedEditorUIPrompt
    ) -> UIIntentSchemaBuildResult {
        let chromePlan = chromePlan(
            for: candidate.operation,
            requestedSize: candidate.requestedSize
        )
        return UIIntentSchemaBuildResult(
            renderState: renderState(
                prompt: prompt,
                candidate: candidate,
                playback: context.currentRenderState.playback,
                timeline: context.currentRenderState.timeline,
                chromePlan: chromePlan,
                warnings: []
            ),
            warnings: []
        )
    }

    func componentState(
        componentId: EditorComponentID,
        operation: UIIntentOperation,
        requestedSize: EditorComponentSize?
    ) -> EditorJITComponentState {
        switch operation {
        case .hide:
            return .hidden(componentId)
        case .compress:
            return .visible(componentId, size: .compressed)
        case .expand, .focus:
            return .visible(componentId, size: requestedSize ?? .expanded)
        case .show, .restore:
            return .visible(componentId, size: requestedSize ?? .standard)
        case .applyWorkspace:
            return .visible(componentId, size: requestedSize ?? .standard)
        }
    }

    func chromePlan(
        for operation: UIIntentOperation,
        requestedSize: EditorComponentSize?
    ) -> EditorBottomChromePlan {
        switch operation {
        case .hide:
            return EditorBottomChromePlan(
                density: .compact,
                parameterGroups: [],
                actions: [],
                showsDock: true
            )
        case .compress:
            return EditorBottomChromePlan(
                density: .compact,
                parameterGroups: [EditorChromePreviewFixtures.colorGroup],
                actions: [],
                showsDock: true,
                activeParameterGroupId: EditorChromePreviewFixtures.colorGroup.id
            )
        case .expand, .focus:
            return EditorBottomChromePlan(
                density: .expanded,
                parameterGroups: EditorChromePreviewFixtures.parameterGroups(for: .fourPlusGroups),
                actions: EditorChromePreviewFixtures.defaultActions,
                showsDock: true,
                activeParameterGroupId: EditorChromePreviewFixtures.colorGroup.id
            )
        case .show, .restore, .applyWorkspace:
            return EditorBottomChromePlan(
                density: density(for: requestedSize),
                parameterGroups: EditorChromePreviewFixtures.parameterGroups(for: .twoGroups),
                actions: EditorChromePreviewFixtures.defaultActions,
                showsDock: true,
                activeParameterGroupId: EditorChromePreviewFixtures.colorGroup.id
            )
        }
    }

    func density(for size: EditorComponentSize?) -> EditorBottomChromeDensity {
        switch size {
        case .compressed: return .compact
        case .expanded: return .expanded
        case .standard, .none: return .standard
        }
    }

    func renderState(
        prompt: NormalizedEditorUIPrompt,
        candidate: EditorUIIntentCandidate,
        playback: EditorJITComponentState,
        timeline: EditorJITComponentState,
        chromePlan: EditorBottomChromePlan,
        warnings: [String]
    ) -> EditorJITRenderState {
        EditorJITRenderState(
            id: "ui-intent-\(candidate.id.sanitizedUIIntentId)",
            title: title(for: candidate),
            promptExample: prompt.originalText,
            resolutionCategory: category(for: candidate.source),
            playback: playback,
            timeline: timeline,
            chromePlan: chromePlan,
            validationWarnings: warnings,
            isValid: true
        )
    }

    func title(for candidate: EditorUIIntentCandidate) -> String {
        switch candidate.operation {
        case .show: return "Show \(candidate.target.displayName)"
        case .hide: return "Hide \(candidate.target.displayName)"
        case .expand: return "Expand \(candidate.target.displayName)"
        case .compress: return "Compress \(candidate.target.displayName)"
        case .restore: return "Restore \(candidate.target.displayName)"
        case .focus: return "Focus \(candidate.target.displayName)"
        case .applyWorkspace: return "Apply \(candidate.target.displayName)"
        }
    }

    func category(for source: UIIntentCandidateSource) -> EditorJITResolutionCategory {
        switch source {
        case .direct: return .direct
        case .contextual: return .contextual
        case .workspacePhrase, .embedding: return .workspace
        }
    }
}

private extension String {
    var sanitizedUIIntentId: String {
        replacingOccurrences(of: "[^a-zA-Z0-9-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
