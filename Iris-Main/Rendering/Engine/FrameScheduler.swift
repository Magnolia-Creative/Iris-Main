import Foundation

final class FrameScheduler {
    struct FrameRequest {
        let clipID: UUID
        let assetURL: URL
        let sourceTime: Double
        let priority: Int
        let timelineTime: Double
    }

    struct PrefetchPlan {
        let flat: [FrameRequest]
        let byAsset: [URL: [FrameRequest]]
        let direction: Double
    }

    func computeFramesToPrefetch(
        timeline: RenderTimelineInput,
        currentTime: Double,
        intent: RenderIntent,
        cache: FrameCache
    ) -> PrefetchPlan {
        let prefetchWindow: Double
        let stepSize: Double
        let direction: Double
        let maxRequests: Int
        let candidateTimes: [Double]

        switch intent {
        case .playback:
            prefetchWindow = 1.0
            stepSize = 1.0 / 30.0
            direction = 1.0
            maxRequests = 24
            var times: [Double] = []
            var t = max(0, currentTime - (stepSize * 2.0))
            while t <= min(timeline.duration, currentTime + prefetchWindow) {
                times.append(t)
                t += stepSize
            }
            candidateTimes = times
        case .scrub(let velocity):
            let absVel = abs(velocity)
            if absVel > 20 {
                stepSize = 1.0 / 20.0
                prefetchWindow = 0.40
                maxRequests = 6
            } else if absVel > 8 {
                stepSize = 1.0 / 24.0
                prefetchWindow = 0.55
                maxRequests = 10
            } else {
                stepSize = 1.0 / 30.0
                prefetchWindow = 0.65
                maxRequests = 14
            }
            direction = velocity >= 0 ? 1.0 : -1.0
            var times: [Double] = [currentTime]
            var delta = stepSize
            while delta <= prefetchWindow {
                let forward = currentTime + delta
                let backward = currentTime - delta
                if forward <= timeline.duration { times.append(forward) }
                if backward >= 0 { times.append(backward) }
                delta += stepSize
            }
            candidateTimes = times
        }

        var requests: [FrameRequest] = []
        var seenKeys = Set<FrameCache.CacheKey>()
        var priority = 0

        for t in candidateTimes {
            if requests.count >= maxRequests { break }
            for track in timeline.tracks {
                for clip in track.clips {
                    if requests.count >= maxRequests { break }
                    guard clip.timelineRange.contains(t) else { continue }
                    let sourceTime = Self.mapToSourceTime(timelineTime: t, clip: clip)
                    let key = FrameCache.CacheKey(clipID: clip.id, time: sourceTime)
                    if cache.get(key) == nil, !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        requests.append(FrameRequest(
                            clipID: clip.id,
                            assetURL: clip.assetURL,
                            sourceTime: sourceTime,
                            priority: priority,
                            timelineTime: t
                        ))
                    }
                }
            }
            priority += 1
        }

        let sorted = requests.sorted { $0.priority < $1.priority }
        var byAsset: [URL: [FrameRequest]] = [:]
        for request in sorted {
            byAsset[request.assetURL, default: []].append(request)
        }

        return PrefetchPlan(flat: sorted, byAsset: byAsset, direction: direction)
    }

    static func pruneBehindPlayhead(
        requests: [FrameRequest],
        currentTime: Double,
        direction: Double
    ) -> [FrameRequest] {
        requests.filter { request in
            if direction >= 0 {
                return request.timelineTime >= currentTime - 0.1
            } else {
                return request.timelineTime <= currentTime + 0.1
            }
        }
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
