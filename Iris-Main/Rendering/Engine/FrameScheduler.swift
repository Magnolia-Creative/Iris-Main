import Foundation

final class FrameScheduler {
    struct FrameRequest {
        let clipID: UUID
        let assetURL: URL
        let sourceTime: Double
        let priority: Int
    }

    func computeFramesToPrefetch(
        timeline: RenderTimelineInput,
        currentTime: Double,
        intent: RenderIntent,
        cache: FrameCache
    ) -> [FrameRequest] {
        let prefetchWindow: Double
        let stepSize: Double
        let direction: Double

        switch intent {
        case .playback:
            prefetchWindow = 2.0
            stepSize = 1.0 / 30.0
            direction = 1.0
        case .scrub(let velocity):
            let absVel = max(abs(velocity), 0.01)
            stepSize = max(1.0 / 30.0, min(absVel * 0.05, 0.5))
            prefetchWindow = max(0.5, min(absVel * 0.2, 3.0))
            direction = velocity >= 0 ? 1.0 : -1.0
        }

        var requests: [FrameRequest] = []
        var seenKeys = Set<FrameCache.CacheKey>()
        var t = currentTime
        var priority = 0

        while abs(t - currentTime) <= prefetchWindow, t >= 0, t <= timeline.duration {
            for track in timeline.tracks {
                for clip in track.clips {
                    guard clip.timelineRange.contains(t) else { continue }
                    let sourceTime = Self.mapToSourceTime(timelineTime: t, clip: clip)
                    let key = FrameCache.CacheKey(clipID: clip.id, time: sourceTime)
                    if cache.get(key) == nil, !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        requests.append(FrameRequest(
                            clipID: clip.id,
                            assetURL: clip.assetURL,
                            sourceTime: sourceTime,
                            priority: priority
                        ))
                    }
                }
            }
            t += stepSize * direction
            priority += 1

            if priority > 200 { break }
        }

        return requests.sorted { $0.priority < $1.priority }
    }

    static func mapToSourceTime(timelineTime: Double, clip: RenderClipInput) -> Double {
        let timelineOffset = timelineTime - clip.timelineRange.lowerBound
        let timelineDuration = clip.timelineRange.upperBound - clip.timelineRange.lowerBound
        guard timelineDuration > 0 else { return clip.sourceRange.lowerBound }
        let normalized = timelineOffset / timelineDuration
        let sourceDuration = clip.sourceRange.upperBound - clip.sourceRange.lowerBound
        return clip.sourceRange.lowerBound + normalized * sourceDuration
    }
}
