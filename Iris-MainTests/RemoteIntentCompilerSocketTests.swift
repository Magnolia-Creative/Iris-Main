import Foundation
import Testing
@testable import Iris_Main

struct RemoteIntentCompilerSocketTests {
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
}

