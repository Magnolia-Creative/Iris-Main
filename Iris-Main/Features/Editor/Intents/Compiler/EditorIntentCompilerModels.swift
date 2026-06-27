import Foundation

struct NormalizedEditorIntentPrompt: Equatable {
    let originalText: String
    let normalizedText: String
    let tokens: [String]
    let bigrams: [String]
    let trigrams: [String]
    let numericTokens: [String]
    let canonicalPhraseReplacements: [EditorIntentPhraseReplacement]
}

struct EditorIntentPhraseReplacement: Codable, Equatable {
    let source: String
    let canonical: String
}

struct EditorIntentCompilerContext: Equatable {
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

enum EditorIntentCandidateSource: String, Codable, Equatable {
    case direct
    case contextual
    case workspacePhrase
    case embedding
}

enum EditorIntentOperation: String, Codable, Equatable {
    case show
    case hide
    case expand
    case compress
    case restore
    case focus
    case applyWorkspace
}

enum EditorIntentTarget: Codable, Equatable {
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

struct EditorIntentCandidate: Equatable {
    let id: String
    let source: EditorIntentCandidateSource
    let operation: EditorIntentOperation
    let target: EditorIntentTarget
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

struct EditorIntentScoredCandidate: Equatable {
    let candidate: EditorIntentCandidate
    let score: Double
    let penalties: [String]
}

struct EditorIntentClarificationOption: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

struct EditorIntentRemoteResolutionRequest: Codable, Equatable {
    let prompt: String
    let normalizedPrompt: String
    let activeSpace: String
    let availableComponentIds: [String]
    let supportedStates: [String: [String]]
    let localCandidates: [EditorIntentCandidateDiagnostic]
    let reason: String
}

struct EditorIntentCandidateDiagnostic: Codable, Equatable, Identifiable {
    let id: String
    let source: String
    let operation: String
    let target: String
    let score: Double
    let matchedTerms: [String]
    let ruleId: String?
    let assumptions: [String]
}

struct EditorIntentRenderStateSnapshot: Codable, Equatable {
    let id: String
    let title: String
    let category: String
    let playback: EditorIntentComponentSnapshot
    let timeline: EditorIntentComponentSnapshot
    let chromeDensity: String
    let chromeVisibleTiers: [String]
    let validationWarnings: [String]
    let isValid: Bool
}

struct EditorIntentComponentSnapshot: Codable, Equatable {
    let componentId: String
    let size: String
    let isVisible: Bool
}

struct EditorIntentCompilerReport: Codable, Equatable {
    let interpretation: String
    let normalizedPrompt: String
    let selectedCandidate: EditorIntentCandidateDiagnostic?
    let candidates: [EditorIntentCandidateDiagnostic]
    let renderState: EditorIntentRenderStateSnapshot?
    let validationWarnings: [String]
    let validationErrors: [String]
}

enum EditorIntentCompilerResult: Equatable {
    case resolved(
        renderState: EditorJITRenderState,
        interpretation: String,
        report: EditorIntentCompilerReport
    )
    case clarificationRequired(
        options: [EditorIntentClarificationOption],
        report: EditorIntentCompilerReport
    )
    case deferredToRemote(
        request: EditorIntentRemoteResolutionRequest,
        report: EditorIntentCompilerReport
    )
    case unsupported(
        reason: String,
        report: EditorIntentCompilerReport
    )

    var report: EditorIntentCompilerReport {
        switch self {
        case .resolved(_, _, let report),
             .clarificationRequired(_, let report),
             .deferredToRemote(_, let report),
             .unsupported(_, let report):
            return report
        }
    }
}

extension EditorIntentCandidateDiagnostic {
    init(candidate: EditorIntentCandidate, score: Double? = nil) {
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

extension EditorIntentRenderStateSnapshot {
    init(_ state: EditorJITRenderState) {
        self.init(
            id: state.id,
            title: state.title,
            category: state.resolutionCategory.rawValue,
            playback: EditorIntentComponentSnapshot(state.playback),
            timeline: EditorIntentComponentSnapshot(state.timeline),
            chromeDensity: state.chromePlan.density.rawValue,
            chromeVisibleTiers: state.chromePlan.visibleTiers.map(\.editorIntentDisplayTitle),
            validationWarnings: state.validationWarnings,
            isValid: state.isValid
        )
    }
}

extension EditorIntentComponentSnapshot {
    init(_ state: EditorJITComponentState) {
        self.init(
            componentId: state.componentId.rawValue,
            size: state.size.rawValue,
            isVisible: state.isVisible
        )
    }
}

private extension EditorBottomChromeTier {
    var editorIntentDisplayTitle: String {
        switch self {
        case .spatialParameters: return "spatial"
        case .parameters: return "parameters"
        case .actions: return "actions"
        case .dock: return "dock"
        }
    }
}
