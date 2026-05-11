import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
struct AppleFoundationIntentLLMProvider: IntentLLMProvider {
    func complete(prompt: String) async throws -> String {
        print("[IntentLLM][AppleFM] Starting completion promptLength=\(prompt.count)")

        guard SystemLanguageModel.default.isAvailable else {
            print("[IntentLLM][AppleFM] System language model unavailable. Enable Apple Intelligence on a supported device.")
            throw IntentCompilerError.llmUnavailable
        }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model) {
            "You convert structured timeline-edit requests into valid JSON."
            "When the user message asks for JSON only, respond with a single JSON object and no markdown code fences or explanation."
        }

        do {
            let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 768)
            let response = try await session.respond(to: prompt, options: options)
            let text = response.content
            print("[IntentLLM][AppleFM] Completed outputLength=\(text.count)")
            return text
        } catch {
            print("[IntentLLM][AppleFM] Generation failed: \(error)")
            throw error
        }
    }
}
#endif
