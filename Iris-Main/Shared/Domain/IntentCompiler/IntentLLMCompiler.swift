import Foundation

struct IntentLLMCompiler {
    let provider: IntentLLMProvider
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        provider: IntentLLMProvider,
        encoder: JSONEncoder = IntentLLMCompiler.makeEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.provider = provider
        self.encoder = encoder
        self.decoder = decoder
    }

    func compile(
        prompt: String,
        context: IntentCompilerContext,
        deterministicResult: IntentCompileResult?,
        embeddingCandidates: [IntentEmbeddingCandidate]
    ) async -> IntentCompileResult {
        do {
            print("[IntentLLM] Building LLM-only prompt originalPrompt='\(prompt)'")
            let llmPrompt = try makePrompt(
                prompt: prompt,
                context: context,
                deterministicResult: deterministicResult,
                embeddingCandidates: embeddingCandidates
            )
            print("[IntentLLM] Sending LLM-only prompt length=\(llmPrompt.count)")
            let response = try await provider.complete(prompt: llmPrompt)
            print("[IntentLLM] Received provider response length=\(response.count)")
            print("[IntentLLM] Raw provider response:\n\(response)")
            let payload = try decodePayload(from: response)
            print("[IntentLLM] Decoded semantic operations count=\(payload.operations.count) needsClarification=\(payload.needsClarification)")
            print("[IntentLLM] Decoded semantic IR:\n\(IntentCompilerLog.json(payload))")
            return IntentCompiler().compile(payload, originalPrompt: prompt, context: context)
        } catch IntentCompilerError.llmUnavailable {
            print("[IntentLLM] Provider reported llmUnavailable for prompt='\(prompt)'")
            return IntentCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: prompt,
                warnings: [.llmUnavailable],
                needsClarification: true
            )
        } catch {
            print("[IntentLLM] LLM-only compilation failed with error: \(error)")
            return IntentCompileResult(
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

private struct LLMEditorContext: Codable {
    let timelineId: String
    let selectedClipId: String?
    let selectedTrackId: String?
    let playheadTimeUs: Int64?
    let selectedClip: Clip?
    let currentClipAtPlayheadId: String?
    let availableClipIds: [String]
    let orderedClipIdsByTrackId: [String: [String]]

    init(context: IntentCompilerContext) {
        self.timelineId = context.timelineId
        self.selectedClipId = context.selectedClipId
        self.selectedTrackId = context.selectedTrackId
        self.playheadTimeUs = context.playheadTimeUs
        self.selectedClip = context.selectedClip
        self.currentClipAtPlayheadId = Self.currentClipAtPlayheadId(in: context)
        self.availableClipIds = context.clipsById.keys.sorted()
        self.orderedClipIdsByTrackId = context.orderedClipIdsByTrackId
    }

    private static func currentClipAtPlayheadId(in context: IntentCompilerContext) -> String? {
        guard let playheadTimeUs = context.playheadTimeUs else {
            return nil
        }

        if let selectedTrackId = context.selectedTrackId,
           let clipId = clipId(at: playheadTimeUs, trackId: selectedTrackId, context: context) {
            return clipId
        }

        for trackId in context.orderedClipIdsByTrackId.keys.sorted() {
            if let clipId = clipId(at: playheadTimeUs, trackId: trackId, context: context) {
                return clipId
            }
        }

        return nil
    }

    private static func clipId(at timeUs: Int64, trackId: String, context: IntentCompilerContext) -> String? {
        context.orderedClipIdsByTrackId[trackId]?
            .compactMap { context.clipsById[$0] }
            .first { $0.timelineRange.start <= timeUs && timeUs < $0.timelineRange.end }?
            .clipId
    }
}

private extension IntentLLMCompiler {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    func makePrompt(
        prompt: String,
        context: IntentCompilerContext,
        deterministicResult: IntentCompileResult?,
        embeddingCandidates: [IntentEmbeddingCandidate]
    ) throws -> String {
        _ = deterministicResult
        _ = embeddingCandidates
        let contextJson = try jsonString(LLMEditorContext(context: context))

        let llmPrompt = """
        You are the semantic parser stage in a video editor timeline command compiler.
        Your job is to translate one natural-language editing request into a semantic edit plan.
        You are not responsible for timeline math. The app resolves clip IDs, track IDs, microseconds, ranges, validation, and final Actions after you respond.

        Return valid JSON only. Do not explain. Do not wrap JSON in markdown.

        Supported intent types:
        - splitClip: split one clip at a semantic position.
        - removeClip: remove one clip from the timeline.
        - trimClip: shorten a clip by describing an edge and semantic duration.
        - moveClip: reorder one clip within its track.
        - replaceTrackClips: replace all clips in one track with a provided ordered clip list.
        - unknown: the request cannot be represented with the supported timeline actions.

        General rules:
        - Use only the supported intent types.
        - Decompose compound requests joined by "and", "then", "also", commas, or sequential wording.
        - Emit one operation per supported edit clause, in the same order as the user request.
        - Prefer the smallest number of operations that fully satisfies the request.
        - If the request can be represented as splitClip, removeClip, trimClip, moveClip, or replaceTrackClips, do that.
        - Do not invent clip IDs, media IDs, track IDs, timeline times, source ranges, or timeline ranges.
        - sourceText must be the exact phrase for that operation, not the entire prompt unless the prompt has only one operation.
        - If the target is "this clip", "the clip", "selected clip", "current clip", or similar, use {"type":"selectedClip"}.
        - If a later clause refers to "it", "same clip", "that clip", or a previous target, use {"type":"sameAsPrevious"}.
        - If the request refers to "here", "at the playhead", or "current time", use a playhead time expression.
        - If the request refers to "first clip", "second clip", "third clip", or "last clip", use an ordinal clip reference.
        - If required information is missing, return needsClarification = true with a concise clarificationQuestion.
        - Do not create effects, captions, audio edits, color edits, style edits, transitions, or AI-generated media.
        - For requests outside timeline position/range edits, return unknown unless a clarification could resolve them into a supported action.

        Parameter rules:
        - splitClip parameters must include position as a semantic time expression.
        - For "in half", "halfway", or "middle", use {"type":"fractionOfClip","value":0.5,"relativeTo":"postPreviousOperations"}.
        - removeClip usually needs no parameters.
        - trimClip parameters must include edge ("start" or "end") and amount as a semantic duration expression.
        - For explicit durations like "2 seconds", amount must be {"type":"duration","value":2,"unit":"second"}.
        - Duration value must be a number, never an object. Do not convert an explicit duration to vague.
        - moveClip may include placement ("beginning", "start", "first", "end", "last") or orderedClipIds.
        - replaceTrackClips must include orderedClipIds.
        - Do not calculate final microseconds unless the user explicitly gives an absolute timestamp. Even then, return an absoluteTimelineTime expression with value and unit.

        Semantic target references:
        - {"type":"selectedClip"}
        - {"type":"clipId","clipId":"existing-clip-id"}
        - {"type":"sameAsPrevious"}
        - {"type":"ordinal","value":"first | second | third | last","track":{"type":"selectedTrack"}}
        - {"type":"currentClipAtPlayhead"}
        - {"type":"selectedTrack"}
        - {"type":"trackId","trackId":"existing-track-id"}

        Semantic duration expressions:
        - {"type":"duration","value":1,"unit":"microsecond | millisecond | second | minute"}
        - {"type":"percentage","value":50}
        - {"type":"vague","phrase":"a little"}

        Semantic time expressions:
        - {"type":"playhead"}
        - {"type":"absoluteTimelineTime","value":10,"unit":"second"}
        - {"type":"fractionOfClip","value":0.5,"relativeTo":"originalClip | postPreviousOperations"}
        - {"type":"afterStart","amount":{"type":"duration","value":1,"unit":"second"}}
        - {"type":"beforeEnd","amount":{"type":"duration","value":1,"unit":"second"}}

        Editor context:
        \(contextJson)

        Original prompt:
        \(prompt)

        Return this exact JSON shape:
        {
          "operations": [
            {
              "type": "splitClip | removeClip | trimClip | moveClip | replaceTrackClips | unknown",
              "sourceText": "exact phrase from the user prompt",
              "target": {"type": "selectedClip"},
              "confidence": 0.0,
              "parameters": {}
            }
          ],
          "needsClarification": false,
          "clarificationQuestion": null
        }

        Examples:

        User prompt: "Trim the first 2 seconds and split this clip in half"
        {
          "operations": [
            {
              "type": "trimClip",
              "sourceText": "Trim the first 2 seconds",
              "target": {
                "type": "selectedClip"
              },
              "confidence": 0.95,
              "parameters": {
                "edge": "start",
                "amount": {
                  "type": "duration",
                  "value": 2,
                  "unit": "second"
                }
              }
            },
            {
              "type": "splitClip",
              "sourceText": "split this clip in half",
              "target": {
                "type": "sameAsPrevious"
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

        User prompt: "cut this clip in half"
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

        User prompt: "delete the selected clip"
        {
          "operations": [
            {
              "type": "removeClip",
              "sourceText": "delete the selected clip",
              "target": {
                "type": "selectedClip"
              },
              "confidence": 0.9,
              "parameters": {}
            }
          ],
          "needsClarification": false,
          "clarificationQuestion": null
        }

        User prompt: "move this clip to the end"
        {
          "operations": [
            {
              "type": "moveClip",
              "sourceText": "move this clip to the end",
              "target": {
                "type": "selectedClip"
              },
              "confidence": 0.85,
              "parameters": {
                "placement": "end"
              }
            }
          ],
          "needsClarification": false,
          "clarificationQuestion": null
        }

        User prompt: "make it cinematic"
        {
          "operations": [
            {
              "type": "unknown",
              "sourceText": "make it cinematic",
              "target": null,
              "confidence": 0.1,
              "parameters": {}
            }
          ],
          "needsClarification": false,
          "clarificationQuestion": null
        }
        """

        print("[IntentLLM] Editor context provided to LLM:\n\(contextJson)")
        print("[IntentLLM] Full prompt provided to LLM:\n\(llmPrompt)")
        return llmPrompt
    }

    func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func decodePayload(from response: String) throws -> SemanticEditPlan {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = extractJSONObject(from: trimmed) ?? trimmed
        guard let data = jsonText.data(using: .utf8) else {
            throw IntentCompilerError.invalidLLMResponse
        }
        return try decoder.decode(SemanticEditPlan.self, from: data)
    }

    func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }
}
