import Foundation
internal import Combine

@MainActor
final class PlaybackController: ObservableObject {
    struct ClipContext {
        let clip: Clip
        let localTimeUs: Int64
    }

    @Published private(set) var state: TimelineState?
    @Published private(set) var currentClipContext: ClipContext?

    private var cancellables: Set<AnyCancellable> = []
    private let actions: TimelineStateMutating

    init(
        statePublisher: AnyPublisher<TimelineState, Never>,
        actions: TimelineStateMutating
    ) {
        self.actions = actions
        statePublisher
            .sink { [weak self] updatedState in
                self?.update(with: updatedState)
            }
            .store(in: &cancellables)
    }

    func play() {
        actions.setPlaybackState(.playing)
    }

    func pause() {
        actions.setPlaybackState(.idle)
    }

    func jumpToStart() {
        actions.jumpToStart()
    }

    func jumpToEnd() {
        actions.jumpToEnd()
    }

    func isPlaying() -> Bool {
        state?.playbackState == .playing
    }

    private func update(with state: TimelineState) {
        self.state = state
        currentClipContext = resolveClipContext(
            playheadTimeUs: state.currentTimeAtCenter,
            clips: state.clips
        )
    }

    private func resolveClipContext(playheadTimeUs: Int64, clips: [Clip]) -> ClipContext? {
        let orderedClips = clips.sorted { left, right in
            if left.timelineRange.start == right.timelineRange.start {
                return left.timelineRange.end < right.timelineRange.end
            }
            return left.timelineRange.start < right.timelineRange.start
        }
        guard !orderedClips.isEmpty else { return nil }

        var low = 0
        var high = orderedClips.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let clip = orderedClips[mid]
            let range = clip.timelineRange

            if playheadTimeUs < range.start {
                high = mid - 1
            } else if playheadTimeUs >= range.end {
                low = mid + 1
            } else {
                let localTimeUs = clip.sourceRange.start + (playheadTimeUs - range.start)
                return ClipContext(clip: clip, localTimeUs: localTimeUs)
            }
        }
        return nil
    }
}
