import CoreGraphics
import Foundation
import UIKit

/// Builds per-chunk JPEG stills for backend multimodal indexing, using the same 4s / 0.5s overlap windows used by the backend indexing API.
enum SemanticUploadFrameSampling {
    /// Maximum image dimension for uploaded frames.
    static let uploadFrameMaximumDimension: CGFloat = 640

    /// Produces overlapping time windows for backend indexing uploads.
    static func chunkTimeWindows(durationSeconds: Double) -> [(start: Double, end: Double, center: Double)] {
        guard durationSeconds > 0 else { return [] }

        let chunkDuration = min(4.0, durationSeconds)
        guard chunkDuration > 0 else { return [] }

        if durationSeconds <= chunkDuration {
            return [(0, durationSeconds, durationSeconds / 2)]
        }

        let stride = 3.5
        var starts: [Double] = []
        var currentStart = 0.0

        while currentStart + chunkDuration < durationSeconds {
            starts.append(currentStart)
            currentStart += stride
        }

        let finalStart = max(0, durationSeconds - chunkDuration)
        if !starts.isEmpty {
            if abs(starts.last! - finalStart) > 0.001 {
                starts.append(finalStart)
            }
        } else {
            starts.append(finalStart)
        }

        return starts.map { start in
            let end = min(start + chunkDuration, durationSeconds)
            let center = min(durationSeconds, start + (end - start) / 2)
            return (start, end, center)
        }
    }

    static func safeFormFilenameToken(from localKey: String) -> String {
        let mapped = localKey.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                return ch
            }
            return "_"
        }
        let collapsed = String(mapped)
        if collapsed.count <= 64 {
            return collapsed.isEmpty ? "clip" : collapsed
        }
        return String(collapsed.prefix(64))
    }

    /// Samples the center frame of each chunk window, encodes JPEG, writes temp files.
    static func buildJPEGFramesForUpload(
        videoURL: URL,
        localKey: String,
        frameSampler: any VideoFrameSampling = VideoFrameSampler()
    ) async throws -> [VisualFrameUploadChunk] {
        let duration = try await frameSampler.loadDurationSeconds(videoURL: videoURL)
        let windows = chunkTimeWindows(durationSeconds: duration)
        guard !windows.isEmpty else { return [] }

        let centers = windows.map(\.center)
        let samples = try await frameSampler.sampleFrames(
            videoURL: videoURL,
            atTimestamps: centers,
            maximumDimension: uploadFrameMaximumDimension
        )

        let token = safeFormFilenameToken(from: localKey)
        let paired = zip(windows, samples)
        var chunks: [VisualFrameUploadChunk] = []

        for (chunkIndex, pair) in paired.enumerated() {
            let (window, sample) = pair
            let formFilename = "vf_\(token)_\(chunkIndex).jpg"
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("iris-upload-\(UUID().uuidString)-\(formFilename)")

            let image = UIImage(cgImage: sample.image)
            guard let data = image.jpegData(compressionQuality: 0.82) else {
                continue
            }
            try data.write(to: fileURL, options: .atomic)
            chunks.append(
                VisualFrameUploadChunk(
                    chunkIndex: chunkIndex,
                    startTimeSeconds: window.start,
                    endTimeSeconds: window.end,
                    centerTimeSeconds: window.center,
                    fileURL: fileURL,
                    formFilename: formFilename
                )
            )
        }

        return chunks
    }
}
