import Foundation

/// Integer width:height pair for playback / render canvas aspect (e.g. 16×9, 9×16).
struct OutputAspectRatio: Equatable, Hashable, Codable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var aspectRatio: Double {
        guard height > 0 else { return 16.0 / 9.0 }
        return Double(width) / Double(height)
    }

    /// Normalized pair with positive gcd-reduced values.
    func normalized() -> OutputAspectRatio {
        guard width > 0, height > 0 else { return self }
        let g = Self.gcd(width, height)
        return OutputAspectRatio(width: width / g, height: height / g)
    }

    /// Pixel output size with the longer side set to `longSide` (even dimensions).
    func pixelSize(longSide: Int = 1920) -> OutputPixelSize {
        guard longSide > 0, width > 0, height > 0 else {
            return OutputPixelSize(width: 1920, height: 1080)
        }
        let w = Double(width)
        let h = Double(height)
        let outWidth: Double
        let outHeight: Double
        if w >= h {
            outWidth = Double(longSide)
            outHeight = outWidth * h / w
        } else {
            outHeight = Double(longSide)
            outWidth = outHeight * w / h
        }
        let roundedWidth = max(2, Int(outWidth.rounded(.toNearestOrAwayFromZero)))
        let roundedHeight = max(2, Int(outHeight.rounded(.toNearestOrAwayFromZero)))
        return OutputPixelSize(width: Self.makeEven(roundedWidth), height: Self.makeEven(roundedHeight))
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

    private static func makeEven(_ v: Int) -> Int {
        let e = v - (v % 2)
        return max(2, e)
    }
}

struct OutputPixelSize: Equatable, Hashable, Codable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
