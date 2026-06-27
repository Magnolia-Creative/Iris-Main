import Foundation

struct EditorIntentDirectRule: Equatable {
    let id: String
    let pattern: String
    let target: EditorIntentTarget
    let operation: EditorIntentOperation
    let requestedSize: EditorComponentSize?
    let matchedTerms: [String]
    let baseScore: Double
}

struct EditorIntentDirectRuleMatcher {
    private let rules: [EditorIntentDirectRule]

    init(rules: [EditorIntentDirectRule] = Self.defaultRules) {
        self.rules = rules
    }

    func candidates(
        for prompt: NormalizedEditorIntentPrompt,
        context: EditorIntentCompilerContext
    ) -> [EditorIntentCandidate] {
        var candidates = explicitRuleCandidates(for: prompt)
        candidates.append(contentsOf: workspacePhraseCandidates(for: prompt))
        candidates.append(contentsOf: lexiconCombinationCandidates(for: prompt))
        candidates.append(contentsOf: contextualCandidates(for: prompt, context: context))
        return deduplicated(candidates)
    }
}

extension EditorIntentDirectRuleMatcher {
    static let defaultRules: [EditorIntentDirectRule] = [
        EditorIntentDirectRule(
            id: "timeline.expand",
            pattern: #"\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b.*\b(?:expanded|expand|focus)\b|\b(?:expanded|expand|focus)\b.*\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b"#,
            target: .component("timeline.full"),
            operation: .expand,
            requestedSize: .expanded,
            matchedTerms: ["timeline", "expanded"],
            baseScore: 0.92
        ),
        EditorIntentDirectRule(
            id: "timeline.compress",
            pattern: #"\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b.*\b(?:compressed|compress|collapse|shrink)\b|\b(?:compressed|compress|collapse|shrink)\b.*\b(?:timeline|tracks|clips|bottom(?: area| section)?)\b"#,
            target: .component("timeline.full"),
            operation: .compress,
            requestedSize: .compressed,
            matchedTerms: ["timeline", "compressed"],
            baseScore: 0.92
        ),
        EditorIntentDirectRule(
            id: "preview.expand",
            pattern: #"\b(?:preview|viewer|player|video|screen|playback)\b.*\b(?:expanded|expand|focus)\b|\b(?:expanded|expand|focus)\b.*\b(?:preview|viewer|player|video|screen|playback)\b"#,
            target: .component("playback.section"),
            operation: .expand,
            requestedSize: .expanded,
            matchedTerms: ["preview", "expanded"],
            baseScore: 0.92
        ),
        EditorIntentDirectRule(
            id: "preview.show",
            pattern: #"\b(?:show|open|visible)\b.*\b(?:preview|viewer|player|video|screen|playback)\b"#,
            target: .component("playback.section"),
            operation: .show,
            requestedSize: .standard,
            matchedTerms: ["show", "preview"],
            baseScore: 0.9
        ),
        EditorIntentDirectRule(
            id: "controls.hide",
            pattern: #"\b(?:hide|close|remove|dismiss|off)\b.*\b(?:controls|parameter controls|inspector|chrome)\b"#,
            target: .chromeControls,
            operation: .hide,
            requestedSize: nil,
            matchedTerms: ["hide", "controls"],
            baseScore: 0.9
        ),
        EditorIntentDirectRule(
            id: "controls.show",
            pattern: #"\b(?:show|open|visible)\b.*\b(?:controls|parameter controls|inspector|chrome)\b"#,
            target: .chromeControls,
            operation: .show,
            requestedSize: .standard,
            matchedTerms: ["show", "controls"],
            baseScore: 0.9
        ),
        EditorIntentDirectRule(
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

private extension EditorIntentDirectRuleMatcher {
    func explicitRuleCandidates(for prompt: NormalizedEditorIntentPrompt) -> [EditorIntentCandidate] {
        rules.compactMap { rule in
            guard prompt.normalizedText.matches(pattern: rule.pattern) else { return nil }
            return EditorIntentCandidate(
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

    func workspacePhraseCandidates(for prompt: NormalizedEditorIntentPrompt) -> [EditorIntentCandidate] {
        EditorIntentLexicon.workspaceMatches(in: prompt).map { match in
            EditorIntentCandidate(
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

    func lexiconCombinationCandidates(for prompt: NormalizedEditorIntentPrompt) -> [EditorIntentCandidate] {
        let componentMatches = EditorIntentLexicon.componentMatches(in: prompt)
        let operationMatches = EditorIntentLexicon.operationMatches(in: prompt)
        guard !componentMatches.isEmpty, !operationMatches.isEmpty else { return [] }

        return componentMatches.flatMap { component in
            operationMatches.map { operation in
                EditorIntentCandidate(
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
        for prompt: NormalizedEditorIntentPrompt,
        context: EditorIntentCompilerContext
    ) -> [EditorIntentCandidate] {
        guard prompt.tokens.contains("this") else { return [] }
        guard let componentId = context.lastInteractedComponent else { return [] }

        return EditorIntentLexicon.operationMatches(in: prompt).map { operation in
            EditorIntentCandidate(
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

    func deduplicated(_ candidates: [EditorIntentCandidate]) -> [EditorIntentCandidate] {
        var seen = Set<String>()
        var result: [EditorIntentCandidate] = []
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
