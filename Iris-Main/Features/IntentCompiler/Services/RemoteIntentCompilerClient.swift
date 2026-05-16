import Foundation
import OSLog

final class RemoteIntentCompilerClient {
    typealias StatusHandler = @MainActor (String) -> Void

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "RemoteIntentCompiler"
    )

    private let urlSession: URLSession
    private let authClient: AuthenticatedBackendClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        urlSession: URLSession = .shared,
        authClient: AuthenticatedBackendClient = AuthenticatedBackendClient(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.urlSession = urlSession
        self.authClient = authClient
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
        request = try await authClient.authenticatedRequest(request)
        Self.logger.info(
            "[IntentRun] POST \(AppConfiguration.intentRunsEndpoint.absoluteString, privacy: .public) promptChars=\(prompt.count, privacy: .public) timeline=\(context.timelineId, privacy: .public) selectedClip=\(context.selectedClipId ?? "nil", privacy: .public) clips=\(context.clipsById.count, privacy: .public) transcripts=\(context.transcriptContextsByClipId.count, privacy: .public)"
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("[IntentRun] POST returned non-HTTP response")
            return try decoder.decode(RemoteIntentRunCreateResponse.self, from: data)
        }

        Self.logger.info(
            "[IntentRun] POST status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)"
        )

        if !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Self.logger.error(
                "[IntentRun] POST failed status=\(httpResponse.statusCode, privacy: .public) body=\(body ?? "<empty>", privacy: .public)"
            )
            throw RemoteIntentCompilerError.requestFailed(
                statusCode: httpResponse.statusCode,
                body: body
            )
        }

        let run = try decoder.decode(RemoteIntentRunCreateResponse.self, from: data)
        Self.logger.info(
            "[IntentRun] Created run=\(run.runID, privacy: .public) backendSocket=\(run.websocketURL.absoluteString, privacy: .public)"
        )
        return run
    }

    private func awaitResult(
        for run: RemoteIntentRunCreateResponse,
        statusHandler: StatusHandler?
    ) async throws -> IntentCompileResult {
        let socketURL = AppConfiguration.intentRunWebSocketEndpoint(runID: run.runID) ?? run.websocketURL
        let authenticatedSocketURL = try await authClient.authenticatedWebSocketURL(socketURL)
        Self.logger.info(
            "[IntentRun] Opening websocket run=\(run.runID, privacy: .public) url=\(socketURL.absoluteString, privacy: .public) backendURL=\(run.websocketURL.absoluteString, privacy: .public)"
        )
        let task = urlSession.webSocketTask(with: authenticatedSocketURL)
        task.resume()
        defer {
            Self.logger.info("[IntentRun] Cancelling websocket run=\(run.runID, privacy: .public)")
            task.cancel(with: .normalClosure, reason: nil)
        }

        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                Self.logger.error(
                    "[IntentRun] Websocket receive failed run=\(run.runID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                throw error
            }

            let data: Data
            let rawText: String
            switch message {
            case .string(let text):
                data = Data(text.utf8)
                rawText = text
            case .data(let payload):
                data = payload
                rawText = String(data: payload, encoding: .utf8) ?? "<\(payload.count) binary bytes>"
            @unknown default:
                Self.logger.warning("[IntentRun] Unknown websocket message run=\(run.runID, privacy: .public)")
                continue
            }
            Self.logger.info(
                "[IntentRun] Received message run=\(run.runID, privacy: .public) bytes=\(data.count, privacy: .public) payload=\(Self.truncatedForLog(rawText), privacy: .public)"
            )

            let event: RemoteIntentCompilerEvent
            do {
                event = try RemoteIntentCompilerEvent.decode(from: data, using: decoder)
            } catch {
                Self.logger.error(
                    "[IntentRun] Failed to decode websocket event run=\(run.runID, privacy: .public) error=\(error.localizedDescription, privacy: .public) payload=\(Self.truncatedForLog(rawText, maxLength: 4000), privacy: .public)"
                )
                throw error
            }
            switch event {
            case .runStarted(let prompt):
                Self.logger.info(
                    "[IntentRun] Event run_started run=\(run.runID, privacy: .public) promptChars=\(prompt?.count ?? 0, privacy: .public)"
                )
                await statusHandler?("Backend run started.")
            case .status(let type, let message):
                Self.logger.info(
                    "[IntentRun] Event \(type, privacy: .public) run=\(run.runID, privacy: .public) message=\(message ?? "nil", privacy: .public)"
                )
                await statusHandler?(message ?? Self.defaultStatusMessage(for: type))
            case .intentResult(_, let result):
                Self.logger.info(
                    "[IntentRun] Event intent_result run=\(run.runID, privacy: .public) actions=\(result.actions.count, privacy: .public) effects=\(result.experimentalEffectOperations.count, privacy: .public) warnings=\(result.warnings.map(\.rawValue).joined(separator: ","), privacy: .public) needsClarification=\(result.needsClarification, privacy: .public)"
                )
                await statusHandler?("Intent result received.")
                return result
            case .error(let detail):
                Self.logger.error(
                    "[IntentRun] Event error run=\(run.runID, privacy: .public) detail=\(detail, privacy: .public)"
                )
                throw RemoteIntentCompilerError.serverError(detail)
            case .unknown(let type):
                Self.logger.warning(
                    "[IntentRun] Unknown event type=\(type, privacy: .public) run=\(run.runID, privacy: .public)"
                )
                continue
            }
        }

        Self.logger.warning("[IntentRun] Await cancelled run=\(run.runID, privacy: .public)")
        throw RemoteIntentCompilerError.cancelled
    }

    private static func truncatedForLog(_ text: String, maxLength: Int = 1200) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "...<truncated \(text.count - maxLength) chars>"
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
    case requestFailed(statusCode: Int, body: String?)
    case serverError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let body):
            if let body, !body.isEmpty {
                return "Intent run failed (\(statusCode)): \(body)"
            }
            return "Intent run failed with status \(statusCode)."
        case .serverError(let detail):
            return detail
        case .cancelled:
            return "Intent compilation was cancelled."
        }
    }
}

