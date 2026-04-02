import AVFoundation
import CoreGraphics
import Foundation

struct SampledVideoFrame {
    let timestampSeconds: Double
    let image: CGImage
}

enum VideoFrameSamplerError: LocalizedError {
    case invalidDuration
    case mediaNotPlayable
    case protectedContent
    case noVideoTrack
    case allFramesFailed(details: String)

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Video has an invalid duration."
        case .mediaNotPlayable:
            return "Video asset is not marked as playable by AVFoundation."
        case .protectedContent:
            return "Video appears to be protected content and cannot be decoded for frame extraction."
        case .noVideoTrack:
            return "Video has no decodable video track."
        case .allFramesFailed(let details):
            return "Unable to extract any frames from this video. \(details)"
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
        stepSeconds: Double,
        maximumDimension: CGFloat? = nil
    ) async throws -> [SampledVideoFrame] {
        print("[SemanticIndex] sampleFrames start url=\(videoURL.lastPathComponent) start=\(startTime)s end=\(endTime ?? -1)s step=\(stepSeconds)s")
        let asset = AVURLAsset(url: videoURL)
        let isPlayable = try await asset.load(.isPlayable)
        if !isPlayable {
            print("[SemanticIndex] sampleFrames asset not playable for \(videoURL.lastPathComponent)")
            throw VideoFrameSamplerError.mediaNotPlayable
        }

        let hasProtectedContent = try await asset.load(.hasProtectedContent)
        if hasProtectedContent {
            print("[SemanticIndex] sampleFrames protected content for \(videoURL.lastPathComponent)")
            throw VideoFrameSamplerError.protectedContent
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if videoTracks.isEmpty {
            print("[SemanticIndex] sampleFrames no video tracks for \(videoURL.lastPathComponent)")
            throw VideoFrameSamplerError.noVideoTrack
        }

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

        let timescale = CMTimeScale(NSEC_PER_SEC)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maximumDimension, maximumDimension > 0 {
            generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
        }
        // Allow nearby frame decode when exact timestamp has no keyframe.
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: timescale)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: timescale)

        var samples: [SampledVideoFrame] = []
        var current = clampedStart
        var failures = 0
        var firstFailureDescription: String?

        while current <= clampedEnd {
            // Avoid strict zero-second extraction which often fails on some MP4s.
            let targetTime = (current == 0) ? min(0.1, clampedEnd) : current
            let requestedTime = CMTime(seconds: targetTime, preferredTimescale: timescale)
            do {
                let image = try generator.copyCGImage(at: requestedTime, actualTime: nil)
                samples.append(SampledVideoFrame(timestampSeconds: targetTime, image: image))
            } catch {
                failures += 1
                if firstFailureDescription == nil {
                    firstFailureDescription = error.localizedDescription
                }
                print("[SemanticIndex] copyCGImage failed at \(current)s for \(videoURL.lastPathComponent): \(error)")
            }
            current += stepSeconds
        }

        if samples.isEmpty {
            let details = firstFailureDescription ?? "Unknown frame extraction failure."
            throw VideoFrameSamplerError.allFramesFailed(details: details)
        }

        if failures > 0 {
            print("[SemanticIndex] sampleFrames partial failures for \(videoURL.lastPathComponent): failures=\(failures) successes=\(samples.count)")
        }
        print("[SemanticIndex] sampleFrames done url=\(videoURL.lastPathComponent) count=\(samples.count)")
        return samples
    }

    func sampleFrames(
        videoURL: URL,
        atTimestamps timestamps: [Double],
        maximumDimension: CGFloat? = nil
    ) async throws -> [SampledVideoFrame] {
        guard !timestamps.isEmpty else { return [] }

        print("[SemanticIndex] sampleFrames(atTimestamps) start url=\(videoURL.lastPathComponent) requested=\(timestamps.count)")
        let asset = AVURLAsset(url: videoURL)
        let isPlayable = try await asset.load(.isPlayable)
        if !isPlayable {
            print("[SemanticIndex] sampleFrames(atTimestamps) asset not playable for \(videoURL.lastPathComponent)")
            throw VideoFrameSamplerError.mediaNotPlayable
        }

        let hasProtectedContent = try await asset.load(.hasProtectedContent)
        if hasProtectedContent {
            print("[SemanticIndex] sampleFrames(atTimestamps) protected content for \(videoURL.lastPathComponent)")
            throw VideoFrameSamplerError.protectedContent
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if videoTracks.isEmpty {
            print("[SemanticIndex] sampleFrames(atTimestamps) no video tracks for \(videoURL.lastPathComponent)")
            throw VideoFrameSamplerError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let videoDuration = CMTimeGetSeconds(duration)
        guard videoDuration.isFinite, videoDuration > 0 else {
            print("[SemanticIndex] sampleFrames(atTimestamps) invalid duration for \(videoURL.lastPathComponent): \(videoDuration)")
            throw VideoFrameSamplerError.invalidDuration
        }

        let timescale = CMTimeScale(NSEC_PER_SEC)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maximumDimension, maximumDimension > 0 {
            generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
        }
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: timescale)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: timescale)

        var samples: [SampledVideoFrame] = []
        var failures = 0
        var firstFailureDescription: String?

        for timestamp in timestamps {
            let clamped = min(max(0, timestamp), videoDuration)
            let targetTime = (clamped == 0) ? min(0.1, videoDuration) : clamped
            let requestedTime = CMTime(seconds: targetTime, preferredTimescale: timescale)
            do {
                let image = try generator.copyCGImage(at: requestedTime, actualTime: nil)
                samples.append(SampledVideoFrame(timestampSeconds: targetTime, image: image))
            } catch {
                failures += 1
                if firstFailureDescription == nil {
                    firstFailureDescription = error.localizedDescription
                }
                print("[SemanticIndex] sampleFrames(atTimestamps) copyCGImage failed at \(targetTime)s for \(videoURL.lastPathComponent): \(error)")
            }
        }

        if samples.isEmpty {
            let details = firstFailureDescription ?? "Unknown frame extraction failure."
            throw VideoFrameSamplerError.allFramesFailed(details: details)
        }

        if failures > 0 {
            print("[SemanticIndex] sampleFrames(atTimestamps) partial failures for \(videoURL.lastPathComponent): failures=\(failures) successes=\(samples.count)")
        }
        print("[SemanticIndex] sampleFrames(atTimestamps) done url=\(videoURL.lastPathComponent) count=\(samples.count)")
        return samples
    }
}
