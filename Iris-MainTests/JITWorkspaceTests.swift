import XCTest
@testable import Iris_Main

@MainActor
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

    func testCoordinatorSanitizeDropsUnknownWidgets() {
        let coordinator = JITWorkspaceCoordinator(activeSpace: .edit, hasSelectedClip: false)
        let invalidPlan = UIWorkspacePlan(
            workspaceId: "bad",
            intentSummary: "test",
            intentSlices: [],
            currentSliceId: nil,
            currentSliceIndex: 0,
            layout: UILayoutNode(
                type: .widget,
                widget: UIWidgetPlacement(widgetId: "unknown.widget", intentSliceId: "default")
            ),
            toolbar: UIToolbarPlacement(),
            isDefaultWorkspace: false
        )
        let sanitized = coordinator.sanitizedPlan(invalidPlan)
        XCTAssertEqual(sanitized.workspaceId, "bad")
    }

    func testSupportedWorkspaceParameterIdsExcludeGrain() {
        XCTAssertFalse(UIWorkspaceCatalog.isSupportedWorkspaceParameter("grain"))
        XCTAssertTrue(UIWorkspaceCatalog.isSupportedWorkspaceParameter("saturation"))
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
}
