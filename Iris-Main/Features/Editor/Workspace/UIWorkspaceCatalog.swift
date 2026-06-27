import Foundation

enum UIWorkspaceCatalog {
    static let version = "1"

    static let supportedWidgetIds: Set<String> = [
        "playback.viewer",
        "playback.beforeAfterViewer",
        "timeline.full",
        "timeline.primaryTrack",
        "timeline.focusedClipStrip",
        "audio.levelsMeter",
        "toolbar.parameterControls",
        "toolbar.reviewActions",
        "toolbar.promptBar",
        "toolbar.clipTools",
        "panel.importBrowser",
        "panel.exportSettings"
    ]

    static func isSupported(widgetId: String) -> Bool {
        supportedWidgetIds.contains(widgetId) && UIEditorWidgetRegistry.descriptor(for: widgetId) != nil
    }

    /// Parameters the local editor can apply to the selected clip today.
    static let supportedWorkspaceParameterIds: Set<String> = [
        "vintageIntensity",
        "temperature",
        "saturation",
        "contrast",
        "exposure",
        "highlights",
        "shadows",
        "volumeGain"
    ]

    static func isSupportedWorkspaceParameter(_ parameterId: String) -> Bool {
        supportedWorkspaceParameterIds.contains(parameterId)
    }

    static func localPlan(
        for prompt: String,
        editorContext: UIEditorContext?
    ) -> UIWorkspacePlan? {
        let normalized = IntentPromptNormalizer.normalize(prompt)
        guard normalized.contains("timeline"), !mentionsClipEditTarget(normalized) else {
            return nil
        }

        if isTimelineHidePrompt(normalized) {
            return timelineHiddenPlan()
        }

        if isTimelineShowPrompt(normalized) {
            return fallbackDefaultPlan(
                activeSpace: editorSpace(from: editorContext),
                hasSelectedClip: editorContext?.hasSelectedClip ?? false
            )
        }

        return nil
    }

    static func fallbackDefaultPlan(
        activeSpace: EditorSpace,
        hasSelectedClip: Bool
    ) -> UIWorkspacePlan {
        let toolbarWidgets: [UIWidgetPlacement] = [
            UIWidgetPlacement(
                widgetId: "toolbar.promptBar",
                variant: "idle",
                prominence: .primary,
                intentSliceId: "default",
                reason: "Default prompt entry"
            )
        ] + (hasSelectedClip
            ? [
                UIWidgetPlacement(
                    widgetId: "toolbar.clipTools",
                    variant: "collapsed",
                    prominence: .supporting,
                    intentSliceId: "default",
                    reason: "Clip tools when selected"
                )
            ]
            : [])

        let previewNode = UILayoutNode(
            type: .widget,
            widget: UIWidgetPlacement(
                widgetId: "playback.viewer",
                variant: "compact",
                prominence: .primary,
                size: UIWidgetSizeHint(weight: 0.35, minHeight: nil, maxHeight: nil, importance: .primary, collapsible: nil),
                intentSliceId: "default",
                reason: "Preview"
            )
        )
        let timelineNode = UILayoutNode(
            type: .widget,
            widget: UIWidgetPlacement(
                widgetId: "timeline.full",
                variant: "expanded",
                prominence: .primary,
                size: UIWidgetSizeHint(weight: 0.45, minHeight: nil, maxHeight: nil, importance: .primary, collapsible: nil),
                intentSliceId: "default",
                reason: "Timeline"
            )
        )
        let hiddenTimelineWidgets = [
            "timeline.full",
            "timeline.primaryTrack",
            "timeline.focusedClipStrip"
        ]

        let layoutChildren: [UILayoutNode]
        let hiddenBecauseIrrelevant: [String]
        switch activeSpace {
        case .edit:
            layoutChildren = [previewNode, timelineNode]
            hiddenBecauseIrrelevant = []
        case .importMedia:
            layoutChildren = [
                previewNode,
                UILayoutNode(
                    type: .widget,
                    widget: UIWidgetPlacement(
                        widgetId: "panel.importBrowser",
                        variant: "standard",
                        prominence: .supporting,
                        intentSliceId: "default",
                        reason: "Import"
                    )
                )
            ]
            hiddenBecauseIrrelevant = hiddenTimelineWidgets
        case .export:
            layoutChildren = [
                previewNode,
                UILayoutNode(
                    type: .widget,
                    widget: UIWidgetPlacement(
                        widgetId: "panel.exportSettings",
                        variant: "standard",
                        prominence: .supporting,
                        intentSliceId: "default",
                        reason: "Export"
                    )
                )
            ]
            hiddenBecauseIrrelevant = hiddenTimelineWidgets
        }

        return UIWorkspacePlan(
            catalogVersion: version,
            workspaceId: "default",
            intentSummary: "Default editor workspace",
            intentSlices: [
                UIIntentSlice(
                    id: "default",
                    title: "Edit",
                    goal: "General editing",
                    modality: "mixed",
                    parameterIds: []
                )
            ],
            currentSliceId: "default",
            currentSliceIndex: 0,
            layout: UILayoutNode(type: .vstack, children: layoutChildren),
            toolbar: UIToolbarPlacement(
                widgets: toolbarWidgets,
                showNavigation: true,
                showPromptBar: true
            ),
            hiddenBecauseIrrelevant: hiddenBecauseIrrelevant,
            warnings: [],
            isDefaultWorkspace: true,
            restoreDefaultOnComplete: false
        )
    }
}

