import AVFoundation
import Foundation
#if DEBUG
import os
#endif

extension RenderTimelineInput {
    /// Loads asset tracks and drops visual-track clips that have no video track (VideoLab cannot composite them).
    /// Audio tracks (`zOrder < 0`) keep clips even if video-only, so audio-only sources still play.
    func preparedForVideoLabPreview() async -> RenderTimelineInput {
        var newTracks: [RenderTrackInput] = []

        for track in tracks {
            if track.zOrder < 0 {
                newTracks.append(track)
                continue
            }

            var keptClips: [RenderClipInput] = []
            for clip in track.clips {
                let asset = AVURLAsset(url: clip.assetURL)
                do {
                    let avTracks = try await asset.load(.tracks)
                    let hasVideo = avTracks.contains { $0.mediaType == .video }
                    if hasVideo {
                        keptClips.append(clip)
                    } else {
                        #if DEBUG
                        VideoLabPreviewDiagnostics.logDroppedClip(
                            reason: "no_video_track",
                            zOrder: track.zOrder,
                            url: clip.assetURL
                        )
                        #endif
                    }
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
}

#if DEBUG
enum VideoLabPreviewDiagnostics {
    private static let logger = Logger(subsystem: "Iris-Main", category: "VideoLabPreview")

    static func logDroppedClip(reason: String, zOrder: Int, url: URL, error: Error? = nil) {
        if let err = error {
            logger.warning("clip dropped reason=\(reason, privacy: .public) zOrder=\(zOrder) url=\(url.lastPathComponent, privacy: .public) error=\(String(describing: err), privacy: .public)")
        } else {
            logger.warning("clip dropped reason=\(reason, privacy: .public) zOrder=\(zOrder) url=\(url.lastPathComponent, privacy: .public)")
        }
    }

    static func logTimelineSummary(_ input: RenderTimelineInput) {
        let visual = input.tracks.filter { $0.zOrder >= 0 }.count
        let audio = input.tracks.filter { $0.zOrder < 0 }.count
        let clips = input.tracks.flatMap(\.clips).count
        logger.debug("renderInput tracks=\(input.tracks.count) visualTracks=\(visual) audioTracks=\(audio) clips=\(clips) duration=\(input.duration) output=\(Int(input.outputSize.width))x\(Int(input.outputSize.height))")
    }

    static func logPlayerItem(_ item: AVPlayerItem) {
        let st = item.status.rawValue
        let err = item.error.map { String(describing: $0) } ?? "nil"
        let hasVC = item.videoComposition != nil
        logger.debug("playerItem status=\(st) error=\(err, privacy: .public) videoComposition=\(hasVC)")
    }

    static func logPlayerLayerReady(_ ready: Bool, bounds: CGRect) {
        logger.debug("playerLayer isReadyForDisplay=\(ready) bounds=\(String(describing: bounds))")
    }

    static func logTimeControl(_ status: AVPlayer.TimeControlStatus) {
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
