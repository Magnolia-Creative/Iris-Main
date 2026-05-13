import Foundation

/// One JPEG still for a semantic chunk window, written to a temp file for multipart upload.
struct VisualFrameUploadChunk: Sendable {
    let chunkIndex: Int
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let centerTimeSeconds: Double
    let fileURL: URL
    /// `filename` in `Content-Disposition` and in `visual_frame_manifest` (must match uploaded part).
    let formFilename: String
}
