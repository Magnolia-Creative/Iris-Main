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
        if !actions.isEmpty {
            refreshDerivedOutputAspect()
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

        case let .removeClipRanges(clipId, sourceRanges):
            return applyRemoveClipRanges(clipId: clipId, sourceRanges: sourceRanges)

        case let .moveClip(clipId, orderedClipIds):
            return applyMoveClipCommitted(clipId: clipId, orderedClipIds: orderedClipIds)

        case let .replaceTrackClips(trackId, replacement):
            return applyReplaceTrackClips(trackId: trackId, clips: replacement)

        case let .updateClipColorFilter(clipId, adjustments):
            return applyUpdateClipColorFilter(clipId: clipId, adjustments: adjustments)

        case let .setClipColorFilter(clipId, filter):
            return applySetClipColorFilter(clipId: clipId, filter: filter)

        case let .resetClipColorFilter(clipId):
            return applyResetClipColorFilter(clipId: clipId)
        }
    }

    // MARK: - Undo / redo (history)

    /// Applies `forward` via `apply`, optionally records an undo group, and returns the combined inverse batch.
    @discardableResult
    mutating func applyRecordingUndo(forward actions: [Action], recordUndo: Bool) -> [Action] {
        let inverse = apply(actions)
        if recordUndo, !inverse.isEmpty {
            undoActionStack.append(
                TimelineActionHistoryGroup(forwardActions: actions, inverseActions: inverse)
            )
            redoActionStack.removeAll()
        }
        return inverse
    }

    /// Pops the latest undo group, applies its inverse, and pushes a redo entry. Returns whether a step ran.
    @discardableResult
    mutating func undoLastActionGroupFromHistory() -> Bool {
        guard let group = undoActionStack.popLast() else { return false }
        let redoForward = apply(group.inverseActions)
        redoActionStack.append(
            TimelineActionHistoryGroup(forwardActions: redoForward, inverseActions: group.inverseActions)
        )
        return true
    }

    /// Pops the latest redo group, reapplies its forward batch, and pushes an undo entry. Returns whether a step ran.
    @discardableResult
    mutating func redoLastActionGroupFromHistory() -> Bool {
        guard let group = redoActionStack.popLast() else { return false }
        let undoInverse = apply(group.forwardActions)
        undoActionStack.append(
            TimelineActionHistoryGroup(forwardActions: group.forwardActions, inverseActions: undoInverse)
        )
        return true
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
        applyCaptionCueSplit(originalClipId: clipId, leftClip: leftClip, rightClip: rightClip, sourceMid: sourceMid)

        if selectedClipId == clipId {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedClipId = nil
            }
        }

        return [Action.replaceTrackClips(timelineId: timelineId, trackId: trackId, clips: before)]
    }

    private mutating func applyCaptionCueSplit(
        originalClipId: String,
        leftClip: Clip,
        rightClip: Clip,
        sourceMid: Int64
    ) {
        guard !captionCues.isEmpty else { return }
        let now = Date()
        var updatedCues: [CaptionCue] = []

        for cue in captionCues {
            guard cue.clipId == originalClipId,
                  let sourceStart = cue.sourceStartUs,
                  let sourceEnd = cue.sourceEndUs,
                  sourceEnd > sourceStart
            else {
                updatedCues.append(cue)
                continue
            }

            if sourceEnd <= sourceMid {
                if let reassigned = cue.reanchored(to: leftClip, sourceStartUs: sourceStart, sourceEndUs: sourceEnd, updatedAt: now) {
                    updatedCues.append(reassigned)
                }
            } else if sourceStart >= sourceMid {
                if let reassigned = cue.reanchored(to: rightClip, sourceStartUs: sourceStart, sourceEndUs: sourceEnd, updatedAt: now) {
                    updatedCues.append(reassigned)
                }
            } else {
                let splitText = splitCaptionText(cue.text, sourceStartUs: sourceStart, splitUs: sourceMid, sourceEndUs: sourceEnd)
                if let leftCue = cue.reanchored(to: leftClip, sourceStartUs: sourceStart, sourceEndUs: sourceMid, text: splitText.left, updatedAt: now) {
                    updatedCues.append(leftCue)
                }
                if let rightCue = CaptionCue(
                    groupId: cue.groupId,
                    clipId: rightClip.clipId,
                    text: splitText.right,
                    timelineStartUs: cue.timelineStartUs,
                    timelineEndUs: cue.timelineEndUs,
                    sourceStartUs: sourceMid,
                    sourceEndUs: sourceEnd,
                    createdAt: cue.createdAt,
                    updatedAt: now
                ).projectedThroughCurrentClip(rightClip) {
                    updatedCues.append(rightCue)
                }
            }
        }

        captionCues = updatedCues.sorted { lhs, rhs in
            lhs.timelineStartUs == rhs.timelineStartUs
                ? lhs.cueId < rhs.cueId
                : lhs.timelineStartUs < rhs.timelineStartUs
        }
    }

    private func splitCaptionText(_ text: String, sourceStartUs: Int64, splitUs: Int64, sourceEndUs: Int64) -> (left: String, right: String) {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1, sourceEndUs > sourceStartUs else { return (text, text) }

        let ratio = Double(splitUs - sourceStartUs) / Double(sourceEndUs - sourceStartUs)
        let rawLeftCount = Int((Double(words.count) * ratio).rounded())
        let leftCount = min(max(rawLeftCount, 1), words.count - 1)
        return (
            words[..<leftCount].joined(separator: " "),
            words[leftCount...].joined(separator: " ")
        )
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

    private mutating func applyRemoveClipRanges(clipId: String, sourceRanges: [TimeRange]) -> [Action] {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return [] }
        let trackId = clip.trackId
        let before = orderedClips(for: trackId)
        let removalRanges = normalizedRemovalRanges(sourceRanges, within: clip.sourceRange)
        guard removalRanges.isEmpty == false else { return [] }

        let survivors = survivorRanges(from: clip.sourceRange, removing: removalRanges)
        if survivors.isEmpty {
            return applyRemoveClip(clipId: clipId)
        }

        let trackClips = orderedClips(for: trackId)
        let replacementClips = replacementTrackClips(
            trackClips: trackClips,
            replacing: clip,
            withSourceRanges: survivors
        )
        clips.removeAll { $0.trackId == trackId }
        clips.append(contentsOf: packedClips(from: replacementClips))

        if selectedClipId == clipId {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedClipId = nil
            }
        }

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

    private func normalizedRemovalRanges(_ ranges: [TimeRange], within sourceRange: TimeRange) -> [TimeRange] {
        let bounded = ranges.compactMap { range -> TimeRange? in
            let start = max(sourceRange.start, range.start)
            let end = min(sourceRange.end, range.end)
            guard end > start else { return nil }
            return TimeRange(start: start, end: end)
        }
        .sorted { left, right in
            left.start == right.start ? left.end < right.end : left.start < right.start
        }

        return bounded.reduce(into: [TimeRange]()) { merged, range in
            guard let last = merged.last else {
                merged.append(range)
                return
            }
            if range.start <= last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
    }

    private func survivorRanges(from sourceRange: TimeRange, removing removalRanges: [TimeRange]) -> [TimeRange] {
        var survivors: [TimeRange] = []
        var cursor = sourceRange.start
        for range in removalRanges {
            if range.start > cursor {
                survivors.append(TimeRange(start: cursor, end: range.start))
            }
            cursor = max(cursor, range.end)
        }
        if cursor < sourceRange.end {
            survivors.append(TimeRange(start: cursor, end: sourceRange.end))
        }
        return survivors.filter { $0.duration > 0 }
    }

    // MARK: - Color filter executors

    private mutating func applyUpdateClipColorFilter(
        clipId: String,
        adjustments: ClipColorFilterPatch
    ) -> [Action] {
        guard clips.contains(where: { $0.clipId == clipId }) else { return [] }
        let previousFilter = latestClipColorFilter(for: clipId)
        let baseline = previousFilter ?? .neutral
        let nextFilter = baseline.applying(adjustments)
        return writeClipColorFilter(
            clipId: clipId,
            nextFilter: nextFilter,
            previousFilter: previousFilter
        )
    }

    private mutating func applySetClipColorFilter(
        clipId: String,
        filter: ClipColorFilter
    ) -> [Action] {
        guard clips.contains(where: { $0.clipId == clipId }) else { return [] }
        let previousFilter = latestClipColorFilter(for: clipId)
        return writeClipColorFilter(
            clipId: clipId,
            nextFilter: filter,
            previousFilter: previousFilter
        )
    }

    private mutating func applyResetClipColorFilter(clipId: String) -> [Action] {
        guard clips.contains(where: { $0.clipId == clipId }) else { return [] }
        let previousFilter = latestClipColorFilter(for: clipId)
        guard previousFilter != nil else { return [] }
        removeAllClipColorFilterEffects(for: clipId)
        return [
            Action.setClipColorFilter(
                timelineId: timelineId,
                clipId: clipId,
                filter: previousFilter ?? .neutral
            )
        ]
    }

    /// Writes `nextFilter` onto the clip, collapsing any duplicate
    /// `clip_color_filter` effects to a single row, and returns the inverse
    /// action that restores the previous filter (or removes it).
    private mutating func writeClipColorFilter(
        clipId: String,
        nextFilter: ClipColorFilter,
        previousFilter: ClipColorFilter?
    ) -> [Action] {
        let inverse: Action
        if let previousFilter {
            inverse = Action.setClipColorFilter(
                timelineId: timelineId,
                clipId: clipId,
                filter: previousFilter
            )
        } else {
            inverse = Action.resetClipColorFilter(timelineId: timelineId, clipId: clipId)
        }

        if nextFilter.isNeutral {
            removeAllClipColorFilterEffects(for: clipId)
            return previousFilter == nil ? [] : [inverse]
        }

        if previousFilter == nextFilter {
            return []
        }

        let matching = clipColorFilterEffects(for: clipId)
        let existing = matching.max { $0.updatedAt < $1.updatedAt }
        let now = Date()
        let updatedEffect = Effect.clipColorFilter(
            timelineId: timelineId,
            clipId: clipId,
            filter: nextFilter,
            effectId: existing?.effectId ?? UUID().uuidString,
            createdAt: existing?.createdAt ?? now
        )

        let duplicateIds = Set(matching.map(\.effectId)).subtracting([updatedEffect.effectId])
        effects.removeAll { duplicateIds.contains($0.effectId) }
        if let index = effects.firstIndex(where: { $0.effectId == updatedEffect.effectId }) {
            effects[index] = updatedEffect
        } else {
            effects.append(updatedEffect)
        }

        return [inverse]
    }

    private func clipColorFilterEffects(for clipId: String) -> [Effect] {
        effects.filter {
            $0.targetId == clipId
                && $0.appliesTo == .clip
                && $0.type == ClipColorFilter.effectType
        }
    }

    private func latestClipColorFilter(for clipId: String) -> ClipColorFilter? {
        clipColorFilterEffects(for: clipId)
            .max { $0.updatedAt < $1.updatedAt }?
            .clipColorFilter
    }

    private mutating func removeAllClipColorFilterEffects(for clipId: String) {
        let matchingIds = Set(clipColorFilterEffects(for: clipId).map(\.effectId))
        guard !matchingIds.isEmpty else { return }
        effects.removeAll { matchingIds.contains($0.effectId) }
    }

    private func replacementTrackClips(
        trackClips: [Clip],
        replacing clip: Clip,
        withSourceRanges sourceRanges: [TimeRange]
    ) -> [Clip] {
        trackClips.flatMap { candidate -> [Clip] in
            guard candidate.clipId == clip.clipId else { return [candidate] }
            return sourceRanges.map { sourceRange in
                Clip(
                    trackId: clip.trackId,
                    mediaId: clip.mediaId,
                    sourceRange: sourceRange,
                    timelineRange: TimeRange(start: 0, end: sourceRange.duration)
                )
            }
        }
    }
}

private extension CaptionCue {
    func reanchored(
        to clip: Clip,
        sourceStartUs: Int64,
        sourceEndUs: Int64,
        text: String? = nil,
        updatedAt: Date
    ) -> CaptionCue? {
        CaptionCue(
            cueId: cueId,
            groupId: groupId,
            clipId: clip.clipId,
            text: text ?? self.text,
            timelineStartUs: timelineStartUs,
            timelineEndUs: timelineEndUs,
            sourceStartUs: sourceStartUs,
            sourceEndUs: sourceEndUs,
            createdAt: createdAt,
            updatedAt: updatedAt
        ).projectedThroughCurrentClip(clip)
    }

    func projectedThroughCurrentClip(_ clip: Clip) -> CaptionCue? {
        guard let range = CaptionCueProjection.currentTimelineRange(for: self, clips: [clip.clipId: clip]) else { return nil }
        var cue = self
        cue.timelineStartUs = range.start
        cue.timelineEndUs = range.end
        return cue
    }
}
