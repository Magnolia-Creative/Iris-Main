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
            return "MobileCLIP model could not be loaded. Confirm compiled .modelc files are available."
        case .textTooLong:
            return "Query text is too long for MobileCLIP. Keep it under 77 characters."
        case .textEmbeddingFailed:
            return "Failed to generate text embedding with MobileCLIP."
        case .imageEmbeddingFailed:
            return "Failed to generate image embedding with MobileCLIP."
        }
    }
}

protocol MobileCLIPEmbeddingProviding {
    func textEmbedding(for text: String) async throws -> [Float]
    func imageEmbedding(for image: CGImage) async throws -> [Float]
}

struct MobileCLIPEmbeddingService: MobileCLIPEmbeddingProviding {
    private let encoderURI: String

    init(encoderURIString: String = AppConfiguration.semanticMobileCLIPEncoderURI) {
        self.encoderURI = encoderURIString
    }

    func textEmbedding(for text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 77 else {
            print("[SemanticIndex] textEmbedding rejected (>77 chars): \(trimmed.count)")
            throw MobileCLIPEmbeddingError.textTooLong
        }

        #if canImport(MobileCLIP)
        print("[SemanticIndex] textEmbedding using encoderURI=\(encoderURI)")
        guard !encoderURI.isEmpty else { throw MobileCLIPEmbeddingError.modelUnavailable }
        let encoder = try NewClipEncoder(uri: encoderURI)
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
        guard !encoderURI.isEmpty else { throw MobileCLIPEmbeddingError.modelUnavailable }
        let encoder = try NewClipEncoder(uri: encoderURI)
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
