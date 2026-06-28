import Foundation

struct EditorJITUIPlanAdapterResult: Equatable {
    let renderState: EditorJITRenderState
    let validationResult: EditorJITValidationResult
}

struct EditorJITUIPlanAdapter {
    func adapt(
        uiPlan: RemoteIntentUIPlan,
        prompt: String,
        fallback: EditorJITRenderState = EditorJITRecipeCatalog.defaultRecipe.makeRawState()
    ) -> EditorJITUIPlanAdapterResult {
        let widgets = collectWidgets(from: uiPlan.layout) + toolbarWidgets(from: uiPlan.toolbar)
        var playback = fallback.playback
        var timeline = fallback.timeline
        var chromePlan = chromePlan(from: uiPlan, fallback: fallback.chromePlan)
        var warnings = uiPlan.warnings
        var sawTimelineWidget = false

        for widget in widgets {
            switch widget.widgetId {
            case "playback.viewer", "playback.beforeAfterViewer":
                playback = .visible("playback.section", size: playbackSize(for: widget))

            case "timeline.full":
                sawTimelineWidget = true
                timeline = .visible("timeline.full", size: timelineSize(for: widget))

            case "timeline.primaryTrack", "timeline.focusedClipStrip":
                sawTimelineWidget = true
                timeline = .visible("timeline.track", size: timelineSize(for: widget))

            case "toolbar.parameterControls":
                if let group = parameterGroup(from: widget, currentSliceId: uiPlan.currentSliceId) {
                    chromePlan.parameterGroups = [group]
                    chromePlan.activeParameterGroupId = group.id
                }

            case "toolbar.reviewActions":
                chromePlan.isDismissable = true

            case "toolbar.clipTools":
                chromePlan.actions = EditorChromePreviewFixtures.defaultActions

            case "toolbar.promptBar":
                chromePlan.showsDock = true

            case "audio.levelsMeter", "panel.importBrowser", "panel.exportSettings":
                break

            default:
                warnings.append("Unsupported backend widget '\(widget.widgetId)' was ignored.")
            }
        }

        if uiPlan.hiddenBecauseIrrelevant.contains("timeline.full"), !sawTimelineWidget {
            timeline = .hidden(timeline.componentId)
        }

        let rawState = EditorJITRenderState(
            id: "backend-ui-\(uiPlan.workspaceId.sanitizedJITPlanId)",
            title: uiPlan.intentSummary.isEmpty ? "Intent Workspace" : uiPlan.intentSummary,
            promptExample: prompt,
            resolutionCategory: uiPlan.isDefaultWorkspace ? .workspace : .contextual,
            playback: playback,
            timeline: timeline,
            chromePlan: chromePlan,
            validationWarnings: warnings,
            isValid: true
        )

        var (validated, validation) = EditorJITRenderValidator.validate(rawState)
        validated.validationWarnings.append(contentsOf: warnings)
        validation = EditorJITValidationResult(
            isValid: validation.isValid,
            warnings: validation.warnings + warnings,
            errors: validation.errors
        )
        return EditorJITUIPlanAdapterResult(renderState: validated, validationResult: validation)
    }

    private func chromePlan(
        from uiPlan: RemoteIntentUIPlan,
        fallback: EditorBottomChromePlan
    ) -> EditorBottomChromePlan {
        var plan = fallback
        plan.parameterGroups = []
        plan.actions = []
        plan.isDismissable = false
        plan.activeParameterGroupId = nil

        if let showPromptBar = uiPlan.toolbar["showPromptBar"]?.boolValue {
            plan.showsDock = showPromptBar
        }
        if let showNavigation = uiPlan.toolbar["showNavigation"]?.boolValue, showNavigation {
            plan.showsDock = true
        }
        if uiPlan.hiddenBecauseIrrelevant.contains("toolbar.promptBar"),
           uiPlan.toolbar["showNavigation"]?.boolValue != true {
            plan.showsDock = false
        }

        return plan
    }

    private func playbackSize(for widget: BackendWidget) -> EditorComponentSize {
        if widget.widgetId == "playback.beforeAfterViewer" {
            return .expanded
        }
        return EditorComponentRegistry.parseSize(widget.variant)
    }

    private func timelineSize(for widget: BackendWidget) -> EditorComponentSize {
        EditorComponentRegistry.parseSize(widget.variant)
    }

    private func parameterGroup(
        from widget: BackendWidget,
        currentSliceId: String?
    ) -> EditorParameterGroup? {
        let controls = widget.controls.compactMap(parameterDescriptor)
        guard !controls.isEmpty else { return nil }
        let groupId = "backend.\((currentSliceId ?? widget.intentSliceId ?? "intent").sanitizedJITPlanId).parameters"
        return EditorParameterGroup(
            id: groupId,
            title: "Intent Controls",
            controls: controls,
            maxVisibleControls: max(controls.count, EditorParameterGroupVisibility.defaultMaxVisibleControls)
        )
    }

    private func parameterDescriptor(from raw: [String: JSONValue]) -> EditorParameterDescriptor? {
        guard let parameterId = raw["parameterId"]?.stringValue else { return nil }
        let title = raw["label"]?.stringValue ?? parameterId
        let lower = raw["minValue"]?.doubleValue ?? 0
        let upper = raw["maxValue"]?.doubleValue ?? 1
        let defaultValue = raw["defaultValue"]?.doubleValue ?? lower
        return EditorParameterDescriptor(
            id: parameterId,
            title: title,
            bounds: EditorParameterBounds(lower: lower, upper: upper),
            defaultValue: .scalar(defaultValue),
            display: .compact
        )
    }

    private func collectWidgets(from node: [String: JSONValue]) -> [BackendWidget] {
        var widgets: [BackendWidget] = []
        if let widgetObject = node["widget"]?.objectValue,
           let widget = BackendWidget(raw: widgetObject) {
            widgets.append(widget)
        }
        for child in node["children"]?.arrayValue ?? [] {
            guard let childObject = child.objectValue else { continue }
            widgets.append(contentsOf: collectWidgets(from: childObject))
        }
        return widgets
    }

    private func toolbarWidgets(from toolbar: [String: JSONValue]) -> [BackendWidget] {
        (toolbar["widgets"]?.arrayValue ?? []).compactMap { value in
            guard let raw = value.objectValue else { return nil }
            return BackendWidget(raw: raw)
        }
    }
}

private struct BackendWidget: Equatable {
    let widgetId: String
    let variant: String?
    let intentSliceId: String?
    let controls: [[String: JSONValue]]

    init?(raw: [String: JSONValue]) {
        guard let widgetId = raw["widgetId"]?.stringValue else { return nil }
        self.widgetId = widgetId
        self.variant = raw["variant"]?.stringValue
        self.intentSliceId = raw["intentSliceId"]?.stringValue
        self.controls = (raw["controls"]?.arrayValue ?? []).compactMap(\.objectValue)
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

private extension String {
    var sanitizedJITPlanId: String {
        replacingOccurrences(of: "[^a-zA-Z0-9-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
