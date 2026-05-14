import AVFoundation
import Foundation
#if DEBUG
import os
#endif

extension RenderTimelineInput {
    /// Loads each clip’s asset, drops invalid visual clips, clamps source/timeline ranges to real media duration,
    /// then returns a timeline VideoLab can consume without out-of-bounds `selectedTimeRange` values.
    func preparedForVideoLabPreview() async -> RenderTimelineInput {
        var newTracks: [RenderTrackInput] = []

        for track in tracks {
            var keptClips: [RenderClipInput] = []
            for clip in track.clips {
                let asset = AVURLAsset(url: clip.assetURL)
                do {
                    let (avTracks, assetDuration) = try await asset.load(.tracks, .duration)
                    let isVisualTrack = track.zOrder >= 0

                    if isVisualTrack {
                        let hasVideo = avTracks.contains { $0.mediaType == .video }
                        if !hasVideo {
                            #if DEBUG
                            VideoLabPreviewDiagnostics.logDroppedClip(
                                reason: "no_video_track",
                                zOrder: track.zOrder,
                                url: clip.assetURL
                            )
                            #endif
                            continue
                        }
                    }

                    let mediaSeconds = max(0, assetDuration.seconds)
                    guard mediaSeconds.isFinite else {
                        #if DEBUG
                        VideoLabPreviewDiagnostics.logDroppedClip(
                            reason: "invalid_media_duration",
                            zOrder: track.zOrder,
                            url: clip.assetURL
                        )
                        #endif
                        continue
                    }

                    guard let clamped = Self.clampClipToMediaDuration(clip, mediaSeconds: mediaSeconds) else {
                        #if DEBUG
                        VideoLabPreviewDiagnostics.logDroppedClip(
                            reason: "clamp_invalid",
                            zOrder: track.zOrder,
                            url: clip.assetURL
                        )
                        #endif
                        continue
                    }

                    #if DEBUG
                    if clamped.sourceRange != clip.sourceRange || clamped.timelineRange != clip.timelineRange {
                        VideoLabPreviewDiagnostics.logClipNormalized(
                            zOrder: track.zOrder,
                            url: clip.assetURL,
                            oldSource: clip.sourceRange,
                            newSource: clamped.sourceRange,
                            oldTimeline: clip.timelineRange,
                            newTimeline: clamped.timelineRange
                        )
                    }
                    #endif

                    keptClips.append(clamped)
                } catch {
                    #if DEBUG
                    VideoLabPreviewDiagnostics.logDroppedClip(
                        reason: "load_failed",
                        zOrder: track.zOrder,
                        url: clip.assetURL,
                        error: error
                    )
                    #endif
                }
            }

            if !keptClips.isEmpty {
                newTracks.append(RenderTrackInput(id: track.id, clips: keptClips, zOrder: track.zOrder))
            }
        }

        let computedDuration = Self.maximumTimelineEnd(from: newTracks)
        let duration = max(computedDuration, 0)

        return RenderTimelineInput(
            tracks: newTracks,
            captions: captions,
            outputSize: outputSize,
            duration: duration
        )
    }

    private static func maximumTimelineEnd(from tracks: [RenderTrackInput]) -> Double {
        tracks.flatMap(\.clips).map(\.timelineRange.upperBound).max() ?? 0
    }

    /// Clamps source range to `[0, mediaSeconds]` and adjusts timeline span to preserve playback speed when possible.
    private static func clampClipToMediaDuration(
        _ clip: RenderClipInput,
        mediaSeconds: Double
    ) -> RenderClipInput? {
        let minSpan = 1.0 / 600.0

        var s0 = clip.sourceRange.lowerBound
        var s1 = clip.sourceRange.upperBound
        let t0 = clip.timelineRange.lowerBound
        var t1 = clip.timelineRange.upperBound

        guard s1 > s0, t1 > t0 else { return nil }

        s0 = min(max(s0, 0), mediaSeconds)
        s1 = min(max(s1, s0 + minSpan), mediaSeconds)

        let oldSourceDur = clip.sourceRange.upperBound - clip.sourceRange.lowerBound
        let oldTimelineDur = clip.timelineRange.upperBound - clip.timelineRange.lowerBound
        let newSourceDur = s1 - s0

        if oldSourceDur > 0, oldTimelineDur > 0 {
            if abs(oldTimelineDur - oldSourceDur) < 1e-6 {
                t1 = t0 + newSourceDur
            } else {
                let rate = oldTimelineDur / oldSourceDur
                t1 = t0 + newSourceDur * rate
            }
        } else {
            t1 = t0 + newSourceDur
        }

        return RenderClipInput(
            id: clip.id,
            assetURL: clip.assetURL,
            timelineRange: t0...t1,
            sourceRange: s0...s1,
            transform: clip.transform,
            colorAdjustments: clip.colorAdjustments,
            opacity: clip.opacity
        )
    }
}

#if DEBUG
enum VideoLabPreviewDiagnostics {
    private static let logger = Logger(subsystem: "Iris-Main", category: "VideoLabPreview")

    private static var lastTimeControlStatus: AVPlayer.TimeControlStatus?
    private static var lastLayerReady: Bool?
    private static var lastLayerBounds: CGRect?
    private static var lastPlayerItemSignature: String?

