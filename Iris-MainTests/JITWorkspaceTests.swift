import XCTest
@testable import Iris_Main

final class JITWorkspaceTests: XCTestCase {
    func testDefaultWorkspaceIncludesTimelineAndPromptBar() {
        let plan = UIWorkspaceCatalog.fallbackDefaultPlan(
            activeSpace: .edit,
            hasSelectedClip: false
        )
        XCTAssertTrue(plan.isDefaultWorkspace)
        XCTAssertTrue(plan.toolbar.showPromptBar)
        XCTAssertTrue(plan.toolbar.showNavigation)
        XCTAssertTrue(containsWidget("timeline.full", in: plan.layout))
    }

    func testTransitionCoordinatorMarksNewWidgetsAsEnter() {
        let previous = UIWorkspaceCatalog.fallbackDefaultPlan(activeSpace: .edit, hasSelectedClip: false)
        let nextPlan = UIWorkspacePlan(
            workspaceId: "visual_style",
            intentSummary: "Vintage",
            intentSlices: [
                UIIntentSlice(id: "visual_style", title: "Visual", goal: "Tune look", modality: "visual")
            ],
            currentSliceId: "visual_style",
            currentSliceIndex: 0,
            layout: UILayoutNode(
                type: .widget,
                widget: UIWidgetPlacement(
                    widgetId: "playback.beforeAfterViewer",
                    intentSliceId: "visual_style"
                )
            ),
            toolbar: UIToolbarPlacement(showNavigation: false, showPromptBar: false),
            isDefaultWorkspace: false
        )
        let transitions = JITWorkspaceTransitionCoordinator.plan(from: previous, to: nextPlan)
        XCTAssertTrue(transitions.contains(where: { $0.widgetId == "playback.beforeAfterViewer" && $0.style == .enter }))
    }

    @MainActor
    func testCoordinatorSanitizeDropsUnknownWidgets() async {
        let coordinator = JITWorkspaceCoordinator(activeSpace: .edit, hasSelectedClip: false)
        let invalidPlan = UIWorkspacePlan(
            workspaceId: "visual_style",
            intentSummary: "test",
            intentSlices: [
                UIIntentSlice(id: "visual_style", title: "Visual", goal: "Tune", modality: "visual")
            ],
            currentSliceId: "visual_style",
            currentSliceIndex: 0,
            layout: UILayoutNode(
                type: .widget,
                widget: UIWidgetPlacement(widgetId: "playback.viewer", intentSliceId: "visual_style")
            ),
            toolbar: UIToolbarPlacement(
                widgets: [
                    UIWidgetPlacement(widgetId: "unknown.widget", intentSliceId: "visual_style"),
                    UIWidgetPlacement(widgetId: "toolbar.reviewActions", intentSliceId: "visual_style")
                ]
            ),
            isDefaultWorkspace: false
        )
        let sanitized = coordinator.sanitizedPlan(invalidPlan)
        XCTAssertEqual(sanitized.workspaceId, "visual_style")
        XCTAssertFalse(sanitized.toolbar.widgets.contains { $0.widgetId == "unknown.widget" })
        XCTAssertTrue(sanitized.toolbar.widgets.contains { $0.widgetId == "toolbar.reviewActions" })
    }

    func testSupportedWorkspaceParameterIdsExcludeGrain() {
        XCTAssertFalse(UIWorkspaceCatalog.isSupportedWorkspaceParameter("grain"))
        XCTAssertTrue(UIWorkspaceCatalog.isSupportedWorkspaceParameter("saturation"))
    }

    func testLocalTimelineHidePromptProducesHiddenTimelinePlan() {
        let plan = UIWorkspaceCatalog.localPlan(
            for: "Make the timeline disappear",
            editorContext: UIEditorContext(activeSpace: EditorSpace.edit.rawValue)
        )

        let unwrappedPlan = tryUnwrap(plan)
        XCTAssertEqual(unwrappedPlan?.workspaceId, "timeline_hidden")
        XCTAssertFalse(containsWidget("timeline.full", in: unwrappedPlan?.layout))
        XCTAssertTrue(containsWidget("playback.viewer", in: unwrappedPlan?.layout))
        XCTAssertTrue(unwrappedPlan?.hiddenBecauseIrrelevant.contains("timeline.full") == true)
    }

    func testLocalTimelineHidePromptDoesNotCaptureClipRemoval() {
        let plan = UIWorkspaceCatalog.localPlan(
            for: "Remove this clip from the timeline",
            editorContext: UIEditorContext(activeSpace: EditorSpace.edit.rawValue)
        )

        XCTAssertNil(plan)
    }

    @MainActor
    func testCoordinatorAppliesLocalTimelineHideWithoutProjectId() async {
        let coordinator = JITWorkspaceCoordinator(activeSpace: .edit, hasSelectedClip: false)
        await coordinator.activateIntentWorkspace(
            prompt: "Make the timeline disappear",
            context: IntentCompilerContext(
                timelineId: "timeline-1",
                selectedClipId: nil,
                selectedTrackId: nil,
                selectedRange: nil,
                playheadTimeUs: nil,
                clipsById: [:],
                orderedClipIdsByTrackId: [:]
            ),
            editorContext: UIEditorContext(activeSpace: EditorSpace.edit.rawValue),
            projectId: nil
        )

        XCTAssertEqual(coordinator.activePlan.workspaceId, "timeline_hidden")
        XCTAssertNil(coordinator.lastErrorMessage)
        XCTAssertEqual(coordinator.timelinePresentation(for: coordinator.activePlan), .hidden)
    }

    func testDecodeWorkspacePlanResponse() throws {
        let json = """
        {
          "plan": {
            "workspaceId": "visual_style",
            "intentSummary": "Vintage look",
            "intentSlices": [
              {
                "id": "visual_style",
                "title": "Visual style",
                "goal": "Tune vintage",
                "modality": "visual",
                "parameterIds": ["vintageIntensity"]
              }
            ],
            "currentSliceId": "visual_style",
            "currentSliceIndex": 0,
            "layout": {
              "type": "widget",
              "widget": {
                "widgetId": "playback.beforeAfterViewer",
                "prominence": "primary",
                "intentSliceId": "visual_style"
              }
            },
            "toolbar": {
              "widgets": [],
              "showNavigation": false,
              "showPromptBar": false
            },
            "hiddenBecauseIrrelevant": [],
            "warnings": [],
            "isDefaultWorkspace": false,
            "restoreDefaultOnComplete": true
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(UIWorkspacePlanResponse.self, from: data)
        XCTAssertEqual(response.plan.workspaceId, "visual_style")
    }

    private func containsWidget(_ widgetId: String, in node: UILayoutNode) -> Bool {
        if node.widget?.widgetId == widgetId { return true }
        return node.children.contains { containsWidget(widgetId, in: $0) }
    }

    private func containsWidget(_ widgetId: String, in node: UILayoutNode?) -> Bool {
        guard let node else { return false }
        return containsWidget(widgetId, in: node)
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T? {
        XCTAssertNotNil(value, file: file, line: line)
        return value
    }
}
