import Foundation
import OSLog

enum UIWorkspaceServiceError: LocalizedError {
    case missingProjectId
    case requestFailed(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .missingProjectId:
            return "A backend project id is required to plan the editor workspace."
        case let .requestFailed(statusCode, body):
            return "UI workspace planning failed (\(statusCode)): \(body ?? "no body")"
        }
    }
}

final class UIWorkspaceService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "UIWorkspace"
    )

    private let urlSession: URLSession
    private let authClient: AuthenticatedBackendClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        urlSession: URLSession = .shared,
        authClient: AuthenticatedBackendClient = AuthenticatedBackendClient()
    ) {
        self.urlSession = urlSession
        self.authClient = authClient
        encoder.dateEncodingStrategy = .secondsSince1970
    }

    func fetchPlan(request: UIWorkspacePlanRequest, projectId: String) async throws -> UIWorkspacePlan {
        guard !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UIWorkspaceServiceError.missingProjectId
        }
        let endpoint = AppConfiguration.projectUIWorkspacePlanEndpoint(projectID: projectId)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)
        urlRequest = try await authClient.authenticatedRequest(urlRequest)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            return try decoder.decode(UIWorkspacePlanResponse.self, from: data).plan
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Self.logger.error(
                "UI workspace plan failed status=\(httpResponse.statusCode, privacy: .public) body=\(body ?? "<empty>", privacy: .public)"
            )
            throw UIWorkspaceServiceError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
        let plan = try decoder.decode(UIWorkspacePlanResponse.self, from: data).plan
        Self.logger.info("UI workspace plan workspaceId=\(plan.workspaceId, privacy: .public)")
        return plan
    }
}
