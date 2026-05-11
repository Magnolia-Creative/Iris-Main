import Foundation
import NaturalLanguage

struct IntentEmbeddingRetriever {
    static let acceptableCandidateThreshold = 0.88
    static let earlyExitThreshold = 0.92

    let embeddingProvider: EmbeddingProvider
    let examplesByType: [IntentEditType: [String]]

    init(
        embeddingProvider: EmbeddingProvider,
        examplesByType: [IntentEditType: [String]] = Self.defaultExamplesByType
    ) {
        self.embeddingProvider = embeddingProvider
        self.examplesByType = examplesByType
    }

    func candidates(for prompt: String, limit: Int = 5) async throws -> [IntentEmbeddingCandidate] {
        let promptEmbedding = try await embeddingProvider.embed(prompt)
        var candidates: [IntentEmbeddingCandidate] = []

        for (type, examples) in examplesByType {
            for example in examples {
                let exampleEmbedding = try await embeddingProvider.embed(example)
                let score = cosineSimilarity(promptEmbedding, exampleEmbedding)
                guard score.isFinite, score >= Self.acceptableCandidateThreshold else { continue }

                candidates.append(
                    IntentEmbeddingCandidate(
                        type: type,
                        example: example,
                        score: score
                    )
                )
            }
        }

        return candidates
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    func compileHighConfidenceCandidate(
        _ candidate: IntentEmbeddingCandidate,
        prompt: String,
        context: IntentCompilerContext
    ) -> IntentCompileResult? {
        guard candidate.score >= Self.earlyExitThreshold else { return nil }

        switch candidate.type {
        case .splitClip:
            return compileSplit(prompt: prompt, context: context, score: candidate.score)
        case .removeClip:
            return compileRemove(prompt: prompt, context: context, score: candidate.score)
        case .trimClip:
            return nil
        case .moveClip:
            return compileMove(prompt: prompt, context: context, score: candidate.score)
        case .replaceTrackClips, .unknown:
            return nil
        }
    }
}

extension IntentEmbeddingRetriever {
    static let defaultExamplesByType: [IntentEditType: [String]] = [
        .splitClip: [
            "split this clip",
            "cut this in half",
            "make two clips from this",
            "divide the clip into two parts"
        ],
        .removeClip: [
            "delete this clip",
            "remove this clip",
            "get rid of this clip",
            "take this clip out"
        ],
        .trimClip: [
            "shorten this clip",
            "cut off the beginning",
            "cut off the end",
            "remove the first few seconds",
            "remove the last few seconds"
        ],
        .moveClip: [
            "move this clip to the beginning",
            "move this clip to the end",
            "put this clip first",
            "put this clip last",
            "reorder this clip"
        ]
    ]
}

private extension IntentEmbeddingRetriever {
    func compileSplit(
        prompt: String,
        context: IntentCompilerContext,
        score: Double
    ) -> IntentCompileResult? {
        let normalized = IntentPromptNormalizer.normalize(prompt)
        guard normalized.contains("two")
            || normalized.contains("half")
            || normalized.contains("divide")
            || normalized.contains("split")
            || normalized.contains("cut") else {
            return nil
        }

        guard let clip = context.selectedClip else {
            return IntentCompileResult(
                actions: [],
                confidence: score,
                source: .embedding,
                unresolvedText: prompt,
                warnings: [.missingSelectedClip],
                needsClarification: true
            )
        }

        let midpoint = clip.timelineRange.start + (clip.timelineRange.duration / 2)
        return IntentCompileResult(
            actions: [
                Action.splitClip(timelineId: context.timelineId, clipId: clip.clipId, atTimeUs: midpoint)
            ],
            confidence: score,
            source: .embedding,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )
    }

    func compileRemove(
        prompt: String,
        context: IntentCompilerContext,
        score: Double
    ) -> IntentCompileResult? {
        let normalized = IntentPromptNormalizer.normalize(prompt)
        guard normalized.contains("delete")
            || normalized.contains("remove")
            || normalized.contains("rid")
            || normalized.contains("take") else {
            return nil
        }

        guard let clip = context.selectedClip else {
            return IntentCompileResult(
                actions: [],
                confidence: score,
                source: .embedding,
                unresolvedText: prompt,
                warnings: [.missingSelectedClip],
                needsClarification: true
            )
        }

        return IntentCompileResult(
            actions: [
                Action.removeClip(timelineId: context.timelineId, clipId: clip.clipId)
            ],
            confidence: score,
            source: .embedding,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )
    }

