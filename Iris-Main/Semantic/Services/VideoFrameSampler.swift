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
        var targetTimestamps: [Double] = []
        var current = clampedStart
        while current <= clampedEnd {
            targetTimestamps.append((current == 0) ? min(0.1, clampedEnd) : current)
            current += stepSeconds
        }

        let samples = try await generateFrames(
            for: asset,
            videoURL: videoURL,
            targetTimestamps: targetTimestamps,
            timescale: timescale,
            maximumDimension: maximumDimension,
            logPrefix: "[SemanticIndex] sampleFrames"
        )
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
        let targetTimestamps = timestamps.map { timestamp in
            let clamped = min(max(0, timestamp), videoDuration)
            return (clamped == 0) ? min(0.1, videoDuration) : clamped
        }
        let samples = try await generateFrames(
            for: asset,
            videoURL: videoURL,
            targetTimestamps: targetTimestamps,
            timescale: timescale,
            maximumDimension: maximumDimension,
            logPrefix: "[SemanticIndex] sampleFrames(atTimestamps)"
        )
        print("[SemanticIndex] sampleFrames(atTimestamps) done url=\(videoURL.lastPathComponent) count=\(samples.count)")
        return samples
    }

    private func generateFrames(
        for asset: AVURLAsset,
        videoURL: URL,
        targetTimestamps: [Double],
        timescale: CMTimeScale,
        maximumDimension: CGFloat?,
        logPrefix: String
    ) async throws -> [SampledVideoFrame] {
        try Task.checkCancellation()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maximumDimension, maximumDimension > 0 {
            generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
        }
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: timescale)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: timescale)

        let requestTimes = targetTimestamps.map { CMTime(seconds: $0, preferredTimescale: timescale) }
        let requestValues = requestTimes.map(NSValue.init(time:))
        let timeIndexByKey = Dictionary(uniqueKeysWithValues: requestTimes.enumerated().map { index, time in
            (timeKey(for: time), index)
        })

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let lock = NSLock()
                var frames = Array<CGImage?>(repeating: nil, count: requestTimes.count)
                var failures = 0
                var firstFailureDescription: String?
                var completedCount = 0
                var didResume = false

                generator.generateCGImagesAsynchronously(forTimes: requestValues) { requestedTime, image, _, result, error in
                    lock.lock()
                    defer { lock.unlock() }

                    guard !didResume else { return }

                    if let index = timeIndexByKey[self.timeKey(for: requestedTime)] {
                        switch result {
                        case .succeeded:
                            frames[index] = image
                        case .failed, .cancelled:
                            failures += 1
                            if firstFailureDescription == nil {
                                firstFailureDescription = error?.localizedDescription
                            }
                            let targetTime = targetTimestamps[index]
                            let reason = error?.localizedDescription ?? String(describing: result)
                            print("\(logPrefix) async frame generation failed at \(targetTime)s for \(videoURL.lastPathComponent): \(reason)")
                        @unknown default:
                            failures += 1
                            if firstFailureDescription == nil {
                                firstFailureDescription = "Unknown AVAssetImageGenerator result."
                            }
                        }
                    }

                    completedCount += 1
                    guard completedCount == requestValues.count else { return }
                    didResume = true

                    let samples = frames.enumerated().compactMap { index, image in
                        image.map { SampledVideoFrame(timestampSeconds: targetTimestamps[index], image: $0) }
                    }

                    if samples.isEmpty {
                        let details = firstFailureDescription ?? "Unknown frame extraction failure."
                        continuation.resume(throwing: VideoFrameSamplerError.allFramesFailed(details: details))
                        return
                    }

                    if failures > 0 {
                        print("\(logPrefix) partial failures for \(videoURL.lastPathComponent): failures=\(failures) successes=\(samples.count)")
                    }
                    continuation.resume(returning: samples)
                }
            }
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }

    private func timeKey(for time: CMTime) -> String {
        "\(time.value):\(time.timescale):\(time.epoch)"
    }
}
