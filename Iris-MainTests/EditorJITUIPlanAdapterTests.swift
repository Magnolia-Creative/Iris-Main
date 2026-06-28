import Foundation
import Testing
@testable import Iris_Main

struct EditorJITUIPlanAdapterTests {
    @Test func adaptsVisualStylePlanIntoPlaybackTimelineAndControls() throws {
        let result = try adaptPlan(
            """
            {
              "catalogVersion": "1",
              "workspaceId": "visual_style",
              "intentSummary": "Make the selected clip cinematic",
              "intentSlices": [],
              "currentSliceId": "visual_style",
              "currentSliceIndex": 0,
              "layout": {
                "type": "vstack",
                "children": [
                  {
                    "type": "widget",
                    "children": [],
                    "widget": {
                      "widgetId": "playback.beforeAfterViewer",
                      "variant": "large",
                      "intentSliceId": "visual_style",
                      "controls": [],
                      "props": {}
                    }
                  },
                  {
                    "type": "widget",
                    "children": [],
                    "widget": {
                      "widgetId": "timeline.focusedClipStrip",
                      "variant": "compact",
                      "intentSliceId": "visual_style",
                      "controls": [],
                      "props": {}
                    }
                  }
                ]
              },
              "toolbar": {
                "widgets": [
                  {
                    "widgetId": "toolbar.parameterControls",
                    "variant": "sliderGroup",
                    "intentSliceId": "visual_style",
                    "controls": [
                      { "parameterId": "grain", "label": "Grain", "minValue": 0, "maxValue": 1, "defaultValue": 0.35 },
                      { "parameterId": "contrast", "label": "Contrast", "minValue": -1, "maxValue": 1, "defaultValue": 0.2 }
                    ],
                    "props": {}
                  },
                  {
                    "widgetId": "toolbar.reviewActions",
                    "variant": "compact",
                    "intentSliceId": "visual_style",
                    "controls": [],
                    "props": {}
                  }
                ],
                "showNavigation": false,
                "showPromptBar": false
              },
              "transitions": [],
              "hiddenBecauseIrrelevant": ["toolbar.promptBar"],
              "warnings": [],
              "isDefaultWorkspace": false,
              "restoreDefaultOnComplete": true
            }
            """
        )

        #expect(result.validationResult.isValid)
        #expect(result.renderState.playback.componentId.rawValue == "playback.section")
        #expect(result.renderState.playback.size == .expanded)
        #expect(result.renderState.timeline.componentId.rawValue == "timeline.track")
        #expect(result.renderState.timeline.size == .compressed)
        #expect(result.renderState.chromePlan.showsDock == false)
        #expect(result.renderState.chromePlan.isDismissable)
        #expect(result.renderState.chromePlan.parameterGroups.first?.controls.map(\.id) == ["grain", "contrast"])
        #expect(result.renderState.chromePlan.activeParameterGroupId == "backend.visual-style.parameters")
    }

    @Test func adaptsAudioPlanByHidingIrrelevantTimeline() throws {
        let result = try adaptPlan(
            """
            {
              "catalogVersion": "1",
              "workspaceId": "audio_balance",
              "intentSummary": "Adjust voice volume",
              "intentSlices": [],
              "currentSliceId": "audio_balance",
              "currentSliceIndex": 0,
              "layout": {
                "type": "vstack",
                "children": [
                  {
                    "type": "widget",
                    "children": [],
                    "widget": {
                      "widgetId": "playback.viewer",
                      "variant": "large",
                      "intentSliceId": "audio_balance",
                      "controls": [],
                      "props": {}
                    }
                  },
                  {
                    "type": "widget",
                    "children": [],
                    "widget": {
                      "widgetId": "audio.levelsMeter",
                      "variant": "standard",
                      "intentSliceId": "audio_balance",
                      "controls": [],
                      "props": {}
                    }
                  }
                ]
              },
              "toolbar": {
                "widgets": [
                  {
                    "widgetId": "toolbar.parameterControls",
                    "variant": "sliderGroup",
                    "intentSliceId": "audio_balance",
                    "controls": [
                      { "parameterId": "volumeGain", "label": "Volume", "minValue": 0, "maxValue": 2, "defaultValue": 1.1 }
                    ],
                    "props": {}
                  }
                ],
                "showNavigation": false,
                "showPromptBar": false
              },
              "transitions": [],
              "hiddenBecauseIrrelevant": ["timeline.full", "toolbar.promptBar"],
              "warnings": [],
              "isDefaultWorkspace": false,
              "restoreDefaultOnComplete": true
            }
            """
        )

        #expect(result.validationResult.isValid)
        #expect(result.renderState.playback.size == .expanded)
        #expect(result.renderState.timeline.isVisible == false)
        #expect(result.renderState.chromePlan.showsDock == false)
        #expect(result.renderState.chromePlan.parameterGroups.first?.controls.first?.id == "volumeGain")
    }

