import Foundation
import Photos
import UIKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailUpdate {
    let image: UIImage?
    let isFinal: Bool
}

private struct ThumbnailStripGenerationRequest: Sendable {
    let key: String
    let outputPath: String
    let videoURL: URL
    let duration: Double
    let frameCount: Int
    let height: Int
    let aspectRatio: CGFloat
}

private actor ThumbnailStripGenerationCoordinator {
    private var tasks: [String: Task<ThumbnailService.ThumbnailStripInfo?, Error>] = [:]

    func run(
        request: ThumbnailStripGenerationRequest,
        operation: @Sendable @escaping (ThumbnailStripGenerationRequest) async throws -> ThumbnailService.ThumbnailStripInfo?
    ) async throws -> ThumbnailService.ThumbnailStripInfo? {
        if let existing = tasks[request.key] {
            return try await existing.value
        }

        let task = Task {
            try await operation(request)
        }
        tasks[request.key] = task
        defer { tasks[request.key] = nil }
        return try await task.value
    }
}

final class ThumbnailService {
    static let shared = ThumbnailService()
    private let db = DatabaseManager.shared
    private let thumbnailStripHeight: CGFloat = 96
    private let thumbnailStripIntervalSeconds: Double = 1.5
    private let thumbnailStripMaxFrames: Int = 60
    private let thumbnailStripCompressionQuality: CGFloat = 0.84
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let thumbnailStripCache = NSCache<NSString, UIImage>()
    private let stripGenerationCoordinator = ThumbnailStripGenerationCoordinator()

    private init() {
        thumbnailCache.countLimit = 200
        thumbnailStripCache.countLimit = 64
    }

    struct ThumbnailStripInfo: Sendable {
        let path: String
        let height: Int
        let frameCount: Int
    }

    func loadThumbnailStream(for asset: PHAsset, size: CGSize) -> AsyncStream<ThumbnailUpdate> {
        loadThumbnailStream(for: asset, size: size, cacheKey: nil)
    }

    private func loadThumbnailStream(for asset: PHAsset, size: CGSize, cacheKey: String?) -> AsyncStream<ThumbnailUpdate> {
        AsyncStream { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true

            let lock = NSLock()
            var didFinish = false

            let requestId = PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFill, options: options
            ) { image, info in
                let info = info ?? [:]
                let shouldFinish: Bool
                let update: ThumbnailUpdate

                if info[PHImageCancelledKey] as? Bool == true {
                    update = ThumbnailUpdate(image: nil, isFinal: true)
                    shouldFinish = true
                } else if info[PHImageErrorKey] != nil {
                    update = ThumbnailUpdate(image: nil, isFinal: true)
                    shouldFinish = true
                } else {
                    let isDegraded = info[PHImageResultIsDegradedKey] as? Bool == true
                    update = ThumbnailUpdate(image: image, isFinal: !isDegraded)
                    shouldFinish = !isDegraded
                    if let cacheKey, let image, shouldFinish {
                        self.cacheThumbnail(image, forKey: cacheKey)
                    }
                }

                lock.lock()
                defer { lock.unlock() }
                guard !didFinish else { return }
                continuation.yield(update)
                if shouldFinish {
                    didFinish = true
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                PHImageManager.default().cancelImageRequest(requestId)
            }
        }
    }

    func loadThumbnailStream(for assetRefId: String, size: CGSize) throws -> AsyncStream<ThumbnailUpdate> {
        let cacheKey = thumbnailCacheKey(for: assetRefId, size: size)
        if let image = cachedThumbnail(forKey: cacheKey) {
            return immediateThumbnailStream(with: image)
        }

        guard let assetRef = try db.getAssetReference(assetRefId: assetRefId) else {
            return immediateThumbnailStream(with: nil)
        }

        if AppSandboxFileURI.isLikelySandboxFile(assetRef.uri) {
            if let fileURL = AppSandboxFileURI.resolveFileURL(storedURI: assetRef.uri) {
                return loadThumbnailStream(for: fileURL, size: size, cacheKey: cacheKey)
            }
            return immediateThumbnailStream(with: nil)
        }

        let results = PHAsset.fetchAssets(withLocalIdentifiers: [assetRef.uri], options: nil)
        if let asset = results.firstObject {
            return loadThumbnailStream(for: asset, size: size, cacheKey: cacheKey)
        }

        if let fileURL = AppSandboxFileURI.resolveFileURL(storedURI: assetRef.uri) {
            return loadThumbnailStream(for: fileURL, size: size, cacheKey: cacheKey)
        }
        return immediateThumbnailStream(with: nil)
    }

