import Foundation

struct UIIntentComponentAlias: Equatable {
    let componentId: EditorComponentID
    let aliases: Set<String>
    let spatialAliases: Set<String>
    let workflowTerms: Set<String>
}

struct UIIntentOperationAlias: Equatable {
    let operation: UIIntentOperation
    let size: EditorComponentSize?
    let aliases: Set<String>
}

struct UIIntentWorkspaceAlias: Equatable {
    let recipeId: String
    let aliases: Set<String>
}

struct UIIntentCapability: Equatable {
    let target: UIIntentTarget
    let supportedOperations: Set<UIIntentOperation>
    let supportedSizes: Set<EditorComponentSize>
}

struct UIIntentLexiconMatch<Value: Equatable>: Equatable {
    let value: Value
    let matchedTerm: String
    let isPhraseMatch: Bool
}

enum UIIntentLexicon {
    static let componentAliases: [UIIntentComponentAlias] = [
        UIIntentComponentAlias(
            componentId: "timeline.full",
            aliases: ["timeline", "tracks", "track", "clips", "sequence"],
            spatialAliases: ["bottom", "bottom area", "bottom section", "lower section"],
            workflowTerms: ["edit clips", "editing clips", "trim clips", "clip editing"]
        ),
        UIIntentComponentAlias(
            componentId: "playback.section",
            aliases: ["preview", "viewer", "player", "video", "screen", "playback"],
            spatialAliases: ["top", "top area", "viewer area", "video area"],
            workflowTerms: ["watch video", "review video", "focus video", "preview video"]
        ),
        UIIntentComponentAlias(
            componentId: "chrome.bottomStack",
            aliases: ["controls", "parameter controls", "inspector", "chrome", "bottom chrome"],
            spatialAliases: ["bottom controls", "control area"],
            workflowTerms: ["adjust parameters", "tune controls", "edit controls"]
        ),
        UIIntentComponentAlias(
            componentId: "toolbar.collection",
            aliases: ["tools", "edit tools", "toolbar", "tool bar"],
            spatialAliases: ["tool area"],
            workflowTerms: ["use tools", "open tools", "clip tools"]
        )
    ]

    static let operationAliases: [UIIntentOperationAlias] = [
        UIIntentOperationAlias(
            operation: .expand,
            size: .expanded,
            aliases: ["expanded", "expand", "bigger", "larger", "more room", "more space", "focus"]
        ),
        UIIntentOperationAlias(
            operation: .compress,
            size: .compressed,
            aliases: ["compressed", "compress", "collapse", "smaller", "shrink", "less room", "less space"]
        ),
        UIIntentOperationAlias(
            operation: .restore,
            size: .standard,
            aliases: ["standard", "normal", "restore", "default", "regular"]
        ),
        UIIntentOperationAlias(
            operation: .hide,
            size: nil,
            aliases: ["hide", "hidden", "close", "remove", "dismiss", "off"]
        ),
        UIIntentOperationAlias(
            operation: .show,
            size: .standard,
            aliases: ["show", "open", "visible", "bring back", "on"]
        ),
        UIIntentOperationAlias(
            operation: .focus,
            size: .expanded,
            aliases: ["focus", "focus on", "prioritize"]
        )
    ]

    static let workspaceAliases: [UIIntentWorkspaceAlias] = [
        UIIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.previewFocus.id,
            aliases: ["focus on the video", "focus video", "preview focus", "give me more room to preview", "watch the video"]
        ),
        UIIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.timelineFocus.id,
            aliases: ["timeline focus", "give me more room to edit clips", "more room to edit clips", "focus on editing clips"]
        ),
        UIIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.lessCluttered.id,
            aliases: ["clean workspace", "cleaner workspace", "less cluttered", "minimal workspace", "reduce clutter"]
        ),
        UIIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.clipEditing.id,
            aliases: ["clip editing", "edit clips", "focus on clips", "work on clips"]
        )
    ]

    static var capabilities: [UIIntentCapability] {
        var capabilities = EditorComponentRegistry.entries.map { entry in
            UIIntentCapability(
                target: .component(entry.id),
                supportedOperations: [.show, .hide, .expand, .compress, .restore, .focus],
                supportedSizes: entry.supportedSizes
            )
        }
        capabilities.append(
            UIIntentCapability(
                target: .chromeControls,
                supportedOperations: [.show, .hide, .expand, .compress, .restore],
                supportedSizes: [.compressed, .standard, .expanded]
            )
        )
        return capabilities
    }

    static func componentMatches(in prompt: NormalizedEditorUIPrompt) -> [UIIntentLexiconMatch<EditorComponentID>] {
        componentAliases.flatMap { component in
            matches(
                terms: component.aliases.union(component.spatialAliases).union(component.workflowTerms),
                prompt: prompt,
                value: component.componentId
            )
        }
    }

    static func operationMatches(in prompt: NormalizedEditorUIPrompt) -> [UIIntentLexiconMatch<UIIntentOperationAlias>] {
        operationAliases.flatMap { operation in
            matches(terms: operation.aliases, prompt: prompt, value: operation)
        }
    }

    static func workspaceMatches(in prompt: NormalizedEditorUIPrompt) -> [UIIntentLexiconMatch<UIIntentWorkspaceAlias>] {
        workspaceAliases.flatMap { workspace in
            matches(terms: workspace.aliases, prompt: prompt, value: workspace)
        }
    }

    static func aliases(for componentId: EditorComponentID) -> UIIntentComponentAlias? {
        componentAliases.first { $0.componentId == componentId }
    }

    static func capability(for target: UIIntentTarget) -> UIIntentCapability? {
        capabilities.first { $0.target == target }
    }

    static func componentId(forSpatialTerm term: String) -> [EditorComponentID] {
        componentAliases
            .filter { $0.spatialAliases.contains(term) }
            .map(\.componentId)
    }

    private static func matches<Value: Equatable>(
        terms: Set<String>,
        prompt: NormalizedEditorUIPrompt,
        value: Value
    ) -> [UIIntentLexiconMatch<Value>] {
        terms.compactMap { term in
            let isPhrase = term.contains(" ")
            let matched = isPhrase
                ? prompt.normalizedText.contains(term)
                : prompt.tokens.contains(term)
            guard matched else { return nil }
            return UIIntentLexiconMatch(
                value: value,
                matchedTerm: term,
                isPhraseMatch: isPhrase
            )
        }
    }
}
