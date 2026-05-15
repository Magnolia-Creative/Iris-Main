import Foundation
import VideoLab

/// Caches Metal `Texture` LUTs built from `RenderColorAdjustmentsInput` for VideoLab `LookupFilter`.
enum VideoLabColorAdjustmentLUT {
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

        guard let cgImage = VideoLabColorAdjustmentLUTCore.makeLUTCGImage(for: adjustments) else { return nil }
        guard let texture = Texture.makeTexture(cgImage: cgImage) else { return nil }

        cacheLock.lock()
        cache.setObject(texture, forKey: key)
        cacheLock.unlock()
        return texture
    }
}
