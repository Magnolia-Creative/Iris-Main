import Foundation
import Testing
@testable import Iris_Main

struct RemoteIntentCompilerSocketTests {
    @Test func encodesAgentRunIntentPayload() throws {
        let context = IntentCompilerContext(
            timelineId: "timeline-test",
            selectedClipId: "clip-a",
            selectedTrackId: "track-video",
            selectedRange: nil,
            playheadTimeUs: 1_000_000,
            clipsById: [:],
            orderedClipIdsByTrackId: [:]
        )
        let payload = RemoteIntentRunCreatePayload(
            prompt: "make it cinematic",
            context: context,
            editorContext: RemoteIntentEditorContext(activeSpace: "Edit", hasSelectedClip: true),
            currentWorkspaceId: "visual_style"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["kind"] as? String == "intent")
        #expect(object["prompt"] as? String == "make it cinematic")
        #expect(object["currentWorkspaceId"] as? String == "visual_style")

        let editorContext = try #require(object["editorContext"] as? [String: Any])
        #expect(editorContext["activeSpace"] as? String == "Edit")
        #expect(editorContext["hasSelectedClip"] as? Bool == true)
    }

    @Test func decodesDirectIntentAgentResponse() throws {
        let json = """
        {
          "edit": {
            "actions": [],
            "confidence": 0.91,
            "source": "mixed",
            "unresolvedText": null,
            "warnings": [],
            "needsClarification": false,
            "experimentalEffectOperations": []
          },
          "ui": {
            "catalogVersion": "1",
            "workspaceId": "visual_style",
            "intentSummary": "Make it cinematic",
            "intentSlices": [
              { "id": "visual_style", "title": "Visual style", "parameterIds": ["grain"] }
            ],
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
                    "prominence": "primary",
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
                  "prominence": "primary",
                  "intentSliceId": "visual_style",
                  "controls": [
                    {
                      "parameterId": "grain",
                      "control": "slider",
                      "label": "Grain",
                      "minValue": 0,
                      "maxValue": 1,
                      "defaultValue": 0.2
                    }
                  ],
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
          },
          "meta": {
            "hydration": {},
            "edit_events": [{ "type": "planner_started", "status": "Parsing prompt." }],
            "ui_events": [{ "type": "ui_planner_completed", "workspace_id": "visual_style" }],
            "timings": [{ "branch": "total", "elapsed_ms": 42 }]
          }
        }
        """

        let response = try JSONDecoder().decode(RemoteIntentAgentResponse.self, from: Data(json.utf8))

        #expect(response.edit.confidence == 0.91)
        #expect(response.ui.workspaceId == "visual_style")
        #expect(response.ui.intentSlices.first?["id"]?.stringValue == "visual_style")
        if case .bool(let showPromptBar) = response.ui.toolbar["showPromptBar"] {
            #expect(showPromptBar == false)
        } else {
            Issue.record("Expected toolbar.showPromptBar to decode as a bool")
        }
        #expect(response.meta.editEvents.first?["type"]?.stringValue == "planner_started")
        #expect(response.meta.timings.first?.elapsedMs == 42)
    }

