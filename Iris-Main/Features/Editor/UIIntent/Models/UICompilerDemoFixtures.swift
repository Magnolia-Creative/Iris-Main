import Foundation

enum UICompilerDemoFixtures {
    static let defaultContext = EditorUICompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.defaultRecipe.makeRawState(),
        lastInteractedComponent: nil,
        activeParameterGroupId: nil,
        hasSelectedClip: false,
        controlsAvailable: false
    )

    static let timelineContext = EditorUICompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.defaultRecipe.makeRawState(),
        lastInteractedComponent: "timeline.full",
        activeParameterGroupId: nil,
        hasSelectedClip: true,
        controlsAvailable: true
    )

    static let previewContext = EditorUICompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.defaultRecipe.makeRawState(),
        lastInteractedComponent: "playback.section",
        activeParameterGroupId: nil,
        hasSelectedClip: false,
        controlsAvailable: false
    )

    static let controlsContext = EditorUICompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.colorCorrection.makeRawState(),
        lastInteractedComponent: "chrome.bottomStack",
        activeParameterGroupId: EditorChromePreviewFixtures.colorGroup.id,
        hasSelectedClip: true,
        controlsAvailable: true
    )

    static let allContexts: [NamedUICompilerContext] = [
        NamedUICompilerContext(
            id: "default",
            title: "Default Editor",
            context: defaultContext
        ),
        NamedUICompilerContext(
            id: "timeline",
            title: "Timeline Recently Used",
            context: timelineContext
        ),
        NamedUICompilerContext(
            id: "preview",
            title: "Preview Recently Used",
            context: previewContext
        ),
        NamedUICompilerContext(
            id: "controls",
            title: "Controls Available",
            context: controlsContext
        )
    ]
}

struct NamedUICompilerContext: Identifiable, Equatable {
    let id: String
    let title: String
    let context: EditorUICompilerContext
}
