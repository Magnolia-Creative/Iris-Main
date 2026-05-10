import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
struct AppleFoundationTimelineLLMProvider: TimelineLLMProvider {
    func complete(prompt: String) async throws -> String {
        print("[TimelineLLM][AppleFM] Starting completion promptLength=\(prompt.count)")

        guard SystemLanguageModel.default.isAvailable else {
            print("[TimelineLLM][AppleFM] System language model unavailable. Enable Apple Intelligence on a supported device.")
            throw TimelineCompilerError.llmUnavailable
        }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model) {
            "You convert structured timeline-edit requests into valid JSON."
            "When the user message asks for JSON only, respond with a single JSON object and no markdown code fences or explanation."
        }

        do {
            let response = try await session.respond(to: prompt)
            let text = response.content
            print("[TimelineLLM][AppleFM] Completed outputLength=\(text.count)")
            return text
        } catch {
            print("[TimelineLLM][AppleFM] Generation failed: \(error)")
            throw error
        }
    }
}
#endif
