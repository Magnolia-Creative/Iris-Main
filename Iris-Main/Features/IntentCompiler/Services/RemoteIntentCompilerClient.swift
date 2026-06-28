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
        let response = try await compilePromptResponse(
            prompt: prompt,
            context: context,
            statusHandler: statusHandler
        )
        return response.edit
    }

    func compilePromptResponse(
        prompt: String,
        context: IntentCompilerContext,
        editorContext: RemoteIntentEditorContext? = nil,
        currentWorkspaceId: String? = nil,
        statusHandler: StatusHandler? = nil
    ) async throws -> RemoteIntentAgentResponse {
        var request = URLRequest(url: AppConfiguration.agentRunsEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            RemoteIntentRunCreatePayload(
                prompt: prompt,
                context: context,
                editorContext: editorContext,
                currentWorkspaceId: currentWorkspaceId
            )
        )
        request = try await authClient.authenticatedRequest(request)
        Self.logger.info(
            "[IntentRun] POST \(AppConfiguration.agentRunsEndpoint.absoluteString, privacy: .public) promptChars=\(prompt.count, privacy: .public) timeline=\(context.timelineId, privacy: .public) selectedClip=\(context.selectedClipId ?? "nil", privacy: .public) clips=\(context.clipsById.count, privacy: .public) transcripts=\(context.transcriptContextsByClipId.count, privacy: .public)"
        )
        await statusHandler?("Starting backend intent run.")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("[IntentRun] POST returned non-HTTP response")
            let decoded = try decoder.decode(RemoteIntentAgentResponse.self, from: data)
            await emitStatusEvents(from: decoded.meta, statusHandler: statusHandler)
            return decoded
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

        let result = try decoder.decode(RemoteIntentAgentResponse.self, from: data)
        Self.logger.info(
            "[IntentRun] Completed workspace=\(result.ui.workspaceId, privacy: .public) actions=\(result.edit.actions.count, privacy: .public) effects=\(result.edit.experimentalEffectOperations.count, privacy: .public) warnings=\(result.edit.warnings.map(\.rawValue).joined(separator: ","), privacy: .public) needsClarification=\(result.edit.needsClarification, privacy: .public)"
        )
        await emitStatusEvents(from: result.meta, statusHandler: statusHandler)
        await statusHandler?("Intent result received.")
        return result
    }

    private func emitStatusEvents(
        from meta: RemoteIntentAgentMeta,
        statusHandler: StatusHandler?
    ) async {
        guard let statusHandler else { return }
        let events = meta.editEvents + meta.uiEvents
        for event in events {
            guard let type = event["type"]?.stringValue else { continue }
            let message = event["status"]?.stringValue
                ?? event["status_message"]?.stringValue
                ?? event["intent"]?.stringValue
                ?? Self.defaultStatusMessage(for: type)
            await statusHandler(message)
        }
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
        case "ui_planner_started":
            return "Planning workspace."
        case "ui_planner_completed":
            return "Workspace planned."
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

