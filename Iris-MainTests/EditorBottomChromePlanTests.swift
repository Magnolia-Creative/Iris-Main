import XCTest
@testable import Iris_Main

@MainActor
final class EditorBottomChromePlanTests: XCTestCase {
    func testVisibleControlsCapsAtThree() {
        let group = EditorParameterGroup(
            id: "dense",
            title: "Dense",
            controls: (0..<5).map { index in
                EditorParameterDescriptor(
                    id: "param-\(index)",
                    title: "Param \(index)",
                    defaultValue: .scalar(Double(index))
                )
            },
            maxVisibleControls: 3
        )

        let visible = EditorParameterGroupVisibility.visibleControls(in: group)
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(visible.map(\.id), ["param-0", "param-1", "param-2"])
    }

    func testGroupNeedsChipPickerWhenMoreThanMaxVisible() {
        let group = EditorParameterGroup(
            id: "overflow",
            title: "Overflow",
            controls: [
                EditorParameterDescriptor(id: "a", title: "A", defaultValue: .scalar(0)),
                EditorParameterDescriptor(id: "b", title: "B", defaultValue: .scalar(0)),
                EditorParameterDescriptor(id: "c", title: "C", defaultValue: .scalar(0)),
                EditorParameterDescriptor(id: "d", title: "D", defaultValue: .scalar(0))
            ],
            maxVisibleControls: 3
        )

        XCTAssertTrue(group.needsChipPicker)
    }

    func testPlanVisibleTiersReflectsContent() {
        var plan = EditorBottomChromePlan(
            spatialParameters: [
                EditorSpatialParameterDescriptor(id: "spatial", title: "Velocity")
            ],
            parameterGroups: [EditorChromePreviewFixtures.colorGroup],
            actions: EditorChromePreviewFixtures.defaultActions,
            showsDock: true
        )

        XCTAssertEqual(
            plan.visibleTiers,
            [.spatialParameters, .parameters, .actions, .dock]
        )
        XCTAssertEqual(plan.tierCountAboveDock, 3)
    }

    func testDismissablePlanShowsActionsTierWithoutActions() {
        let plan = EditorBottomChromePlan(
            actions: [],
            isDismissable: true,
            showsDock: true
        )

        XCTAssertEqual(plan.visibleTiers, [.actions, .dock])
        XCTAssertEqual(plan.tierCountAboveDock, 1)
    }

    func testPreviewFixturesSeedScalarDefaults() {
        let groups = EditorChromePreviewFixtures.parameterGroups(for: .fourPlusGroups)
        let values = EditorChromePreviewFixtures.seedValues(for: groups)

        XCTAssertEqual(values["temperature"], .scalar(0))
        XCTAssertEqual(values["volumeGain"], .scalar(1))
    }

    func testActiveParameterGroupFallsBackToFirstGroup() {
        var plan = EditorBottomChromePlan(
            parameterGroups: [EditorChromePreviewFixtures.colorGroup, EditorChromePreviewFixtures.audioGroup],
            activeParameterGroupId: "missing"
        )

        XCTAssertEqual(plan.activeParameterGroup?.id, EditorChromePreviewFixtures.colorGroup.id)
    }

    func testMakePlanRespectsTierToggles() {
        let plan = EditorChromePreviewFixtures.makePlan(
            showsDock: false,
            showsActions: false,
            showsParameterGroups: true,
            showsSpatialControls: false,
            showsOverflowChips: true,
            groupScenario: .oneGroup,
            density: .compact
        )

        XCTAssertFalse(plan.showsDock)
        XCTAssertTrue(plan.parameterGroups.count == 1)
        XCTAssertTrue(plan.actions.isEmpty)
        XCTAssertFalse(plan.isDismissable)
        XCTAssertEqual(plan.density, .compact)
        XCTAssertEqual(plan.visibleTiers, [.parameters])
    }
}
