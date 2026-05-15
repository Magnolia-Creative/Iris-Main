import Foundation
import Metal
import VideoLab

/// Caches Metal `Texture` LUTs built from `RenderColorAdjustmentsInput` for VideoLab `LookupFilter`.
enum VideoLabColorAdjustmentLUT {
    private static let lutSide = 512
    private static let bytesPerRow = lutSide * 4

    private static let cache = NSCache<NSString, Texture>()
    private static let cacheLock = NSLock()

    static func texture(for adjustments: RenderColorAdjustmentsInput) -> Texture? {
        let key = VideoLabColorAdjustmentLUTCore.cacheKey(for: adjustments) as NSString
        cacheLock.lock()
        if let cached = cache.object(forKey: key) {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let mtlTexture = makeLUTMetalTexture(for: adjustments) else { return nil }
        let texture = Texture(texture: mtlTexture)

        cacheLock.lock()
        cache.setObject(texture, forKey: key)
        cacheLock.unlock()
        return texture
    }

    /// Builds a `bgra8Unorm` 512×512 texture from CPU-packed HALD bytes (same layout VideoLab uses for video frames).
    private static func makeLUTMetalTexture(for adjustments: RenderColorAdjustmentsInput) -> MTLTexture? {
        let pixels = VideoLabColorAdjustmentLUTCore.makeLUTBGRA8PixelData(for: adjustments)
        precondition(pixels.count == lutSide * lutSide * 4)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: lutSide,
            height: lutSide,
            mipmapped: false
        )
        desc.usage = [.shaderRead]

        guard let mtlTexture = sharedMetalRenderingDevice.device.makeTexture(descriptor: desc) else {
            return nil
        }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: lutSide, height: lutSide, depth: 1)
        )
        pixels.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            mtlTexture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: bytesPerRow
            )
        }
        return mtlTexture
    }
}
