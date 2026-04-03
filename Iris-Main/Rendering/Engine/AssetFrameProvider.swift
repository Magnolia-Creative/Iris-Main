import AVFoundation
import Metal
import CoreVideo
import QuartzCore
import os

final class AssetFrameProvider {
    struct DecodedFrame {
        let texture: MTLTexture
        let actualTime: Double
        let backing: Any?

        init(texture: MTLTexture, actualTime: Double, backing: Any? = nil) {
            self.texture = texture
            self.actualTime = actualTime
            self.backing = backing
        }
    }

    private let metalContext: MetalContext
    private var pools: [URL: GeneratorPool] = [:]
    private var sequentialReaders: [URL: SequentialReader] = [:]
    private let lock = NSLock()
    private var lastDriftLogTimeByURL: [URL: CFTimeInterval] = [:]

    #if DEBUG
    private static let logger = Logger(subsystem: "Iris-Main", category: "Render.AssetFrameProvider")
    #endif

    init(metalContext: MetalContext) {
        self.metalContext = metalContext
    }

    // MARK: - Playback decode (AVAssetReader, zero-copy CVPixelBuffer path)

    func decodeFrameForPlayback(from assetURL: URL, at time: Double) async throws -> DecodedFrame {
        let reader = getOrCreateReader(for: assetURL)
        try await reader.ensureTrackLoaded()

        guard let sampleBuffer = reader.readFrame(near: time) else {
            #if DEBUG
            Self.logger.error(
                "playback decode missing sample file=\(assetURL.lastPathComponent, privacy: .public) requested=\(time, format: .fixed(precision: 3))s"
            )
            #endif
            throw RenderEngineError.failedToDecodeFrame
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            #if DEBUG
            Self.logger.error(
                "playback decode missing pixel buffer file=\(assetURL.lastPathComponent, privacy: .public) requested=\(time, format: .fixed(precision: 3))s actual=\(presentationTime, format: .fixed(precision: 3))s"
            )
            #endif
            throw RenderEngineError.failedToDecodeFrame
        }

        if let backed = metalContext.textureFromPixelBuffer(pixelBuffer) {
            maybeLogDecodeDrift(url: assetURL, requested: time, actual: presentationTime)
            return DecodedFrame(texture: backed.texture, actualTime: presentationTime, backing: backed.backing)
        }

        #if DEBUG
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        Self.logger.error(
            "playback texture wrap failed file=\(assetURL.lastPathComponent, privacy: .public) requested=\(time, format: .fixed(precision: 3))s actual=\(presentationTime, format: .fixed(precision: 3))s format=\(pixelFormat) size=\(width)x\(height)"
        )
        #endif
        throw RenderEngineError.failedToDecodeFrame
    }

    // MARK: - Random-access decode (AVAssetImageGenerator, for scrub/thumbnails)

    func decodeFrame(from assetURL: URL, at time: Double, maxSize: CGSize? = nil) async throws -> DecodedFrame {
        let pool = getOrCreatePool(for: assetURL, maxSize: maxSize)
        let checkoutStart = CACurrentMediaTime()
        let generator = await pool.checkout()
        let waitMs = (CACurrentMediaTime() - checkoutStart) * 1000
        defer { pool.checkin(generator) }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let decodeStart = CACurrentMediaTime()
        let (cgImage, actualTime) = try await generator.image(at: cmTime)
        let decodeMs = (CACurrentMediaTime() - decodeStart) * 1000
        maybeLogDecodeDrift(url: assetURL, requested: time, actual: actualTime.seconds)
        #if DEBUG
        if waitMs >= 8 || decodeMs >= 25 {
            let sizeText: String
            if let maxSize {
                sizeText = "\(Int(maxSize.width))x\(Int(maxSize.height))"
            } else {
                sizeText = "full"
            }
            Self.logger.debug(
                "scrub decode file=\(assetURL.lastPathComponent, privacy: .public) requested=\(time, format: .fixed(precision: 3))s actual=\(actualTime.seconds, format: .fixed(precision: 3))s wait_ms=\(waitMs, format: .fixed(precision: 1)) decode_ms=\(decodeMs, format: .fixed(precision: 1)) size=\(sizeText, privacy: .public)"
            )
        }
        #endif
        guard let texture = metalContext.textureFromCGImage(cgImage) else {
            throw RenderEngineError.failedToDecodeFrame
        }
        return DecodedFrame(texture: texture, actualTime: actualTime.seconds)
    }

