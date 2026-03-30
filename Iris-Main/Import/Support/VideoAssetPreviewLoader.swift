@preconcurrency import AVFoundation
import Foundation

enum VideoAssetPreviewLoader {
    static func loadDuration(for videoURL: URL) async -> Double {
        let asset = AVURLAsset(url: videoURL)

        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            return seconds.isFinite && seconds > 0 ? seconds : 0
        } catch {
            return 0
        }
    }

    static func generateThumbnail(for videoURL: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 800, height: 800)
            let requestTime = CMTime(seconds: 0.1, preferredTimescale: 600)

            return await withCheckedContinuation { continuation in
                generator.generateCGImageAsynchronously(for: requestTime) { image, _, error in
                    continuation.resume(returning: error == nil ? image : nil)
                }
            }
        }.value
    }
}
