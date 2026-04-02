import AVFoundation
import CoreGraphics
import Foundation

struct SampledVideoFrame {
    let timestampSeconds: Double
    let image: CGImage
}

enum VideoFrameSamplerError: LocalizedError {
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Video has an invalid duration."
        }
    }
}

struct VideoFrameSampler {
    func loadDurationSeconds(videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw VideoFrameSamplerError.invalidDuration
        }
        return seconds
    }

    func sampleFrames(
        videoURL: URL,
        startTime: Double = 0,
        endTime: Double? = nil,
        stepSeconds: Double
    ) async throws -> [SampledVideoFrame] {
        print("[SemanticIndex] sampleFrames start url=\(videoURL.lastPathComponent) start=\(startTime)s end=\(endTime ?? -1)s step=\(stepSeconds)s")
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let videoDuration = CMTimeGetSeconds(duration)
        guard videoDuration.isFinite, videoDuration > 0 else {
            print("[SemanticIndex] sampleFrames invalid duration for \(videoURL.lastPathComponent): \(videoDuration)")
            throw VideoFrameSamplerError.invalidDuration
        }

        let clampedStart = max(0, startTime)
        let clampedEnd = min(endTime ?? videoDuration, videoDuration)
        guard clampedEnd > clampedStart, stepSeconds > 0 else {
            print("[SemanticIndex] sampleFrames produced empty time window for \(videoURL.lastPathComponent)")
            return []
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        var samples: [SampledVideoFrame] = []
        var current = clampedStart
        let timescale = CMTimeScale(NSEC_PER_SEC)

        while current <= clampedEnd {
            let requestedTime = CMTime(seconds: current, preferredTimescale: timescale)
            do {
                let image = try generator.copyCGImage(at: requestedTime, actualTime: nil)
                samples.append(SampledVideoFrame(timestampSeconds: current, image: image))
            } catch {
                print("[SemanticIndex] copyCGImage failed at \(current)s for \(videoURL.lastPathComponent): \(error)")
                throw error
            }
            current += stepSeconds
        }

        print("[SemanticIndex] sampleFrames done url=\(videoURL.lastPathComponent) count=\(samples.count)")
        return samples
    }
}
