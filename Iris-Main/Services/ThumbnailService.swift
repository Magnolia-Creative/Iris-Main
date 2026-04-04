import Foundation
import Photos
import UIKit
import AVFoundation
import SwiftUI

struct ThumbnailUpdate {
    let image: UIImage?
    let isFinal: Bool
}

final class ThumbnailService {
    static let shared = ThumbnailService()
    private let db = DatabaseManager.shared
    private let thumbnailStripHeight: CGFloat = .spacing(.sp10)
    private let thumbnailStripIntervalSeconds: Double = 1.0
    private let thumbnailStripMaxFrames: Int = 120

    private init() {}

    struct ThumbnailStripInfo {
        let path: String
        let height: Int
        let frameCount: Int
    }

    func loadThumbnailStream(for asset: PHAsset, size: CGSize) -> AsyncStream<ThumbnailUpdate> {
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
        guard let assetRef = try db.getAssetReference(assetRefId: assetRefId) else {
            return AsyncStream { continuation in
                continuation.yield(ThumbnailUpdate(image: nil, isFinal: true))
                continuation.finish()
            }
        }

        let results = PHAsset.fetchAssets(withLocalIdentifiers: [assetRef.uri], options: nil)
        if let asset = results.firstObject {
            return loadThumbnailStream(for: asset, size: size)
        }

        let fileURL = URL(fileURLWithPath: assetRef.uri)
        return loadThumbnailStream(for: fileURL, size: size)
    }

    func loadThumbnail(for assetRefId: String, size: CGSize) async throws -> UIImage? {
        let stream = try loadThumbnailStream(for: assetRefId, size: size)
        var latest: UIImage?
        for await update in stream {
            if let image = update.image { latest = image }
            if update.isFinal { break }
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
           FileManager.default.fileExists(atPath: path),
           let image = UIImage(contentsOfFile: path) {
            return image
        }

        do {
            guard let url = try await loadVideoURL(for: media.assetRefId) else { return nil }
            guard let stripInfo = try await generateThumbnailStripIfNeeded(for: media, videoURL: url) else { return nil }
            var updatedMedia = media
            updatedMedia.spec.thumbnailStripPath = stripInfo.path
            updatedMedia.spec.thumbnailStripHeight = stripInfo.height
            updatedMedia.spec.thumbnailStripFrameCount = stripInfo.frameCount
            updatedMedia.updatedAt = Date()
            try db.update(updatedMedia)
            return UIImage(contentsOfFile: stripInfo.path)
        } catch {
            return nil
        }
    }

    func loadVideoThumbnails(for assetRefId: String, size: CGSize, times: [Double]) async throws -> [UIImage] {
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
                continuation.resume(returning: images)
            }
        }
    }

    func loadVideoURL(for assetRefId: String) async throws -> URL? {
        guard let assetRef = try db.getAssetReference(assetRefId: assetRefId) else { return nil }

        if assetRef.uri.hasPrefix("/"), FileManager.default.fileExists(atPath: assetRef.uri) {
            return URL(fileURLWithPath: assetRef.uri)
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
        if let path = media.spec.thumbnailStripPath,
           FileManager.default.fileExists(atPath: path),
           let height = media.spec.thumbnailStripHeight,
           let frameCount = media.spec.thumbnailStripFrameCount {
            return ThumbnailStripInfo(path: path, height: height, frameCount: frameCount)
        }

        let duration = max(media.spec.duration ?? 0, 0.01)
        let intervalFrames = Int(ceil(duration / thumbnailStripIntervalSeconds))
        let frameCount = max(1, min(thumbnailStripMaxFrames, intervalFrames))
        let height = media.spec.thumbnailStripHeight ?? Int(thumbnailStripHeight)
        let aspectRatio = resolvedAspectRatio(for: media)

        guard let stripImage = try await generateThumbnailStripImage(
            videoURL: videoURL, duration: duration, frameCount: frameCount,
            height: CGFloat(height), aspectRatio: aspectRatio
        ) else { return nil }

        let url = try thumbnailStripURL(for: media.assetRefId)
        if let data = stripImage.pngData() {
            try data.write(to: url, options: .atomic)
            return ThumbnailStripInfo(path: url.path, height: height, frameCount: frameCount)
        }
        return nil
    }

    // MARK: - Private Helpers

    private func loadThumbnailStream(for fileURL: URL, size: CGSize) -> AsyncStream<ThumbnailUpdate> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AsyncStream { continuation in
                continuation.yield(ThumbnailUpdate(image: nil, isFinal: true))
                continuation.finish()
            }
        }

        if let image = UIImage(contentsOfFile: fileURL.path) {
            return AsyncStream { continuation in
                continuation.yield(ThumbnailUpdate(image: image, isFinal: true))
                continuation.finish()
            }
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
                    continuation.yield(ThumbnailUpdate(image: UIImage(cgImage: cgImage), isFinal: true))
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
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        let safeDuration = max(duration, 0.01)
        let step = safeDuration / Double(frameCount)
        let times: [CMTime] = (0..<frameCount).map { index in
            CMTime(seconds: min(safeDuration, (Double(index) + 0.5) * step), preferredTimescale: 600)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var frames: [UIImage] = []
                frames.reserveCapacity(times.count)
                for time in times {
                    do {
                        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                        frames.append(UIImage(cgImage: cgImage))
                    } catch { continue }
                }
                let stripImage = self.stitchThumbnailStrip(frames: frames, segmentSize: segmentSize)
                continuation.resume(returning: stripImage)
            }
        }
    }

    private func stitchThumbnailStrip(frames: [UIImage], segmentSize: CGSize) -> UIImage? {
        guard !frames.isEmpty else { return nil }
        let stripSize = CGSize(width: segmentSize.width * CGFloat(frames.count), height: segmentSize.height)
        let renderer = UIGraphicsImageRenderer(size: stripSize)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: stripSize))
            var x: CGFloat = 0
            for frame in frames {
                frame.draw(in: CGRect(x: x, y: 0, width: segmentSize.width, height: segmentSize.height))
                x += segmentSize.width
            }
        }
    }

    private func thumbnailStripURL(for assetRefId: String) throws -> URL {
        let baseURL = try thumbnailStripDirectory()
        let sanitizedName = "\(assetRefId).png".replacingOccurrences(of: "/", with: "_")
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
}
