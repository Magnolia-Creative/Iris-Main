import CoreGraphics
import Foundation

#if canImport(MobileCLIP)
import MobileCLIP
#endif

enum MobileCLIPEmbeddingError: LocalizedError {
    case packageUnavailable
    case modelUnavailable
    case textTooLong
    case textEmbeddingFailed
    case imageEmbeddingFailed

    var errorDescription: String? {
        switch self {
        case .packageUnavailable:
            return "swift-mobileclip is not linked. Add the package dependency to the app target."
        case .modelUnavailable:
            return "MobileCLIP s2 model is unavailable. Set encoder URI to an explicit folder path like s2:///absolute/path containing mobileclip_s2_text.mlmodelc and mobileclip_s2_image.mlmodelc."
        case .textTooLong:
            return "Query text is too long for MobileCLIP. Keep it under 77 characters."
        case .textEmbeddingFailed:
            return "Failed to generate text embedding with MobileCLIP."
        case .imageEmbeddingFailed:
            return "Failed to generate image embedding with MobileCLIP."
        }
    }
}

protocol MobileCLIPEmbeddingProviding: Sendable {
    func textEmbedding(for text: String) async throws -> [Float]
    func imageEmbedding(for image: CGImage) async throws -> [Float]
}

actor MobileCLIPEmbeddingService: MobileCLIPEmbeddingProviding {
    static let shared = MobileCLIPEmbeddingService()

    private let encoderURI: String
    #if canImport(MobileCLIP)
    private var cachedEncoder: CLIPEncoder?
    private var hasValidatedModelAvailability = false
    #endif

    init(encoderURIString: String = AppConfiguration.semanticMobileCLIPEncoderURI) {
        self.encoderURI = encoderURIString
    }

    private func explicitModelsDirectoryPath() -> String? {
        guard let components = URLComponents(string: encoderURI) else { return nil }
        let trimmedPath = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? nil : trimmedPath
    }

    private func ensureModelAvailability() throws {
        guard !encoderURI.isEmpty else {
            print("[SemanticIndex] model availability failed: empty encoder URI")
            throw MobileCLIPEmbeddingError.modelUnavailable
        }

        // Avoid the package crash path that force-unwraps bundled model URLs when missing.
        guard let modelsDirectoryPath = explicitModelsDirectoryPath() else {
            print("[SemanticIndex] model availability failed: encoderURI has no explicit path (\(encoderURI))")
            throw MobileCLIPEmbeddingError.modelUnavailable
        }

        let imagePath = (modelsDirectoryPath as NSString).appendingPathComponent("mobileclip_s2_image.mlmodelc")
        let textPath = (modelsDirectoryPath as NSString).appendingPathComponent("mobileclip_s2_text.mlmodelc")
        let fileManager = FileManager.default
        let imageExists = fileManager.fileExists(atPath: imagePath)
        let textExists = fileManager.fileExists(atPath: textPath)
        print("[SemanticIndex] model availability check dir=\(modelsDirectoryPath) imageExists=\(imageExists) textExists=\(textExists)")

        guard imageExists, textExists else {
            throw MobileCLIPEmbeddingError.modelUnavailable
        }
    }

    #if canImport(MobileCLIP)
    private func encoder() throws -> CLIPEncoder {
        if let cachedEncoder {
            return cachedEncoder
        }

        if !hasValidatedModelAvailability {
            try ensureModelAvailability()
            hasValidatedModelAvailability = true
        }

        let encoder = try NewClipEncoder(uri: encoderURI)
        cachedEncoder = encoder
        return encoder
    }
    #endif

    func textEmbedding(for text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 77 else {
            print("[SemanticIndex] textEmbedding rejected (>77 chars): \(trimmed.count)")
            throw MobileCLIPEmbeddingError.textTooLong
        }

        #if canImport(MobileCLIP)
        print("[SemanticIndex] textEmbedding using encoderURI=\(encoderURI)")
        let encoder = try encoder()
        let tokenizer = CLIPTokenizer()
        let result = await ComputeTextEmbeddings(
            encoder: encoder,
            tokenizer: tokenizer,
            text: trimmed
        )

        switch result {
        case .success(let embeddings):
            print("[SemanticIndex] textEmbedding success dimensions=\(embeddings.dimensions)")
            return embeddings.embeddings.map { Float($0) }
        case .failure:
            print("[SemanticIndex] textEmbedding failed result for text='\(trimmed)'")
            throw MobileCLIPEmbeddingError.textEmbeddingFailed
        }
        #else
        print("[SemanticIndex] textEmbedding package unavailable")
        throw MobileCLIPEmbeddingError.packageUnavailable
        #endif
    }

    func imageEmbedding(for image: CGImage) async throws -> [Float] {
        #if canImport(MobileCLIP)
        print("[SemanticIndex] imageEmbedding using encoderURI=\(encoderURI)")
        let encoder = try encoder()
        let result = await ComputeImageEmbeddings(
            encoder: encoder,
            image: image
        )

        switch result {
        case .success(let embeddings):
            print("[SemanticIndex] imageEmbedding success dimensions=\(embeddings.dimensions)")
            return embeddings.embeddings.map { Float($0) }
        case .failure:
            print("[SemanticIndex] imageEmbedding failed result")
            throw MobileCLIPEmbeddingError.imageEmbeddingFailed
        }
        #else
        print("[SemanticIndex] imageEmbedding package unavailable")
        throw MobileCLIPEmbeddingError.packageUnavailable
        #endif
    }
}

actor MobileCLIPEmbeddingPool: MobileCLIPEmbeddingProviding {
    static let shared = MobileCLIPEmbeddingPool()

    private let services: [MobileCLIPEmbeddingService]
    private var nextServiceIndex = 0

    init(
        poolSize: Int = max(1, min(2, ProcessInfo.processInfo.activeProcessorCount / 4)),
        encoderURIString: String = AppConfiguration.semanticMobileCLIPEncoderURI
    ) {
        let normalizedPoolSize = max(1, poolSize)
        self.services = (0..<normalizedPoolSize).map { _ in
            MobileCLIPEmbeddingService(encoderURIString: encoderURIString)
        }
        print("[SemanticIndex] Initialized encoder pool size=\(normalizedPoolSize)")
    }

    private func nextService() -> MobileCLIPEmbeddingService {
        let service = services[nextServiceIndex]
        nextServiceIndex = (nextServiceIndex + 1) % services.count
        return service
    }

    func textEmbedding(for text: String) async throws -> [Float] {
        // Text embedding is infrequent; route to one service.
        let service = nextService()
        return try await service.textEmbedding(for: text)
    }

    func imageEmbedding(for image: CGImage) async throws -> [Float] {
        let service = nextService()
        return try await service.imageEmbedding(for: image)
    }
}