    /// Clears de-duplication state when a new `AVPlayerItem` / preview session is wired.
    static func resetPreviewSessionState() {
        lastTimeControlStatus = nil
        lastLayerReady = nil
        lastLayerBounds = nil
        lastPlayerItemSignature = nil
    }

    static func logDroppedClip(reason: String, zOrder: Int, url: URL, error: Error? = nil) {
        if let err = error {
            logger.warning("clip dropped reason=\(reason, privacy: .public) zOrder=\(zOrder) url=\(url.lastPathComponent, privacy: .public) error=\(String(describing: err), privacy: .public)")
        } else {
            logger.warning("clip dropped reason=\(reason, privacy: .public) zOrder=\(zOrder) url=\(url.lastPathComponent, privacy: .public)")
        }
    }

    static func logClipNormalized(
        zOrder: Int,
        url: URL,
        oldSource: ClosedRange<Double>,
        newSource: ClosedRange<Double>,
        oldTimeline: ClosedRange<Double>,
        newTimeline: ClosedRange<Double>
    ) {
        logger.debug(
            "clip normalized zOrder=\(zOrder) url=\(url.lastPathComponent, privacy: .public) source \(oldSource.lowerBound, privacy: .public)-\(oldSource.upperBound, privacy: .public) -> \(newSource.lowerBound, privacy: .public)-\(newSource.upperBound, privacy: .public) timeline \(oldTimeline.lowerBound, privacy: .public)-\(oldTimeline.upperBound, privacy: .public) -> \(newTimeline.lowerBound, privacy: .public)-\(newTimeline.upperBound, privacy: .public)"
        )
    }

    static func logVideoLabSourcesPrepared(count: Int) {
        logger.debug("VideoLab bridge: loaded and restored trim on \(count) AVAssetSource instance(s)")
    }

    static func logPlayerItemWired(_ item: AVPlayerItem, timelineDuration: Double) {
        let dur = item.duration.seconds
        let durStr = dur.isFinite ? String(format: "%.3f", dur) : "non-finite"
        logger.debug(
            "VideoLab preview wired itemStatus=\(item.status.rawValue) itemDuration=\(durStr, privacy: .public)s timelineDuration=\(timelineDuration, privacy: .public) videoComposition=\(item.videoComposition != nil)"
        )
    }

    static func logTimelineSummary(_ input: RenderTimelineInput) {
        let visual = input.tracks.filter { $0.zOrder >= 0 }.count
        let audio = input.tracks.filter { $0.zOrder < 0 }.count
        let clips = input.tracks.flatMap(\.clips).count
        logger.debug("renderInput tracks=\(input.tracks.count) visualTracks=\(visual) audioTracks=\(audio) clips=\(clips) duration=\(input.duration) output=\(Int(input.outputSize.width))x\(Int(input.outputSize.height))")
    }

    static func logPlayerItemIfChanged(_ item: AVPlayerItem) {
        let sig = "\(item.status.rawValue)|\(item.error.map { String(describing: $0) } ?? "nil")|\(item.videoComposition != nil)"
        guard sig != lastPlayerItemSignature else { return }
        lastPlayerItemSignature = sig
        logPlayerItem(item)
    }

    static func logPlayerItem(_ item: AVPlayerItem) {
        let st = item.status.rawValue
        let err = item.error.map { String(describing: $0) } ?? "nil"
        let hasVC = item.videoComposition != nil
        logger.debug("playerItem status=\(st) error=\(err, privacy: .public) videoComposition=\(hasVC)")
        if item.status == .failed {
            logger.warning("playerItem failed; Console may show <<<< CustomVideoCompositor >>>> err=-12784 when VideoLab’s Metal compositor drops a frame (often transient while seeking).")
        }
    }

    static func logPlayerLayerReadyIfChanged(ready: Bool, bounds: CGRect) {
        if let lr = lastLayerReady, let lb = lastLayerBounds, lr == ready, lb.equalTo(bounds) {
            return
        }
        lastLayerReady = ready
        lastLayerBounds = bounds
        logger.debug("playerLayer isReadyForDisplay=\(ready) bounds=\(String(describing: bounds))")
    }

    static func logTimeControlIfChanged(_ status: AVPlayer.TimeControlStatus) {
        guard status != lastTimeControlStatus else { return }
        lastTimeControlStatus = status
        logger.debug("player timeControlStatus=\(String(describing: status))")
    }

    static func logPerAssetTrackSummary(for input: RenderTimelineInput) async {
        let urls = Set(input.tracks.flatMap(\.clips).map(\.assetURL))
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let asset = AVURLAsset(url: url)
            do {
                let avTracks = try await asset.load(.tracks)
                let videoCount = avTracks.filter { $0.mediaType == .video }.count
                let audioCount = avTracks.filter { $0.mediaType == .audio }.count
                logger.debug("asset \(url.lastPathComponent, privacy: .public) videoTracks=\(videoCount) audioTracks=\(audioCount)")
            } catch {
                logger.warning("asset load failed \(url.lastPathComponent, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }
}
#endif
