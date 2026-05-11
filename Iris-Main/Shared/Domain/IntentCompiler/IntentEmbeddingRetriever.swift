import Foundation

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
