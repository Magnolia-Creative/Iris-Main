import Foundation

enum EditorIntentCompilerDiagnosticsFixtures {
    static let defaultContext = EditorIntentCompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.defaultRecipe.makeRawState(),
        lastInteractedComponent: nil,
        activeParameterGroupId: nil,
        hasSelectedClip: false,
        controlsAvailable: false
    )

    static let timelineContext = EditorIntentCompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.defaultRecipe.makeRawState(),
        lastInteractedComponent: "timeline.full",
        activeParameterGroupId: nil,
        hasSelectedClip: true,
        controlsAvailable: true
    )

    static let previewContext = EditorIntentCompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.defaultRecipe.makeRawState(),
        lastInteractedComponent: "playback.section",
        activeParameterGroupId: nil,
        hasSelectedClip: false,
        controlsAvailable: false
    )

    static let controlsContext = EditorIntentCompilerContext(
        activeSpace: .edit,
        currentRenderState: EditorJITRecipeCatalog.colorCorrection.makeRawState(),
        lastInteractedComponent: "chrome.bottomStack",
        activeParameterGroupId: EditorChromePreviewFixtures.colorGroup.id,
        hasSelectedClip: true,
        controlsAvailable: true
    )

    static let allContexts: [NamedEditorIntentCompilerContext] = [
        NamedEditorIntentCompilerContext(
            id: "default",
            title: "Default Editor",
            context: defaultContext
        ),
        NamedEditorIntentCompilerContext(
            id: "timeline",
            title: "Timeline Recently Used",
            context: timelineContext
        ),
        NamedEditorIntentCompilerContext(
            id: "preview",
            title: "Preview Recently Used",
            context: previewContext
        ),
        NamedEditorIntentCompilerContext(
            id: "controls",
            title: "Controls Available",
            context: controlsContext
        )
    ]
}

struct NamedEditorIntentCompilerContext: Identifiable, Equatable {
    let id: String
    let title: String
    let context: EditorIntentCompilerContext
}
