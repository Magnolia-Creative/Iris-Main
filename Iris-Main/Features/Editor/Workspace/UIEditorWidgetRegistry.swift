import Foundation

/// Semantic widget metadata mirrored from the backend catalog for local validation and rendering.
enum UIEditorWidgetRegistry {
    struct Descriptor: Equatable {
        let id: String
        let displayName: String
        let role: UIWidgetRole
        let intentContributions: Set<String>
        let variants: Set<String>
    }

    static let descriptors: [String: Descriptor] = [
        "playback.viewer": Descriptor(
            id: "playback.viewer",
            displayName: "Playback",
            role: .monitor,
            intentContributions: ["preview", "scrub"],
            variants: ["compact", "large"]
        ),
        "playback.beforeAfterViewer": Descriptor(
            id: "playback.beforeAfterViewer",
            displayName: "Before/After Preview",
            role: .monitor,
            intentContributions: ["compare_before_after", "preview"],
            variants: ["large", "split"]
        ),
        "timeline.full": Descriptor(
            id: "timeline.full",
            displayName: "Full Timeline",
            role: .representation,
            intentContributions: ["navigate_timeline", "edit_structure"],
            variants: ["expanded", "compressed"]
        ),
        "timeline.primaryTrack": Descriptor(
            id: "timeline.primaryTrack",
            displayName: "Primary Video Track",
            role: .representation,
            intentContributions: ["focus_clip", "trim_range"],
            variants: ["affectedRangeOnly", "full"]
        ),
        "timeline.focusedClipStrip": Descriptor(
            id: "timeline.focusedClipStrip",
            displayName: "Focused Clip Strip",
            role: .representation,
            intentContributions: ["focus_clip", "scrub"],
            variants: ["compact", "expanded"]
        ),
        "audio.levelsMeter": Descriptor(
            id: "audio.levelsMeter",
            displayName: "Audio Levels",
            role: .monitor,
            intentContributions: ["monitor_audio"],
            variants: ["compact", "expanded"]
        ),
        "toolbar.parameterControls": Descriptor(
            id: "toolbar.parameterControls",
            displayName: "Parameter Controls",
            role: .inspector,
            intentContributions: ["tune_parameter"],
            variants: ["sliderGroup", "compact"]
        ),
        "toolbar.reviewActions": Descriptor(
            id: "toolbar.reviewActions",
            displayName: "Review Actions",
            role: .review,
            intentContributions: ["approve_edit", "reject_edit", "refine_prompt"],
            variants: ["standard"]
        ),
        "toolbar.promptBar": Descriptor(
            id: "toolbar.promptBar",
            displayName: "Prompt Bar",
            role: .tool,
            intentContributions: ["refine_prompt", "submit_intent"],
            variants: ["idle", "refine"]
        ),
        "toolbar.clipTools": Descriptor(
            id: "toolbar.clipTools",
            displayName: "Clip Tools",
            role: .tool,
            intentContributions: ["tune_parameter"],
            variants: ["collapsed", "expanded"]
        ),
        "panel.importBrowser": Descriptor(
            id: "panel.importBrowser",
            displayName: "Import Browser",
            role: .navigator,
            intentContributions: ["import_media"],
            variants: ["standard"]
        ),
        "panel.exportSettings": Descriptor(
            id: "panel.exportSettings",
            displayName: "Export Settings",
            role: .navigator,
            intentContributions: ["export_project"],
            variants: ["standard"]
        )
    ]

    static func descriptor(for widgetId: String) -> Descriptor? {
        descriptors[widgetId]
    }
}