private extension UIWorkspaceCatalog {
    static func timelineHiddenPlan() -> UIWorkspacePlan {
        UIWorkspacePlan(
            catalogVersion: version,
            workspaceId: "timeline_hidden",
            intentSummary: "Hide the timeline",
            intentSlices: [
                UIIntentSlice(
                    id: "timeline_hidden",
                    title: "Preview",
                    goal: "Keep playback visible while hiding timeline controls",
                    modality: "visual",
                    parameterIds: []
                )
            ],
            currentSliceId: "timeline_hidden",
            currentSliceIndex: 0,
            layout: UILayoutNode(
                type: .widget,
                widget: UIWidgetPlacement(
                    widgetId: "playback.viewer",
                    variant: "large",
                    prominence: .primary,
                    size: UIWidgetSizeHint(
                        weight: 1,
                        minHeight: nil,
                        maxHeight: nil,
                        importance: .primary,
                        collapsible: nil
                    ),
                    intentSliceId: "timeline_hidden",
                    reason: "Timeline hidden by direct UI intent"
                )
            ),
            toolbar: UIToolbarPlacement(
                widgets: [
                    UIWidgetPlacement(
                        widgetId: "toolbar.promptBar",
                        variant: "refine",
                        prominence: .primary,
                        intentSliceId: "timeline_hidden",
                        reason: "Allow follow-up UI intents"
                    )
                ],
                showNavigation: true,
                showPromptBar: true
            ),
            hiddenBecauseIrrelevant: [
                "timeline.full",
                "timeline.primaryTrack",
                "timeline.focusedClipStrip"
            ],
            warnings: [],
            isDefaultWorkspace: false,
            restoreDefaultOnComplete: false
        )
    }

    static func isTimelineHidePrompt(_ prompt: String) -> Bool {
        prompt == "hide timeline"
            || prompt == "hide the timeline"
            || prompt == "make timeline disappear"
            || prompt == "make the timeline disappear"
            || prompt == "make timeline invisible"
            || prompt == "make the timeline invisible"
            || prompt == "get rid of timeline"
            || prompt == "get rid of the timeline"
            || prompt == "remove timeline"
            || prompt == "remove the timeline"
            || prompt == "take away timeline"
            || prompt == "take away the timeline"
    }

    static func isTimelineShowPrompt(_ prompt: String) -> Bool {
        prompt == "show timeline"
            || prompt == "show the timeline"
            || prompt == "make timeline visible"
            || prompt == "make the timeline visible"
            || prompt == "bring back timeline"
            || prompt == "bring back the timeline"
            || prompt == "restore timeline"
            || prompt == "restore the timeline"
            || prompt == "unhide timeline"
            || prompt == "unhide the timeline"
    }

    static func mentionsClipEditTarget(_ prompt: String) -> Bool {
        prompt.contains("clip")
            || prompt.contains("clips")
            || prompt.contains("selection")
            || prompt.contains("selected")
            || prompt.contains("track")
            || prompt.contains("tracks")
    }

    static func editorSpace(from context: UIEditorContext?) -> EditorSpace {
        guard let activeSpace = context?.activeSpace,
              let editorSpace = EditorSpace(rawValue: activeSpace) else {
            return .edit
        }
        return editorSpace
    }
}
