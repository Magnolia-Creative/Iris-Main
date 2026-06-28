import Foundation

struct TimelineEditingService {
    struct MutationSnapshot {
        let beforeClips: [Clip]
        let beforeEffects: [Effect]
        let beforeCaptionCues: [CaptionCue]
        let afterClips: [Clip]
        let afterEffects: [Effect]
        let afterCaptionCues: [CaptionCue]

        init(before stateBefore: TimelineState, after stateAfter: TimelineState) {
            beforeClips = stateBefore.clips
            beforeEffects = stateBefore.effects
            beforeCaptionCues = stateBefore.captionCues
            afterClips = stateAfter.clips
            afterEffects = stateAfter.effects
            afterCaptionCues = stateAfter.captionCues
        }
    }

    struct ActionApplication {
        let snapshot: MutationSnapshot
        let inverseActions: [Action]
    }

    struct EffectMutation {
        let created: [Effect]
        let updated: [Effect]
        let deletedIds: [String]
    }

    func applyActions(
        _ actions: [Action],
        to state: inout TimelineState,
        recordUndo: Bool = true
    ) -> ActionApplication? {
        guard !actions.isEmpty else { return nil }
        let before = state
        let inverseActions = state.applyRecordingUndo(forward: actions, recordUndo: recordUndo)
        return ActionApplication(
            snapshot: MutationSnapshot(before: before, after: state),
            inverseActions: inverseActions
        )
    }

    func undoLastActionGroup(in state: inout TimelineState) -> MutationSnapshot? {
        let before = state
        guard state.undoLastActionGroupFromHistory() else { return nil }
        return MutationSnapshot(before: before, after: state)
    }

    func redoLastActionGroup(in state: inout TimelineState) -> MutationSnapshot? {
        let before = state
        guard state.redoLastActionGroupFromHistory() else { return nil }
        return MutationSnapshot(before: before, after: state)
    }

    func moveClipActions(timelineId: String, clipId: String, orderedClipIds: [String]) -> [Action] {
        [
            Action.moveClip(
                timelineId: timelineId,
                clipId: clipId,
                orderedClipIds: orderedClipIds
            )
        ]
    }

    func trimClipActions(timelineId: String, clipId: String, sourceRange: TimeRange) -> [Action] {
        [
            Action.trimClip(
                timelineId: timelineId,
                clipId: clipId,
                sourceRange: sourceRange
            )
        ]
    }

    func previewTrimClip(
        clipId: String,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        in state: inout TimelineState
    ) {
        state.trimClip(
            clipId: clipId,
            sourceRange: sourceRange,
            timelineRange: timelineRange,
            commit: false
        )
    }

    func deleteSelectedClipActions(in state: TimelineState) -> [Action]? {
        guard let clipId = state.selectedClipId else { return nil }
        return [Action.removeClip(timelineId: state.timelineId, clipId: clipId)]
    }

    func splitSelectedClipActions(in state: TimelineState) -> [Action]? {
        guard let clipId = state.selectedClipId else { return nil }
        return [
            Action.splitClip(
                timelineId: state.timelineId,
                clipId: clipId,
                atTimeUs: state.currentTimeAtCenter
            )
        ]
    }

    func clipColorFilter(for clipId: String, in state: TimelineState) -> ClipColorFilter {
        latestClipColorFilterEffect(for: clipId, in: state)?.clipColorFilter ?? .neutral
    }

    func setClipColorFilterActions(clipId: String, filter: ClipColorFilter, in state: TimelineState) -> [Action]? {
        guard state.clips.contains(where: { $0.clipId == clipId }) else { return nil }
        if filter.isNeutral {
            return resetClipColorFilterActions(clipId: clipId, in: state)
        }
        return [
            Action.setClipColorFilter(
                timelineId: state.timelineId,
                clipId: clipId,
                filter: filter
            )
        ]
    }

    func resetClipColorFilterActions(clipId: String, in state: TimelineState) -> [Action] {
        [Action.resetClipColorFilter(timelineId: state.timelineId, clipId: clipId)]
    }

    func clipVolume(for clipId: String, in state: TimelineState) -> ClipVolume {
        latestClipVolumeEffect(for: clipId, in: state)?.clipVolume ?? .neutral
    }

    func setClipVolume(clipId: String, volume: ClipVolume, in state: inout TimelineState) -> EffectMutation? {
        guard state.clips.contains(where: { $0.clipId == clipId }) else { return nil }
        if volume.isNeutral {
            return resetClipVolume(clipId: clipId, in: &state)
        }

        let matchingEffects = clipVolumeEffects(for: clipId, in: state)
        let existingEffect = matchingEffects.max { $0.updatedAt < $1.updatedAt }
        let updatedEffect = Effect.clipVolume(
            timelineId: state.timelineId,
            clipId: clipId,
            volume: volume,
            effectId: existingEffect?.effectId ?? UUID().uuidString,
            createdAt: existingEffect?.createdAt ?? Date()
        )

        let duplicateEffectIds = Set(matchingEffects.map(\.effectId)).subtracting([updatedEffect.effectId])
        state.effects.removeAll { duplicateEffectIds.contains($0.effectId) }

        if let index = state.effects.firstIndex(where: { $0.effectId == updatedEffect.effectId }) {
            state.effects[index] = updatedEffect
            return EffectMutation(created: [], updated: [updatedEffect], deletedIds: Array(duplicateEffectIds))
        } else {
            state.effects.append(updatedEffect)
            return EffectMutation(created: [updatedEffect], updated: [], deletedIds: Array(duplicateEffectIds))
        }
    }

    func resetClipVolume(clipId: String, in state: inout TimelineState) -> EffectMutation? {
        let matchingEffects = clipVolumeEffects(for: clipId, in: state)
        guard !matchingEffects.isEmpty else { return nil }

        let deletedIds = matchingEffects.map(\.effectId)
        state.effects.removeAll { deletedIds.contains($0.effectId) }
        return EffectMutation(created: [], updated: [], deletedIds: deletedIds)
    }

    private func clipColorFilterEffects(for clipId: String, in state: TimelineState) -> [Effect] {
        state.effects.filter {
            $0.targetId == clipId
                && $0.appliesTo == .clip
                && $0.type == ClipColorFilter.effectType
        }
    }

    private func latestClipColorFilterEffect(for clipId: String, in state: TimelineState) -> Effect? {
        clipColorFilterEffects(for: clipId, in: state).max { $0.updatedAt < $1.updatedAt }
    }

    private func clipVolumeEffects(for clipId: String, in state: TimelineState) -> [Effect] {
        state.effects.filter {
            $0.targetId == clipId
                && $0.appliesTo == .clip
                && $0.type == ClipVolume.effectType
        }
    }

    private func latestClipVolumeEffect(for clipId: String, in state: TimelineState) -> Effect? {
        clipVolumeEffects(for: clipId, in: state).max { $0.updatedAt < $1.updatedAt }
    }
}
