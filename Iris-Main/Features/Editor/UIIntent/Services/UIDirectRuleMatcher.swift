import Foundation

struct UIDirectRule: Equatable {
    let id: String
    let pattern: String
    let target: UIIntentTarget
    let operation: UIIntentOperation
    let requestedSize: EditorComponentSize?
    let matchedTerms: [String]
    let baseScore: Double
}

struct UIDirectRuleMatcher {
    private let rules: [UIDirectRule]

    init(rules: [UIDirectRule] = Self.defaultRules) {
        self.rules = rules
    }

    func candidates(
        for prompt: NormalizedEditorUIPrompt,
        context: EditorUICompilerContext
    ) -> [EditorUIIntentCandidate] {
        var candidates = explicitRuleCandidates(for: prompt)
        candidates.append(contentsOf: workspacePhraseCandidates(for: prompt))
        candidates.append(contentsOf: lexiconCombinationCandidates(for: prompt))
        candidates.append(contentsOf: contextualCandidates(for: prompt, context: context))
        return deduplicated(candidates)
    }
}

extension UIDirectRuleMatcher {
    static let defaultRules: [UIDirectRule] = [
        UIDirectRule(
            id: "timeline.expand",
            pattern: #"\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b.*\b(?:expanded|expand|focus)\b|\b(?:expanded|expand|focus)\b.*\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b"#,
            target: .component("timeline.full"),
            operation: .expand,
            requestedSize: .expanded,
            matchedTerms: ["timeline", "expanded"],
            baseScore: 0.92
        ),
        UIDirectRule(
            id: "timeline.compress",
            pattern: #"\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b.*\b(?:compressed|compress|collapse|shrink)\b|\b(?:compressed|compress|collapse|shrink)\b.*\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b"#,
            target: .component("timeline.full"),
            operation: .compress,
            requestedSize: .compressed,
            matchedTerms: ["timeline", "compressed"],
            baseScore: 0.92
        ),
        UIDirectRule(
            id: "preview.expand",
            pattern: #"\b(?:preview|viewer|player|video|screen|playback)\b.*\b(?:expanded|expand|focus)\b|\b(?:expanded|expand|focus)\b.*\b(?:preview|viewer|player|video|screen|playback)\b"#,
            target: .component("playback.section"),
            operation: .expand,
            requestedSize: .expanded,
            matchedTerms: ["preview", "expanded"],
            baseScore: 0.92
        ),
        UIDirectRule(
            id: "preview.show",
            pattern: #"\b(?:show|open|visible)\b.*\b(?:preview|viewer|player|video|screen|playback)\b"#,
            target: .component("playback.section"),
            operation: .show,
            requestedSize: .standard,
            matchedTerms: ["show", "preview"],
            baseScore: 0.9
        ),
        UIDirectRule(
            id: "controls.hide",
            pattern: #"\b(?:hide|close|remove|dismiss|off)\b.*\b(?:controls|parameter controls|inspector|chrome)\b"#,
            target: .chromeControls,
            operation: .hide,
            requestedSize: nil,
            matchedTerms: ["hide", "controls"],
            baseScore: 0.9
        ),
        UIDirectRule(
            id: "controls.show",
            pattern: #"\b(?:show|open|visible)\b.*\b(?:controls|parameter controls|inspector|chrome)\b"#,
            target: .chromeControls,
            operation: .show,
            requestedSize: .standard,
            matchedTerms: ["show", "controls"],
            baseScore: 0.9
        ),
        UIDirectRule(
            id: "tools.show",
            pattern: #"\b(?:show|open|visible)\b.*\b(?:tools|edit tools|toolbar|tool bar)\b"#,
            target: .component("toolbar.collection"),
            operation: .show,
            requestedSize: .standard,
            matchedTerms: ["show", "tools"],
            baseScore: 0.88
        )
    ]
}

