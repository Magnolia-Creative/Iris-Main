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
            print("[IntentLLM] Building fallback prompt originalPrompt='\(prompt)' embeddingCandidateCount=\(embeddingCandidates.count)")
            let llmPrompt = try makePrompt(
                prompt: prompt,
                context: context,
                deterministicResult: deterministicResult,
                embeddingCandidates: embeddingCandidates
            )
            print("[IntentLLM] Sending fallback prompt length=\(llmPrompt.count)")
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
            print("[IntentLLM] Fallback failed with error: \(error)")
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
        let contextJson = try jsonString(context)
        let deterministicJson = try jsonString(deterministicResult)
        let embeddingJson = try jsonString(embeddingCandidates)

        let llmPrompt = """
        You are the semantic parser stage in a video editor timeline command compiler.
        Your job is to translate one natural-language editing request into a semantic edit plan.
        You are not responsible for timeline math. The app will resolve clip IDs, track IDs, microseconds, ranges, validation, and final Actions after you respond.

        Return valid JSON only. Do not explain. Do not wrap JSON in markdown.

        How to use the inputs:
        - Editor context: the current timeline state. Use it only to choose semantic references like selectedClip, selectedTrack, currentClipAtPlayhead, or ordinal.
        - Original prompt: the user's exact request. Preserve the relevant phrase in sourceText.
        - Deterministic results: an earlier compiler stage's best attempt. Use it as a hint, but correct it if the original prompt and editor context show a better interpretation.
        - Embedding candidates: semantically similar supported intents. Use them as hints for intent type only; do not copy parameters unless they are supported by the editor context.

        Supported intent types:
        - splitClip: split one clip at a semantic position.
        - removeClip: remove one clip from the timeline.
        - trimClip: shorten a clip by describing an edge and semantic duration.
        - moveClip: reorder one clip within its track.
        - replaceTrackClips: replace all clips in one track with a provided ordered clip list.
        - unknown: the request cannot be represented with the supported timeline actions.

        General rules:
        - Use only the supported intent types.
        - Prefer the smallest number of intents that fully satisfy the request.
        - If the request can be represented as splitClip, removeClip, trimClip, moveClip, or replaceTrackClips, do that.
        - Do not invent clip IDs, media IDs, track IDs, timeline times, source ranges, or timeline ranges.
        - If the target is "this clip", "the clip", "selected clip", "current clip", or similar, use {"type":"selectedClip"}.
        - If the request refers to "it", "same clip", or a previous target, use {"type":"sameAsPrevious"}.
        - If the request refers to "here", "at the playhead", or "current time", use a playhead time expression.
        - If the request refers to "first clip", "second clip", "third clip", or "last clip", use an ordinal clip reference.
        - If required information is missing, return needsClarification = true with a concise clarificationQuestion.
        - Do not create effects, captions, audio edits, color edits, style edits, transitions, or AI-generated media.
        - For requests outside timeline position/range edits, return unknown unless a clarification could resolve them into a supported action.

        Parameter rules:
        - splitClip parameters must include position as a semantic time expression.
        - removeClip usually needs no parameters.
        - trimClip parameters must include edge ("start" or "end") and amount as a semantic duration expression.
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

        Deterministic results:
        \(deterministicJson)

        Embedding candidates:
        \(embeddingJson)

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
