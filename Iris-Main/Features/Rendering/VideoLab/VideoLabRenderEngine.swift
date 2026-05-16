import AVFoundation
import QuartzCore
import UIKit
import VideoLab

@MainActor
final class VideoLabRenderEngine: NSObject {
    private(set) var currentTime: Double = 0
    private(set) var isPlaying: Bool = false
    private(set) var metrics: RenderMetrics = RenderMetrics()

    var onTimeChanged: ((Double) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?

    private var timeline: RenderTimelineInput = .empty

    /// Composition frame rate; used for `RenderComposition.frameDuration` and periodic time updates.
    var previewFrameRate: Int = 30 {
        didSet {
            let clamped = max(1, min(previewFrameRate, 120))
            if clamped != previewFrameRate {
                previewFrameRate = clamped
                return
            }
            guard oldValue != previewFrameRate, timeline.duration > 0 else { return }
            scheduleRebuild()
        }
    }
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private weak var playerHostView: UIView?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var captionSyncLayer: AVSynchronizedLayer?
    private var rebuildTask: Task<Void, Never>?
    private var isScrubbing: Bool = false
    /// Duration of the last built `AVPlayerItem` (after visual-track filtering). Used to clamp `currentTime` when it differs from `timeline.duration`.
    private var compositionDuration: Double = 0

    private var effectiveTimelineDuration: Double {
        if compositionDuration > 0 {
            return min(timeline.duration, compositionDuration)
        }
        return timeline.duration
    }

#if DEBUG
    private var debugItemStatusObservation: NSKeyValueObservation?
    private var debugItemVideoCompositionObservation: NSKeyValueObservation?
    private var debugPlayerTimeControlObservation: NSKeyValueObservation?
    private var debugPlayerLayerReadyObservation: NSKeyValueObservation?
#endif

    func bindPlayerHost(_ view: UIView) {
        guard let avLayer = view.layer as? AVPlayerLayer else {
            assertionFailure("VideoLab preview requires a UIView whose layerClass is AVPlayerLayer")
            return
        }

        let hostIdentityChanged = !(playerHostView === view)
        if let oldLayer = playerLayer, oldLayer !== avLayer {
            oldLayer.removeFromSuperlayer()
        }

        playerHostView = view
        playerLayer = avLayer
        avLayer.videoGravity = .resizeAspect

        layoutPlayerHost()
        if player == nil {
            player = AVPlayer()
        }
        avLayer.player = player

        if hostIdentityChanged, timeline.duration > 0 {
            scheduleRebuild()
        }
    }

    func layoutPlayerHost() {
        guard let view = playerHostView else { return }
        playerLayer?.frame = view.bounds
        captionSyncLayer?.frame = view.bounds
#if DEBUG
        if view.bounds.width < 1 || view.bounds.height < 1 {
            VideoLabPreviewDiagnostics.logPlayerLayerReadyIfChanged(ready: playerLayer?.isReadyForDisplay ?? false, bounds: view.bounds)
        }
#endif
    }

    func configure(timeline: RenderTimelineInput) {
        self.timeline = timeline
        scheduleRebuild()
    }

    func updateTimeline(_ timeline: RenderTimelineInput) {
        self.timeline = timeline
        scheduleRebuild()
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        let snapshot = timeline
        rebuildTask = Task { [weak self] in
            await self?.rebuildPlayer(from: snapshot)
        }
    }

    func play() {
        guard !isPlaying, effectiveTimelineDuration > 0 else { return }
        isScrubbing = false
        if currentTime >= effectiveTimelineDuration {
            currentTime = 0
            seekPlayer(to: 0)
        }
        isPlaying = true
        player?.play()
        onPlaybackStateChanged?(true)
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        player?.pause()
        syncCurrentTimeFromPlayer()
        onPlaybackStateChanged?(false)
    }

    func seek(to time: Double, intent: RenderIntent = .scrub(velocity: 0)) {
        let clamped = max(0, min(time, effectiveTimelineDuration))
        switch intent {
        case .playback:
            currentTime = clamped
        case .scrub(let velocity):
            let quantum: Double = {
                if isScrubbing {
                    if abs(velocity) > 20 { return 1.0 / 24.0 }
                    if abs(velocity) > 8 { return 1.0 / 30.0 }
                    return 1.0 / 45.0
                }
                return 1.0 / 60.0
            }()
            let quantized = (clamped / quantum).rounded() * quantum
            currentTime = max(0, min(quantized, effectiveTimelineDuration))
        }
        seekPlayer(to: currentTime)
        if isScrubbing {
            player?.pause()
        } else if isPlaying {
            player?.play()
        }
        onTimeChanged?(currentTime)
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if scrubbing {
            player?.pause()
        } else if isPlaying {
            player?.play()
        } else {
            seekPlayer(to: currentTime)
        }
    }

    func loadAssetDuration(for url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    private func rebuildPlayer(from timeline: RenderTimelineInput) async {
        guard !Task.isCancelled else { return }

        removeObservers()
        captionSyncLayer?.removeFromSuperlayer()
        captionSyncLayer = nil

        guard timeline.duration > 0 else {
            compositionDuration = 0
            player?.replaceCurrentItem(with: nil)
            return
        }

        let prepared = await timeline.preparedForVideoLabPreview()
        guard !Task.isCancelled else { return }

        guard prepared.duration > 0 else {
            compositionDuration = 0
            player?.replaceCurrentItem(with: nil)
#if DEBUG
            VideoLabPreviewDiagnostics.logTimelineSummary(prepared)
#endif
            return
        }

        compositionDuration = prepared.duration

#if DEBUG
        VideoLabPreviewDiagnostics.logTimelineSummary(prepared)
        await VideoLabPreviewDiagnostics.logPerAssetTrackSummary(for: prepared)
#endif

        let fps = max(1, previewFrameRate)
        let videoLab = await VideoLabTimelineAdapter.makeVideoLabAsync(from: prepared, frameRate: fps)
        guard !Task.isCancelled else { return }

        let item = videoLab.makePlayerItem()
        item.seekingWaitsForVideoCompositionRendering = true

        if player == nil {
            player = AVPlayer()
        }

        // Observe the new item before attaching it so status/videoComposition KVO is not missed during transition.
        addObservers(for: item)

        player?.replaceCurrentItem(with: item)
        playerLayer?.player = player

#if DEBUG
        let rc = videoLab.renderComposition
        VideoLabPreviewDiagnostics.logBuiltVideoLabPreview(
            layerCount: rc.layers.count,
            renderWidth: Int(rc.renderSize.width),
            renderHeight: Int(rc.renderSize.height),
            frameDurationSeconds: rc.frameDuration.seconds,
            hasAnimationLayer: rc.animationLayer != nil,
            item: item,
            frameRate: fps
        )
        VideoLabPreviewDiagnostics.logPlayerItemWired(item, timelineDuration: prepared.duration)
#endif

        if !prepared.captions.isEmpty, let host = playerHostView {
            let animationLayer = VideoLabCaptionLayerFactory.makeAnimationLayer(
                cues: prepared.captions,
                timelineDuration: max(prepared.duration, 0.01),
                renderSize: prepared.outputSize
            )
            let sync = AVSynchronizedLayer(playerItem: item)
            sync.frame = host.bounds
            sync.addSublayer(animationLayer)
            host.layer.addSublayer(sync)
            captionSyncLayer = sync
        }

        guard !Task.isCancelled else { return }

        seekPlayer(to: min(currentTime, prepared.duration))
        onTimeChanged?(currentTime)
    }

    private func seekPlayer(to seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        if isScrubbing {
            let tol = CMTime(value: 1, timescale: 15)
            player?.seek(to: t, toleranceBefore: tol, toleranceAfter: tol)
        } else {
            player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func syncCurrentTimeFromPlayer() {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return }
        currentTime = max(0, min(seconds, effectiveTimelineDuration))
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(value: 1, timescale: Int32(max(1, previewFrameRate)))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.isScrubbing else { return }
                let s = time.seconds
                guard s.isFinite else { return }
                let newTime = max(0, min(s, self.effectiveTimelineDuration))
                self.currentTime = newTime
                self.onTimeChanged?(newTime)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.player?.pause()
            self.currentTime = self.effectiveTimelineDuration
            self.onPlaybackStateChanged?(false)
            self.onTimeChanged?(self.currentTime)
        }

#if DEBUG
        installDebugObservers(for: item)
#endif
    }

#if DEBUG
    private func installDebugObservers(for item: AVPlayerItem) {
        removeDebugObservers()
        VideoLabPreviewDiagnostics.resetPreviewSessionState()

        VideoLabPreviewDiagnostics.logPlayerItemIfChanged(item)

        debugItemStatusObservation = item.observe(\.status, options: [.new]) { observed, _ in
            Task { @MainActor in
                VideoLabPreviewDiagnostics.logPlayerItemIfChanged(observed)
            }
        }

        debugItemVideoCompositionObservation = item.observe(\.videoComposition, options: [.new]) { observed, _ in
            Task { @MainActor in
                VideoLabPreviewDiagnostics.logPlayerItemIfChanged(observed)
            }
        }

        if let player {
            VideoLabPreviewDiagnostics.logTimeControlIfChanged(player.timeControlStatus)
            debugPlayerTimeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { observed, _ in
                Task { @MainActor in
                    VideoLabPreviewDiagnostics.logTimeControlIfChanged(observed.timeControlStatus)
                }
            }
        }

        if let layer = playerLayer {
            VideoLabPreviewDiagnostics.logPlayerLayerReadyIfChanged(ready: layer.isReadyForDisplay, bounds: layer.bounds)
            debugPlayerLayerReadyObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { observed, _ in
                let ready = observed.isReadyForDisplay
                let bounds = observed.bounds
                Task { @MainActor in
                    VideoLabPreviewDiagnostics.logPlayerLayerReadyIfChanged(ready: ready, bounds: bounds)
                }
            }
        }
    }

    private func removeDebugObservers() {
        debugItemStatusObservation?.invalidate()
        debugItemStatusObservation = nil
        debugItemVideoCompositionObservation?.invalidate()
        debugItemVideoCompositionObservation = nil
        debugPlayerTimeControlObservation?.invalidate()
        debugPlayerTimeControlObservation = nil
        debugPlayerLayerReadyObservation?.invalidate()
        debugPlayerLayerReadyObservation = nil
    }
#endif

    private func removeObservers() {
#if DEBUG
        removeDebugObservers()
#endif
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}
