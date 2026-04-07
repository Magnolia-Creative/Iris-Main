import Foundation
import SwiftUI
internal import Combine

@MainActor
final class TimelineRenderBridge: ObservableObject {
    let engine: RenderEngine
    private var cancellables: Set<AnyCancellable> = []
    private var lastSyncedClipIds: Set<String> = []
    private var lastSeekTime: CFTimeInterval = 0
    private var scrubEndWorkItem: DispatchWorkItem?
    private var isUserScrubbing: Bool = false

    init() {
        self.engine = RenderEngine()
    }

    func bind(to controller: TimelineController) {
        controller.$state
            .removeDuplicates { old, new in
                old.clips.map(\.clipId) == new.clips.map(\.clipId)
                    && old.clips.map(\.timelineRange.start) == new.clips.map(\.timelineRange.start)
                    && old.clips.map(\.timelineRange.end) == new.clips.map(\.timelineRange.end)
                    && old.clips.map(\.sourceRange.start) == new.clips.map(\.sourceRange.start)
                    && old.clips.map(\.sourceRange.end) == new.clips.map(\.sourceRange.end)
            }
            .sink { [weak self] state in
                self?.syncTimeline(from: state)
            }
            .store(in: &cancellables)

        engine.onTimeChanged = { [weak self, weak controller] seconds in
            let us = Int64(seconds * 1_000_000)
            Task { @MainActor in
                guard let self, self.engine.isPlaying else { return }
                controller?.updateCurrentTime(us)
            }
        }

        engine.onPlaybackStateChanged = { [weak self, weak controller] playing in
            guard !playing else { return }
            Task { @MainActor in
                guard let self else { return }
                let endTimeUs = Int64(self.engine.currentTime * 1_000_000)
                controller?.updateCurrentTime(endTimeUs)
                controller?.setPlaybackState(.idle)
            }
        }

        controller.$state
            .map(\.playbackState)
            .removeDuplicates()
            .sink { [weak self] playbackState in
                guard let self else { return }
                switch playbackState {
                case .playing:
                    self.scrubEndWorkItem?.cancel()
                    self.isUserScrubbing = false
                    self.play()
                case .idle:
                    self.pause()
                case .scrubbing:
                    self.setScrubbing(true)
                }
            }
            .store(in: &cancellables)

        controller.$state
            .map(\.currentTimeAtCenter)
            .removeDuplicates()
            .sink { [weak self] timeUs in
                guard let self else { return }
                guard !self.engine.isPlaying else { return }
                self.seek(to: timeUs)
            }
            .store(in: &cancellables)
    }

    func syncTimeline(from state: TimelineState) {
        let renderInput = buildRenderInput(from: state)
        engine.configure(timeline: renderInput)
    }

    func handleScroll(timeUs: Int64, velocity: Double = 0) {
        let seconds = Double(timeUs) / 1_000_000.0
        engine.seek(to: seconds, intent: .scrub(velocity: velocity))
    }

    func play() {
        engine.play()
    }

    func pause() {
        engine.pause()
    }

    func seek(to timeUs: Int64) {
        let seconds = Double(timeUs) / 1_000_000.0
        let now = CACurrentMediaTime()
        let dt = now - lastSeekTime
        let velocity = (lastSeekTime > 0 && dt < 0.25)
            ? (seconds - engine.currentTime) / max(dt, 0.001)
            : 0
        lastSeekTime = now

        if !isUserScrubbing {
            isUserScrubbing = true
            engine.setScrubbing(true)
        }
        scrubEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.engine.isPlaying else { return }
            self.isUserScrubbing = false
            self.lastSeekTime = 0
            self.engine.setScrubbing(false)
        }
        scrubEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)

        engine.seek(to: seconds, intent: .scrub(velocity: velocity))
    }

    func setScrubbing(_ scrubbing: Bool) {
        scrubEndWorkItem?.cancel()
        if !scrubbing {
            lastSeekTime = 0
            isUserScrubbing = false
            engine.setScrubbing(false)
            engine.seek(to: engine.currentTime, intent: .scrub(velocity: 0))
        } else {
            lastSeekTime = 0
            isUserScrubbing = true
            engine.setScrubbing(true)
        }
    }

    private func buildRenderInput(from state: TimelineState) -> RenderTimelineInput {
        var renderTracks: [RenderTrackInput] = []

        for track in state.orderedTracks {
            let trackClips = state.clips.filter { $0.trackId == track.trackId }
            let renderClips = trackClips.compactMap { clip -> RenderClipInput? in
                guard let media = state.mediaById[clip.mediaId] else { return nil }

                let assetURL: URL
                if let assetRef = try? DatabaseManager.shared.getAssetReference(assetRefId: media.assetRefId) {
                    if assetRef.uri.hasPrefix("/") {
                        assetURL = URL(fileURLWithPath: assetRef.uri)
                    } else {
                        return nil
                    }
                } else {
                    return nil
                }

                let timelineStart = Double(clip.timelineRange.start) / 1_000_000.0
                let timelineEnd = Double(clip.timelineRange.end) / 1_000_000.0
                let sourceStart = Double(clip.sourceRange.start) / 1_000_000.0
                let sourceEnd = Double(clip.sourceRange.end) / 1_000_000.0

                return RenderClipInput(
                    id: UUID(uuidString: clip.clipId) ?? UUID(),
                    assetURL: assetURL,
                    timelineRange: timelineStart...timelineEnd,
                    sourceRange: sourceStart...sourceEnd
                )
            }

            let zOrder: Int = {
                switch track.kind {
                case .video: return 0
                case .overlay: return 1
                case .audio: return -1
                }
            }()

            renderTracks.append(RenderTrackInput(
                id: UUID(uuidString: track.trackId) ?? UUID(),
                clips: renderClips,
                zOrder: zOrder
            ))
        }

        let duration = state.timelineDurationSeconds
        return RenderTimelineInput(
            tracks: renderTracks,
            captions: [],
            outputSize: CGSize(width: 1920, height: 1080),
            duration: duration
        )
    }
}
