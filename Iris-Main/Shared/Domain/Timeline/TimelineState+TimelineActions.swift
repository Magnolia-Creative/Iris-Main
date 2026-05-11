import Foundation
import SwiftUI

extension TimelineState {
    /// Applies timeline commands in order. Returns inverse actions (apply these in order to undo the batch).
    mutating func apply(_ actions: [Action]) -> [Action] {
        var combinedInverse: [Action] = []
        for action in actions {
            let inverse = apply(action)
            combinedInverse = inverse + combinedInverse
        }
        return combinedInverse
    }

    mutating func apply(_ action: Action) -> [Action] {
        guard action.timelineId == timelineId else { return [] }

        switch action.payload {
        case let .splitClip(clipId, atTimeUs):
            return applySplitClip(clipId: clipId, atTimeUs: atTimeUs)

        case let .removeClip(clipId):
            return applyRemoveClip(clipId: clipId)

        case let .addClip(clip):
            return applyAddClip(clip)

        case let .trimClip(clipId, sourceRange):
            return applyTrimClipCommitted(
                clipId: clipId,
                sourceRange: sourceRange
            )

        case let .moveClip(clipId, orderedClipIds):
            return applyMoveClipCommitted(clipId: clipId, orderedClipIds: orderedClipIds)

        case let .replaceTrackClips(trackId, replacement):
            return applyReplaceTrackClips(trackId: trackId, clips: replacement)
        }
    }

    // MARK: - Private executors

    private mutating func applySplitClip(clipId: String, atTimeUs cutTimeUs: Int64) -> [Action] {
        guard let index = clips.firstIndex(where: { $0.clipId == clipId }) else { return [] }
        let clip = clips[index]
        let trackId = clip.trackId
        let before = orderedClips(for: trackId)

        guard cutTimeUs > clip.timelineRange.start, cutTimeUs < clip.timelineRange.end else {
            return []
        }

        let leftDuration = cutTimeUs - clip.timelineRange.start
        let rightDuration = clip.timelineRange.end - cutTimeUs
        guard leftDuration > 0, rightDuration > 0 else { return [] }

        let sourceMid = clip.sourceRange.start + leftDuration
        let leftClip = Clip(
            trackId: clip.trackId,
            mediaId: clip.mediaId,
            sourceRange: TimeRange(start: clip.sourceRange.start, end: sourceMid),
            timelineRange: TimeRange(start: clip.timelineRange.start, end: cutTimeUs)
        )
        let rightClip = Clip(
            trackId: clip.trackId,
            mediaId: clip.mediaId,
            sourceRange: TimeRange(start: sourceMid, end: clip.sourceRange.end),
            timelineRange: TimeRange(start: cutTimeUs, end: clip.timelineRange.end)
        )

        clips.remove(at: index)
        clips.append(leftClip)
        clips.append(rightClip)

        if selectedClipId == clipId {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedClipId = nil
            }
        }

        return [Action.replaceTrackClips(timelineId: timelineId, trackId: trackId, clips: before)]
    }

    private mutating func applyRemoveClip(clipId: String) -> [Action] {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return [] }
        let trackId = clip.trackId
        let before = orderedClips(for: trackId)

        clips.removeAll { $0.clipId == clipId }
        packTrackClips(trackId: trackId, animate: true)

        let maxScrollTimeUs = max(0, calculatedTimelineDurationUs) + scrollBufferUs
        if currentTimeAtCenter > maxScrollTimeUs {
            requestScrollTo(timeUs: maxScrollTimeUs)
        }

        if selectedClipId == clipId {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedClipId = nil
            }
        }

        return [Action.replaceTrackClips(timelineId: timelineId, trackId: trackId, clips: before)]
    }

    private mutating func applyAddClip(_ clip: Clip) -> [Action] {
        let trackId = clip.trackId
        let before = orderedClips(for: trackId)
        clips.append(clip)
        return [Action.replaceTrackClips(timelineId: timelineId, trackId: trackId, clips: before)]
    }

    private mutating func applyTrimClipCommitted(
        clipId: String,
        sourceRange: TimeRange
    ) -> [Action] {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return [] }
        guard sourceRange.duration > 0 else { return [] }
        let trackId = clip.trackId
        let before = orderedClips(for: trackId)
        trimClip(clipId: clipId, sourceRange: sourceRange, timelineRange: clip.timelineRange, commit: true)
        return [Action.replaceTrackClips(timelineId: timelineId, trackId: trackId, clips: before)]
    }

    private mutating func applyMoveClipCommitted(clipId: String, orderedClipIds: [String]) -> [Action] {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return [] }
        let trackId = clip.trackId
        let before = orderedClips(for: trackId)
        moveClip(clipId: clipId, toStartTimeUs: 0, orderedClipIds: orderedClipIds)
        return [Action.replaceTrackClips(timelineId: timelineId, trackId: trackId, clips: before)]
    }

    private mutating func applyReplaceTrackClips(trackId: String, clips replacement: [Clip]) -> [Action] {
        let previous = orderedClips(for: trackId)
        clips.removeAll { $0.trackId == trackId }
        clips.append(contentsOf: replacement)

        if let sel = selectedClipId, !clips.contains(where: { $0.clipId == sel }) {
            selectedClipId = nil
        }

        return [Action.replaceTrackClips(timelineId: timelineId, trackId: trackId, clips: previous)]
    }
}
