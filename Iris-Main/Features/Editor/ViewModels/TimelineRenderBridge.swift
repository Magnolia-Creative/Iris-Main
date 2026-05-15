import Foundation
import SwiftUI
internal import Combine

@MainActor
final class TimelineRenderBridge: ObservableObject {
    let engine: VideoLabRenderEngine
    private var cancellables: Set<AnyCancellable> = []
    private var lastSeekTime: CFTimeInterval = 0
    private var scrubEndWorkItem: DispatchWorkItem?
    private var isUserScrubbing: Bool = false

    init() {
        self.engine = VideoLabRenderEngine()
    }

    func bind(to controller: TimelineController) {
        controller.$state
            .removeDuplicates { old, new in
                old.clips.map(\.clipId) == new.clips.map(\.clipId)
                    && old.clips.map(\.timelineRange.start) == new.clips.map(\.timelineRange.start)
                    && old.clips.map(\.timelineRange.end) == new.clips.map(\.timelineRange.end)
                    && old.clips.map(\.sourceRange.start) == new.clips.map(\.sourceRange.start)
                    && old.clips.map(\.sourceRange.end) == new.clips.map(\.sourceRange.end)
                    && Self.clipColorFiltersByClipId(from: old.effects) == Self.clipColorFiltersByClipId(from: new.effects)
                    && Self.clipVolumesByClipId(from: old.effects) == Self.clipVolumesByClipId(from: new.effects)
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
        let renderInput = state.makeRenderTimelineInput()
        engine.configure(timeline: renderInput)
    }

    func handleScroll(timeUs: Int64, velocity: Double = 0) {
        seek(to: timeUs, scrollVelocity: velocity)
    }

    func play() {
        engine.play()
    }

    func pause() {
        engine.pause()
    }

    func seek(to timeUs: Int64) {
        seek(to: timeUs, scrollVelocity: nil)
    }

    private func seek(to timeUs: Int64, scrollVelocity: Double?) {
        let seconds = Double(timeUs) / 1_000_000.0
        let now = CACurrentMediaTime()
        let dt = now - lastSeekTime
        let velocity: Double
        if let scrollVelocity {
            velocity = scrollVelocity
        } else {
            velocity = (lastSeekTime > 0 && dt < 0.25)
                ? (seconds - engine.currentTime) / max(dt, 0.001)
                : 0
        }
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

    private static func clipColorFiltersByClipId(from effects: [Effect]) -> [String: ClipColorFilter] {
        let latestFilters = effects.reduce(into: [String: (updatedAt: Date, filter: ClipColorFilter)]()) { result, effect in
            guard let filter = effect.clipColorFilter else { return }
            if let existing = result[effect.targetId], existing.updatedAt > effect.updatedAt {
                return
            }
            result[effect.targetId] = (effect.updatedAt, filter)
        }

        return latestFilters.mapValues(\.filter)
    }

    private static func clipVolumesByClipId(from effects: [Effect]) -> [String: ClipVolume] {
        let latestVolumes = effects.reduce(into: [String: (updatedAt: Date, volume: ClipVolume)]()) { result, effect in
            guard let volume = effect.clipVolume else { return }
            if let existing = result[effect.targetId], existing.updatedAt > effect.updatedAt {
                return
            }
            result[effect.targetId] = (effect.updatedAt, volume)
        }

        return latestVolumes.mapValues(\.volume)
    }
}
