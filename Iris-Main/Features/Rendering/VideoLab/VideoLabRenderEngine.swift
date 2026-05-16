import AVFoundation
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
    private var playerLayerVideoRectObservation: NSKeyValueObservation?
    private var captionSyncLayer: AVSynchronizedLayer?
    private var captionRenderSize: CGSize = .zero
    private var rebuildTask: Task<Void, Never>?
    private var boundsRetryTask: Task<Void, Never>?
    private var rebuildGeneration: UInt64 = 0
    private var waitingForNonzeroHostBounds = false
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
            playerLayerVideoRectObservation?.invalidate()
            playerLayerVideoRectObservation = nil
            oldLayer.removeFromSuperlayer()
        }

        playerHostView = view
        playerLayer = avLayer
        avLayer.videoGravity = .resizeAspect
        installPlayerLayerVideoRectObserverIfNeeded(for: avLayer)

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
        layoutCaptionSyncLayer()
        if waitingForNonzeroHostBounds, hasNonzeroHostBounds {
            waitingForNonzeroHostBounds = false
            boundsRetryTask?.cancel()
            boundsRetryTask = nil
            scheduleRebuild()
        }
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
        let cancelledPrevious = rebuildTask != nil
        rebuildTask?.cancel()
        rebuildGeneration &+= 1
        let generation = rebuildGeneration
        let snapshot = timeline
#if DEBUG
        VideoLabPreviewDiagnostics.logRebuildScheduled(
            generation: generation,
            cancelledPrevious: cancelledPrevious,
            input: snapshot,
            hostBounds: playerHostView?.bounds ?? .zero
        )
