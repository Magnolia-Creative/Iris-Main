import Foundation

enum ProjectClipProcessingError: LocalizedError {
    case invalidResponse
    case missingProjectInformation
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response could not be understood."
        case .missingProjectInformation:
            return "The import session is missing project information."
        case let .requestFailed(statusCode, body):
            return body.isEmpty ? "Request failed with status \(statusCode)." : "Request failed with status \(statusCode): \(body)"
        }
    }
}

struct ProjectClipProcessingService {
    private let session: URLSession
    private let authClient: AuthenticatedBackendClient
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared, authClient: AuthenticatedBackendClient = AuthenticatedBackendClient()) {
        self.session = session
        self.authClient = authClient
    }

    func createRemoteProject(displayName: String?) async throws -> RemoteProjectCreateResponse {
        var request = URLRequest(url: AppConfiguration.projectsCreateEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["name": displayName].compactMapValues { $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        request = try await authClient.authenticatedRequest(request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(RemoteProjectCreateResponse.self, from: data)
    }

    func createAgentSession(projectID: String, sessionName: String?) async throws -> RemoteImportSessionResponse {
        var request = URLRequest(url: AppConfiguration.projectAgentSessionsEndpoint(projectID: projectID))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["session_name": sessionName].compactMapValues { $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        request = try await authClient.authenticatedRequest(request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(RemoteImportSessionResponse.self, from: data)
    }

    func uploadBatch(
        _ assets: [ProcessedAudioAsset],
        visualFramesByLocalKey: [String: [VisualFrameUploadChunk]] = [:],
        backendProjectID: String
    ) async throws -> IngestResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let endpoint = AppConfiguration.projectClipProcessingEndpoint(projectID: backendProjectID)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let filteredFrames = visualFramesByLocalKey.filter { !$0.value.isEmpty }
        let body = try makeMultipartBody(
            assets: assets,
            visualFramesByLocalKey: filteredFrames,
            boundary: boundary
        )
        request = try await authClient.authenticatedRequest(request)
        let (data, response) = try await session.upload(for: request, from: body)
        try validate(response: response, data: data)
        return try decoder.decode(IngestResponse.self, from: data)
    }

    func fetchProjectClipStatus(projectID: String) async throws -> IngestResponse {
        let endpoint = AppConfiguration.projectClipStatusEndpoint(projectID: projectID)
        let request = try await authClient.authenticatedRequest(URLRequest(url: endpoint))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(IngestResponse.self, from: data)
    }

    func fetchSessionStatus(sessionID: String) async throws -> IngestResponse {
        let endpoint = AppConfiguration.sessionStatusEndpoint(sessionID: sessionID)
        let request = try await authClient.authenticatedRequest(URLRequest(url: endpoint))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(IngestResponse.self, from: data)
    }

    @discardableResult
    func cancelClip(localKey: String, backendProjectID: String) async throws -> CancelClipResponse {
        let endpoint = AppConfiguration.projectClipCancelEndpoint(
            projectID: backendProjectID,
            localKey: localKey
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"

        request = try await authClient.authenticatedRequest(request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(CancelClipResponse.self, from: data)
    }

    private func makeMultipartBody(
        assets: [ProcessedAudioAsset],
        visualFramesByLocalKey: [String: [VisualFrameUploadChunk]],
        boundary: String
    ) throws -> Data {
        var body = Data()

        for asset in assets {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(AppConfiguration.uploadFieldName)\"; filename=\"\(asset.fileName)\"\r\n")
            body.append("Content-Type: \(asset.mimeType)\r\n\r\n")
            body.append(try Data(contentsOf: asset.audioURL))
            body.append("\r\n")
            appendTextPart(
                named: AppConfiguration.uploadLocalKeyFieldName,
                value: asset.localKey,
                to: &body,
                boundary: boundary
            )
        }

        if !visualFramesByLocalKey.isEmpty {
            try appendVisualFrameManifestAndFiles(
                assets: assets,
                visualFramesByLocalKey: visualFramesByLocalKey,
                to: &body,
                boundary: boundary
            )
        }

        body.append("--\(boundary)--\r\n")
        return body
    }

    private func appendVisualFrameManifestAndFiles(
        assets: [ProcessedAudioAsset],
        visualFramesByLocalKey: [String: [VisualFrameUploadChunk]],
        to body: inout Data,
        boundary: String
    ) throws {
        var clips: [[String: Any]] = []
        for asset in assets {
            guard let frames = visualFramesByLocalKey[asset.localKey], !frames.isEmpty else { continue }
            let frameObjects: [[String: Any]] = frames.map { frame in
                [
                    "chunk_index": frame.chunkIndex,
                    "start_time_seconds": frame.startTimeSeconds,
                    "end_time_seconds": frame.endTimeSeconds,
                    "center_time_seconds": frame.centerTimeSeconds,
                    "filename": frame.formFilename,
                ]
            }
            clips.append([
                "local_key": asset.localKey,
                "frames": frameObjects,
            ])
        }

        guard !clips.isEmpty else { return }

        let manifest: [String: Any] = ["clips": clips]
        let jsonData = try JSONSerialization.data(withJSONObject: manifest, options: [])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ProjectClipProcessingError.invalidResponse
        }

        appendTextPart(
            named: AppConfiguration.visualFrameManifestFieldName,
            value: jsonString,
            to: &body,
            boundary: boundary
        )

        for asset in assets {
            guard let frames = visualFramesByLocalKey[asset.localKey] else { continue }
            for frame in frames {
                body.append("--\(boundary)\r\n")
                body.append(
                    "Content-Disposition: form-data; name=\"\(AppConfiguration.visualFramesFieldName)\"; filename=\"\(frame.formFilename)\"\r\n"
                )
                body.append("Content-Type: image/jpeg\r\n\r\n")
                body.append(try Data(contentsOf: frame.fileURL))
                body.append("\r\n")
            }
        }
    }

    private func appendTextPart(named name: String, value: String, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        body.append("Content-Type: text/plain; charset=utf-8\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProjectClipProcessingError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProjectClipProcessingError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