    @Test func backendRouteHelpersUseAgentAndSourcesDomains() throws {
        #expect(AppConfiguration.agentRunsEndpoint.path == "/agent/runs")
        #expect(AppConfiguration.transcriptSentencesEndpoint.path == "/agent/transcriptions/sentences")
        #expect(AppConfiguration.projectSourcesEndpoint(projectID: "42").path == "/projects/42/sources")
        #expect(AppConfiguration.projectSourceSearchEndpoint(projectID: "42").path == "/projects/42/sources/search")
        #expect(
            AppConfiguration.projectSourceTranscriptEndpoint(projectID: "42", localKey: "clip-a").path
                == "/projects/42/sources/clip-a/transcript"
        )
        #expect(AppConfiguration.agentWebSocketEndpoint(sessionID: "9")?.path == "/agent/runs/9/stream")
        #expect(AppConfiguration.transcriptionWebSocketEndpoint()?.path == "/agent/voice/transcribe")
        #expect(AppConfiguration.voiceIntentWebSocketEndpoint()?.path == "/agent/voice/intent")
    }

    @Test func decodesRemoteIntentResultEvent() throws {
        let json = """
        {
          "type": "intent_result",
          "prompt": "make it vintage",
          "result": {
            "actions": [],
            "confidence": 0,
            "source": "llm",
            "unresolvedText": "make it vintage",
            "warnings": ["unsupportedAction"],
            "needsClarification": false,
            "experimentalEffectOperations": [
              {
                "operation": "addGrain",
                "sourceText": "make it vintage",
                "intention": "add film grain",
                "target": { "type": "selectedClip" },
                "confidence": 0.8,
                "parameters": { "amount": 0.35 }
              }
            ]
          }
        }
        """

        let event = try RemoteIntentCompilerEvent.decode(from: Data(json.utf8), using: JSONDecoder())
        guard case .intentResult(let prompt, let result) = event else {
            Issue.record("Expected intent result event")
            return
        }

        #expect(prompt == "make it vintage")
        #expect(result.actions.isEmpty)
        #expect(result.experimentalEffectOperations.first?.operation == "addGrain")
        #expect(result.experimentalEffectOperations.first?.intention == "add film grain")
        #expect(result.warnings == [.unsupportedAction])
    }

    @Test func decodesVoiceTranscriptAndResultEvents() throws {
        let transcript = #"{"type":"transcript_completed","text":"make this clip feel more vintage"}"#
        let transcriptEvent = try VoiceIntentServerEvent.decode(from: Data(transcript.utf8), using: JSONDecoder())
        guard case .transcriptCompleted(let text) = transcriptEvent else {
            Issue.record("Expected transcript event")
            return
        }
        #expect(text == "make this clip feel more vintage")

        let result = """
        {
          "type": "intent_result",
          "prompt": "make it vintage",
          "result": {
            "actions": [],
            "confidence": 0,
            "source": "llm",
            "unresolvedText": "make it vintage",
            "warnings": [],
            "needsClarification": false,
            "experimentalEffectOperations": []
          }
        }
        """
        let resultEvent = try VoiceIntentServerEvent.decode(from: Data(result.utf8), using: JSONDecoder())
        guard case .intentResult(let prompt, let compileResult) = resultEvent else {
            Issue.record("Expected voice intent result event")
            return
        }
        #expect(prompt == "make it vintage")
        #expect(compileResult.actions.isEmpty)
    }

    @Test func decodesRemoveClipRangesAction() throws {
        let json = """
        {
          "type": "intent_result",
          "prompt": "cut out the dead space",
          "result": {
            "actions": [
              {
                "action_id": "action-1",
                "timeline_id": "timeline-test",
                "created_at": 800000000,
                "type": "REMOVE_CLIP_RANGES",
                "payload": {
                  "removeClipRanges": {
                    "clipId": "clip-b",
                    "sourceRanges": [
                      { "start": 2000000, "end": 3000000 }
                    ]
                  }
                }
              }
            ],
            "confidence": 0.9,
            "source": "llm",
            "unresolvedText": null,
            "warnings": [],
            "needsClarification": false,
            "experimentalEffectOperations": []
          }
        }
        """

        let event = try RemoteIntentCompilerEvent.decode(from: Data(json.utf8), using: JSONDecoder())
        guard case .intentResult(_, let result) = event,
              case .removeClipRanges(let clipId, let sourceRanges) = result.actions.first?.payload else {
            Issue.record("Expected removeClipRanges action")
            return
        }

        #expect(clipId == "clip-b")
        #expect(sourceRanges == [TimeRange(start: 2_000_000, end: 3_000_000)])
    }
}

