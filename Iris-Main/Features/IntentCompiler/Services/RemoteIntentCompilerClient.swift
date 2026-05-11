import Foundation

final class RemoteIntentCompilerClient {
    typealias StatusHandler = @MainActor (String) -> Void

    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        urlSession: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.urlSession = urlSession
        self.encoder = encoder
        self.decoder = decoder
    }

    func compilePrompt(
        prompt: String,
        context: IntentCompilerContext,
        statusHandler: StatusHandler? = nil
    ) async throws -> IntentCompileResult {
        let run = try await createRun(prompt: prompt, context: context)
        await statusHandler?("Intent run created.")
        return try await awaitResult(for: run, statusHandler: statusHandler)
    }

    private func createRun(prompt: String, context: IntentCompilerContext) async throws -> RemoteIntentRunCreateResponse {
        var request = URLRequest(url: AppConfiguration.intentRunsEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RemoteIntentRunCreatePayload(prompt: prompt, context: context))

        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw RemoteIntentCompilerError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(RemoteIntentRunCreateResponse.self, from: data)
    }

    private func awaitResult(
        for run: RemoteIntentRunCreateResponse,
        statusHandler: StatusHandler?
    ) async throws -> IntentCompileResult {
        let socketURL = AppConfiguration.intentRunWebSocketEndpoint(runID: run.runID) ?? run.websocketURL
        let task = urlSession.webSocketTask(with: socketURL)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
        }

        while !Task.isCancelled {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .string(let text):
                data = Data(text.utf8)
            case .data(let payload):
                data = payload
            @unknown default:
                continue
            }

            let event = try RemoteIntentCompilerEvent.decode(from: data, using: decoder)
            switch event {
            case .runStarted:
                await statusHandler?("Backend run started.")
            case .status(let type, let message):
                await statusHandler?(message ?? Self.defaultStatusMessage(for: type))
            case .intentResult(_, let result):
                await statusHandler?("Intent result received.")
                return result
            case .error(let detail):
                throw RemoteIntentCompilerError.serverError(detail)
            case .unknown:
                continue
            }
        }

        throw RemoteIntentCompilerError.cancelled
    }

    private static func defaultStatusMessage(for type: String) -> String {
        switch type {
        case "planner_started":
            return "Parsing prompt."
        case "planner_completed":
            return "Prompt parsed."
        case "effect_planner_started":
            return "Planning effects."
        case "effect_planner_completed":
            return "Effects planned."
        case "validation_completed":
            return "Validated result."
        default:
            return "Processing intent."
        }
    }
}

enum RemoteIntentCompilerError: LocalizedError {
    case requestFailed(statusCode: Int)
    case serverError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode):
            return "Intent run request failed with status \(statusCode)."
        case .serverError(let detail):
            return detail
        case .cancelled:
            return "Intent compilation was cancelled."
        }
    }
}