#endif
        rebuildTask = Task { [weak self] in
            await self?.rebuildPlayer(from: snapshot, generation: generation)
        }
    }

    private var hasNonzeroHostBounds: Bool {
        guard let bounds = playerHostView?.bounds else { return false }
        return bounds.width > 0 && bounds.height > 0
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

    private func clearPlayerItem() {
        let wasPlaying = isPlaying
        player?.pause()
        isPlaying = false
        isScrubbing = false
        compositionDuration = 0
        currentTime = 0
        waitingForNonzeroHostBounds = false
        boundsRetryTask?.cancel()
        boundsRetryTask = nil
        removeObservers()
        removeCaptionSyncLayer()
        playerLayer?.player = nil
        player?.replaceCurrentItem(with: nil)
        if wasPlaying {
            onPlaybackStateChanged?(false)
        }
        onTimeChanged?(0)
    }

    private func isRebuildCurrent(_ generation: UInt64, stage: String) -> Bool {
        guard !Task.isCancelled, generation == rebuildGeneration else {
#if DEBUG
            VideoLabPreviewDiagnostics.logRebuildSuperseded(
                generation: generation,
                currentGeneration: rebuildGeneration,
                stage: stage
            )
#endif
            return false
        }
        return true
    }

    private func rebuildPlayer(from timeline: RenderTimelineInput, generation: UInt64) async {
        guard isRebuildCurrent(generation, stage: "start") else { return }

#if DEBUG
        VideoLabPreviewDiagnostics.logRebuildStarted(
            generation: generation,
            input: timeline,
            hostBounds: playerHostView?.bounds ?? .zero
        )
#endif

        removeObservers()
        removeCaptionSyncLayer()

        guard timeline.duration > 0 else {
#if DEBUG
            VideoLabPreviewDiagnostics.logRebuildCleared(
                generation: generation,
                reason: "empty_duration",
                input: timeline,
                hostBounds: playerHostView?.bounds ?? .zero
            )
#endif
            clearPlayerItem()
            return
        }

        let prepared = await timeline.preparedForVideoLabPreview()
        guard isRebuildCurrent(generation, stage: "prepared") else { return }

        guard prepared.duration > 0 else {
#if DEBUG
            VideoLabPreviewDiagnostics.logRebuildCleared(
                generation: generation,
                reason: "prepared_empty",
                input: prepared,
                hostBounds: playerHostView?.bounds ?? .zero
            )
            VideoLabPreviewDiagnostics.logTimelineSummary(prepared)
#endif
            clearPlayerItem()
            return
        }

        compositionDuration = prepared.duration

#if DEBUG
        VideoLabPreviewDiagnostics.logTimelineSummary(prepared)
        VideoLabPreviewDiagnostics.logRebuildBuilding(
            generation: generation,
            input: prepared,
            hostBounds: playerHostView?.bounds ?? .zero
        )
        await VideoLabPreviewDiagnostics.logPerAssetTrackSummary(for: prepared)
        guard isRebuildCurrent(generation, stage: "asset_summary") else { return }
#endif

        let fps = max(1, previewFrameRate)
        let videoLab = await VideoLabTimelineAdapter.makeVideoLabAsync(from: prepared, frameRate: fps)
        guard isRebuildCurrent(generation, stage: "video_lab") else { return }

        let item = videoLab.makePlayerItem()
        item.seekingWaitsForVideoCompositionRendering = true

        if player == nil {
            player = AVPlayer()
        }

        guard hasNonzeroHostBounds else {
            deferRebuildUntilHostBounds(generation: generation, input: prepared)
            return
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

        if let animationLayer = videoLab.renderComposition.animationLayer, let host = playerHostView {
            let sync = AVSynchronizedLayer(playerItem: item)
            sync.frame = host.bounds
            sync.addSublayer(animationLayer)
            host.layer.addSublayer(sync)
            captionSyncLayer = sync
            captionRenderSize = videoLab.renderComposition.renderSize
            layoutCaptionSyncLayer()
        }

        guard isRebuildCurrent(generation, stage: "final_seek") else { return }

        seekPlayer(to: min(currentTime, prepared.duration))
        onTimeChanged?(currentTime)
    }

    private func deferRebuildUntilHostBounds(generation: UInt64, input: RenderTimelineInput) {
        guard isRebuildCurrent(generation, stage: "defer_zero_bounds") else { return }
        waitingForNonzeroHostBounds = true
#if DEBUG
        VideoLabPreviewDiagnostics.logRebuildDeferredForBounds(
            generation: generation,
            input: input,
            hostBounds: playerHostView?.bounds ?? .zero
        )
#endif
        boundsRetryTask?.cancel()
        boundsRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            await self?.retryRebuildAfterBoundsWait(generation: generation)
        }
    }

    private func retryRebuildAfterBoundsWait(generation: UInt64) {
        guard waitingForNonzeroHostBounds else { return }
        guard isRebuildCurrent(generation, stage: "bounds_retry") else { return }
        guard hasNonzeroHostBounds else {
#if DEBUG
            VideoLabPreviewDiagnostics.logRebuildStillWaitingForBounds(
                generation: generation,
                hostBounds: playerHostView?.bounds ?? .zero
            )
#endif
            return
        }
        waitingForNonzeroHostBounds = false
        boundsRetryTask = nil
        scheduleRebuild()
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

    private func layoutCaptionSyncLayer() {
        guard let host = playerHostView,
              let sync = captionSyncLayer,
              let captionLayer = sync.sublayers?.first,
              captionRenderSize.width > 0,
              captionRenderSize.height > 0 else {
            return
        }

        sync.frame = host.bounds
        let visibleVideoRect: CGRect = {
            guard let rect = playerLayer?.videoRect,
                  rect.width > 0,
                  rect.height > 0 else {
                return host.bounds
            }
            return rect
        }()

        let layout = Self.captionLayerLayout(
            captionRenderSize: captionRenderSize,
            visibleVideoRect: visibleVideoRect
        )
        captionLayer.anchorPoint = CGPoint(x: 0, y: 0)
        captionLayer.bounds = layout.bounds
        captionLayer.position = layout.position
        captionLayer.setAffineTransform(layout.transform)
    }

    static func captionLayerLayout(
        captionRenderSize: CGSize,
        visibleVideoRect: CGRect
    ) -> (bounds: CGRect, position: CGPoint, transform: CGAffineTransform) {
        let scaleX = visibleVideoRect.width / captionRenderSize.width
        let scaleY = visibleVideoRect.height / captionRenderSize.height
        return (
            bounds: CGRect(origin: .zero, size: captionRenderSize),
            position: visibleVideoRect.origin,
            transform: CGAffineTransform(scaleX: scaleX, y: scaleY)
        )
    }

    private func installPlayerLayerVideoRectObserverIfNeeded(for layer: AVPlayerLayer) {
        guard playerLayerVideoRectObservation == nil else { return }
        playerLayerVideoRectObservation = layer.observe(\.videoRect, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.layoutCaptionSyncLayer()
            }
        }
    }

    private func removeCaptionSyncLayer() {
        captionSyncLayer?.removeFromSuperlayer()
        captionSyncLayer = nil
        captionRenderSize = .zero
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
