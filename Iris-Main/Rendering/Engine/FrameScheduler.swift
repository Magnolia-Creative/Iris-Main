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
            prefetchWindow = 0.4
            stepSize = 1.0 / 30.0
            direction = 1.0
            maxRequests = 10
            var times: [Double] = []
            var t = max(0, currentTime - stepSize)
            while t <= min(timeline.duration, currentTime + prefetchWindow) {
                times.append(t)
                t += stepSize
            }
            candidateTimes = times
        case .scrub(let velocity):
            let absVel = abs(velocity)

            // Scale lookahead window with velocity. Step size is derived from
            // the window and request count so that requests actually span the
            // full window instead of clustering near the playhead.
            let forwardWindow: Double
            let backwardWindow: Double

            if absVel < 2 {
                forwardWindow = 0.42
                backwardWindow = 0.42
                maxRequests = 8
            } else if absVel > 40 {
                forwardWindow = 1.8
                backwardWindow = 0.3
                maxRequests = 6
            } else if absVel > 20 {
                forwardWindow = 1.2
                backwardWindow = 0.2
                maxRequests = 6
            } else if absVel > 8 {
                forwardWindow = 0.8
                backwardWindow = 0.3
                maxRequests = 8
            } else {
                forwardWindow = 0.55
                backwardWindow = 0.35
                maxRequests = 10
            }
            let aheadCount = max(maxRequests - 2, 3)
            stepSize = max(forwardWindow / Double(aheadCount), 1.0 / 30.0)
            prefetchWindow = max(forwardWindow, backwardWindow)
            direction = velocity >= 0 ? 1.0 : -1.0

            let aheadWindow = direction >= 0 ? forwardWindow : backwardWindow
            let behindWindow = direction >= 0 ? backwardWindow : forwardWindow

            var aheadTimes: [Double] = []
            var behindTimes: [Double] = []
            var delta = stepSize
            while delta <= aheadWindow {
                let t = currentTime + direction * delta
                if t >= 0, t <= timeline.duration { aheadTimes.append(t) }
                delta += stepSize
            }
            delta = stepSize
            while delta <= behindWindow {
                let t = currentTime - direction * delta
                if t >= 0, t <= timeline.duration { behindTimes.append(t) }
                delta += stepSize
            }
            var times: [Double] = [currentTime]
            times.append(contentsOf: aheadTimes)
            times.append(contentsOf: behindTimes)
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
