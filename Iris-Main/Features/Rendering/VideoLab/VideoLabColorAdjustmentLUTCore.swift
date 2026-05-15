import Foundation
import simd

/// Pure color math and 512×512 HALD LUT pixel data (no VideoLab / Metal import).
enum VideoLabColorAdjustmentLUTCore {
    static func mapRGB(_ rgb: SIMD3<Float>, adjustments: RenderColorAdjustmentsInput) -> SIMD3<Float> {
        var out = rgb
        let temperature = adjustments.temperature
        let tint = adjustments.tint
        let exposure = adjustments.exposure
        let brightness = adjustments.brightness
        let contrast = adjustments.contrast
        let saturation = adjustments.saturation
        let highlights = adjustments.highlights
        let shadows = adjustments.shadows

        out *= pow(2, exposure)
        out.x += temperature * 0.10
        out.z -= temperature * 0.10
        out.x += tint * 0.06
        out.y -= tint * 0.10
        out.z += tint * 0.06
        out += SIMD3<Float>(repeating: brightness * 0.50)

        let luma = simd_dot(out, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        out += highlights * 0.25 * smoothstep(0.45, 1.0, luma)
        out += shadows * 0.25 * (1.0 - smoothstep(0.0, 0.55, luma))

        out = (out - 0.5) * (1.0 + contrast) + 0.5
        let lumaForSat = simd_dot(out, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        let satMix = simd_clamp(1.0 + saturation, 0.0, 2.0)
        let gray = SIMD3<Float>(repeating: lumaForSat)
        out = gray + (out - gray) * satMix
        return simd_clamp(out, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }

    static func cacheKey(for adjustments: RenderColorAdjustmentsInput) -> String {
        func q(_ v: Float) -> Int { Int((v * 512).rounded()) }
        return [
            q(adjustments.temperature),
            q(adjustments.tint),
            q(adjustments.exposure),
            q(adjustments.brightness),
            q(adjustments.contrast),
            q(adjustments.saturation),
            q(adjustments.highlights),
            q(adjustments.shadows),
        ].map(String.init).joined(separator: "|")
    }

    /// 512×512×4 **BGRA8** bytes (opaque), row-major with **y = 0 at top**.
    /// Matches `MTLPixelFormat.bgra8Unorm` channel order for VideoLab’s `LookupFilter` sampling.
    static func makeLUTBGRA8PixelData(for adjustments: RenderColorAdjustmentsInput) -> [UInt8] {
        let width = 512
        let height = 512
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for b in 0 ..< 64 {
            let tileX = b % 8
            let tileY = b / 8
            for g in 0 ..< 64 {
                for r in 0 ..< 64 {
                    let rin = Float(r) / 63.0
                    let gin = Float(g) / 63.0
                    let bin = Float(b) / 63.0
                    let mapped = mapRGB(SIMD3<Float>(rin, gin, bin), adjustments: adjustments)
                    let px = tileX * 64 + r
                    let py = tileY * 64 + g
                    let o = (py * width + px) * bytesPerPixel
                    // BGRA little-endian word layout (B lowest address).
                    pixels[o] = UInt8(mapped.z * 255.0 + 0.5)
                    pixels[o + 1] = UInt8(mapped.y * 255.0 + 0.5)
                    pixels[o + 2] = UInt8(mapped.x * 255.0 + 0.5)
                    pixels[o + 3] = 255
                }
            }
        }
        return pixels
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let denom = max(edge1 - edge0, 1e-6)
        let t = simd_clamp((x - edge0) / denom, 0, 1)
        return t * t * (3 - 2 * t)
    }
}
