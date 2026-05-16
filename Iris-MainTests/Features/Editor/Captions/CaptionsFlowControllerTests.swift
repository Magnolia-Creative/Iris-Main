import Testing
@testable import Iris_Main

@MainActor
struct CaptionsFlowControllerTests {
    @Test func finishStyleEditingClearsExpandedTool() {
        let flow = CaptionsFlowController()
        flow.openStyleEditor(forGroupId: "group")
        flow.expandedStyleTool = "style"

        flow.finishStyleEditing()

        #expect(flow.phase == .idle)
        #expect(flow.expandedStyleTool == nil)
    }

    @Test func cancelStyleEditingClearsSelectionAndExpandedTool() {
        let flow = CaptionsFlowController()
        flow.openStyleEditor(forGroupId: "group")
        flow.selectedCaptionCueId = "cue"
        flow.expandedStyleTool = "background"

        flow.cancelStyleEditing()

        #expect(flow.phase == .idle)
        #expect(flow.selectedCaptionCueId == nil)
        #expect(flow.expandedStyleTool == nil)
    }
}
