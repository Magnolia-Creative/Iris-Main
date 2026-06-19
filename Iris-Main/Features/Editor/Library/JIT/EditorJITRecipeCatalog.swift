import Foundation

enum EditorJITRecipeCatalog {
    static let all: [EditorJITRecipe] = [
        defaultEdit,
        timelineFocus,
        previewFocus,
        colorCorrection,
        clipEditing,
        lessCluttered,
        everythingBigger,
        ambiguousExample,
        unsupportedExample
    ]

    static func recipe(id: String) -> EditorJITRecipe? {
        all.first { $0.id == id }
    }

    static var defaultRecipe: EditorJITRecipe { defaultEdit }

    // MARK: - Recipes

    static let defaultEdit = EditorJITRecipe(
        id: "default-edit",
        title: "Default Edit",
        promptExample: "Standard editing workspace",
        resolutionCategory: .workspace,
        playback: .visible("playback.section", size: .standard),
        timeline: .visible("timeline.full", size: .standard),
        chromePlan: EditorBottomChromePlan(
            density: .standard,
            showsDock: true
        )
    )

    static let timelineFocus = EditorJITRecipe(
        id: "timeline-focus",
        title: "Timeline Focus",
        promptExample: "Make the timeline bigger",
        resolutionCategory: .direct,
        playback: .visible("playback.section", size: .compressed),
        timeline: .visible("timeline.full", size: .expanded),
        chromePlan: EditorBottomChromePlan(
            density: .compact,
            showsDock: true
        )
    )

    static let previewFocus = EditorJITRecipe(
        id: "preview-focus",
        title: "Preview Focus",
        promptExample: "Give me more room to preview the video",
        resolutionCategory: .direct,
        playback: .visible("playback.section", size: .expanded),
        timeline: .visible("timeline.full", size: .compressed),
        chromePlan: EditorBottomChromePlan(
            density: .compact,
            parameterGroups: [],
            showsDock: true
        )
    )

    static let colorCorrection = EditorJITRecipe(
        id: "color-correction",
        title: "Color Correction",
        promptExample: "Set me up for color correction",
        resolutionCategory: .workspace,
        playback: .visible("playback.section", size: .standard),
        timeline: .visible("timeline.full", size: .compressed),
        chromePlan: EditorBottomChromePlan(
            density: .standard,
            parameterGroups: [
                EditorChromePreviewFixtures.colorGroup,
                EditorChromePreviewFixtures.toneGroup
            ],
            showsDock: true,
            activeParameterGroupId: EditorChromePreviewFixtures.colorGroup.id
        )
    )

    static let clipEditing = EditorJITRecipe(
        id: "clip-editing",
        title: "Clip Editing",
        promptExample: "Focus on editing clips",
        resolutionCategory: .contextual,
        playback: .visible("playback.section", size: .compressed),
        timeline: .visible("timeline.full", size: .expanded),
        chromePlan: EditorBottomChromePlan(
            density: .standard,
            actions: EditorChromePreviewFixtures.defaultActions,
            isDismissable: false,
            showsDock: true
        )
    )

    static let lessCluttered = EditorJITRecipe(
        id: "less-cluttered",
        title: "Less Cluttered",
        promptExample: "Make the interface less cluttered",
        resolutionCategory: .workspace,
        playback: .visible("playback.section", size: .standard),
        timeline: .visible("timeline.full", size: .standard),
        chromePlan: EditorBottomChromePlan(
            density: .compact,
            parameterGroups: [],
            actions: [],
            showsDock: true
        )
    )

    static let everythingBigger = EditorJITRecipe(
        id: "everything-bigger",
        title: "Everything Bigger",
        promptExample: "Make everything bigger",
        resolutionCategory: .direct,
        playback: .visible("playback.section", size: .expanded),
        timeline: .visible("timeline.full", size: .expanded),
        chromePlan: EditorBottomChromePlan(
            density: .expanded,
            parameterGroups: EditorChromePreviewFixtures.parameterGroups(for: .twoGroups),
            showsDock: true,
            activeParameterGroupId: EditorChromePreviewFixtures.colorGroup.id
        )
    )

    static let ambiguousExample = EditorJITRecipe(
        id: "ambiguous",
        title: "Ambiguous Request",
        promptExample: "Make this easier to use",
        resolutionCategory: .ambiguous,
        playback: .visible("playback.section", size: .standard),
        timeline: .visible("timeline.full", size: .standard),
        chromePlan: EditorBottomChromePlan(
            density: .standard,
            showsDock: true
        )
    )

    /// Deliberately references an unknown component to exercise validation.
    static let unsupportedExample = EditorJITRecipe(
        id: "unsupported",
        title: "Unsupported Component",
        promptExample: "Show the holographic waveform panel",
        resolutionCategory: .unsupported,
        playback: .visible("playback.section", size: .standard),
        timeline: .visible("timeline.nonexistent", size: .standard),
        chromePlan: EditorBottomChromePlan(showsDock: false)
    )
}
