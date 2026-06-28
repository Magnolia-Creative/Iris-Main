import XCTest
@testable import Iris_Main

@MainActor
final class EditorJITRenderStateTests: XCTestCase {
    func testDefaultRecipeValidates() {
        let raw = EditorJITRecipeCatalog.defaultEdit.makeRawState()
        let (state, result) = EditorJITRenderValidator.validate(raw)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(state.isValid)
        XCTAssertTrue(state.playback.isVisible)
        XCTAssertTrue(state.timeline.isVisible)
    }

    func testTimelineFocusExpandsTimelineAndCompressesPlayback() {
        let raw = EditorJITRecipeCatalog.timelineFocus.makeRawState()
        let (state, result) = EditorJITRenderValidator.validate(raw)

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(state.timeline.size, .expanded)
        XCTAssertEqual(state.playback.size, .compressed)
    }

    func testPreviewFocusHidesParameterGroups() {
        let raw = EditorJITRecipeCatalog.previewFocus.makeRawState()
        let (state, result) = EditorJITRenderValidator.validate(raw)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(state.chromePlan.parameterGroups.isEmpty)
        XCTAssertEqual(state.playback.size, .expanded)
    }

    func testColorCorrectionExposesColorAndToneGroups() {
        let raw = EditorJITRecipeCatalog.colorCorrection.makeRawState()
        let (state, result) = EditorJITRenderValidator.validate(raw)

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(state.chromePlan.parameterGroups.count, 2)
        XCTAssertEqual(state.chromePlan.activeParameterGroupId, EditorChromePreviewFixtures.colorGroup.id)
    }

    func testUnsupportedRecipeFailsValidation() {
        let raw = EditorJITRecipeCatalog.unsupportedExample.makeRawState()
        let (_, result) = EditorJITRenderValidator.validate(raw)

        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testAmbiguousRecipeWarnsButRemainsValid() {
        let raw = EditorJITRecipeCatalog.ambiguousExample.makeRawState()
        let (_, result) = EditorJITRenderValidator.validate(raw)

        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testUnknownComponentIsRejected() {
        var raw = EditorJITRecipeCatalog.defaultEdit.makeRawState()
        raw.timeline = .visible("timeline.nonexistent", size: .standard)
        let (state, result) = EditorJITRenderValidator.validate(raw)

        XCTAssertFalse(result.isValid)
        XCTAssertFalse(state.timeline.isVisible)
    }

    func testTransitionCoordinatorMarksNewRecipeAsEnter() {
        let next = EditorJITRecipeCatalog.timelineFocus.makeRawState()
        let plans = EditorJITRenderTransitionCoordinator.plan(from: nil, to: next)

        XCTAssertTrue(plans.contains { $0.componentId.rawValue == "timeline.full" && $0.style == .enter })
    }

    func testTransitionCoordinatorDetectsSizeChange() {
        let previous = EditorJITRecipeCatalog.defaultEdit.makeRawState()
        let next = EditorJITRecipeCatalog.timelineFocus.makeRawState()
        let plans = EditorJITRenderTransitionCoordinator.plan(from: previous, to: next)

        XCTAssertTrue(plans.contains { $0.componentId.rawValue == "timeline.full" && $0.style == .resize })
    }

    func testLiveRenderStateAppliesValidatedStateAndTracksTransition() {
        let liveState = EditorJITLiveRenderState()
        let previousTimelineSize = liveState.renderState.timeline.size
        let next = EditorJITRecipeCatalog.timelineFocus.makeRawState()

        XCTAssertTrue(liveState.apply(next))
        XCTAssertEqual(liveState.previousRenderState?.timeline.size, previousTimelineSize)
        XCTAssertEqual(liveState.renderState.timeline.size, .expanded)
        XCTAssertTrue(liveState.transitionPlans.contains { $0.componentId.rawValue == "timeline.full" && $0.style == .resize })
    }
}
