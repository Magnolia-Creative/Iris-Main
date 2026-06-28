import Foundation

@MainActor
final class TimelinePersistenceCoordinator {
    struct ClipDiff {
        let added: [Clip]
        let updated: [Clip]
        let deletedIds: [String]
    }

    struct EffectDiff {
        let created: [Effect]
        let updated: [Effect]
        let deletedIds: [String]
    }

    struct CaptionCueDiff {
        let created: [CaptionCue]
        let updated: [CaptionCue]
        let deletedIds: [String]
    }

    private let persistence: TimelinePersistence
    private var persistedTrackIds: Set<String> = []
    private var debouncedSaveTask: Task<Void, Never>?

    init(persistence: TimelinePersistence) {
        self.persistence = persistence
    }

    func markPersistedTracks(_ tracks: [Track]) {
        persistedTrackIds = Set(tracks.map(\.trackId))
    }

    func persistClipChanges(before: [Clip], after: [Clip], tracks: [Track], timeline: Timeline?) {
        let diff = clipDiff(before: before, after: after)
        persistClipChanges(diff, tracks: tracks, timeline: timeline)
    }

    func persistClipChanges(_ diff: ClipDiff, tracks: [Track], timeline: Timeline?) {
        guard !diff.added.isEmpty || !diff.updated.isEmpty || !diff.deletedIds.isEmpty else { return }

        persistNewTracks(tracks)

        do {
            for clip in diff.added { try persistence.createClip(clip) }
            for clip in diff.updated { try persistence.updateClip(clip) }
            for clipId in diff.deletedIds { try persistence.deleteClip(clipId: clipId) }
        } catch {
            print("Failed to persist clip changes: \(error)")
        }

        scheduleDebouncedMetadataSave(timeline: timeline)
    }

    func persistEffectChanges(created: [Effect], updated: [Effect], deletedIds: [String], timeline: Timeline?) {
        guard !created.isEmpty || !updated.isEmpty || !deletedIds.isEmpty else { return }

        do {
            for effect in created { try persistence.createEffect(effect) }
            for effect in updated { try persistence.updateEffect(effect) }
            for effectId in deletedIds { try persistence.deleteEffect(effectId: effectId) }
        } catch {
            print("Failed to persist effect changes: \(error)")
        }

        scheduleDebouncedMetadataSave(timeline: timeline)
    }

    func persistCaptionCueChanges(created: [CaptionCue], updated: [CaptionCue], deletedIds: [String], timeline: Timeline?) {
        guard !created.isEmpty || !updated.isEmpty || !deletedIds.isEmpty else { return }

        do {
            for cue in created { try persistence.createCaptionCue(cue) }
            for cue in updated { try persistence.updateCaptionCue(cue) }
            for cueId in deletedIds { try persistence.deleteCaptionCue(cueId: cueId) }
        } catch {
            print("Failed to persist caption cue changes: \(error)")
        }

        scheduleDebouncedMetadataSave(timeline: timeline)
    }

    func persistNewTracks(_ tracks: [Track]) {
        for track in tracks where !persistedTrackIds.contains(track.trackId) {
            do {
                try persistence.createTrack(track)
                persistedTrackIds.insert(track.trackId)
            } catch {
                // Track may already exist from initial load.
                persistedTrackIds.insert(track.trackId)
            }
        }
    }

    func clipDiff(before: [Clip], after: [Clip]) -> ClipDiff {
        let beforeById = Dictionary(uniqueKeysWithValues: before.map { ($0.clipId, $0) })
        let afterById = Dictionary(uniqueKeysWithValues: after.map { ($0.clipId, $0) })
        let beforeIds = Set(beforeById.keys)
        let afterIds = Set(afterById.keys)

        let added = afterIds.subtracting(beforeIds).compactMap { afterById[$0] }
        let deletedIds = Array(beforeIds.subtracting(afterIds))
        let updated = beforeIds.intersection(afterIds).compactMap { id -> Clip? in
            guard let prev = beforeById[id], let curr = afterById[id] else { return nil }
            guard didClipChange(before: prev, after: curr) else { return nil }
            return curr
        }

        return ClipDiff(added: added, updated: updated, deletedIds: deletedIds)
    }

    func effectDiff(before: [Effect], after: [Effect]) -> EffectDiff {
        let beforeById = Dictionary(uniqueKeysWithValues: before.map { ($0.effectId, $0) })
        let afterById = Dictionary(uniqueKeysWithValues: after.map { ($0.effectId, $0) })
        let beforeIds = Set(beforeById.keys)
        let afterIds = Set(afterById.keys)

        let created = afterIds.subtracting(beforeIds).compactMap { afterById[$0] }
        let deletedIds = Array(beforeIds.subtracting(afterIds))
        let updated = beforeIds.intersection(afterIds).compactMap { id -> Effect? in
            guard let prev = beforeById[id], let curr = afterById[id] else { return nil }
            guard didEffectChange(before: prev, after: curr) else { return nil }
            return curr
        }

        return EffectDiff(created: created, updated: updated, deletedIds: deletedIds)
    }

    func captionCueDiff(before: [CaptionCue], after: [CaptionCue]) -> CaptionCueDiff {
        let beforeById = Dictionary(uniqueKeysWithValues: before.map { ($0.cueId, $0) })
        let afterById = Dictionary(uniqueKeysWithValues: after.map { ($0.cueId, $0) })
        let beforeIds = Set(beforeById.keys)
        let afterIds = Set(afterById.keys)

        let created = afterIds.subtracting(beforeIds).compactMap { afterById[$0] }
        let deletedIds = Array(beforeIds.subtracting(afterIds))
        let updated = beforeIds.intersection(afterIds).compactMap { id -> CaptionCue? in
            guard let prev = beforeById[id], let curr = afterById[id] else { return nil }
            guard didCaptionCueChange(before: prev, after: curr) else { return nil }
            return curr
        }

        return CaptionCueDiff(created: created, updated: updated, deletedIds: deletedIds)
    }

    private func scheduleDebouncedMetadataSave(timeline: Timeline?) {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            if var timeline {
                timeline.updatedAt = Date()
                try? persistence.updateTimeline(timeline)
            }
        }
    }

    private func didEffectChange(before: Effect, after: Effect) -> Bool {
        before.type != after.type
            || before.appliesTo != after.appliesTo
            || before.targetId != after.targetId
            || before.parameters != after.parameters
    }

    private func didClipChange(before: Clip, after: Clip) -> Bool {
        before.trackId != after.trackId || before.mediaId != after.mediaId
            || before.sourceRange.start != after.sourceRange.start
            || before.sourceRange.end != after.sourceRange.end
            || before.timelineRange.start != after.timelineRange.start
            || before.timelineRange.end != after.timelineRange.end
    }

    private func didCaptionCueChange(before: CaptionCue, after: CaptionCue) -> Bool {
        before.groupId != after.groupId
            || before.clipId != after.clipId
            || before.text != after.text
            || before.timelineStartUs != after.timelineStartUs
            || before.timelineEndUs != after.timelineEndUs
            || before.sourceStartUs != after.sourceStartUs
            || before.sourceEndUs != after.sourceEndUs
    }
}