private extension UIDirectRuleMatcher {
    func explicitRuleCandidates(for prompt: NormalizedEditorUIPrompt) -> [EditorUIIntentCandidate] {
        rules.compactMap { rule in
            guard prompt.normalizedText.matches(pattern: rule.pattern) else { return nil }
            return EditorUIIntentCandidate(
                id: rule.id,
                source: .direct,
                operation: rule.operation,
                target: rule.target,
                requestedSize: rule.requestedSize,
                matchedTerms: rule.matchedTerms,
                explicitTargetMatch: true,
                explicitStateMatch: true,
                contextMatchScore: 0,
                lexicalScore: rule.baseScore,
                embeddingScore: nil,
                ruleId: rule.id,
                assumptions: []
            )
        }
    }

    func workspacePhraseCandidates(for prompt: NormalizedEditorUIPrompt) -> [EditorUIIntentCandidate] {
        UIIntentLexicon.workspaceMatches(in: prompt).map { match in
            EditorUIIntentCandidate(
                id: "workspace.\(match.value.recipeId)",
                source: .workspacePhrase,
                operation: .applyWorkspace,
                target: .workspaceRecipe(match.value.recipeId),
                requestedSize: nil,
                matchedTerms: [match.matchedTerm],
                explicitTargetMatch: true,
                explicitStateMatch: true,
                contextMatchScore: 0,
                lexicalScore: match.isPhraseMatch ? 0.91 : 0.84,
                embeddingScore: nil,
                ruleId: "workspace.phrase",
                assumptions: []
            )
        }
    }

    func lexiconCombinationCandidates(for prompt: NormalizedEditorUIPrompt) -> [EditorUIIntentCandidate] {
        let componentMatches = UIIntentLexicon.componentMatches(in: prompt)
        let operationMatches = UIIntentLexicon.operationMatches(in: prompt)
        guard !componentMatches.isEmpty, !operationMatches.isEmpty else { return [] }

        return componentMatches.flatMap { component in
            operationMatches.map { operation in
                EditorUIIntentCandidate(
                    id: "lexicon.\(component.value.rawValue).\(operation.value.operation.rawValue)",
                    source: .direct,
                    operation: operation.value.operation,
                    target: .component(component.value),
                    requestedSize: operation.value.size,
                    matchedTerms: [component.matchedTerm, operation.matchedTerm],
                    explicitTargetMatch: true,
                    explicitStateMatch: true,
                    contextMatchScore: 0,
                    lexicalScore: (component.isPhraseMatch || operation.isPhraseMatch) ? 0.82 : 0.76,
                    embeddingScore: nil,
                    ruleId: "lexicon.component-operation",
                    assumptions: []
                )
            }
        }
    }

    func contextualCandidates(
        for prompt: NormalizedEditorUIPrompt,
        context: EditorUICompilerContext
    ) -> [EditorUIIntentCandidate] {
        guard prompt.tokens.contains("this") else { return [] }
        guard let componentId = context.lastInteractedComponent else { return [] }

        return UIIntentLexicon.operationMatches(in: prompt).map { operation in
            EditorUIIntentCandidate(
                id: "context.\(componentId.rawValue).\(operation.value.operation.rawValue)",
                source: .contextual,
                operation: operation.value.operation,
                target: .component(componentId),
                requestedSize: operation.value.size,
                matchedTerms: ["this", operation.matchedTerm],
                explicitTargetMatch: false,
                explicitStateMatch: true,
                contextMatchScore: 0.2,
                lexicalScore: operation.isPhraseMatch ? 0.68 : 0.62,
                embeddingScore: nil,
                ruleId: "context.last-interacted",
                assumptions: ["Resolved 'this' to \(componentId.rawValue)."]
            )
        }
    }

    func deduplicated(_ candidates: [EditorUIIntentCandidate]) -> [EditorUIIntentCandidate] {
        var seen = Set<String>()
        var result: [EditorUIIntentCandidate] = []
        for candidate in candidates {
            let key = [
                candidate.source.rawValue,
                candidate.operation.rawValue,
                candidate.target.displayName,
                candidate.requestedSize?.rawValue ?? "none"
            ].joined(separator: ":")
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }
}

private extension String {
    func matches(pattern: String) -> Bool {
        range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
