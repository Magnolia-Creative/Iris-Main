import CoreGraphics

extension OutputAspectRatio {
    /// SwiftUI `aspectRatio` expects width/height as a CGFloat.
    var aspectCGFloat: CGFloat {
        CGFloat(aspectRatio)
    }

    func cgPixelSize(longSide: Int = 1920) -> CGSize {
        pixelSize(longSide: longSide).cgSize
    }
}

extension OutputPixelSize {
    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}
