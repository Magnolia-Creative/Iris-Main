import Foundation

struct EditorIntentComponentAlias: Equatable {
    let componentId: EditorComponentID
    let aliases: Set<String>
    let spatialAliases: Set<String>
    let workflowTerms: Set<String>
}

struct EditorIntentOperationAlias: Equatable {
    let operation: EditorIntentOperation
    let size: EditorComponentSize?
    let aliases: Set<String>
}

struct EditorIntentWorkspaceAlias: Equatable {
    let recipeId: String
    let aliases: Set<String>
}

struct EditorIntentCapability: Equatable {
    let target: EditorIntentTarget
    let supportedOperations: Set<EditorIntentOperation>
    let supportedSizes: Set<EditorComponentSize>
}

struct EditorIntentLexiconMatch<Value: Equatable>: Equatable {
    let value: Value
    let matchedTerm: String
    let isPhraseMatch: Bool
}

enum EditorIntentLexicon {
    static let componentAliases: [EditorIntentComponentAlias] = [
        EditorIntentComponentAlias(
            componentId: "timeline.full",
            aliases: ["timeline", "tracks", "track", "clips", "sequence"],
            spatialAliases: ["bottom", "bottom area", "bottom section", "lower section"],
            workflowTerms: ["edit clips", "editing clips", "trim clips", "clip editing"]
        ),
        EditorIntentComponentAlias(
            componentId: "playback.section",
            aliases: ["preview", "viewer", "player", "video", "screen", "playback"],
            spatialAliases: ["top", "top area", "viewer area", "video area"],
            workflowTerms: ["watch video", "review video", "focus video", "preview video"]
        ),
        EditorIntentComponentAlias(
            componentId: "chrome.bottomStack",
            aliases: ["controls", "parameter controls", "inspector", "chrome", "bottom chrome"],
            spatialAliases: ["bottom controls", "control area"],
            workflowTerms: ["adjust parameters", "tune controls", "edit controls"]
        ),
        EditorIntentComponentAlias(
            componentId: "toolbar.collection",
            aliases: ["tools", "edit tools", "toolbar", "tool bar"],
            spatialAliases: ["tool area"],
            workflowTerms: ["use tools", "open tools", "clip tools"]
        )
    ]

    static let operationAliases: [EditorIntentOperationAlias] = [
        EditorIntentOperationAlias(
            operation: .expand,
            size: .expanded,
            aliases: ["expanded", "expand", "bigger", "larger", "more room", "more space", "focus"]
        ),
        EditorIntentOperationAlias(
            operation: .compress,
            size: .compressed,
            aliases: ["compressed", "compress", "collapse", "smaller", "shrink", "less room", "less space"]
        ),
        EditorIntentOperationAlias(
            operation: .restore,
            size: .standard,
            aliases: ["standard", "normal", "restore", "default", "regular"]
        ),
        EditorIntentOperationAlias(
            operation: .hide,
            size: nil,
            aliases: ["hide", "hidden", "close", "remove", "dismiss", "off"]
        ),
        EditorIntentOperationAlias(
            operation: .show,
            size: .standard,
            aliases: ["show", "open", "visible", "bring back", "on"]
        ),
        EditorIntentOperationAlias(
            operation: .focus,
            size: .expanded,
            aliases: ["focus", "focus on", "prioritize"]
        )
    ]

    static let workspaceAliases: [EditorIntentWorkspaceAlias] = [
        EditorIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.previewFocus.id,
            aliases: ["focus on the video", "focus video", "preview focus", "give me more room to preview", "watch the video"]
        ),
        EditorIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.timelineFocus.id,
            aliases: ["timeline focus", "give me more room to edit clips", "more room to edit clips", "focus on editing clips"]
        ),
        EditorIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.lessCluttered.id,
            aliases: ["clean workspace", "cleaner workspace", "less cluttered", "minimal workspace", "reduce clutter"]
        ),
        EditorIntentWorkspaceAlias(
            recipeId: EditorJITRecipeCatalog.clipEditing.id,
            aliases: ["clip editing", "edit clips", "focus on clips", "work on clips"]
        )
    ]

    static var capabilities: [EditorIntentCapability] {
        var capabilities = EditorComponentRegistry.entries.map { entry in
            EditorIntentCapability(
                target: .component(entry.id),
                supportedOperations: [.show, .hide, .expand, .compress, .restore, .focus],
                supportedSizes: entry.supportedSizes
            )
        }
        capabilities.append(
            EditorIntentCapability(
                target: .chromeControls,
                supportedOperations: [.show, .hide, .expand, .compress, .restore],
                supportedSizes: [.compressed, .standard, .expanded]
            )
        )
        return capabilities
    }

    static func componentMatches(in prompt: NormalizedEditorIntentPrompt) -> [EditorIntentLexiconMatch<EditorComponentID>] {
        componentAliases.flatMap { component in
            matches(
                terms: component.aliases.union(component.spatialAliases).union(component.workflowTerms),
                prompt: prompt,
                value: component.componentId
            )
        }
    }

    static func operationMatches(in prompt: NormalizedEditorIntentPrompt) -> [EditorIntentLexiconMatch<EditorIntentOperationAlias>] {
        operationAliases.flatMap { operation in
            matches(terms: operation.aliases, prompt: prompt, value: operation)
        }
    }

    static func workspaceMatches(in prompt: NormalizedEditorIntentPrompt) -> [EditorIntentLexiconMatch<EditorIntentWorkspaceAlias>] {
        workspaceAliases.flatMap { workspace in
            matches(terms: workspace.aliases, prompt: prompt, value: workspace)
        }
    }

    static func aliases(for componentId: EditorComponentID) -> EditorIntentComponentAlias? {
        componentAliases.first { $0.componentId == componentId }
    }

    static func capability(for target: EditorIntentTarget) -> EditorIntentCapability? {
        capabilities.first { $0.target == target }
    }

    static func componentId(forSpatialTerm term: String) -> [EditorComponentID] {
        componentAliases
            .filter { $0.spatialAliases.contains(term) }
            .map(\.componentId)
    }

    private static func matches<Value: Equatable>(
        terms: Set<String>,
        prompt: NormalizedEditorIntentPrompt,
        value: Value
    ) -> [EditorIntentLexiconMatch<Value>] {
        terms.compactMap { term in
            let isPhrase = term.contains(" ")
            let matched = isPhrase
                ? prompt.normalizedText.contains(term)
                : prompt.tokens.contains(term)
            guard matched else { return nil }
            return EditorIntentLexiconMatch(
                value: value,
                matchedTerm: term,
                isPhraseMatch: isPhrase
            )
        }
    }
}
