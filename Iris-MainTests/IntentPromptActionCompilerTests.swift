import Foundation
import Testing
@testable import Iris_Main

struct IntentPromptActionCompilerTests {
    @Test func cutClipInHalfUsesLLMOnlyFlow() async throws {
        let embeddingProvider = TestEmbeddingProvider()
        let llmProvider = TestLLMProvider(response: splitHalfLLMResponse)
        let result = try await makeCompiler(embeddingProvider: embeddingProvider, llmProvider: llmProvider)
            .compilePromptToActions(prompt: "cut this clip in half", context: makeContext())

        #expect(result.source == .llm)
        #expect(result.confidence >= 0.8)
        #expect(result.needsClarification == false)
        #expect(splitTimeUs(from: result) == 10_000_000)
        #expect(await embeddingProvider.callCount() == 0)
        #expect(await llmProvider.callCount() == 1)
    }

    @Test func splitAtPlayheadUsesLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: splitAtPlayheadLLMResponse)).compilePromptToActions(
            prompt: "split at the playhead",
            context: makeContext(playheadTimeUs: 9_000_000)
        )

        #expect(result.source == .llm)
        #expect(splitTimeUs(from: result) == 9_000_000)
    }

    @Test func splitAtExplicitSecondsUsesLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: splitAtAbsoluteTimeLLMResponse)).compilePromptToActions(
            prompt: "split at 10 seconds",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(splitTimeUs(from: result) == 10_000_000)
    }

    @Test func deleteThisClipUsesLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: selectedClipRemoveLLMResponse)).compilePromptToActions(
            prompt: "delete this clip",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(removeClipId(from: result) == "clip-b")
    }

    @Test func removeSelectedClipUsesLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: selectedClipRemoveLLMResponse)).compilePromptToActions(
            prompt: "remove selected clip",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(removeClipId(from: result) == "clip-b")
    }

    @Test func cutFirstThreeSecondsUsesLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: trimFirstThreeSecondsLLMResponse)).compilePromptToActions(
            prompt: "cut the first 3 seconds",
            context: makeContext()
        )

        let payload = trimPayload(from: result)
        #expect(result.source == .llm)
        #expect(payload?.clipId == "clip-b")
        #expect(payload?.sourceRange == TimeRange(start: 3_000_000, end: 10_000_000))
        #expect(payload?.timelineRange == TimeRange(start: 8_000_000, end: 15_000_000))
    }

    @Test func explicitDurationUnitInSourceTextOverridesBadLLMUnit() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: trimFirstTwoSecondsWithBadUnitLLMResponse)).compilePromptToActions(
            prompt: "trim the first 2 seconds of the clip",
            context: makeContext()
        )

        let payload = trimPayload(from: result)
        #expect(result.source == .llm)
        #expect(payload?.clipId == "clip-b")
        #expect(payload?.sourceRange == TimeRange(start: 2_000_000, end: 10_000_000))
        #expect(payload?.timelineRange == TimeRange(start: 7_000_000, end: 15_000_000))
    }

    @Test func trimDurationCanOmitTypeInLLMResponse() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: trimFirstTwoSecondsWithoutTypeLLMResponse)).compilePromptToActions(
            prompt: "trim the first 2 seconds of the clip",
            context: makeContext()
        )

        let payload = trimPayload(from: result)
        #expect(result.source == .llm)
        #expect(result.needsClarification == false)
        #expect(payload?.clipId == "clip-b")
        #expect(payload?.sourceRange == TimeRange(start: 2_000_000, end: 10_000_000))
        #expect(payload?.timelineRange == TimeRange(start: 7_000_000, end: 15_000_000))
    }

    @Test func removeFinalFiveSecondsUsesLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: trimFinalFiveSecondsLLMResponse)).compilePromptToActions(
            prompt: "remove the final 5 seconds",
            context: makeContext()
        )

        let payload = trimPayload(from: result)
        #expect(result.source == .llm)
        #expect(payload?.clipId == "clip-b")
        #expect(payload?.sourceRange == TimeRange(start: 0, end: 5_000_000))
        #expect(payload?.timelineRange == TimeRange(start: 5_000_000, end: 10_000_000))
    }

    @Test func moveClipToBeginningReordersTrackThroughLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: moveToBeginningLLMResponse)).compilePromptToActions(
            prompt: "move this clip to the beginning",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(movePayload(from: result)?.orderedClipIds == ["clip-b", "clip-a", "clip-c"])
    }

    @Test func moveClipToEndReordersTrackThroughLLMOnlyFlow() async throws {
        let result = try await makeCompiler(llmProvider: TestLLMProvider(response: moveToEndLLMResponse)).compilePromptToActions(
            prompt: "move this clip to the end",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(movePayload(from: result)?.orderedClipIds == ["clip-a", "clip-c", "clip-b"])
    }

    @Test func makeTwoClipsSkipsEmbeddingAndUsesLLM() async throws {
        let embeddingProvider = TestEmbeddingProvider()
        let llmProvider = TestLLMProvider(response: splitHalfLLMResponse)
        let result = try await makeCompiler(embeddingProvider: embeddingProvider, llmProvider: llmProvider)
            .compilePromptToActions(prompt: "make two clips from this", context: makeContext())

        #expect(result.source == .llm)
        #expect(splitTimeUs(from: result) == 10_000_000)
        #expect(await embeddingProvider.callCount() == 0)
        #expect(await llmProvider.callCount() == 1)
    }

    @Test func unsupportedStylePromptReturnsNoTimelineAction() async throws {
        let llmProvider = TestLLMProvider(response: unknownLLMResponse)
        let result = try await makeCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "make this clip vintage",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(result.actions.isEmpty)
        #expect(result.warnings.contains(.unsupportedIntent))
        #expect(result.needsClarification == false)
    }

    @Test func llmPromptOmitsDeterministicAndEmbeddingHints() async throws {
        let llmProvider = TestLLMProvider(response: unknownLLMResponse)
        _ = try await makeCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "shorten this clip",
            context: makeContext()
        )

        #expect(await llmProvider.callCount() == 1)
        let prompt = await llmProvider.lastPrompt()
        #expect(prompt?.contains("Deterministic results") == false)
        #expect(prompt?.contains("Embedding candidates") == false)
        #expect(prompt?.contains("Return JSON only") == true)
        #expect(prompt?.contains("split compound requests into ordered operations") == true)
        #expect(prompt?.contains("\"selectedClipId\":\"clip-b\"") == true)
        #expect(prompt?.contains("\"currentClip\":{\"clipId\":\"clip-b\",\"durationUs\":10000000,\"trackId\":\"track-video\"}") == true)
        #expect(prompt?.contains("created_at") == false)
        #expect(prompt?.contains("updated_at") == false)
        #expect(prompt?.contains("source_range") == false)
        #expect(prompt?.contains("timeline_range") == false)
    }

    @Test func llmSemanticTrimThenSplitUsesPostTrimTimelineRange() async throws {
        let llmProvider = TestLLMProvider(response: trimThenSplitLLMResponse)
        let result = try await makeLLMOnlyCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "trim the first second of the clip and split it in half",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(result.needsClarification == false)
        #expect(result.actions.count == 2)
        #expect(trimPayload(from: result, at: 0)?.sourceRange == TimeRange(start: 1_000_000, end: 10_000_000))
        #expect(trimPayload(from: result, at: 0)?.timelineRange == TimeRange(start: 6_000_000, end: 15_000_000))
        #expect(splitTimeUs(from: result, at: 1) == 10_500_000)
    }

    @Test func llmSameAsPreviousResolvesPriorTarget() async throws {
        let llmProvider = TestLLMProvider(response: trimThenSplitLLMResponse)
        let result = try await makeLLMOnlyCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "trim the first second of the clip and split it in half",
            context: makeContext()
        )

        #expect(trimPayload(from: result, at: 0)?.clipId == "clip-b")
        guard case .splitClip(let clipId, _) = result.actions[safe: 1]?.payload else {
            Issue.record("Expected second action to be splitClip")
            return
        }
        #expect(clipId == "clip-b")
    }

    @Test func llmAbsoluteTimelineSecondsConvertDeterministically() async throws {
        let llmProvider = TestLLMProvider(response: splitAtAbsoluteTimeLLMResponse)
        let result = try await makeLLMOnlyCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "put a cut on this clip at 10 seconds",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(splitTimeUs(from: result) == 10_000_000)
    }

    @Test func llmMissingSelectedClipReturnsClarification() async throws {
        let llmProvider = TestLLMProvider(response: selectedClipRemoveLLMResponse)
        let result = try await makeLLMOnlyCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "delete the clip",
            context: makeContext(selectedClipId: nil)
        )

        #expect(result.source == .llm)
        #expect(result.actions.isEmpty)
        #expect(result.needsClarification)
        #expect(result.warnings.contains(.missingSelectedClip))
    }

    @Test func llmOverTrimReturnsClarification() async throws {
        let llmProvider = TestLLMProvider(response: overTrimLLMResponse)
        let result = try await makeLLMOnlyCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "trim 20 seconds off the start",
            context: makeContext()
        )

        #expect(result.source == .llm)
        #expect(result.actions.isEmpty)
        #expect(result.needsClarification)
        #expect(result.warnings.contains(.invalidTrimRange))
    }
}