    func compileMove(
        prompt: String,
        context: IntentCompilerContext,
        score: Double
    ) -> IntentCompileResult? {
        let normalized = IntentPromptNormalizer.normalize(prompt)
        let movesToBeginning = normalized.contains("beginning") || normalized.contains("start") || normalized.contains("first")
        let movesToEnd = normalized.contains("end") || normalized.contains("last")
        guard movesToBeginning || movesToEnd else { return nil }

        guard let clip = context.selectedClip else {
            return IntentCompileResult(
                actions: [],
                confidence: score,
                source: .embedding,
                unresolvedText: prompt,
                warnings: [.missingSelectedClip],
                needsClarification: true
            )
        }

        let originalOrder = context.orderedClipIds(for: clip)
        guard originalOrder.contains(clip.clipId), !originalOrder.isEmpty else {
            return IntentCompileResult(
                actions: [],
                confidence: score,
                source: .embedding,
                unresolvedText: prompt,
                warnings: [.invalidMoveOrder],
                needsClarification: true
            )
        }

        var newOrder = originalOrder.filter { $0 != clip.clipId }
        if movesToBeginning {
            newOrder.insert(clip.clipId, at: 0)
        } else {
            newOrder.append(clip.clipId)
        }

        return IntentCompileResult(
            actions: [
                Action.moveClip(timelineId: context.timelineId, clipId: clip.clipId, orderedClipIds: newOrder)
            ],
            confidence: score,
            source: .embedding,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )
    }
}

struct MobileCLIPTextEmbeddingProvider: EmbeddingProvider {
    let service: any MobileCLIPEmbeddingProviding

    init(service: any MobileCLIPEmbeddingProviding = MobileCLIPEmbeddingPool.shared) {
        self.service = service
    }

    func embed(_ text: String) async throws -> [Float] {
        try await service.textEmbedding(for: text)
    }
}

protocol IntentTextEmbeddingProvider {
    func embedding(for text: String) async throws -> [Float]
}

final class IntentEffectCapabilityRetriever {
    static let defaultScoreThreshold = 0.52

    private let embeddingProvider: any IntentTextEmbeddingProvider
    private let capabilities: [EffectCapability]
    private let scoreThreshold: Double
    private var cachedCapabilityVectors: [String: [Float]] = [:]

    init(
        embeddingProvider: any IntentTextEmbeddingProvider = NLContextualEffectEmbeddingProvider(),
        capabilities: [EffectCapability] = IntentEffectCapabilityCatalog.defaultCapabilities,
        scoreThreshold: Double = IntentEffectCapabilityRetriever.defaultScoreThreshold
    ) {
        self.embeddingProvider = embeddingProvider
        self.capabilities = capabilities
        self.scoreThreshold = scoreThreshold
    }

    func relevantCapabilities(
        for request: SemanticEffectRequest,
        limit: Int = 5
    ) async throws -> [RelevantEffectCapability] {
        let queryText = ([request.intent, request.sourceText] + request.attributes)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .joined(separator: ". ")
        let queryVector = try await embeddingProvider.embedding(for: queryText)
        guard queryVector.isEmpty == false else { return [] }

        var matches: [RelevantEffectCapability] = []
        for capability in capabilities {
            let capabilityVector = try await vector(for: capability)
            let score = IntentVectorMath.cosineSimilarity(queryVector, capabilityVector)
            print("[IntentEffectRetriever] capability=\(capability.operation) score=\(score) request='\(request.intent)'")
            guard score.isFinite, score >= scoreThreshold else { continue }
            matches.append(RelevantEffectCapability(capability: capability, score: score))
        }

        return matches
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private func vector(for capability: EffectCapability) async throws -> [Float] {
        if let cached = cachedCapabilityVectors[capability.operation] {
            return cached
        }

        let text = ([capability.operation, capability.description, capability.retrievalText] + capability.examples)
            .joined(separator: ". ")
        let vector = try await embeddingProvider.embedding(for: text)
        cachedCapabilityVectors[capability.operation] = vector
        return vector
    }
}

final class NLContextualEffectEmbeddingProvider: IntentTextEmbeddingProvider {
    private let language: NLLanguage
    private let model: NLContextualEmbedding?
    private var loadTask: Task<Void, Error>?

    init(language: NLLanguage = .english) {
        self.language = language
        self.model = NLContextualEmbedding(language: language)
    }

    func embedding(for text: String) async throws -> [Float] {
        try await ensureModelLoaded()
        guard let model else { throw IntentCompilerError.embeddingUnavailable }

        let result = try model.embeddingResult(for: text, language: language)
        var pooled = Array<Float>(repeating: 0, count: model.dimension)
        var tokenCount = 0

        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for index in 0..<min(pooled.count, vector.count) {
                pooled[index] += Float(vector[index])
            }
            tokenCount += 1
            return true
        }

