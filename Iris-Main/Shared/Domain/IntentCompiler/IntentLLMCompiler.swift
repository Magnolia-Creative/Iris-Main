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
    let currentClip: LLMCurrentClipContext?
    let orderedClipIdsByTrackId: [String: [String]]

    init(context: IntentCompilerContext) {
        let currentClipAtPlayheadId = Self.currentClipAtPlayheadId(in: context)

        self.selectedClipId = context.selectedClipId
        self.selectedTrackId = context.selectedTrackId
        self.playheadTimeUs = context.playheadTimeUs
        self.currentClipAtPlayheadId = currentClipAtPlayheadId
        self.currentClip = (context.selectedClip ?? context.clip(withId: currentClipAtPlayheadId))
            .map(LLMCurrentClipContext.init)
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

private struct LLMCurrentClipContext: Codable {
    let clipId: String
    let durationUs: Int64
    let trackId: String

    init(clip: Clip) {
        self.clipId = clip.clipId
        self.durationUs = clip.timelineRange.duration
        self.trackId = clip.trackId
    }
}

private extension IntentLLMCompiler {
    static let actionStructureContextByType: [IntentEditType: String] = [
        .splitClip: """
        {"type":"splitClip","sourceText":"exact user clause","target":{"type":"selectedClip|clipId|sameAsPrevious|ordinal|currentClipAtPlayhead","clipId":"optional existing clip id","value":"optional ordinal","track":{"type":"selectedTrack|trackId","trackId":"optional existing track id"}},"confidence":0.0,"parameters":{"position":{"type":"playhead|absoluteTimelineTime|fractionOfClip|afterStart|beforeEnd","value":0.5,"unit":"second|minute|millisecond|microsecond","relativeTo":"postPreviousOperations|originalClip","amount":{"type":"duration|percentage|vague","value":1,"unit":"second","phrase":"optional vague phrase"}}}}
        """,
        .removeClip: """
        {"type":"removeClip","sourceText":"exact user clause","target":{"type":"selectedClip|clipId|sameAsPrevious|ordinal|currentClipAtPlayhead","clipId":"optional existing clip id","value":"optional ordinal","track":{"type":"selectedTrack|trackId","trackId":"optional existing track id"}},"confidence":0.0,"parameters":{}}
        """,
        .trimClip: """
        {"type":"trimClip","sourceText":"exact user clause","target":{"type":"selectedClip|clipId|sameAsPrevious|ordinal|currentClipAtPlayhead","clipId":"optional existing clip id","value":"optional ordinal","track":{"type":"selectedTrack|trackId","trackId":"optional existing track id"}},"confidence":0.0,"parameters":{"edge":"start|end","amount":{"type":"duration|percentage|vague","value":1,"unit":"second|minute|millisecond|microsecond","phrase":"optional vague phrase"}}}
        """,
        .moveClip: """
        {"type":"moveClip","sourceText":"exact user clause","target":{"type":"selectedClip|clipId|sameAsPrevious|ordinal|currentClipAtPlayhead","clipId":"optional existing clip id","value":"optional ordinal","track":{"type":"selectedTrack|trackId","trackId":"optional existing track id"}},"confidence":0.0,"parameters":{"placement":"beginning|start|first|end|last","orderedClipIds":["existing clip ids in final order"]}}
        """,
        .replaceTrackClips: """
        {"type":"replaceTrackClips","sourceText":"exact user clause","target":{"type":"selectedTrack|trackId","trackId":"optional existing track id"},"confidence":0.0,"parameters":{"orderedClipIds":["existing clip ids in final order"]}}
        """,
        .unknown: """
        {"type":"unknown","sourceText":"exact user clause","target":null,"confidence":0.0,"parameters":{}}
        """
    ]

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
        let actionStructureContext = Self.actionStructureContext()

        let llmPrompt = """
        Return JSON only. Parse one video timeline edit request into:
        {"operations":[{"type":"splitClip|removeClip|trimClip|moveClip|replaceTrackClips|unknown","sourceText":"exact user clause","target":null,"confidence":0.0,"parameters":{}}],"needsClarification":false,"clarificationQuestion":null}

        Ops: splitClip, removeClip, trimClip, moveClip, replaceTrackClips, unknown.
        Rules: first derive the ordered operation types. Before writing each operation, retrieve that type's JSON object structure from Action structure context and follow it exactly. If multiple operation types are derived, use each matching structure. every op must include type, sourceText, target, confidence, parameters. target must be null or an object; never use a plain string target. Never output placeholders. split compound requests into ordered operations. Use fewest ops. Use only IDs in ctx. Never invent IDs/ranges/microseconds. sourceText is copied from the user clause. If missing required info, set needsClarification true and ask a short clarificationQuestion. Effects/captions/audio/color/style/transitions/generative media => unknown.
        Targets: this/selected/current/the clip => {"type":"selectedClip"}; it/same/that after prior op => {"type":"sameAsPrevious"}; first/second/third/last clip => {"type":"ordinal","value":"first|second|third|last","track":{"type":"selectedTrack"}}; first/last N seconds are trim edges, not ordinal clip targets. clip under playhead => {"type":"currentClipAtPlayhead"}; track => {"type":"selectedTrack"} or {"type":"trackId","trackId":"id"}; known clip => {"type":"clipId","clipId":"id"}.
        Params: splitClip needs {"position":time}. "in half"/middle => {"type":"fractionOfClip","value":0.5,"relativeTo":"postPreviousOperations"}. trimClip parameters are exactly {"edge":"start|end","amount":duration}; never edgeStart/edgeEnd. Preserve explicit duration units: "2 seconds" => {"type":"duration","value":2,"unit":"second"}, not microsecond. Percent => {"type":"percentage","value":50}. Vague => {"type":"vague","phrase":"a little"}. moveClip can use placement beginning|start|first|end|last or orderedClipIds. replaceTrackClips needs orderedClipIds. Here/playhead/current time => {"type":"playhead"}. Absolute times => {"type":"absoluteTimelineTime","value":10,"unit":"second"}. Relative split/trim times may use afterStart/beforeEnd with amount.
        Action structure context:
        \(actionStructureContext)
        ctx=\(contextJson)
        user=\(prompt)
        """

        return llmPrompt
    }

    static func actionStructureContext() -> String {
        IntentEditType.allCases
            .compactMap { type in
                actionStructureContextByType[type].map { "\(type.rawValue): \($0)" }
            }
            .joined(separator: "\n")
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
