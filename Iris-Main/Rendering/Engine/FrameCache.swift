import Metal
import QuartzCore

final class FrameCache {
    struct CacheKey: Hashable {
        let clipID: UUID
        let timeMs: Int

        /// Quantizes the source time to a 1/30fps grid so that both the
        /// prefetch scheduler (which steps at 1/30s) and the render loop
        /// (which steps at display-refresh rate) produce the same key for
        /// the same underlying source frame.
        init(clipID: UUID, time: Double) {
            self.clipID = clipID
            let quantum = 1.0 / 30.0
            let quantized = (time / quantum).rounded() * quantum
            self.timeMs = Int((quantized * 1000).rounded())
        }
    }

    private struct Entry {
        let texture: MTLTexture
        var lastAccess: CFTimeInterval
        let byteSize: Int
    }

    private var entries: [CacheKey: Entry] = [:]
    private let maxBytes: Int
    private var currentBytes: Int = 0
    private let lock = NSLock()

    init(maxBytes: Int = 256 * 1024 * 1024) {
        self.maxBytes = maxBytes
    }

    func get(_ key: CacheKey) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        entry.lastAccess = CACurrentMediaTime()
        entries[key] = entry
        return entry.texture
    }

    /// Finds the closest cached texture for a clip within a tolerance window.
    /// Use as a fallback when the quantized key produces a miss (e.g. during
    /// fast scrubbing where prefetch hasn't caught up yet).
    func nearest(clipID: UUID, time: Double, toleranceMs: Int = 100) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        let targetMs = Int((time * 1000).rounded())
        var bestEntry: Entry?
        var bestDist = Int.max
        for (key, entry) in entries where key.clipID == clipID {
            let dist = abs(key.timeMs - targetMs)
            if dist < bestDist && dist <= toleranceMs {
                bestDist = dist
                bestEntry = entry
            }
        }
        if var entry = bestEntry {
            entry.lastAccess = CACurrentMediaTime()
        }
        return bestEntry?.texture
    }

    func insert(_ key: CacheKey, texture: MTLTexture) {
        let byteSize = texture.width * texture.height * 4
        lock.lock()
        defer { lock.unlock() }

        if let existing = entries[key] {
            currentBytes -= existing.byteSize
        }

        while currentBytes + byteSize > maxBytes, !entries.isEmpty {
            evictOldest()
        }

        entries[key] = Entry(
            texture: texture,
            lastAccess: CACurrentMediaTime(),
            byteSize: byteSize
        )
        currentBytes += byteSize
    }

    func evictDistant(from currentTime: Double, keepWindow: Double = 5.0) {
        lock.lock()
        defer { lock.unlock() }
        let quantum = 1.0 / 30.0
        let quantizedCurrent = (currentTime / quantum).rounded() * quantum
        let currentMs = Int((quantizedCurrent * 1000).rounded())
        let windowMs = Int(keepWindow * 1000)
        let keysToRemove = entries.keys.filter { abs($0.timeMs - currentMs) > windowMs }
        for key in keysToRemove {
            if let entry = entries.removeValue(forKey: key) {
                currentBytes -= entry.byteSize
            }
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    var usedBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentBytes
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        currentBytes = 0
    }

    private func evictOldest() {
        guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { return }
        currentBytes -= oldest.value.byteSize
        entries.removeValue(forKey: oldest.key)
    }
}
