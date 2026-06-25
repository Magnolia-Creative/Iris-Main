import Foundation

struct NormalizedEditorUIPrompt: Equatable {
    let originalText: String
    let normalizedText: String
    let tokens: [String]
    let bigrams: [String]
    let trigrams: [String]
    let numericTokens: [String]
    let canonicalPhraseReplacements: [UIIntentPhraseReplacement]
}

struct UIIntentPhraseReplacement: Codable, Equatable {
    let source: String
    let canonical: String
}

struct EditorUICompilerContext: Equatable {
    var activeSpace: EditorSpace
    var currentRenderState: EditorJITRenderState
    var lastInteractedComponent: EditorComponentID?
    var activeParameterGroupId: String?
    var hasSelectedClip: Bool
    var controlsAvailable: Bool

    init(
        activeSpace: EditorSpace = .edit,
        currentRenderState: EditorJITRenderState = EditorJITRecipeCatalog.defaultRecipe.makeRawState(),
        lastInteractedComponent: EditorComponentID? = nil,
        activeParameterGroupId: String? = nil,
        hasSelectedClip: Bool = false,
        controlsAvailable: Bool = false
    ) {
        self.activeSpace = activeSpace
        self.currentRenderState = currentRenderState
        self.lastInteractedComponent = lastInteractedComponent
        self.activeParameterGroupId = activeParameterGroupId
        self.hasSelectedClip = hasSelectedClip
        self.controlsAvailable = controlsAvailable
    }
}

enum UIIntentCandidateSource: String, Codable, Equatable {
    case direct
    case contextual
    case workspacePhrase
    case embedding
}

enum UIIntentOperation: String, Codable, Equatable {
    case show
    case hide
    case expand
    case compress
    case restore
    case focus
    case applyWorkspace
}

enum UIIntentTarget: Codable, Equatable {
    case component(EditorComponentID)
    case workspaceRecipe(String)
    case chromeControls

    var displayName: String {
        switch self {
        case .component(let componentId):
            return componentId.rawValue
        case .workspaceRecipe(let recipeId):
            return recipeId
        case .chromeControls:
            return "chrome.controls"
        }
    }
}

struct EditorUIIntentCandidate: Equatable {
    let id: String
    let source: UIIntentCandidateSource
    let operation: UIIntentOperation
    let target: UIIntentTarget
    let requestedSize: EditorComponentSize?
    let matchedTerms: [String]
    let explicitTargetMatch: Bool
    let explicitStateMatch: Bool
    let contextMatchScore: Double
    let lexicalScore: Double
    let embeddingScore: Double?
    let ruleId: String?
    let assumptions: [String]

    var totalScore: Double {
        lexicalScore + contextMatchScore + (embeddingScore ?? 0)
    }
}

struct UIIntentScoredCandidate: Equatable {
    let candidate: EditorUIIntentCandidate
    let score: Double
    let penalties: [String]
}

struct UIIntentClarificationOption: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

struct EditorUIRemoteResolutionRequest: Codable, Equatable {
    let prompt: String
    let normalizedPrompt: String
    let activeSpace: String
    let availableComponentIds: [String]
    let supportedStates: [String: [String]]
    let localCandidates: [UIIntentCandidateDiagnostic]
    let reason: String
}

struct UIIntentCandidateDiagnostic: Codable, Equatable, Identifiable {
    let id: String
    let source: String
    let operation: String
    let target: String
    let score: Double
    let matchedTerms: [String]
    let ruleId: String?
    let assumptions: [String]
}

struct UIIntentRenderStateSnapshot: Codable, Equatable {
    let id: String
    let title: String
    let category: String
    let playback: UIIntentComponentSnapshot
    let timeline: UIIntentComponentSnapshot
    let chromeDensity: String
    let chromeVisibleTiers: [String]
    let validationWarnings: [String]
    let isValid: Bool
}

struct UIIntentComponentSnapshot: Codable, Equatable {
    let componentId: String
    let size: String
    let isVisible: Bool
}

struct UIIntentCompilerReport: Codable, Equatable {
    let interpretation: String
    let normalizedPrompt: String
    let selectedCandidate: UIIntentCandidateDiagnostic?
    let candidates: [UIIntentCandidateDiagnostic]
    let renderState: UIIntentRenderStateSnapshot?
    let validationWarnings: [String]
    let validationErrors: [String]
}

enum EditorUICompilerResult: Equatable {
    case resolved(
        renderState: EditorJITRenderState,
        interpretation: String,
        report: UIIntentCompilerReport
    )
    case clarificationRequired(
        options: [UIIntentClarificationOption],
        report: UIIntentCompilerReport
    )
    case deferredToRemote(
        request: EditorUIRemoteResolutionRequest,
        report: UIIntentCompilerReport
    )
    case unsupported(
        reason: String,
        report: UIIntentCompilerReport
    )

    var report: UIIntentCompilerReport {
        switch self {
        case .resolved(_, _, let report),
             .clarificationRequired(_, let report),
             .deferredToRemote(_, let report),
             .unsupported(_, let report):
            return report
        }
    }
}

extension UIIntentCandidateDiagnostic {
    init(candidate: EditorUIIntentCandidate, score: Double? = nil) {
        self.init(
            id: candidate.id,
            source: candidate.source.rawValue,
            operation: candidate.operation.rawValue,
            target: candidate.target.displayName,
            score: score ?? candidate.totalScore,
            matchedTerms: candidate.matchedTerms,
            ruleId: candidate.ruleId,
            assumptions: candidate.assumptions
        )
    }
}

extension UIIntentRenderStateSnapshot {
    init(_ state: EditorJITRenderState) {
        self.init(
            id: state.id,
            title: state.title,
            category: state.resolutionCategory.rawValue,
            playback: UIIntentComponentSnapshot(state.playback),
            timeline: UIIntentComponentSnapshot(state.timeline),
            chromeDensity: state.chromePlan.density.rawValue,
            chromeVisibleTiers: state.chromePlan.visibleTiers.map(\.uiIntentDisplayTitle),
            validationWarnings: state.validationWarnings,
            isValid: state.isValid
        )
    }
}

extension UIIntentComponentSnapshot {
    init(_ state: EditorJITComponentState) {
        self.init(
            componentId: state.componentId.rawValue,
            size: state.size.rawValue,
            isVisible: state.isVisible
        )
    }
}

private extension EditorBottomChromeTier {
    var uiIntentDisplayTitle: String {
        switch self {
        case .spatialParameters: return "spatial"
        case .parameters: return "parameters"
        case .actions: return "actions"
        case .dock: return "dock"
        }
    }
}
