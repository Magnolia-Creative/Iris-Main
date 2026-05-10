import Foundation

#if canImport(ZeticMLange)
import ZeticMLange
#endif

struct ZeticGemmaTimelineLLMProvider: TimelineLLMProvider {
    let personalKey: String?
    let modelName: String
    let version: Int

    init(
        personalKey: String? = AppConfiguration.zeticPersonalKey,
        modelName: String = "changgeun/gemma-4-E2B-it",
        version: Int = 1
    ) {
        self.personalKey = personalKey
        self.modelName = modelName
        self.version = version
    }

    func complete(prompt: String) async throws -> String {
        guard let personalKey, personalKey.isEmpty == false else {
            throw TimelineCompilerError.llmUnavailable
        }

        #if canImport(ZeticMLange)
        let model = try ZeticMLangeLLMModel(
            personalKey: personalKey,
            name: modelName,
            version: version,
            modelMode: LLMModelMode.RUN_AUTO,
            onDownload: nil
        )
        _ = try model.run(prompt)

        var buffer = ""
        while true {
            let waitResult = model.waitForNextToken()
            let token = waitResult.token
            let generatedTokens = waitResult.generatedTokens

            if generatedTokens == 0 {
                break
            }

            buffer.append(token)
        }

        return buffer
        #else
        throw TimelineCompilerError.llmUnavailable
        #endif
    }
}