    func loadThumbnail(for assetRefId: String, size: CGSize) async throws -> UIImage? {
        let start = EditorDebugTrace.mark()
        let stream = try loadThumbnailStream(for: assetRefId, size: size)
        var latest: UIImage?
        for await update in stream {
            if let image = update.image { latest = image }
            if update.isFinal { break }
        }
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
        if elapsedMs > 150 {
            EditorDebugTrace.log(
                "ThumbnailService",
                "slow thumbnail load assetRefId=\(assetRefId) elapsed=\(String(format: "%.1fms", elapsedMs))"
            )
        }
        return latest
    }

    func loadWaveformImage(for media: Media) async -> UIImage? {
        // Waveform generation requires DSWaveformImage dependency.
        // Returns nil until that package is added.
        return nil
    }

    func loadThumbnailStripImage(for media: Media) async -> UIImage? {
        if let path = media.spec.thumbnailStripPath,
           let image = cachedThumbnailStrip(forPath: path) {
            return image
        }

        do {
            guard let url = try await loadVideoURL(for: media.assetRefId) else { return nil }
            guard let stripInfo = try await generateThumbnailStripIfNeeded(for: media, videoURL: url) else { return nil }
            _ = try db.updateMediaSpec(mediaId: media.mediaId) { spec in
                spec.thumbnailStripPath = stripInfo.path
                spec.thumbnailStripHeight = stripInfo.height
                spec.thumbnailStripFrameCount = stripInfo.frameCount
            }
            guard let resolvedStrip = AppSandboxFileURI.resolveFileURL(storedURI: stripInfo.path),
                  let image = UIImage(contentsOfFile: resolvedStrip.path) else { return nil }
            cacheThumbnailStrip(image, forPath: stripInfo.path)
            return image
        } catch {
            return nil
        }
    }