    func assetDuration(for url: URL) async throws -> Double {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    func invalidate(for url: URL) {
        lock.lock()
        pools.removeValue(forKey: url)
        let reader = sequentialReaders.removeValue(forKey: url)
        lock.unlock()
        reader?.cancel()
    }

    func invalidateAll() {
        lock.lock()
        let readers = Array(sequentialReaders.values)
        pools.removeAll()
        sequentialReaders.removeAll()
        lock.unlock()
        for reader in readers { reader.cancel() }
    }

    func cancelAllPendingDecodes() {
        lock.lock()
        let allPools = Array(pools.values)
        let allReaders = Array(sequentialReaders.values)
        lock.unlock()
        for pool in allPools { pool.cancelAll() }
        for reader in allReaders { reader.cancel() }
    }

    func resetSequentialReaders() {
        lock.lock()
        let readers = Array(sequentialReaders.values)
        sequentialReaders.removeAll()
        lock.unlock()
        for reader in readers { reader.cancel() }
    }

    // MARK: - Pool / Reader management

    private func getOrCreatePool(for url: URL, maxSize: CGSize?) -> GeneratorPool {
        lock.lock()
        defer { lock.unlock() }
        if let existing = pools[url] { return existing }
        let pool = GeneratorPool(url: url, maxSize: maxSize, poolSize: 3)
        pools[url] = pool
        return pool
    }

    private func getOrCreateReader(for url: URL) -> SequentialReader {
        lock.lock()
        defer { lock.unlock() }
        if let existing = sequentialReaders[url] { return existing }
        let reader = SequentialReader(url: url)
        sequentialReaders[url] = reader
        return reader
    }

    private func maybeLogDecodeDrift(url: URL, requested: Double, actual: Double) {
        let driftMs = abs(actual - requested) * 1000
        guard driftMs >= 25 else { return }

        let now = CACurrentMediaTime()
        lock.lock()
        let last = lastDriftLogTimeByURL[url] ?? 0
        guard now - last >= 0.5 else {
            lock.unlock()
            return
        }
        lastDriftLogTimeByURL[url] = now
        lock.unlock()

        #if DEBUG
        Self.logger.debug(
            "decode drift file=\(url.lastPathComponent, privacy: .public) requested=\(requested, format: .fixed(precision: 3))s actual=\(actual, format: .fixed(precision: 3))s drift=\(driftMs, format: .fixed(precision: 1))ms"
        )
        #endif
    }
}

// MARK: - Sequential Reader (AVAssetReader-based)

/// Reads video frames sequentially using AVAssetReader, which leverages hardware
/// decoding and maintains codec state across frames for efficient sequential access.
/// Outputs CVPixelBuffer in BGRA for zero-copy Metal texture wrapping.
final class SequentialReader: @unchecked Sendable {
    private let url: URL
    private let asset: AVAsset
    private var videoTrack: AVAssetTrack?
    private var assetDuration: CMTime = .invalid
    private var trackLoadState: TrackLoadState = .notLoaded
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var lastReadTime: Double = -1
    private let lock = NSLock()

    #if DEBUG
    private static let logger = Logger(subsystem: "Iris-Main", category: "Render.SequentialReader")
    #endif

    private enum TrackLoadState {
        case notLoaded
        case loading
        case loaded
        case failed
    }

    init(url: URL) {
        self.url = url
        self.asset = AVAsset(url: url)
    }

    func ensureTrackLoaded() async throws {
        lock.lock()
        switch trackLoadState {
        case .loaded:
            lock.unlock()
            return
        case .failed:
            lock.unlock()
            throw RenderEngineError.failedToDecodeFrame
        case .loading:
            lock.unlock()
            // Another task is loading; poll until done
            while true {
                try await Task.sleep(nanoseconds: 10_000_000)
                lock.lock()
                let state = trackLoadState
                lock.unlock()
                switch state {
                case .loaded: return
                case .failed: throw RenderEngineError.failedToDecodeFrame
                default: continue
                }
            }
        case .notLoaded:
            trackLoadState = .loading
            lock.unlock()
        }

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let duration = try await asset.load(.duration)
            lock.lock()
            self.videoTrack = tracks.first
            self.assetDuration = duration
            self.trackLoadState = tracks.first != nil ? .loaded : .failed
            let ok = tracks.first != nil
            lock.unlock()
            if !ok { throw RenderEngineError.failedToDecodeFrame }
        } catch {
            lock.lock()
            if trackLoadState == .loading { trackLoadState = .failed }
            lock.unlock()
            throw RenderEngineError.failedToDecodeFrame
        }
    }

    func readFrame(near targetTime: Double) -> CMSampleBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard videoTrack != nil else { return nil }

        let needsNewReader = reader == nil
            || reader?.status != .reading
            || targetTime < lastReadTime - 0.1

        if needsNewReader {
            setupReader(at: targetTime)
        }

        guard let output else {
            #if DEBUG
            let statusText = reader.map { "\($0.status.rawValue)" } ?? "nil"
            let errorText = reader?.error?.localizedDescription ?? "none"
            Self.logger.error(
                "reader unavailable file=\(self.url.lastPathComponent, privacy: .public) target=\(targetTime, format: .fixed(precision: 3))s status=\(statusText, privacy: .public) error=\(errorText, privacy: .public)"
            )
            #endif
            return nil
        }

