import AVFoundation
import Metal

final class AssetFrameProvider {
    private let metalContext: MetalContext
    private var pools: [URL: GeneratorPool] = [:]
    private let lock = NSLock()

    init(metalContext: MetalContext) {
        self.metalContext = metalContext
    }

    func decodeFrame(from assetURL: URL, at time: Double, maxSize: CGSize? = nil) async throws -> MTLTexture {
        let pool = getOrCreatePool(for: assetURL, maxSize: maxSize)
        let generator = await pool.checkout()
        defer { pool.checkin(generator) }

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
        pools.removeValue(forKey: url)
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        pools.removeAll()
    }

    private func getOrCreatePool(for url: URL, maxSize: CGSize?) -> GeneratorPool {
        lock.lock()
        defer { lock.unlock() }

        if let existing = pools[url] { return existing }

        let pool = GeneratorPool(url: url, maxSize: maxSize, poolSize: 3)
        pools[url] = pool
        return pool
    }
}

// MARK: - Generator Pool

/// Manages a fixed-size pool of AVAssetImageGenerator instances for a single
/// asset URL. Callers check out a generator, use it, then return it. When all
/// generators are busy, checkout suspends until one is returned.
final class GeneratorPool: @unchecked Sendable {
    private let url: URL
    private let maxSize: CGSize?
    private var available: [AVAssetImageGenerator]
    private var waiters: [CheckedContinuation<AVAssetImageGenerator, Never>] = []
    private let lock = NSLock()

    init(url: URL, maxSize: CGSize?, poolSize: Int) {
        self.url = url
        self.maxSize = maxSize
        self.available = (0..<poolSize).map { _ in
            Self.makeGenerator(url: url, maxSize: maxSize)
        }
    }

    func checkout() async -> AVAssetImageGenerator {
        lock.lock()
        if let generator = available.popLast() {
            lock.unlock()
            return generator
        }
        lock.unlock()

        return await withCheckedContinuation { continuation in
            lock.lock()
            if let generator = available.popLast() {
                lock.unlock()
                continuation.resume(returning: generator)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func checkin(_ generator: AVAssetImageGenerator) {
        lock.lock()
        if let waiter = waiters.first {
            waiters.removeFirst()
            lock.unlock()
            waiter.resume(returning: generator)
        } else {
            available.append(generator)
            lock.unlock()
        }
    }

    private static func makeGenerator(url: URL, maxSize: CGSize?) -> AVAssetImageGenerator {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.appliesPreferredTrackTransform = true
        if let maxSize {
            generator.maximumSize = maxSize
        }
        return generator
    }
}
