import Metal
import QuartzCore

final class FrameCache {
    struct NearestResult {
        let texture: MTLTexture
        let distanceMs: Int
    }

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

        fileprivate init(clipID: UUID, rawTimeMs: Int) {
            self.clipID = clipID
            self.timeMs = rawTimeMs
        }
    }

    private struct Entry {
        let texture: MTLTexture
        let backing: Any?
        var lastAccess: CFTimeInterval
        let byteSize: Int
    }

    private var entries: [CacheKey: Entry] = [:]
    private var clipTimeIndex: [UUID: [Int]] = [:]
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
    /// Uses a per-clip sorted index for O(log n) binary search.
    func nearest(clipID: UUID, time: Double, toleranceMs: Int = 250) -> MTLTexture? {
        nearestResult(clipID: clipID, time: time, toleranceMs: toleranceMs)?.texture
    }

    func nearestResult(clipID: UUID, time: Double, toleranceMs: Int = 250) -> NearestResult? {
        lock.lock()
        defer { lock.unlock() }

        guard let times = clipTimeIndex[clipID], !times.isEmpty else { return nil }

        let targetMs = Int((time * 1000).rounded())

        let insertionPoint = binarySearch(times, target: targetMs)

        var bestTimeMs: Int?
        var bestDist = Int.max

        if insertionPoint < times.count {
            let dist = abs(times[insertionPoint] - targetMs)
            if dist <= toleranceMs && dist < bestDist {
                bestDist = dist
                bestTimeMs = times[insertionPoint]
            }
        }
        if insertionPoint > 0 {
            let dist = abs(times[insertionPoint - 1] - targetMs)
            if dist <= toleranceMs && dist < bestDist {
                bestDist = dist
                bestTimeMs = times[insertionPoint - 1]
            }
        }

        guard let foundMs = bestTimeMs else { return nil }
        let key = CacheKey(clipID: clipID, rawTimeMs: foundMs)
        guard var entry = entries[key] else { return nil }

        entry.lastAccess = CACurrentMediaTime()
        entries[key] = entry
        return NearestResult(texture: entry.texture, distanceMs: bestDist)
    }

    func insert(_ key: CacheKey, texture: MTLTexture, backing: Any? = nil) {
        let byteSize = texture.width * texture.height * 4
        lock.lock()
        defer { lock.unlock() }

        let isNew = entries[key] == nil
        if let existing = entries[key] {
            currentBytes -= existing.byteSize
        }

        while currentBytes + byteSize > maxBytes, !entries.isEmpty {
            evictOldest()
        }

        entries[key] = Entry(
            texture: texture,
            backing: backing,
            lastAccess: CACurrentMediaTime(),
            byteSize: byteSize
        )
        currentBytes += byteSize

        if isNew {
            insertIntoIndex(clipID: key.clipID, timeMs: key.timeMs)
        }
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
                removeFromIndex(clipID: key.clipID, timeMs: key.timeMs)
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
        clipTimeIndex.removeAll()
        currentBytes = 0
    }

    // MARK: - Index maintenance

    private func binarySearch(_ array: [Int], target: Int) -> Int {
        var lo = 0
        var hi = array.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if array[mid] < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    private func insertIntoIndex(clipID: UUID, timeMs: Int) {
        var times = clipTimeIndex[clipID] ?? []
        let pos = binarySearch(times, target: timeMs)
        if pos < times.count && times[pos] == timeMs { return }
        times.insert(timeMs, at: pos)
        clipTimeIndex[clipID] = times
    }

    private func removeFromIndex(clipID: UUID, timeMs: Int) {
        guard var times = clipTimeIndex[clipID] else { return }
        let pos = binarySearch(times, target: timeMs)
        if pos < times.count && times[pos] == timeMs {
            times.remove(at: pos)
            if times.isEmpty {
                clipTimeIndex.removeValue(forKey: clipID)
            } else {
                clipTimeIndex[clipID] = times
            }
        }
    }

    private func evictOldest() {
        guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { return }
        currentBytes -= oldest.value.byteSize
        removeFromIndex(clipID: oldest.key.clipID, timeMs: oldest.key.timeMs)
        entries.removeValue(forKey: oldest.key)
    }
}
