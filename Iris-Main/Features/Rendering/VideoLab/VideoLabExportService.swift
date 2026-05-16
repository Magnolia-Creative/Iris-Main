import AVFoundation
import Foundation
import VideoLab

enum VideoLabExportError: Error, LocalizedError {
    case noExportSession
    case exportFailed(status: AVAssetExportSession.Status, underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .noExportSession:
            return "Could not create export session."
        case .exportFailed(_, let underlying):
            return underlying?.localizedDescription ?? "Export failed."
        }
    }
}

enum VideoLabExportService {
    static func presetName(for outputWidth: CGFloat) -> String {
        AVAssetExportPresetMediumQuality
    }

    static func export(
        input: RenderTimelineInput,
        outputURL: URL,
        frameRate: Int,
        presetName: String? = nil,
        progress: @escaping (Float) -> Void
    ) async throws {
        let preset = presetName ?? Self.presetName(for: input.outputSize.width)
        let videoLab = await VideoLabTimelineAdapter.makeVideoLabAsync(from: input, frameRate: frameRate)
        guard let session = videoLab.makeExportSession(presetName: preset, outputURL: outputURL) else {
            throw VideoLabExportError.noExportSession
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                progress(session.progress)
            }
            RunLoop.main.add(timer, forMode: .common)

            session.exportAsynchronously {
                timer.invalidate()
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(
                        throwing: VideoLabExportError.exportFailed(status: session.status, underlying: session.error)
                    )
                case .cancelled:
                    continuation.resume(
                        throwing: VideoLabExportError.exportFailed(status: session.status, underlying: session.error)
                    )
                default:
                    continuation.resume(
                        throwing: VideoLabExportError.exportFailed(status: session.status, underlying: session.error)
                    )
                }
            }
        }
    }
}
