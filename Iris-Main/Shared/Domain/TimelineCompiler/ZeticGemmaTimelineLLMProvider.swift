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
        print("[TimelineLLM][Zetic] Starting completion model=\(modelName) version=\(version) promptLength=\(prompt.count)")

        guard let personalKey, personalKey.isEmpty == false else {
            print("[TimelineLLM][Zetic] Personal key missing. Set ZETIC_PERSONAL_KEY in Info.plist/build settings or environment.")
            throw TimelineCompilerError.llmUnavailable
        }
        print("[TimelineLLM][Zetic] Personal key found length=\(personalKey.count)")

        #if canImport(ZeticMLange)
        print("[TimelineLLM][Zetic] ZeticMLange module is available. Initializing model.")
        let model: ZeticMLangeLLMModel
        do {
            model = try ZeticMLangeLLMModel(
                personalKey: personalKey,
                name: modelName,
                version: version,
                modelMode: LLMModelMode.RUN_AUTO,
                onDownload: { progress in
                    print("[TimelineLLM][Zetic] Model download progress=\(progress)")
                }
            )
            print("[TimelineLLM][Zetic] Model initialized.")
        } catch {
            print("[TimelineLLM][Zetic] Model initialization failed: \(error)")
            throw error
        }

        do {
            _ = try model.run(prompt)
            print("[TimelineLLM][Zetic] Generation started.")
        } catch {
            print("[TimelineLLM][Zetic] model.run failed: \(error)")
            throw error
        }

        var buffer = ""
        var tokenCount = 0
        while true {
            let waitResult = model.waitForNextToken()
            let token = waitResult.token
            let generatedTokens = waitResult.generatedTokens

            if generatedTokens == 0 {
                print("[TimelineLLM][Zetic] Generation completed tokenCount=\(tokenCount) outputLength=\(buffer.count)")
                break
            }

            buffer.append(token)
            tokenCount += generatedTokens
        }

        return buffer
        #else
        print("[TimelineLLM][Zetic] ZeticMLange module is unavailable at compile time. Ensure the ZeticMLange product is linked to the Iris-Main target.")
        throw TimelineCompilerError.llmUnavailable
        #endif
    }
}
