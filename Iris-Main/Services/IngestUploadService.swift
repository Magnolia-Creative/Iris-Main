import Foundation

enum IngestUploadError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response could not be understood."
        case let .requestFailed(statusCode, body):
            return body.isEmpty ? "Upload failed with status \(statusCode)." : "Upload failed with status \(statusCode): \(body)"
        }
    }
}

struct IngestUploadService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func upload(_ assets: [ProcessedAudioAsset], to endpoint: URL) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try makeMultipartBody(assets: assets, boundary: boundary)
        let (data, response) = try await session.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IngestUploadError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw IngestUploadError.requestFailed(statusCode: httpResponse.statusCode, body: bodyText)
        }

        return UploadResponse(
            rawBody: String(data: data, encoding: .utf8) ?? "",
            statusCode: httpResponse.statusCode
        )
    }

    private func makeMultipartBody(assets: [ProcessedAudioAsset], boundary: String) throws -> Data {
        var body = Data()

        for asset in assets {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(AppConfiguration.uploadFieldName)\"; filename=\"\(asset.fileName)\"\r\n")
            body.append("Content-Type: \(asset.mimeType)\r\n\r\n")
            body.append(try Data(contentsOf: asset.audioURL))
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        return body
    }
}

struct UploadResponse {
    let rawBody: String
    let statusCode: Int
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
