import Foundation
import Testing
@testable import Iris_Main

struct TimelinePromptActionCompilerTests {
    @Test func cutClipInHalfUsesDeterministicEarlyExit() async throws {
        let embeddingProvider = TestEmbeddingProvider()
        let llmProvider = TestLLMProvider(response: unknownLLMResponse)
        let result = try await makeCompiler(embeddingProvider: embeddingProvider, llmProvider: llmProvider)
            .compilePromptToActions(prompt: "cut this clip in half", context: makeContext())

        #expect(result.source == .deterministic)
        #expect(result.confidence >= 0.95)
        #expect(result.needsClarification == false)
        #expect(splitTimeUs(from: result) == 10_000_000)
        #expect(await embeddingProvider.callCount() == 0)
        #expect(await llmProvider.callCount() == 0)
    }

    @Test func splitAtPlayheadUsesDeterministicSplit() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "split at the playhead",
            context: makeContext(playheadTimeUs: 9_000_000)
        )

        #expect(result.source == .deterministic)
        #expect(splitTimeUs(from: result) == 9_000_000)
    }

    @Test func splitAtExplicitSecondsUsesParsedTime() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "split at 10 seconds",
            context: makeContext()
        )

        #expect(result.source == .deterministic)
        #expect(splitTimeUs(from: result) == 10_000_000)
    }

    @Test func deleteThisClipUsesDeterministicRemove() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "delete this clip",
            context: makeContext()
        )

        #expect(result.source == .deterministic)
        #expect(removeClipId(from: result) == "clip-b")
    }

    @Test func removeSelectedClipUsesDeterministicRemove() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "remove selected clip",
            context: makeContext()
        )

        #expect(result.source == .deterministic)
        #expect(removeClipId(from: result) == "clip-b")
    }

    @Test func cutFirstThreeSecondsUsesTrimClip() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "cut the first 3 seconds",
            context: makeContext()
        )

        let payload = trimPayload(from: result)
        #expect(result.source == .deterministic)
        #expect(payload?.clipId == "clip-b")
        #expect(payload?.sourceRange == TimeRange(start: 3_000_000, end: 10_000_000))
        #expect(payload?.timelineRange == TimeRange(start: 8_000_000, end: 15_000_000))
    }

    @Test func removeFinalFiveSecondsUsesTrimClip() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "remove the final 5 seconds",
            context: makeContext()
        )

        let payload = trimPayload(from: result)
        #expect(result.source == .deterministic)
        #expect(payload?.clipId == "clip-b")
        #expect(payload?.sourceRange == TimeRange(start: 0, end: 5_000_000))
        #expect(payload?.timelineRange == TimeRange(start: 5_000_000, end: 10_000_000))
    }

    @Test func moveClipToBeginningReordersTrack() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "move this clip to the beginning",
            context: makeContext()
        )

        #expect(result.source == .deterministic)
        #expect(movePayload(from: result)?.orderedClipIds == ["clip-b", "clip-a", "clip-c"])
    }

    @Test func moveClipToEndReordersTrack() async throws {
        let result = try await makeCompiler().compilePromptToActions(
            prompt: "move this clip to the end",
            context: makeContext()
        )

        #expect(result.source == .deterministic)
        #expect(movePayload(from: result)?.orderedClipIds == ["clip-a", "clip-c", "clip-b"])
    }

    @Test func makeTwoClipsUsesEmbeddingEarlyExitWhenResolvable() async throws {
        let embeddingProvider = TestEmbeddingProvider()
        let llmProvider = TestLLMProvider(response: unknownLLMResponse)
        let result = try await makeCompiler(embeddingProvider: embeddingProvider, llmProvider: llmProvider)
            .compilePromptToActions(prompt: "make two clips from this", context: makeContext())

        #expect(result.source == .embedding)
        #expect(splitTimeUs(from: result) == 10_000_000)
        #expect(await embeddingProvider.callCount() > 0)
        #expect(await llmProvider.callCount() == 0)
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

    @Test func ambiguousEmbeddingFallsThroughToLLM() async throws {
        let llmProvider = TestLLMProvider(response: unknownLLMResponse)
        _ = try await makeCompiler(llmProvider: llmProvider).compilePromptToActions(
            prompt: "shorten this clip",
            context: makeContext()
        )

        #expect(await llmProvider.callCount() == 1)
    }
}

private let unknownLLMResponse = """
{
  "intents": [
    {
      "type": "unknown",
      "sourceText": "make this clip vintage",
      "targetClipId": null,
      "targetTrackId": null,
      "confidence": 0.0,
      "parameters": {}
    }
  ],
  "needsClarification": false,
  "clarificationQuestion": null
}
"""

private func makeCompiler(
    embeddingProvider: TestEmbeddingProvider = TestEmbeddingProvider(),
    llmProvider: TestLLMProvider = TestLLMProvider(response: unknownLLMResponse)
) -> TimelinePromptActionCompiler {
    TimelinePromptActionCompiler(
        embeddingRetriever: TimelineEmbeddingIntentRetriever(embeddingProvider: embeddingProvider),
        llmCompiler: TimelineLLMCompiler(provider: llmProvider)
    )
}

private func makeContext(playheadTimeUs: Int64 = 10_000_000) -> TimelineCompilerContext {
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

    return TimelineCompilerContext(
        timelineId: "timeline-1",
        selectedClipId: "clip-b",
        selectedTrackId: "track-video",
        selectedRange: nil,
        playheadTimeUs: playheadTimeUs,
        clipsById: Dictionary(uniqueKeysWithValues: clips.map { ($0.clipId, $0) }),
        orderedClipIdsByTrackId: ["track-video": ["clip-a", "clip-b", "clip-c"]]
    )
}

private func splitTimeUs(from result: TimelineCompileResult) -> Int64? {
    guard case .splitClip(_, let atTimeUs) = result.actions.first?.payload else {
        return nil
    }
    return atTimeUs
}

private func removeClipId(from result: TimelineCompileResult) -> String? {
    guard case .removeClip(let clipId) = result.actions.first?.payload else {
        return nil
    }
    return clipId
}

private func trimPayload(from result: TimelineCompileResult) -> (
    clipId: String,
    sourceRange: TimeRange,
    timelineRange: TimeRange
)? {
    guard case .trimClip(let clipId, let sourceRange, let timelineRange) = result.actions.first?.payload else {
        return nil
    }
    return (clipId, sourceRange, timelineRange)
}

private func movePayload(from result: TimelineCompileResult) -> (
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
        return TimelineKeywordEmbedding.vector(for: text)
    }

    func callCount() -> Int {
        calls
    }
}

private actor TestLLMProvider: TimelineLLMProvider {
    private let response: String
    private var calls = 0

    init(response: String) {
        self.response = response
    }

    func complete(prompt: String) async throws -> String {
        calls += 1
        return response
    }

    func callCount() -> Int {
        calls
    }
}