private let unknownLLMResponse = """
{
  "operations": [
    {
      "type": "unknown",
      "sourceText": "make this clip vintage",
      "target": null,
      "confidence": 0.0,
      "parameters": {}
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let splitHalfLLMResponse = """
{
  "operations": [
    {
      "type": "splitClip",
      "sourceText": "cut this clip in half",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.9,
      "parameters": {
        "position": {
          "type": "fractionOfClip",
          "value": 0.5,
          "relativeTo": "postPreviousOperations"
        }
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let splitAtPlayheadLLMResponse = """
{
  "operations": [
    {
      "type": "splitClip",
      "sourceText": "split at the playhead",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.9,
      "parameters": {
        "position": {
          "type": "playhead"
        }
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let trimFirstThreeSecondsLLMResponse = """
{
  "operations": [
    {
      "type": "trimClip",
      "sourceText": "cut the first 3 seconds",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.9,
      "parameters": {
        "edge": "start",
        "amount": {
          "type": "duration",
          "value": 3,
          "unit": "second"
        }
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let trimFirstTwoSecondsWithBadUnitLLMResponse = """
{
  "operations": [
    {
      "type": "trimClip",
      "sourceText": "first 2 seconds",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.0,
      "parameters": {
        "edge": "start",
        "amount": {
          "type": "duration",
          "value": 2,
          "unit": "microsecond"
        }
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let trimFirstTwoSecondsWithoutTypeLLMResponse = """
{
  "operations": [
    {
      "type": "trimClip",
      "sourceText": "first 2 seconds",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.9,
      "parameters": {
        "edge": "start",
        "amount": {
          "value": 2,
          "unit": "second"
        }
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let trimFinalFiveSecondsLLMResponse = """
{
  "operations": [
    {
      "type": "trimClip",
      "sourceText": "remove the final 5 seconds",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.9,
      "parameters": {
        "edge": "end",
        "amount": {
          "type": "duration",
          "value": 5,
          "unit": "second"
        }
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let moveToBeginningLLMResponse = """
{
  "operations": [
    {
      "type": "moveClip",
      "sourceText": "move this clip to the beginning",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.9,
      "parameters": {
        "placement": "beginning"
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let moveToEndLLMResponse = """
{
  "operations": [
    {
      "type": "moveClip",
      "sourceText": "move this clip to the end",
      "target": {
        "type": "selectedClip"
      },
      "confidence": 0.9,
      "parameters": {
        "placement": "end"
      }
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let trimThenSplitLLMResponse = """
{
  "operations": [
    {
      "type": "trimClip",
      "sourceText": "trim the first second of the clip",
      "target": {
        "type": "selectedClip"
      },
      "parameters": {
        "edge": "start",
        "amount": {
          "type": "duration",
          "value": 1,
          "unit": "second"
        }
      },
      "confidence": 0.92
    },
    {
      "type": "splitClip",
      "sourceText": "split it in half",
      "target": {
        "type": "sameAsPrevious"
      },
      "parameters": {
        "position": {
          "type": "fractionOfClip",
          "value": 0.5,
          "relativeTo": "postPreviousOperations"
        }
      },
      "confidence": 0.9
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let splitAtAbsoluteTimeLLMResponse = """
{
  "operations": [
    {
      "type": "splitClip",
      "sourceText": "split this clip at 10 seconds",
      "target": {
        "type": "selectedClip"
      },
      "parameters": {
        "position": {
          "type": "absoluteTimelineTime",
          "value": 10,
          "unit": "second"
        }
      },
      "confidence": 0.88
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let selectedClipRemoveLLMResponse = """
{
  "operations": [
    {
      "type": "removeClip",
      "sourceText": "delete the clip",
      "target": {
        "type": "selectedClip"
      },
      "parameters": {},
      "confidence": 0.86
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private let overTrimLLMResponse = """
{
  "operations": [
    {
      "type": "trimClip",
      "sourceText": "trim 20 seconds off the start",
      "target": {
        "type": "selectedClip"
      },
      "parameters": {
        "edge": "start",
        "amount": {
          "type": "duration",
          "value": 20,
          "unit": "second"
        }
      },
      "confidence": 0.84
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private func makeCompiler(
    embeddingProvider: TestEmbeddingProvider = TestEmbeddingProvider(),
    llmProvider: TestLLMProvider = TestLLMProvider(response: unknownLLMResponse)
) -> IntentPromptActionCompiler {
    IntentPromptActionCompiler(
        embeddingRetriever: IntentEmbeddingRetriever(embeddingProvider: embeddingProvider),
        llmCompiler: IntentLLMCompiler(provider: llmProvider)
    )
}

private func makeLLMOnlyCompiler(llmProvider: TestLLMProvider) -> IntentPromptActionCompiler {
    IntentPromptActionCompiler(
        embeddingRetriever: IntentEmbeddingRetriever(
            embeddingProvider: TestEmbeddingProvider(),
            examplesByType: [:]
        ),
        llmCompiler: IntentLLMCompiler(provider: llmProvider)
    )
}

private func makeContext(
    selectedClipId: String? = "clip-b",
    playheadTimeUs: Int64 = 10_000_000
) -> IntentCompilerContext {
    let clips = [
        Clip(
            clipId: "clip-a",
            trackId: "track-video",
            mediaId: "media-a",
            sourceRange: TimeRange(start: 0, end: 5_000_000),
            timelineRange: TimeRange(start: 0, end: 5_000_000)
        ),
        Clip(
            clipId: "clip-b",
            trackId: "track-video",
            mediaId: "media-b",
            sourceRange: TimeRange(start: 0, end: 10_000_000),
            timelineRange: TimeRange(start: 5_000_000, end: 15_000_000)
        ),
        Clip(
            clipId: "clip-c",
            trackId: "track-video",
            mediaId: "media-c",
            sourceRange: TimeRange(start: 0, end: 5_000_000),
            timelineRange: TimeRange(start: 15_000_000, end: 20_000_000)
        )
    ]

    return IntentCompilerContext(
        timelineId: "timeline-1",
        selectedClipId: selectedClipId,
        selectedTrackId: "track-video",
        selectedRange: nil,
        playheadTimeUs: playheadTimeUs,
        clipsById: Dictionary(uniqueKeysWithValues: clips.map { ($0.clipId, $0) }),
        orderedClipIdsByTrackId: ["track-video": ["clip-a", "clip-b", "clip-c"]]
    )
}

private func splitTimeUs(from result: IntentCompileResult, at index: Int = 0) -> Int64? {
    guard case .splitClip(_, let atTimeUs) = result.actions[safe: index]?.payload else {
        return nil
    }
    return atTimeUs
}

private func removeClipId(from result: IntentCompileResult) -> String? {
    guard case .removeClip(let clipId) = result.actions.first?.payload else {
        return nil
    }
    return clipId
}

private func trimPayload(from result: IntentCompileResult, at index: Int = 0) -> (
    clipId: String,
    sourceRange: TimeRange,
    timelineRange: TimeRange
)? {
    guard case .trimClip(let clipId, let sourceRange, let timelineRange) = result.actions[safe: index]?.payload else {
        return nil
    }
    return (clipId, sourceRange, timelineRange)
}

private func movePayload(from result: IntentCompileResult) -> (
    clipId: String,
    orderedClipIds: [String]
)? {
    guard case .moveClip(let clipId, let orderedClipIds) = result.actions.first?.payload else {
        return nil
    }
    return (clipId, orderedClipIds)
}

private actor TestEmbeddingProvider: EmbeddingProvider {
    private var calls = 0

    func embed(_ text: String) async throws -> [Float] {
        calls += 1
        return IntentKeywordEmbedding.vector(for: text)
    }

    func callCount() -> Int {
        calls
    }
}

private actor TestLLMProvider: IntentLLMProvider {
    private let response: String
    private var calls = 0
    private var capturedPrompt: String?

    init(response: String) {
        self.response = response
    }

    func complete(prompt: String) async throws -> String {
        calls += 1
        capturedPrompt = prompt
        return response
    }

    func callCount() -> Int {
        calls
    }

    func lastPrompt() -> String? {
        capturedPrompt
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
