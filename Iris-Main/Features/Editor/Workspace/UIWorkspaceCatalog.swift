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

        var layoutChildren: [UILayoutNode] = [
            UILayoutNode(
                type: .widget,
                widget: UIWidgetPlacement(
                    widgetId: "playback.viewer",
                    variant: "compact",
                    prominence: .primary,
                    size: UIWidgetSizeHint(weight: 0.35, minHeight: nil, maxHeight: nil, importance: .primary, collapsible: nil),
                    intentSliceId: "default",
                    reason: "Preview"
                )
            ),
            UILayoutNode(
                type: .widget,
                widget: UIWidgetPlacement(
                    widgetId: "timeline.full",
                    variant: activeSpace == .edit ? "expanded" : "compressed",
                    prominence: .primary,
                    size: UIWidgetSizeHint(weight: 0.45, minHeight: nil, maxHeight: nil, importance: .primary, collapsible: nil),
                    intentSliceId: "default",
                    reason: "Timeline"
                )
            )
        ]

        if activeSpace == .importMedia {
            layoutChildren.append(
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
            )
        }
        if activeSpace == .export {
            layoutChildren.append(
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
            )
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
            hiddenBecauseIrrelevant: [],
            warnings: [],
            isDefaultWorkspace: true,
            restoreDefaultOnComplete: false
        )
    }
}
