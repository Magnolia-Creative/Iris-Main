import CoreGraphics
import Foundation
import simd
import UIKit
import VideoLab

/// Builds VideoLab-compatible 512×512 HALD LUT textures from `RenderColorAdjustmentsInput`.
enum VideoLabColorAdjustmentLUT {
    private static let cache = NSCache<NSString, Texture>()
    private static let cacheLock = NSLock()

    /// Pure mapping used for LUT texels and unit tests.
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

    /// Quantized cache key so scrubbing reuses identical LUT textures when possible.
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

    static func texture(for adjustments: RenderColorAdjustmentsInput) -> Texture? {
        let key = cacheKey(for: adjustments) as NSString
        cacheLock.lock()
        if let cached = cache.object(forKey: key) {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let cgImage = makeLUTCGImage(for: adjustments) else { return nil }
        guard let texture = Texture.makeTexture(cgImage: cgImage) else { return nil }

        cacheLock.lock()
        cache.setObject(texture, forKey: key)
        cacheLock.unlock()
        return texture
    }

    private static func makeLUTCGImage(for adjustments: RenderColorAdjustmentsInput) -> CGImage? {
        let width = 512
        let height = 512
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
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
                    pixels[o] = UInt8(mapped.z * 255.0 + 0.5)
                    pixels[o + 1] = UInt8(mapped.y * 255.0 + 0.5)
                    pixels[o + 2] = UInt8(mapped.x * 255.0 + 0.5)
                    pixels[o + 3] = 255
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let denom = max(edge1 - edge0, 1e-6)
        let t = simd_clamp((x - edge0) / denom, 0, 1)
        return t * t * (3 - 2 * t)
    }
}
