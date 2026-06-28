import Foundation
import Testing
@testable import Iris_Main

@MainActor
struct EditorPromptBarViewModelTests {
    @Test func localIntentSuccessSkipsRemoteCompiler() async throws {
        var handledLocalPrompts: [String] = []
        var remoteCallCount = 0
        let viewModel = EditorPromptBarViewModelTests.makeViewModel { _, _, _, _, _ in
            remoteCallCount += 1
            return try Self.makeRemoteResponse()
        }

        viewModel.openTextPrompt()
        viewModel.promptDraft = "Make the timeline bigger"

        await viewModel.submitTextPrompt { prompt in
            handledLocalPrompts.append(prompt)
            return true
        }

        #expect(handledLocalPrompts == ["Make the timeline bigger"])
        #expect(remoteCallCount == 0)
        #expect(viewModel.phase == EditorPromptBarPhase.idle)
    }

    @Test func localIntentFailureFallsBackToRemoteCompiler() async throws {
        var handledLocalPrompts: [String] = []
        var remotePrompts: [String] = []
        let viewModel = EditorPromptBarViewModelTests.makeViewModel { prompt, _, _, _, statusHandler in
            remotePrompts.append(prompt)
            await statusHandler?("Remote compiler ran.")
            return try Self.makeRemoteResponse()
        }

        viewModel.openTextPrompt()
        viewModel.promptDraft = "Cut out dead space"

        await viewModel.submitTextPrompt { prompt in
            handledLocalPrompts.append(prompt)
            return false
        }

        #expect(handledLocalPrompts == ["Cut out dead space"])
        #expect(remotePrompts == ["Cut out dead space"])
        #expect(viewModel.phase == EditorPromptBarPhase.idle)
    }
}

private extension EditorPromptBarViewModelTests {
    static func makeViewModel(
        remoteCompile: @escaping EditorPromptBarViewModel.RemoteCompileHandler
    ) -> EditorPromptBarViewModel {
        EditorPromptBarViewModel(
            contextProvider: {
                IntentCompilerContext(
                    timelineId: "timeline-1",
                    selectedClipId: nil,
                    selectedTrackId: nil,
                    selectedRange: nil,
                    playheadTimeUs: nil,
                    clipsById: [:],
                    orderedClipIdsByTrackId: [:]
                )
            },
            applyActions: { _ in true },
            remoteCompile: remoteCompile
        )
    }

    static func makeRemoteResponse() throws -> RemoteIntentAgentResponse {
        let json = """
        {
          "edit": {
            "actions": [],
            "confidence": 1.0,
            "source": "deterministic",
            "unresolvedText": null,
            "warnings": [],
            "needsClarification": false,
            "experimentalEffectOperations": []
          },
          "ui": {
            "catalogVersion": "1",
            "workspaceId": "default",
            "intentSummary": "",
            "intentSlices": [],
            "currentSliceId": null,
            "currentSliceIndex": 0,
            "layout": {},
            "toolbar": {},
            "transitions": [],
            "hiddenBecauseIrrelevant": [],
            "warnings": [],
            "isDefaultWorkspace": true,
            "restoreDefaultOnComplete": true
          },
          "meta": {
            "hydration": {},
            "edit_events": [],
            "ui_events": [],
            "timings": []
          }
        }
        """
        return try JSONDecoder().decode(RemoteIntentAgentResponse.self, from: Data(json.utf8))
    }
}