        var bestSample: CMSampleBuffer?

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            lastReadTime = pts
            bestSample = sampleBuffer

            if pts >= targetTime - 0.02 {
                break
            }
        }

        #if DEBUG
        if bestSample == nil {
            let statusText = reader.map { "\($0.status.rawValue)" } ?? "nil"
            let errorText = reader?.error?.localizedDescription ?? "none"
            Self.logger.error(
                "reader returned no sample file=\(self.url.lastPathComponent, privacy: .public) target=\(targetTime, format: .fixed(precision: 3))s last=\(self.lastReadTime, format: .fixed(precision: 3))s status=\(statusText, privacy: .public) error=\(errorText, privacy: .public)"
            )
        }
        #endif

        return bestSample
    }

    func cancel() {
        lock.lock()
        reader?.cancelReading()
        reader = nil
        output = nil
        lastReadTime = -1
        lock.unlock()
    }

    private func setupReader(at startTime: Double) {
        reader?.cancelReading()
        reader = nil
        output = nil

        guard let videoTrack else {
            #if DEBUG
            Self.logger.error("missing video track file=\(self.url.lastPathComponent, privacy: .public)")
            #endif
            return
        }

        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        readerOutput.alwaysCopiesSampleData = false

        guard let assetReader = try? AVAssetReader(asset: asset) else {
            #if DEBUG
            Self.logger.error("failed to create reader file=\(self.url.lastPathComponent, privacy: .public)")
            #endif
            return
        }
        guard assetReader.canAdd(readerOutput) else {
            #if DEBUG
            Self.logger.error("cannot add reader output file=\(self.url.lastPathComponent, privacy: .public)")
            #endif
            return
        }
        assetReader.add(readerOutput)

        let seekTime = max(0, startTime - 0.1)
        let start = CMTime(seconds: seekTime, preferredTimescale: 600)
        let remainingDuration: CMTime = {
            guard assetDuration.isNumeric, assetDuration > start else {
                return CMTime(seconds: 1, preferredTimescale: 600)
            }
            return CMTimeSubtract(assetDuration, start)
        }()
        assetReader.timeRange = CMTimeRange(start: start, duration: remainingDuration)

        guard assetReader.startReading() else {
            #if DEBUG
            let errorText = assetReader.error?.localizedDescription ?? "none"
            Self.logger.error(
                "startReading failed file=\(self.url.lastPathComponent, privacy: .public) start=\(seekTime, format: .fixed(precision: 3))s duration=\(remainingDuration.seconds, format: .fixed(precision: 3))s error=\(errorText, privacy: .public)"
            )
            #endif
            return
        }

        self.reader = assetReader
        self.output = readerOutput
        self.lastReadTime = seekTime

        #if DEBUG
        Self.logger.debug(
            "reader started file=\(self.url.lastPathComponent, privacy: .public) start=\(seekTime, format: .fixed(precision: 3))s duration=\(remainingDuration.seconds, format: .fixed(precision: 3))s"
        )
        #endif
    }
}

// MARK: - Generator Pool (for random-access / scrub)

/// Manages a fixed-size pool of AVAssetImageGenerator instances for a single
/// asset URL. Callers check out a generator, use it, then return it. When all
/// generators are busy, checkout suspends until one is returned.
final class GeneratorPool: @unchecked Sendable {
    private let url: URL
    private let maxSize: CGSize?
    private var available: [AVAssetImageGenerator]
    private var waiters: [CheckedContinuation<AVAssetImageGenerator, Never>] = []
    private let lock = NSLock()

    #if DEBUG
    private static let logger = Logger(subsystem: "Iris-Main", category: "Render.GeneratorPool")
    #endif

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
        #if DEBUG
        let waiterCount = waiters.count
        Self.logger.debug(
            "pool empty file=\(self.url.lastPathComponent, privacy: .public) waiters=\(waiterCount) available=0"
        )
        #endif
        lock.unlock()

        return await withCheckedContinuation { continuation in
            lock.lock()
            if let generator = available.popLast() {
                lock.unlock()
                continuation.resume(returning: generator)
            } else {
                waiters.append(continuation)
                #if DEBUG
                let waiterCount = waiters.count
                Self.logger.debug(
                    "pool enqueue file=\(self.url.lastPathComponent, privacy: .public) waiters=\(waiterCount)"
                )
                #endif
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

    func cancelAll() {
        lock.lock()
        let generators = available
        let waiterCount = waiters.count
        lock.unlock()
        #if DEBUG
        Self.logger.debug(
            "pool cancel_all file=\(self.url.lastPathComponent, privacy: .public) generators=\(generators.count) waiters=\(waiterCount)"
        )
        #endif
        for generator in generators {
            generator.cancelAllCGImageGeneration()
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