    func loadVideoThumbnails(for assetRefId: String, size: CGSize, times: [Double]) async throws -> [UIImage] {
        let start = EditorDebugTrace.mark()
        guard let url = try await loadVideoURL(for: assetRefId) else { return [] }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var images: [UIImage] = []
                images.reserveCapacity(times.count)
                for timeSeconds in times {
                    let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
                    do {
                        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                        images.append(UIImage(cgImage: cgImage))
                    } catch { continue }
                }
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
                if elapsedMs > 150 {
                    EditorDebugTrace.log(
                        "ThumbnailService",
                        "slow video thumbnail load assetRefId=\(assetRefId) requested=\(times.count) elapsed=\(String(format: "%.1fms", elapsedMs))"
                    )
                }
                continuation.resume(returning: images)
            }
        }
    }

    func loadVideoURL(for assetRefId: String) async throws -> URL? {
        guard let assetRef = try db.getAssetReference(assetRefId: assetRefId) else { return nil }

        if AppSandboxFileURI.isLikelySandboxFile(assetRef.uri) {
            return AppSandboxFileURI.resolveFileURL(storedURI: assetRef.uri)
        }

        let results = PHAsset.fetchAssets(withLocalIdentifiers: [assetRef.uri], options: nil)
        guard let asset = results.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func generateThumbnailStripIfNeeded(for media: Media, videoURL: URL) async throws -> ThumbnailStripInfo? {
        if let existing = existingThumbnailStripInfo(for: media) {
            return existing
        }

        let duration = max(media.spec.duration ?? 0, 0.01)
        let intervalFrames = Int(ceil(duration / thumbnailStripIntervalSeconds))
        let frameCount = max(1, min(thumbnailStripMaxFrames, intervalFrames))
        let height = media.spec.thumbnailStripHeight ?? Int(thumbnailStripHeight)
        let aspectRatio = resolvedAspectRatio(for: media)
        let url = try thumbnailStripURL(for: media.assetRefId)
        let request = ThumbnailStripGenerationRequest(
            key: media.assetRefId,
            outputPath: url.path,
            videoURL: videoURL,
            duration: duration,
            frameCount: frameCount,
            height: height,
            aspectRatio: aspectRatio
        )

        return try await stripGenerationCoordinator.run(request: request) { [self] request in
            if FileManager.default.fileExists(atPath: request.outputPath) {
                return ThumbnailStripInfo(
                    path: request.outputPath,
                    height: request.height,
                    frameCount: request.frameCount
                )
            }

            guard let stripImage = try await generateThumbnailStripImage(
                videoURL: request.videoURL,
                duration: request.duration,
                frameCount: request.frameCount,
                height: CGFloat(request.height),
                aspectRatio: request.aspectRatio
            ) else {
                return nil
            }

            return try await persistThumbnailStripImage(
                stripImage,
                to: URL(fileURLWithPath: request.outputPath),
                height: request.height,
                frameCount: request.frameCount
            )
        }
    }

    // MARK: - Private Helpers

    private func loadThumbnailStream(for fileURL: URL, size: CGSize, cacheKey: String?) -> AsyncStream<ThumbnailUpdate> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return immediateThumbnailStream(with: nil)
        }

        if let cacheKey, let image = cachedThumbnail(forKey: cacheKey) {
            return immediateThumbnailStream(with: image)
        }

        if isLikelyStillImageFile(fileURL), let image = UIImage(contentsOfFile: fileURL.path) {
            if let cacheKey {
                cacheThumbnail(image, forKey: cacheKey)
            }
            return immediateThumbnailStream(with: image)
        }

        return AsyncStream { continuation in
            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = size
            let time = CMTime(seconds: 0, preferredTimescale: 600)

            let lock = NSLock()
            var didFinish = false

            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                lock.lock()
                defer { lock.unlock() }
                guard !didFinish else { return }
                didFinish = true
                if let cgImage {
                    let image = UIImage(cgImage: cgImage)
                    if let cacheKey {
                        self.cacheThumbnail(image, forKey: cacheKey)
                    }
                    continuation.yield(ThumbnailUpdate(image: image, isFinal: true))
                } else {
                    continuation.yield(ThumbnailUpdate(image: nil, isFinal: true))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                generator.cancelAllCGImageGeneration()
            }
        }
    }

    private func resolvedAspectRatio(for media: Media) -> CGFloat {
        if let width = media.spec.width, let height = media.spec.height, width > 0, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 16.0 / 9.0
    }

    private func existingThumbnailStripInfo(for media: Media) -> ThumbnailStripInfo? {
        guard let rawPath = media.spec.thumbnailStripPath,
              let resolved = AppSandboxFileURI.resolveFileURL(storedURI: rawPath),
              FileManager.default.fileExists(atPath: resolved.path),
              let height = media.spec.thumbnailStripHeight,
              let frameCount = media.spec.thumbnailStripFrameCount else {
            return nil
        }

        return ThumbnailStripInfo(path: resolved.path, height: height, frameCount: frameCount)
    }

    private func generateThumbnailStripImage(
        videoURL: URL, duration: Double, frameCount: Int,
        height: CGFloat, aspectRatio: CGFloat
    ) async throws -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let segmentWidth = max(1, round(height * aspectRatio))
        let segmentSize = CGSize(width: segmentWidth, height: height)
        generator.maximumSize = segmentSize
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = tolerance
        generator.requestedTimeToleranceBefore = tolerance

        let safeDuration = max(duration, 0.01)
        let step = safeDuration / Double(frameCount)
        let times: [CMTime] = (0..<frameCount).map { index in
            CMTime(seconds: min(safeDuration, (Double(index) + 0.5) * step), preferredTimescale: 600)
        }
        let timeIndexByKey = Dictionary(uniqueKeysWithValues: times.enumerated().map { index, time in
            (timeKey(for: time), index)
        })

        return try await withCheckedThrowingContinuation { continuation in
            let requestTimes = times.map(NSValue.init(time:))
            let lock = NSLock()
            var frames = Array<CGImage?>(repeating: nil, count: times.count)
            var completedCount = 0
            var didResume = false

            generator.generateCGImagesAsynchronously(forTimes: requestTimes) { requestedTime, cgImage, _, _, _ in
                lock.lock()
                defer { lock.unlock() }

                guard !didResume else { return }
                if let index = timeIndexByKey[self.timeKey(for: requestedTime)] {
                    frames[index] = cgImage
                }

                completedCount += 1
                guard completedCount == requestTimes.count else { return }
                didResume = true

                DispatchQueue.global(qos: .utility).async {
                    let stripSize = CGSize(width: segmentSize.width * CGFloat(frames.count), height: segmentSize.height)
                    let renderer = UIGraphicsImageRenderer(size: stripSize)
                    var renderedFrameCount = 0
                    let stripImage = renderer.image { context in
                        UIColor.black.setFill()
                        context.fill(CGRect(origin: .zero, size: stripSize))

                        var x: CGFloat = 0
                        for frame in frames {
                            autoreleasepool {
                                if let frame {
                                    renderedFrameCount += 1
                                    UIImage(cgImage: frame).draw(
                                        in: CGRect(x: x, y: 0, width: segmentSize.width, height: segmentSize.height)
                                    )
                                }
                                x += segmentSize.width
                            }
                        }
                    }
                    continuation.resume(returning: renderedFrameCount > 0 ? stripImage : nil)
                }
            }
        }
    }

    private func thumbnailStripURL(for assetRefId: String) throws -> URL {
        let baseURL = try thumbnailStripDirectory()
        let sanitizedName = "\(assetRefId).jpg".replacingOccurrences(of: "/", with: "_")
        return baseURL.appendingPathComponent(sanitizedName)
    }

    private func thumbnailStripDirectory() throws -> URL {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let stripsURL = cachesURL.appendingPathComponent("ThumbnailStrips", isDirectory: true)
        if !FileManager.default.fileExists(atPath: stripsURL.path) {
            try FileManager.default.createDirectory(at: stripsURL, withIntermediateDirectories: true)
        }
        return stripsURL
    }

    private func persistThumbnailStripImage(
        _ image: UIImage,
        to url: URL,
        height: Int,
        frameCount: Int
    ) async throws -> ThumbnailStripInfo? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let data = image.jpegData(compressionQuality: self.thumbnailStripCompressionQuality) else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    try data.write(to: url, options: .atomic)
                    let storedPath = AppSandboxFileURI.canonicalStoredPath(forFileAt: url)
                    continuation.resume(
                        returning: ThumbnailStripInfo(path: storedPath, height: height, frameCount: frameCount)
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func immediateThumbnailStream(with image: UIImage?) -> AsyncStream<ThumbnailUpdate> {
        AsyncStream { continuation in
            continuation.yield(ThumbnailUpdate(image: image, isFinal: true))
            continuation.finish()
        }
    }

    private func thumbnailCacheKey(for assetRefId: String, size: CGSize) -> String {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        return "\(assetRefId)-\(width)x\(height)"
    }

    private func cacheThumbnail(_ image: UIImage, forKey key: String) {
        thumbnailCache.setObject(image, forKey: key as NSString)
    }

    private func cachedThumbnail(forKey key: String) -> UIImage? {
        thumbnailCache.object(forKey: key as NSString)
    }

    private func cacheThumbnailStrip(_ image: UIImage, forPath path: String) {
        thumbnailStripCache.setObject(image, forKey: path as NSString)
    }

    private func cachedThumbnailStrip(forPath path: String) -> UIImage? {
        if let image = thumbnailStripCache.object(forKey: path as NSString) {
            return image
        }
        guard let resolved = AppSandboxFileURI.resolveFileURL(storedURI: path),
              FileManager.default.fileExists(atPath: resolved.path),
              let image = UIImage(contentsOfFile: resolved.path) else {
            return nil
        }
        cacheThumbnailStrip(image, forPath: path)
        return image
    }

    private func isLikelyStillImageFile(_ url: URL) -> Bool {
        guard !url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private func timeKey(for time: CMTime) -> String {
        "\(time.value):\(time.timescale):\(time.epoch)"
    }
}
