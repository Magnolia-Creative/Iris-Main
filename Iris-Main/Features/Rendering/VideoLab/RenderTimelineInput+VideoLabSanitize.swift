import CoreGraphics
import Foundation

extension RenderTimelineInput {
    /// Clamp `outputSize` to finite, bounded dimensions suitable for `RenderComposition.renderSize`.
    func sanitizedForVideoLabRendering() -> RenderTimelineInput {
        let clamped = Self.sanitizeOutputSize(outputSize)
        if clamped.width == outputSize.width, clamped.height == outputSize.height {
            return self
        }
        #if DEBUG
        VideoLabPreviewDiagnostics.logOutputSizeSanitized(from: outputSize, to: clamped)
        #endif
        return RenderTimelineInput(
            tracks: tracks,
            captions: captions,
            outputSize: clamped,
            duration: duration
        )
    }

    private static func sanitizeOutputSize(_ size: CGSize) -> CGSize {
        let minSide: CGFloat = 2
        let maxSide: CGFloat = 8192
        guard size.width.isFinite, size.height.isFinite,
              size.width >= minSide, size.height >= minSide,
              size.width <= maxSide, size.height <= maxSide
        else {
            return CGSize(width: 1920, height: 1080)
        }
        return CGSize(
            width: max(minSide, min(maxSide, round(size.width))),
            height: max(minSide, min(maxSide, round(size.height)))
        )
    }
}
