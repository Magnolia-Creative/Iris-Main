import Foundation
import NaturalLanguage

protocol EditorUITextEmbeddingProvider {
    func embedding(for text: String) async throws -> [Float]
}

enum EditorIntentEmbeddingResolverWarning: String, Codable, Equatable {
    case providerUnavailable
    case noExamplesAvailable
}

struct EditorIntentEmbeddingExample: Equatable {
    let id: String
    let text: String
    let source: EditorIntentCandidateSource
    let operation: EditorIntentOperation
    let target: EditorIntentTarget
    let requestedSize: EditorComponentSize?
    let assumptions: [String]
}

struct EditorIntentEmbeddingResolution {
    let candidates: [EditorIntentCandidate]
    let warnings: [EditorIntentEmbeddingResolverWarning]
}

actor EditorIntentEmbeddingResolver {
    private let provider: any EditorUITextEmbeddingProvider
    private let examples: [EditorIntentEmbeddingExample]
    private let minimumScore: Double
    private var cachedExampleVectors: [String: [Float]] = [:]

    init(
        provider: (any EditorUITextEmbeddingProvider)? = nil,
        examples: [EditorIntentEmbeddingExample]? = nil,
        minimumScore: Double = 0.52
    ) {
        self.provider = provider ?? NLContextualEditorIntentEmbeddingProvider()
        self.examples = examples ?? EditorIntentEmbeddingResolver.defaultExamples
        self.minimumScore = minimumScore
    }

    func candidates(for prompt: NormalizedEditorIntentPrompt) async -> EditorIntentEmbeddingResolution {
        guard !examples.isEmpty else {
            return EditorIntentEmbeddingResolution(candidates: [], warnings: [.noExamplesAvailable])
        }

        do {
            let promptVector = try await provider.embedding(for: prompt.normalizedText)
            guard !promptVector.isEmpty else {
                return EditorIntentEmbeddingResolution(candidates: [], warnings: [.providerUnavailable])
            }

            var candidates: [EditorIntentCandidate] = []
            for example in examples {
                let exampleVector = try await vector(for: example)
                let score = IntentVectorMath.cosineSimilarity(promptVector, exampleVector)
                guard score.isFinite, score >= minimumScore else { continue }
                candidates.append(candidate(from: example, score: score))
            }

            return EditorIntentEmbeddingResolution(
                candidates: candidates.sorted { ($0.embeddingScore ?? 0) > ($1.embeddingScore ?? 0) },
                warnings: []
            )
        } catch {
            return EditorIntentEmbeddingResolution(candidates: [], warnings: [.providerUnavailable])
        }
    }

    private func vector(for example: EditorIntentEmbeddingExample) async throws -> [Float] {
        if let cached = cachedExampleVectors[example.id] {
            return cached
        }
        let vector = try await provider.embedding(for: example.text)
        cachedExampleVectors[example.id] = vector
        return vector
    }

    private func candidate(from example: EditorIntentEmbeddingExample, score: Double) -> EditorIntentCandidate {
        EditorIntentCandidate(
            id: "embedding.\(example.id)",
            source: example.source,
            operation: example.operation,
            target: example.target,
            requestedSize: example.requestedSize,
            matchedTerms: [example.text],
            explicitTargetMatch: false,
            explicitStateMatch: false,
            contextMatchScore: 0,
            lexicalScore: 0,
            embeddingScore: score,
            ruleId: "embedding.semantic-example",
            assumptions: example.assumptions
        )
    }
}

extension EditorIntentEmbeddingResolver {
    static let defaultExamples: [EditorIntentEmbeddingExample] = [
        EditorIntentEmbeddingExample(
            id: "timeline-focus-edit-clips",
            text: "give me more room to edit clips",
            source: .embedding,
            operation: .applyWorkspace,
            target: .workspaceRecipe(EditorJITRecipeCatalog.timelineFocus.id),
            requestedSize: nil,
            assumptions: ["Mapped clip-editing workspace language to the timeline focus recipe."]
        ),
        EditorIntentEmbeddingExample(
            id: "timeline-focus-tracks",
            text: "make the tracks easier to edit",
            source: .embedding,
            operation: .expand,
            target: .component("timeline.full"),
            requestedSize: .expanded,
            assumptions: ["Mapped track-editing language to the timeline component."]
        ),
        EditorIntentEmbeddingExample(
            id: "preview-focus-video",
            text: "focus on the video preview",
            source: .embedding,
            operation: .applyWorkspace,
            target: .workspaceRecipe(EditorJITRecipeCatalog.previewFocus.id),
            requestedSize: nil,
            assumptions: ["Mapped video focus language to the preview focus recipe."]
        ),
        EditorIntentEmbeddingExample(
            id: "clean-workspace",
            text: "use a cleaner workspace with fewer controls",
            source: .embedding,
            operation: .applyWorkspace,
            target: .workspaceRecipe(EditorJITRecipeCatalog.lessCluttered.id),
            requestedSize: nil,
            assumptions: ["Mapped reduced-clutter language to the less cluttered recipe."]
        ),
        EditorIntentEmbeddingExample(
            id: "controls-hide",
            text: "hide the inspector and parameter controls",
            source: .embedding,
            operation: .hide,
            target: .chromeControls,
            requestedSize: nil,
            assumptions: ["Mapped controls language to bottom chrome controls."]
        ),
        EditorIntentEmbeddingExample(
            id: "controls-show",
            text: "show the inspector controls",
            source: .embedding,
            operation: .show,
            target: .chromeControls,
            requestedSize: .standard,
            assumptions: ["Mapped controls language to bottom chrome controls."]
        )
    ]
}

final class NLContextualEditorIntentEmbeddingProvider: EditorUITextEmbeddingProvider {
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
