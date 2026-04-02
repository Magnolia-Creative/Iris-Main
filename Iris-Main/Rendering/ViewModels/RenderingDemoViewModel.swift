import AVFoundation
import Combine
import Foundation
import simd

@MainActor
final class RenderingDemoViewModel: ObservableObject {
    // MARK: - Published state

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var metrics: RenderMetrics = RenderMetrics()
    @Published private(set) var duration: Double = 0
    @Published var showMetrics: Bool = true

    @Published var tracks: [DemoTrack] = []
    @Published var captions: [RenderCaptionCueInput] = []
    @Published var selectedClipID: UUID?

    let engine: RenderEngine

    private var uiTimer: Timer?
    private var lastSeekTime: CFTimeInterval = 0

    // MARK: - Demo track model

    struct DemoTrack: Identifiable {
        let id: UUID
        var clips: [DemoClip]
        var zOrder: Int
    }

    struct DemoClip: Identifiable {
        let id: UUID
        let assetURL: URL
        let displayName: String
        let sourceDuration: Double
        var timelineStart: Double
        var timelineDuration: Double
        var transform: RenderTransformInput
        var colorAdjustments: RenderColorAdjustmentsInput
        var opacity: Float
    }

    // MARK: - Init

    init() {
        self.engine = RenderEngine()

        engine.onPlaybackStateChanged = { [weak self] playing in
            Task { @MainActor in self?.isPlaying = playing }
        }

        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = self.engine.currentTime
                self.isPlaying = self.engine.isPlaying
                self.metrics = self.engine.metrics
            }
        }
    }

    deinit {
        uiTimer?.invalidate()
    }

    // MARK: - Clip management

    func addClip(url: URL, displayName: String) async {
        do {
            let dur = try await engine.loadAssetDuration(for: url)
            let timelineStart = tracks.first?.clips.map { $0.timelineStart + $0.timelineDuration }.max() ?? 0

            let clip = DemoClip(
                id: UUID(),
                assetURL: url,
                displayName: displayName,
                sourceDuration: dur,
                timelineStart: timelineStart,
                timelineDuration: dur,
                transform: .identity,
                colorAdjustments: .neutral,
                opacity: 1.0
            )

            if tracks.isEmpty {
                tracks.append(DemoTrack(id: UUID(), clips: [clip], zOrder: 0))
            } else {
                tracks[0].clips.append(clip)
            }

            rebuildTimeline()
        } catch {
            // Silently skip assets that can't be loaded
        }
    }

    func addClipToNewTrack(url: URL, displayName: String) async {
        do {
            let dur = try await engine.loadAssetDuration(for: url)

            let clip = DemoClip(
                id: UUID(),
                assetURL: url,
                displayName: displayName,
                sourceDuration: dur,
                timelineStart: 0,
                timelineDuration: dur,
                transform: .identity,
                colorAdjustments: .neutral,
                opacity: 1.0
            )

            let zOrder = (tracks.map(\.zOrder).max() ?? -1) + 1
            tracks.append(DemoTrack(id: UUID(), clips: [clip], zOrder: zOrder))
            rebuildTimeline()
        } catch {}
    }

    func removeClip(id: UUID) {
        for i in tracks.indices {
            tracks[i].clips.removeAll { $0.id == id }
        }
        tracks.removeAll { $0.clips.isEmpty }
        if selectedClipID == id { selectedClipID = nil }
        rebuildTimeline()
    }

    // MARK: - Transport

    func play() { engine.play() }
    func pause() { engine.pause() }
    func togglePlayback() { isPlaying ? pause() : play() }

    func seek(to time: Double) {
        let now = CACurrentMediaTime()
        let velocity = lastSeekTime > 0 ? (time - currentTime) / max(now - lastSeekTime, 0.001) : 0
        lastSeekTime = now
        engine.seek(to: time, intent: .scrub(velocity: velocity))
    }

    // MARK: - Transform

    var selectedClip: DemoClip? {
        guard let id = selectedClipID else { return nil }
        for track in tracks {
            if let clip = track.clips.first(where: { $0.id == id }) { return clip }
        }
        return nil
    }

    func updateTransform(_ transform: RenderTransformInput) {
        guard let id = selectedClipID else { return }
        mutateClip(id: id) { $0.transform = transform }
    }

    func updateColorAdjustments(_ adj: RenderColorAdjustmentsInput) {
        guard let id = selectedClipID else { return }
        mutateClip(id: id) { $0.colorAdjustments = adj }
    }

    func updateOpacity(_ opacity: Float) {
        guard let id = selectedClipID else { return }
        mutateClip(id: id) { $0.opacity = opacity }
    }

    // MARK: - Captions

    func addCaption(text: String) {
        let start = currentTime
        let end = min(start + 3.0, duration)
        guard end > start else { return }
        captions.append(RenderCaptionCueInput(startTime: start, endTime: end, text: text))
        rebuildTimeline()
    }

    func removeCaption(id: UUID) {
        captions.removeAll { $0.id == id }
        rebuildTimeline()
    }

    // MARK: - Internal

    private func mutateClip(id: UUID, _ mutation: (inout DemoClip) -> Void) {
        for i in tracks.indices {
            if let j = tracks[i].clips.firstIndex(where: { $0.id == id }) {
                mutation(&tracks[i].clips[j])
                rebuildTimeline()
                return
            }
        }
    }

    private func rebuildTimeline() {
        let renderTracks = tracks.map { demoTrack in
            RenderTrackInput(
                id: demoTrack.id,
                clips: demoTrack.clips.map { clip in
                    RenderClipInput(
                        id: clip.id,
                        assetURL: clip.assetURL,
                        timelineRange: clip.timelineStart ... (clip.timelineStart + clip.timelineDuration),
                        sourceRange: 0 ... clip.sourceDuration,
                        transform: clip.transform,
                        colorAdjustments: clip.colorAdjustments,
                        opacity: clip.opacity
                    )
                },
                zOrder: demoTrack.zOrder
            )
        }

        let maxEnd = tracks.flatMap(\.clips).map { $0.timelineStart + $0.timelineDuration }.max() ?? 0
        let captionMaxEnd = captions.map(\.endTime).max() ?? 0
        duration = max(maxEnd, captionMaxEnd)

        let timeline = RenderTimelineInput(
            tracks: renderTracks,
            captions: captions,
            outputSize: CGSize(width: 1920, height: 1080),
            duration: duration
        )

        engine.updateTimeline(timeline)
    }
}

