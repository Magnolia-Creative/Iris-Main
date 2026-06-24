import Foundation

enum UIIntentRankedResolution: Equatable {
    case selected(UIIntentScoredCandidate)
    case ambiguous([UIIntentScoredCandidate])
    case deferred(reason: String, candidates: [UIIntentScoredCandidate])
    case unsupported(reason: String)
}

struct UIIntentCandidateRanker {
    private let policy: UIResolutionPolicy

    init(policy: UIResolutionPolicy = .default) {
        self.policy = policy
    }

    func rank(
        candidates: [EditorUIIntentCandidate],
        context: EditorUICompilerContext
    ) -> UIIntentRankedResolution {
        guard !candidates.isEmpty else {
            return .unsupported(reason: "No local UI component or workspace terms matched the request.")
        }

        let scored = candidates
            .map { score(candidate: $0, context: context) }
            .sorted { $0.score > $1.score }

        guard let best = scored.first else {
            return .unsupported(reason: "No local UI component or workspace terms matched the request.")
        }

        if best.score < policy.localResolutionThreshold {
            return .deferred(
                reason: "The local compiler found weak matches but not enough certainty to apply them.",
                candidates: scored
            )
        }

        let close = scored.filter { candidate in
            candidate.candidate.id != best.candidate.id
                && best.score - candidate.score <= policy.ambiguityBand
        }
        if !close.isEmpty {
            return .ambiguous([best] + close)
        }

        return .selected(best)
    }

    private func score(
        candidate: EditorUIIntentCandidate,
        context: EditorUICompilerContext
    ) -> UIIntentScoredCandidate {
        var score = candidate.totalScore
        var penalties: [String] = []

        if candidate.explicitTargetMatch {
            score += policy.explicitTargetBoost
        }
        if candidate.explicitStateMatch {
            score += policy.explicitStateBoost
        }
        if candidate.source == .contextual {
            score += policy.contextBoost
        }
        if isNoOp(candidate: candidate, context: context) {
            score -= policy.noOpPenalty
            penalties.append("no-op")
        }
        if candidate.source == .embedding,
           (candidate.embeddingScore ?? 0) < policy.embeddingAcceptThreshold {
            score -= policy.noOpPenalty
            penalties.append("weak-embedding")
        }

        return UIIntentScoredCandidate(
            candidate: candidate,
            score: max(0, score),
            penalties: penalties
        )
    }

    private func isNoOp(
        candidate: EditorUIIntentCandidate,
        context: EditorUICompilerContext
    ) -> Bool {
        switch candidate.target {
        case .workspaceRecipe(let recipeId):
            return context.currentRenderState.id == recipeId
        case .chromeControls:
            return candidate.operation == .show && !context.currentRenderState.chromePlan.visibleTiers.isEmpty
        case .component(let componentId):
            let componentState: EditorJITComponentState?
            if componentId.rawValue.hasPrefix("playback.") {
                componentState = context.currentRenderState.playback
            } else if componentId.rawValue.hasPrefix("timeline.") {
                componentState = context.currentRenderState.timeline
            } else {
                componentState = nil
            }
            guard let componentState else { return false }
            switch candidate.operation {
            case .show:
                return componentState.isVisible
            case .hide:
                return !componentState.isVisible
            case .expand, .focus:
                return componentState.isVisible && componentState.size == .expanded
            case .compress:
                return componentState.isVisible && componentState.size == .compressed
            case .restore:
                return componentState.isVisible && componentState.size == .standard
            case .applyWorkspace:
                return false
            }
        }
    }
}
