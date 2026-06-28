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
}
