import Foundation

struct TimelineLLMCompiler {
    let provider: TimelineLLMProvider
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        provider: TimelineLLMProvider,
        encoder: JSONEncoder = TimelineLLMCompiler.makeEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.provider = provider
        self.encoder = encoder
        self.decoder = decoder
    }

    func compile(
        prompt: String,
        context: TimelineCompilerContext,
        deterministicResult: TimelineCompileResult?,
        embeddingCandidates: [TimelineEmbeddingCandidate]
    ) async -> TimelineCompileResult {
        do {
            print("[TimelineLLM] Building fallback prompt originalPrompt='\(prompt)' embeddingCandidateCount=\(embeddingCandidates.count)")
            let llmPrompt = try makePrompt(
                prompt: prompt,
                context: context,
                deterministicResult: deterministicResult,
                embeddingCandidates: embeddingCandidates
            )
            print("[TimelineLLM] Sending fallback prompt length=\(llmPrompt.count)")
            let response = try await provider.complete(prompt: llmPrompt)
            print("[TimelineLLM] Received provider response length=\(response.count)")
            let payload = try decodePayload(from: response)
            print("[TimelineLLM] Decoded intents count=\(payload.intents.count) needsClarification=\(payload.needsClarification)")
            return compilePayload(payload, originalPrompt: prompt, context: context)
        } catch TimelineCompilerError.llmUnavailable {
            print("[TimelineLLM] Provider reported llmUnavailable for prompt='\(prompt)'")
            return TimelineCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: prompt,
                warnings: [.llmUnavailable],
                needsClarification: true
            )
        } catch {
            print("[TimelineLLM] Fallback failed with error: \(error)")
            return TimelineCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: prompt,
                warnings: [.invalidLLMResponse],
                needsClarification: true
            )
        }
    }
}

private extension TimelineLLMCompiler {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    func makePrompt(
        prompt: String,
        context: TimelineCompilerContext,
        deterministicResult: TimelineCompileResult?,
        embeddingCandidates: [TimelineEmbeddingCandidate]
    ) throws -> String {
        let contextJson = try jsonString(context)
        let deterministicJson = try jsonString(deterministicResult)
        let embeddingJson = try jsonString(embeddingCandidates)

        return """
        You convert user video-editing timeline requests into structured timeline edit intents.

        Return valid JSON only. Do not explain.

        Supported intent types:
        - splitClip: split one clip at a specific time
        - removeClip: remove a clip from the timeline
        - trimClip: update a clip's sourceRange and timelineRange
        - moveClip: reorder a clip within its track
        - replaceTrackClips: replace all clips in a track order/state
        - unknown: the request cannot be represented with the supported timeline actions

        Rules:
        - Use only the supported intent types.
        - Do not invent unsupported operations.
        - Prefer the smallest number of actions.
        - If the prompt can be fully represented as splitClip/removeClip/trimClip/moveClip, do that.
        - If the target is "this clip" or "selected clip", use the selectedClipId from context.
        - If required information is missing, return needsClarification = true.
        - Do not create effects, captions, audio edits, color edits, or style edits.
        - For abstract requests outside timeline position/range edits, return unknown.

        Editor context:
        \(contextJson)

        Original prompt:
        \(prompt)

        Deterministic results:
        \(deterministicJson)

        Embedding candidates:
        \(embeddingJson)

        Return this exact JSON shape:
        {
          "intents": [
            {
              "type": "splitClip | removeClip | trimClip | moveClip | replaceTrackClips | unknown",
              "sourceText": "exact phrase from the user prompt",
              "targetClipId": "clip id or null",
              "targetTrackId": "track id or null",
              "confidence": 0.0,
              "parameters": {}
            }
          ],
          "needsClarification": false,
          "clarificationQuestion": null
        }
        """
    }

    func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func decodePayload(from response: String) throws -> TimelineLLMCompilePayload {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = extractJSONObject(from: trimmed) ?? trimmed
        guard let data = jsonText.data(using: .utf8) else {
            throw TimelineCompilerError.invalidLLMResponse
        }
        return try decoder.decode(TimelineLLMCompilePayload.self, from: data)
    }

