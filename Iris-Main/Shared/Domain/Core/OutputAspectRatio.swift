import CoreGraphics
import Foundation

/// Integer width:height pair for playback / render canvas aspect (e.g. 16×9, 9×16).
struct OutputAspectRatio: Equatable, Hashable, Codable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// SwiftUI `aspectRatio` expects width/height.
    var aspectCGFloat: CGFloat {
        guard height > 0 else { return 16.0 / 9.0 }
        return CGFloat(width) / CGFloat(height)
    }

    /// Normalized pair with positive gcd-reduced values, or nil if invalid.
    func normalized() -> OutputAspectRatio? {
        guard width > 0, height > 0 else { return nil }
        let g = Self.gcd(width, height)
        return OutputAspectRatio(width: width / g, height: height / g)
    }

    /// Pixel output size with the longer side set to `longSide` (even dimensions).
    func pixelSize(longSide: Int = 1920) -> CGSize {
        guard longSide > 0, width > 0, height > 0 else {
            return CGSize(width: 1920, height: 1080)
        }
        let w = CGFloat(width)
        let h = CGFloat(height)
        let out: CGSize
        if w >= h {
            let ow = CGFloat(longSide)
            let oh = ow * h / w
            out = CGSize(width: ow, height: oh)
        } else {
            let oh = CGFloat(longSide)
            let ow = oh * w / h
            out = CGSize(width: ow, height: oh)
        }
        let rw = max(2, Int(out.width.rounded(.toNearestOrAwayFromZero)))
        let rh = max(2, Int(out.height.rounded(.toNearestOrAwayFromZero)))
        return CGSize(width: Self.makeEven(rw), height: Self.makeEven(rh))
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let t = y
            y = x % y
            x = t
        }
        return max(x, 1)
    }

    private static func makeEven(_ v: Int) -> CGFloat {
        let e = v - (v % 2)
        return CGFloat(max(2, e))
    }
}
