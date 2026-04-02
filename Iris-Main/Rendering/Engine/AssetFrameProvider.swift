import AVFoundation
import Metal

final class AssetFrameProvider {
    private let metalContext: MetalContext
    private var generators: [URL: AVAssetImageGenerator] = [:]
    private let lock = NSLock()

    init(metalContext: MetalContext) {
        self.metalContext = metalContext
    }

    func decodeFrame(from assetURL: URL, at time: Double, maxSize: CGSize? = nil) async throws -> MTLTexture {
        let generator = getOrCreateGenerator(for: assetURL, maxSize: maxSize)
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: cmTime)
        guard let texture = metalContext.textureFromCGImage(cgImage) else {
            throw RenderEngineError.failedToDecodeFrame
        }
        return texture
    }

    func assetDuration(for url: URL) async throws -> Double {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    func invalidate(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        generators.removeValue(forKey: url)
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        generators.removeAll()
    }

    private func getOrCreateGenerator(for url: URL, maxSize: CGSize?) -> AVAssetImageGenerator {
        lock.lock()
        defer { lock.unlock() }

        if let existing = generators[url] { return existing }

        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.appliesPreferredTrackTransform = true

        if let maxSize {
            generator.maximumSize = maxSize
        }

        generators[url] = generator
        return generator
    }
}