    func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }

    func compilePayload(
        _ payload: TimelineLLMCompilePayload,
        originalPrompt: String,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult {
        if payload.needsClarification {
            return TimelineCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: payload.clarificationQuestion ?? originalPrompt,
                warnings: [.ambiguousTarget],
                needsClarification: true
            )
        }

        var actions: [Action] = []
        var warnings: [TimelineCompileWarning] = []
        var confidences: [Double] = []

        for intent in payload.intents {
            switch compileIntent(intent, context: context) {
            case .success(let action):
                actions.append(action)
                confidences.append(intent.confidence)
            case .unsupported:
                warnings.append(.unsupportedIntent)
            case .failure(let warning):
                warnings.append(warning)
            }
        }

        if actions.isEmpty {
            return TimelineCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: originalPrompt,
                warnings: warnings.isEmpty ? [.noActionProduced] : Array(Set(warnings)),
                needsClarification: false
            )
        }

        let confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return TimelineCompileResult(
            actions: actions,
            confidence: confidence,
            source: .llm,
            unresolvedText: nil,
            warnings: Array(Set(warnings)),
            needsClarification: false
        )
    }

    enum IntentCompileResult {
        case success(Action)
        case unsupported
        case failure(TimelineCompileWarning)
    }

    func compileIntent(_ intent: TimelineEditIntent, context: TimelineCompilerContext) -> IntentCompileResult {
        switch intent.type {
        case .splitClip:
            return compileSplitIntent(intent, context: context)
        case .removeClip:
            return compileRemoveIntent(intent, context: context)
        case .trimClip:
            return compileTrimIntent(intent, context: context)
        case .moveClip:
            return compileMoveIntent(intent, context: context)
        case .replaceTrackClips:
            return compileReplaceTrackClipsIntent(intent, context: context)
        case .unknown:
            return .unsupported
        }
    }

    func compileSplitIntent(_ intent: TimelineEditIntent, context: TimelineCompilerContext) -> IntentCompileResult {
        guard let clip = resolvedClip(for: intent, context: context) else {
            return .failure(.clipNotFound)
        }
        guard let timeUs = splitTimeUs(from: intent, clip: clip) else {
            return .failure(.missingPlayhead)
        }

        return .success(
            Action.splitClip(timelineId: context.timelineId, clipId: clip.clipId, atTimeUs: timeUs)
        )
    }

    func compileRemoveIntent(_ intent: TimelineEditIntent, context: TimelineCompilerContext) -> IntentCompileResult {
        guard let clip = resolvedClip(for: intent, context: context) else {
            return .failure(.clipNotFound)
        }

        return .success(
            Action.removeClip(timelineId: context.timelineId, clipId: clip.clipId)
        )
    }

    func compileTrimIntent(_ intent: TimelineEditIntent, context: TimelineCompilerContext) -> IntentCompileResult {
        guard let clip = resolvedClip(for: intent, context: context) else {
            return .failure(.clipNotFound)
        }

        if let sourceRange = rangeValue(intent.parameters["sourceRange"]),
           let timelineRange = rangeValue(intent.parameters["timelineRange"]) {
            return .success(
                Action.trimClip(
                    timelineId: context.timelineId,
                    clipId: clip.clipId,
                    sourceRange: sourceRange,
                    timelineRange: timelineRange
                )
            )
        }

        guard let durationUs = durationUs(from: intent.parameters) else {
            return .failure(.invalidTrimRange)
        }

        let edge = intent.parameters["edge"]?.stringValue?.lowercased()
        if edge == "start" || edge == "beginning" {
            let sourceRange = TimeRange(start: clip.sourceRange.start + durationUs, end: clip.sourceRange.end)
            let timelineRange = TimeRange(start: clip.timelineRange.start + durationUs, end: clip.timelineRange.end)
            return .success(Action.trimClip(timelineId: context.timelineId, clipId: clip.clipId, sourceRange: sourceRange, timelineRange: timelineRange))
        }

        if edge == "end" || edge == "final" {
            let sourceRange = TimeRange(start: clip.sourceRange.start, end: clip.sourceRange.end - durationUs)
            let timelineRange = TimeRange(start: clip.timelineRange.start, end: clip.timelineRange.end - durationUs)
            return .success(Action.trimClip(timelineId: context.timelineId, clipId: clip.clipId, sourceRange: sourceRange, timelineRange: timelineRange))
        }

        return .failure(.invalidTrimRange)
    }

    func compileMoveIntent(_ intent: TimelineEditIntent, context: TimelineCompilerContext) -> IntentCompileResult {
        guard let clip = resolvedClip(for: intent, context: context) else {
            return .failure(.clipNotFound)
        }

        if let orderValue = intent.parameters["orderedClipIds"],
           case .array(let ids) = orderValue {
            let orderedClipIds = ids.compactMap(\.stringValue)
            return .success(Action.moveClip(timelineId: context.timelineId, clipId: clip.clipId, orderedClipIds: orderedClipIds))
        }

        let placement = intent.parameters["placement"]?.stringValue?.lowercased()
        let originalOrder = context.orderedClipIds(for: clip)
        guard originalOrder.contains(clip.clipId) else {
            return .failure(.invalidMoveOrder)
        }

        var newOrder = originalOrder.filter { $0 != clip.clipId }
        if placement == "beginning" || placement == "start" || placement == "first" {
            newOrder.insert(clip.clipId, at: 0)
        } else if placement == "end" || placement == "last" {
            newOrder.append(clip.clipId)
        } else {
            return .failure(.ambiguousTarget)
        }

        return .success(Action.moveClip(timelineId: context.timelineId, clipId: clip.clipId, orderedClipIds: newOrder))
    }

    func compileReplaceTrackClipsIntent(_ intent: TimelineEditIntent, context: TimelineCompilerContext) -> IntentCompileResult {
        guard let trackId = intent.targetTrackId ?? context.selectedTrackId else {
            return .failure(.trackNotFound)
        }
        guard let orderedClipIdsValue = intent.parameters["orderedClipIds"],
              case .array(let orderedClipIdValues) = orderedClipIdsValue else {
            return .failure(.invalidMoveOrder)
        }

        let clips = orderedClipIdValues.compactMap { value -> Clip? in
            guard let clipId = value.stringValue else { return nil }
            return context.clipsById[clipId]
        }
        guard clips.count == orderedClipIdValues.count else {
            return .failure(.clipNotFound)
        }

        return .success(Action.replaceTrackClips(timelineId: context.timelineId, trackId: trackId, clips: clips))
    }

    func resolvedClip(for intent: TimelineEditIntent, context: TimelineCompilerContext) -> Clip? {
        if let targetClipId = intent.targetClipId {
            return context.clipsById[targetClipId]
        }
        return context.selectedClip
    }

    func splitTimeUs(from intent: TimelineEditIntent, clip: Clip) -> Int64? {
        if let atTimeUs = intent.parameters["atTimeUs"]?.intValue
            ?? intent.parameters["timeUs"]?.intValue {
            return atTimeUs
        }

        if let seconds = intent.parameters["timeSeconds"]?.doubleValue {
            return Int64(seconds * 1_000_000)
        }

        if intent.parameters["position"]?.stringValue == "50%" {
            return clip.timelineRange.start + (clip.timelineRange.duration / 2)
        }

        return nil
    }

    func rangeValue(_ value: JSONValue?) -> TimeRange? {
        guard case .object(let object) = value,
              let start = object["start"]?.intValue,
              let end = object["end"]?.intValue else {
            return nil
        }
        return TimeRange(start: start, end: end)
    }

    func durationUs(from parameters: [String: JSONValue]) -> Int64? {
        parameters["durationUs"]?.intValue
            ?? parameters["durationSeconds"]?.doubleValue.map { Int64($0 * 1_000_000) }
    }
}