    @Test func adaptsGeneralEditPlanIntoPrimaryTrackWithPromptDock() throws {
        let result = try adaptPlan(
            """
            {
              "catalogVersion": "1",
              "workspaceId": "general_edit",
              "intentSummary": "Trim and review",
              "intentSlices": [],
              "currentSliceId": "general_edit",
              "currentSliceIndex": 0,
              "layout": {
                "type": "vstack",
                "children": [
                  {
                    "type": "widget",
                    "children": [],
                    "widget": {
                      "widgetId": "playback.viewer",
                      "variant": "standard",
                      "intentSliceId": "general_edit",
                      "controls": [],
                      "props": {}
                    }
                  },
                  {
                    "type": "widget",
                    "children": [],
                    "widget": {
                      "widgetId": "timeline.primaryTrack",
                      "variant": "standard",
                      "intentSliceId": "general_edit",
                      "controls": [],
                      "props": {}
                    }
                  }
                ]
              },
              "toolbar": {
                "widgets": [
                  {
                    "widgetId": "toolbar.reviewActions",
                    "variant": "standard",
                    "intentSliceId": "general_edit",
                    "controls": [],
                    "props": {}
                  },
                  {
                    "widgetId": "toolbar.promptBar",
                    "variant": "standard",
                    "intentSliceId": "general_edit",
                    "controls": [],
                    "props": {}
                  }
                ],
                "showNavigation": true,
                "showPromptBar": true
              },
              "transitions": [],
              "hiddenBecauseIrrelevant": [],
              "warnings": [],
              "isDefaultWorkspace": false,
              "restoreDefaultOnComplete": true
            }
            """
        )

        #expect(result.validationResult.isValid)
        #expect(result.renderState.timeline.componentId.rawValue == "timeline.track")
        #expect(result.renderState.timeline.size == .standard)
        #expect(result.renderState.chromePlan.showsDock)
        #expect(result.renderState.chromePlan.isDismissable)
        #expect(result.renderState.chromePlan.parameterGroups.isEmpty)
    }

    @Test func warnsAndIgnoresUnsupportedBackendWidgets() throws {
        let result = try adaptPlan(
            """
            {
              "catalogVersion": "1",
              "workspaceId": "unknown_widget",
              "intentSummary": "Unknown",
              "intentSlices": [],
              "currentSliceId": "unknown_widget",
              "currentSliceIndex": 0,
              "layout": {
                "type": "vstack",
                "children": [
                  {
                    "type": "widget",
                    "children": [],
                    "widget": {
                      "widgetId": "legacy.magicWidget",
                      "variant": "standard",
                      "intentSliceId": "unknown_widget",
                      "controls": [],
                      "props": {}
                    }
                  }
                ]
              },
              "toolbar": { "widgets": [], "showNavigation": false, "showPromptBar": false },
              "transitions": [],
              "hiddenBecauseIrrelevant": [],
              "warnings": [],
              "isDefaultWorkspace": false,
              "restoreDefaultOnComplete": true
            }
            """
        )

        #expect(result.validationResult.warnings.contains("Unsupported backend widget 'legacy.magicWidget' was ignored."))
    }

    @Test func registryMapsBackendWidgetsToCanonicalComponents() {
        #expect(EditorComponentRegistry.backendWidget(for: "playback.viewer") == .playbackViewer)
        #expect(EditorComponentRegistry.backendWidget(for: "timeline.focusedClipStrip") == .timelineFocusedClipStrip)
        #expect(EditorComponentRegistry.componentID(for: .playbackBeforeAfterViewer)?.rawValue == "playback.section")
        #expect(EditorComponentRegistry.componentID(for: .timelineFull)?.rawValue == "timeline.full")
        #expect(EditorComponentRegistry.componentID(for: .timelinePrimaryTrack)?.rawValue == "timeline.track")
        #expect(EditorComponentRegistry.componentID(for: .unsupported(rawId: "x")) == nil)
    }

    private func adaptPlan(_ json: String) throws -> EditorJITUIPlanAdapterResult {
        let plan = try JSONDecoder().decode(RemoteIntentUIPlan.self, from: Data(json.utf8))
        return EditorJITUIPlanAdapter().adapt(uiPlan: plan, prompt: "backend prompt")
    }
}