        guard tokenCount > 0 else { return [] }
        let divisor = Float(tokenCount)
        return IntentVectorMath.normalized(pooled.map { $0 / divisor })
    }

    private func ensureModelLoaded() async throws {
        if let loadTask {
            return try await loadTask.value
        }

        let task = Task { [model] in
            guard let model else { throw IntentCompilerError.embeddingUnavailable }
            if model.hasAvailableAssets {
                try model.load()
                return
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                model.requestAssets { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard result == .available else {
                        continuation.resume(throwing: IntentCompilerError.embeddingUnavailable)
                        return
                    }

                    do {
                        try model.load()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        loadTask = task
        try await task.value
    }
}

enum IntentEffectCapabilityCatalog {
    static let defaultCapabilities: [EffectCapability] = [
        EffectCapability(
            operation: "addGrain",
            description: "Adds film grain or analog noise texture to a clip.",
            parameters: [
                EffectCapabilityParameter(
                    name: "amount",
                    valueType: "number",
                    minimum: 0,
                    maximum: 1,
                    description: "Visible grain intensity."
                )
            ],
            retrievalText: "film grain noise analog texture gritty vintage old camera VHS cinematic texture organic imperfections",
            examples: ["make it grainy", "add old film texture", "make it feel vintage", "give it analog noise"]
        ),
        EffectCapability(
            operation: "setTemperature",
            description: "Adjusts color warmth or coolness.",
            parameters: [
                EffectCapabilityParameter(
                    name: "value",
                    valueType: "number",
                    minimum: -1,
                    maximum: 1,
                    description: "Negative values cool the clip, positive values warm it."
                )
            ],
            retrievalText: "warm cool temperature golden orange blue cold sunset vintage warmth film color cast",
            examples: ["make it warmer", "give it a cool blue feel", "make it feel vintage", "add golden warmth"]
        ),
        EffectCapability(
            operation: "setSaturation",
            description: "Adjusts color intensity.",
            parameters: [
                EffectCapabilityParameter(
                    name: "value",
                    valueType: "number",
                    minimum: -1,
                    maximum: 1,
                    description: "Negative values desaturate, positive values intensify color."
                )
            ],
            retrievalText: "saturation color intensity desaturated faded muted vibrant rich washed out vintage",
            examples: ["make it faded", "make colors pop", "desaturate the clip", "make it look washed out"]
        ),
        EffectCapability(
            operation: "setContrast",
            description: "Adjusts separation between bright and dark tones.",
            parameters: [
                EffectCapabilityParameter(
                    name: "value",
                    valueType: "number",
                    minimum: -1,
                    maximum: 1,
                    description: "Negative values flatten contrast, positive values increase contrast."
                )
            ],
            retrievalText: "contrast punchy flat soft dramatic faded film shadows highlights moody cinematic",
            examples: ["make it more dramatic", "soften the contrast", "make it cinematic", "make it less harsh"]
        ),
        EffectCapability(
            operation: "setExposure",
            description: "Adjusts overall brightness.",
            parameters: [
                EffectCapabilityParameter(
                    name: "value",
                    valueType: "number",
                    minimum: -1,
                    maximum: 1,
                    description: "Negative values darken, positive values brighten."
                )
            ],
            retrievalText: "exposure brightness bright dark moody dim airy overexposed underexposed light",
            examples: ["make it brighter", "darken the clip", "make it moodier", "make it airy"]
        ),
        EffectCapability(
            operation: "setHighlights",
            description: "Adjusts bright image regions.",
            parameters: [
                EffectCapabilityParameter(
                    name: "value",
                    valueType: "number",
                    minimum: -1,
                    maximum: 1,
                    description: "Negative values recover highlights, positive values lift them."
                )
            ],
            retrievalText: "highlights bright areas glow blown out soft light faded film vintage",
            examples: ["soften the highlights", "make bright areas glow", "recover blown highlights"]
        ),
        EffectCapability(
            operation: "setShadows",
            description: "Adjusts dark image regions.",
            parameters: [
                EffectCapabilityParameter(
                    name: "value",
                    valueType: "number",
                    minimum: -1,
                    maximum: 1,
                    description: "Negative values deepen shadows, positive values lift them."
                )
            ],
            retrievalText: "shadows dark areas black levels lifted faded matte moody crushed vintage film",
            examples: ["lift the shadows", "make blacks look faded", "make it moodier", "crush the shadows"]
        )
    ]
}

enum IntentVectorMath {
    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }

        var dot = Float(0)
        var lhsMagnitude = Float(0)
        var rhsMagnitude = Float(0)

        for index in 0..<count {
            dot += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }

        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
        return Double(dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude)))
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}
