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
    let selectedClipId: String?
    let selectedTrackId: String?
    let playheadTimeUs: Int64?
    let currentClipAtPlayheadId: String?
    let orderedClipIdsByTrackId: [String: [String]]

    init(context: IntentCompilerContext) {
        self.selectedClipId = context.selectedClipId
        self.selectedTrackId = context.selectedTrackId
        self.playheadTimeUs = context.playheadTimeUs
        self.currentClipAtPlayheadId = Self.currentClipAtPlayheadId(in: context)
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
        encoder.outputFormatting = [.sortedKeys]
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
        Return JSON only. Parse one video timeline edit request into:
        {"operations":[{"type":"splitClip|removeClip|trimClip|moveClip|replaceTrackClips|unknown","sourceText":"exact user clause","target":null,"confidence":0.0,"parameters":{}}],"needsClarification":false,"clarificationQuestion":null}

        Ops: splitClip, removeClip, trimClip, moveClip, replaceTrackClips, unknown.
        Rules: split compound requests into ordered operations. Use fewest ops. Use only IDs in ctx. Never invent IDs/ranges/microseconds. sourceText is the exact clause. If missing required info, set needsClarification true and ask a short clarificationQuestion. Effects/captions/audio/color/style/transitions/generative media => unknown.
        Targets: this/selected/current clip => {"type":"selectedClip"}; it/same/that after prior op => {"type":"sameAsPrevious"}; first/second/third/last clip => {"type":"ordinal","value":"first|second|third|last","track":{"type":"selectedTrack"}}; clip under playhead => {"type":"currentClipAtPlayhead"}; track => {"type":"selectedTrack"} or {"type":"trackId","trackId":"id"}; known clip => {"type":"clipId","clipId":"id"}.
        Params: splitClip needs position. "in half"/middle => {"type":"fractionOfClip","value":0.5,"relativeTo":"postPreviousOperations"}. trimClip needs edge start|end and amount. Durations => {"type":"duration","value":2,"unit":"microsecond|millisecond|second|minute"}. Percent => {"type":"percentage","value":50}. Vague => {"type":"vague","phrase":"a little"}. moveClip can use placement beginning|start|first|end|last or orderedClipIds. replaceTrackClips needs orderedClipIds. Here/playhead/current time => {"type":"playhead"}. Absolute times => {"type":"absoluteTimelineTime","value":10,"unit":"second"}. Relative split/trim times may use afterStart/beforeEnd with amount.
        ctx=\(contextJson)
        user=\(prompt)
        """

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
