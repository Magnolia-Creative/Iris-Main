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

    func bindPlayerHost(_ view: UIView) {
        let previousHost = playerHostView
        let hostIdentityChanged = previousHost.map { !($0 === view) } ?? true
        playerHostView = view

        if playerLayer == nil {
            let layer = AVPlayerLayer()
            layer.videoGravity = .resizeAspect
            view.layer.insertSublayer(layer, at: 0)
            playerLayer = layer
        } else if playerLayer?.superlayer !== view.layer {
            playerLayer?.removeFromSuperlayer()
            view.layer.insertSublayer(playerLayer!, at: 0)
        }

        layoutPlayerHost()
        if player == nil {
            player = AVPlayer()
        }
        playerLayer?.player = player

        if hostIdentityChanged, timeline.duration > 0 {
            scheduleRebuild()
        }
    }

    func layoutPlayerHost() {
        guard let view = playerHostView else { return }
        playerLayer?.frame = view.bounds
        captionSyncLayer?.frame = view.bounds
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
        guard !isPlaying, timeline.duration > 0 else { return }
        isScrubbing = false
        if currentTime >= timeline.duration {
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
        let clamped = max(0, min(time, timeline.duration))
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
            currentTime = max(0, min(quantized, timeline.duration))
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
            player?.replaceCurrentItem(with: nil)
            return
        }

        let fps = max(1, previewFrameRate)
        let videoLab = VideoLabTimelineAdapter.makeVideoLab(from: timeline, frameRate: fps)
        guard !Task.isCancelled else { return }

        let item = videoLab.makePlayerItem()
        item.seekingWaitsForVideoCompositionRendering = true

        if player == nil {
            player = AVPlayer()
        }
        player?.replaceCurrentItem(with: item)
        playerLayer?.player = player

        if let animationLayer = videoLab.renderComposition.animationLayer,
           let host = playerHostView {
            animationLayer.removeFromSuperlayer()
            let sync = AVSynchronizedLayer(playerItem: item)
            sync.frame = host.bounds
            sync.addSublayer(animationLayer)
            host.layer.addSublayer(sync)
            captionSyncLayer = sync
        }

        guard !Task.isCancelled else { return }

        addObservers(for: item)
        seekPlayer(to: min(currentTime, timeline.duration))
        onTimeChanged?(currentTime)
    }

    private func seekPlayer(to seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func syncCurrentTimeFromPlayer() {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return }
        currentTime = max(0, min(seconds, timeline.duration))
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(value: 1, timescale: Int32(max(1, previewFrameRate)))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.isPlaying, !self.isScrubbing else { return }
            let s = time.seconds
            guard s.isFinite else { return }
            self.currentTime = max(0, min(s, self.timeline.duration))
            self.onTimeChanged?(self.currentTime)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.player?.pause()
            self.currentTime = self.timeline.duration
            self.onPlaybackStateChanged?(false)
            self.onTimeChanged?(self.currentTime)
        }
    }

    private func removeObservers() {
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
