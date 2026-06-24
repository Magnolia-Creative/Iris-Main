import Foundation
import NaturalLanguage

protocol EditorUITextEmbeddingProvider {
    func embedding(for text: String) async throws -> [Float]
}

enum UIEmbeddingResolverWarning: String, Codable, Equatable {
    case providerUnavailable
    case noExamplesAvailable
}

struct UIEmbeddingExample: Equatable {
    let id: String
    let text: String
    let source: UIIntentCandidateSource
    let operation: UIIntentOperation
    let target: UIIntentTarget
    let requestedSize: EditorComponentSize?
    let assumptions: [String]
}

struct UIEmbeddingResolution {
    let candidates: [EditorUIIntentCandidate]
    let warnings: [UIEmbeddingResolverWarning]
}

actor UIEmbeddingResolver {
    private let provider: any EditorUITextEmbeddingProvider
    private let examples: [UIEmbeddingExample]
    private let minimumScore: Double
    private var cachedExampleVectors: [String: [Float]] = [:]

    init(
        provider: any EditorUITextEmbeddingProvider = NLContextualUIEmbeddingProvider(),
        examples: [UIEmbeddingExample] = Self.defaultExamples,
        minimumScore: Double = 0.52
    ) {
        self.provider = provider
        self.examples = examples
        self.minimumScore = minimumScore
    }

    func candidates(for prompt: NormalizedEditorUIPrompt) async -> UIEmbeddingResolution {
        guard !examples.isEmpty else {
            return UIEmbeddingResolution(candidates: [], warnings: [.noExamplesAvailable])
        }

        do {
            let promptVector = try await provider.embedding(for: prompt.normalizedText)
            guard !promptVector.isEmpty else {
                return UIEmbeddingResolution(candidates: [], warnings: [.providerUnavailable])
            }

            var candidates: [EditorUIIntentCandidate] = []
            for example in examples {
                let exampleVector = try await vector(for: example)
                let score = IntentVectorMath.cosineSimilarity(promptVector, exampleVector)
                guard score.isFinite, score >= minimumScore else { continue }
                candidates.append(candidate(from: example, score: score))
            }

            return UIEmbeddingResolution(
                candidates: candidates.sorted { ($0.embeddingScore ?? 0) > ($1.embeddingScore ?? 0) },
                warnings: []
            )
        } catch {
            return UIEmbeddingResolution(candidates: [], warnings: [.providerUnavailable])
        }
    }

    private func vector(for example: UIEmbeddingExample) async throws -> [Float] {
        if let cached = cachedExampleVectors[example.id] {
            return cached
        }
        let vector = try await provider.embedding(for: example.text)
        cachedExampleVectors[example.id] = vector
        return vector
    }

    private func candidate(from example: UIEmbeddingExample, score: Double) -> EditorUIIntentCandidate {
        EditorUIIntentCandidate(
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

extension UIEmbeddingResolver {
    static let defaultExamples: [UIEmbeddingExample] = [
        UIEmbeddingExample(
            id: "timeline-focus-edit-clips",
            text: "give me more room to edit clips",
            source: .embedding,
            operation: .applyWorkspace,
            target: .workspaceRecipe(EditorJITRecipeCatalog.timelineFocus.id),
            requestedSize: nil,
            assumptions: ["Mapped clip-editing workspace language to the timeline focus recipe."]
        ),
        UIEmbeddingExample(
            id: "timeline-focus-tracks",
            text: "make the tracks easier to edit",
            source: .embedding,
            operation: .expand,
            target: .component("timeline.full"),
            requestedSize: .expanded,
            assumptions: ["Mapped track-editing language to the timeline component."]
        ),
        UIEmbeddingExample(
            id: "preview-focus-video",
            text: "focus on the video preview",
            source: .embedding,
            operation: .applyWorkspace,
            target: .workspaceRecipe(EditorJITRecipeCatalog.previewFocus.id),
            requestedSize: nil,
            assumptions: ["Mapped video focus language to the preview focus recipe."]
        ),
        UIEmbeddingExample(
            id: "clean-workspace",
            text: "use a cleaner workspace with fewer controls",
            source: .embedding,
            operation: .applyWorkspace,
            target: .workspaceRecipe(EditorJITRecipeCatalog.lessCluttered.id),
            requestedSize: nil,
            assumptions: ["Mapped reduced-clutter language to the less cluttered recipe."]
        ),
        UIEmbeddingExample(
            id: "controls-hide",
            text: "hide the inspector and parameter controls",
            source: .embedding,
            operation: .hide,
            target: .chromeControls,
            requestedSize: nil,
            assumptions: ["Mapped controls language to bottom chrome controls."]
        ),
        UIEmbeddingExample(
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

final class NLContextualUIEmbeddingProvider: EditorUITextEmbeddingProvider {
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
