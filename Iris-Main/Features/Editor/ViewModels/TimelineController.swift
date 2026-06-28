import Foundation
import OSLog
import Photos
import PhotosUI
import SwiftUI
internal import Combine

final class TimelineController: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "TimelineController"
    )

    @Published private(set) var state: TimelineState
    /// Prompt-bar intent actions awaiting per-step approve/reject (split, trim, remove ranges).
    private let reviewCoordinator = TimelineReviewCoordinator()
    private let db: DatabaseManager
    private let persistence: TimelinePersistence
    private let persistenceCoordinator: TimelinePersistenceCoordinator
    private let editingService = TimelineEditingService()
    private let importService: MediaImportService
    private var hasAppliedInitialImportSeed = false
    private var importedMediaBySeedLocalKey: [String: Media] = [:]
    private var cancellables: Set<AnyCancellable> = []

    var canUndo: Bool { state.canUndo }
    var canRedo: Bool { state.canRedo }
    private(set) var cutReview: TimelineCutReviewSession? {
        get { reviewCoordinator.cutReview }
        set { reviewCoordinator.cutReview = newValue }
    }
    private(set) var promptActionReview: TimelinePromptActionReviewSession? {
        get { reviewCoordinator.promptActionReview }
        set { reviewCoordinator.promptActionReview = newValue }
    }
    private(set) var promptActionReviewMessage: String? {
        get { reviewCoordinator.promptActionReviewMessage }
        set { reviewCoordinator.promptActionReviewMessage = newValue }
    }

    /// Preview geometry and focus for the current pending prompt action, if any.
    var promptActionPreview: TimelinePromptActionPreview? {
        guard let session = promptActionReview,
              let action = session.currentAction,
              action.isPromptSequenceReviewable
        else { return nil }
        return TimelinePromptActionPreviewBuilder.makePreview(state: state, action: action)
    }

    init(
        timelineId: String,
        db: DatabaseManager = .shared,
        importService: MediaImportService = .shared
    ) {
        self.state = TimelineState(timelineId: timelineId)
        self.db = db
        let persistence = TimelinePersistence(db: db)
        self.persistence = persistence
        self.persistenceCoordinator = TimelinePersistenceCoordinator(persistence: persistence)
        self.importService = importService
        reviewCoordinator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func binding<Value>(_ keyPath: WritableKeyPath<TimelineState, Value>) -> Binding<Value> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { self.state[keyPath: keyPath] = $0 }
        )
    }

    /// Persists optional manual canvas aspect on the local project (`nil` = automatic from first clip).
    @MainActor
    func setManualPlaybackOutputAspect(_ aspect: OutputAspectRatio?) throws {
        guard let projectId = state.projectId else { return }
        guard var project = try db.get(Project.self, id: projectId, keyColumn: "project_id") else { return }
        if let aspect {
            project.manualOutputAspectWidth = aspect.width
            project.manualOutputAspectHeight = aspect.height
        } else {
            project.manualOutputAspectWidth = nil
            project.manualOutputAspectHeight = nil
        }
        project.updatedAt = Date()
        try db.update(project)
        var nextState = state
        nextState.manualOutputAspect = aspect
        state = nextState
    }

    /// Unit tests only: installs synthetic tracks/clips without touching persistence.
    internal func replaceTimelineContentForTesting(tracks: [Track], clips: [Clip]) {
        state.tracks = tracks
        state.clips = clips
        state.captionGroups = []
        state.captionCues = []
        state.clearActionHistory()
        state.refreshDerivedOutputAspect()
    }

    func loadTimelineData() async {
        do {
            let loaded = try persistence.loadTimelineData(timelineId: state.timelineId)
            Self.logger.notice(
                """
                [TimelineLoad] loaded timeline=\(self.state.timelineId, privacy: .public) \
                localProject=\(loaded.timeline.projectId, privacy: .public) \
                backendProject=\(loaded.backendProjectId ?? "nil", privacy: .public) \
                tracks=\(loaded.tracks.count, privacy: .public) \
                clips=\(loaded.clips.count, privacy: .public) \
                media=\(loaded.mediaById.count, privacy: .public)
                """
            )
            await MainActor.run {
                state.applyLoadedData(
                    timeline: loaded.timeline,
                    tracks: loaded.tracks,
                    clips: loaded.clips,
                    effects: loaded.effects,
                    mediaLibrary: loaded.mediaLibrary,
                    mediaById: loaded.mediaById,
                    projectTitle: loaded.projectTitle,
                    project: loaded.project,
                    backendProjectId: loaded.backendProjectId,
                    captionGroups: loaded.captionGroups,
                    captionCues: loaded.captionCues
                )
                persistenceCoordinator.markPersistedTracks(loaded.tracks)
            }
        } catch {
            print("Failed to load timeline data: \(error)")
        }
    }

    /// Reloads `TimelineState.backendProjectId` from SQLite when it is missing (e.g. after relink or before captions preflight).
    @MainActor
    internal func refreshBackendProjectMappingFromStoreIfNeeded() async {
        let trimmed = state.backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty else { return }
        do {
            let loaded = try persistence.loadTimelineData(timelineId: state.timelineId)
            let bid = loaded.backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !bid.isEmpty else { return }
            state.backendProjectId = bid
            Self.logger.notice(
                "[TimelineController] refreshed backendProjectId from store timeline=\(self.state.timelineId, privacy: .public) backend=\(bid, privacy: .public)"
            )
        } catch {
            Self.logger.error(
                "[TimelineController] refreshBackendProjectMappingFromStore failed timeline=\(self.state.timelineId, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    @MainActor
    func applyInitialImportSeedIfNeeded(_ seed: ImportedTimelineSeed) async {
        guard !hasAppliedInitialImportSeed else { return }
        hasAppliedInitialImportSeed = true

        guard state.clips.isEmpty else { return }
        await applyImportedTimelineSeed(seed)
    }

    @MainActor
    func applyAgentImportSeed(_ seed: ImportedTimelineSeed) async {
        await applyImportedTimelineSeed(seed)
    }

    func startCutReview() {
        rebuildCutReview(startingAt: 0)
    }

    func finishCutReview() {
        cutReview = nil
        state.selectedClipId = nil
    }

    func approveCurrentCutReview() {
        guard var cutReview else { return }
        let nextIndex = cutReview.currentIndex + 1
        guard nextIndex < cutReview.items.count else {
            finishCutReview()
            return
        }

        cutReview.currentIndex = nextIndex
        cutReview.isRepromptComposerPresented = false
        cutReview.repromptDraft = ""
        self.cutReview = cutReview
        focusCurrentCutReview()
    }

    func showCutReviewRepromptComposer() {
        guard var cutReview else { return }
        cutReview.isRepromptComposerPresented = true
        self.cutReview = cutReview
    }

    func hideCutReviewRepromptComposer() {
        guard var cutReview else { return }
        cutReview.isRepromptComposerPresented = false
        cutReview.repromptDraft = ""
        self.cutReview = cutReview
    }

    func updateCutReviewRepromptDraft(_ draft: String) {
        guard var cutReview else { return }
        cutReview.repromptDraft = draft
        self.cutReview = cutReview
    }

    func cancelCurrentCutReview() {
        guard let activeReview = cutReview, let currentItem = activeReview.currentItem, currentItem.canCancel else {
            return
        }

        let trackClips = currentVideoTrackClips()
        guard
            let leftIndex = trackClips.firstIndex(where: { $0.clipId == currentItem.leftClipId }),
            leftIndex + 1 < trackClips.count
        else {
            rebuildCutReview(startingAt: activeReview.currentIndex)
            return
        }

        let leftClip = trackClips[leftIndex]
        let rightClip = trackClips[leftIndex + 1]
        guard rightClip.clipId == currentItem.rightClipId, leftClip.mediaId == rightClip.mediaId else {
            rebuildCutReview(startingAt: activeReview.currentIndex)
            return
        }

        let before = state.clips
        let mergedSourceRange = TimeRange(
            start: min(leftClip.sourceRange.start, rightClip.sourceRange.start),
            end: max(leftClip.sourceRange.end, rightClip.sourceRange.end)
        )
        let mergedDuration = max(mergedSourceRange.duration, 1)
        let now = Date()

        var mergedClip = leftClip
        mergedClip.sourceRange = mergedSourceRange
        mergedClip.timelineRange = TimeRange(
            start: leftClip.timelineRange.start,
            end: leftClip.timelineRange.start + mergedDuration
        )
        mergedClip.updatedAt = now

        var updatedTrackClips = Array(trackClips.prefix(leftIndex))
        updatedTrackClips.append(mergedClip)

        var cursor = mergedClip.timelineRange.end
        if leftIndex + 2 <= trackClips.count - 1 {
            for clip in trackClips[(leftIndex + 2)...] {
                var shiftedClip = clip
                let duration = max(shiftedClip.duration, 1)
                shiftedClip.timelineRange = TimeRange(start: cursor, end: cursor + duration)
                if shiftedClip.timelineRange.start != clip.timelineRange.start
                    || shiftedClip.timelineRange.end != clip.timelineRange.end {
                    shiftedClip.updatedAt = now
                }
                updatedTrackClips.append(shiftedClip)
                cursor += duration
            }
        }

        replaceTrackClips(trackId: leftClip.trackId, with: updatedTrackClips)
        state.selectedClipId = nil
        persistClipChanges(before: before, after: state.clips)
        rebuildCutReview(startingAt: activeReview.currentIndex)
    }

    func clearSelection() {
        state.clearSelection()
    }

    // MARK: - Prompt action preview / review

    /// Starts sequential review when the batch includes sequence edits and/or color filter updates.
    /// Leading actions that are neither sequence- nor color-reviewable are applied immediately in order.
    /// - Returns: `false` if review could not start (nothing reviewable or invalid timeline id).
    @discardableResult
    func startPromptActionReview(actions: [Action], prompt: String) -> Bool {
        guard actions.contains(where: \.isPromptSequenceReviewable)
            || actions.contains(where: \.isPromptColorReviewable) else { return false }
        guard actions.allSatisfy({ $0.timelineId == state.timelineId }) else { return false }

        promptActionReviewMessage = nil
        let session = TimelinePromptActionReviewSession(originalPrompt: prompt, actions: actions, currentIndex: 0)
        promptActionReview = session
        flushNonReviewableApplyingAll()
        guard promptActionReview != nil else { return false }
        syncPromptReviewPresentation()
        return true
    }

    func finishPromptActionReview() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            promptActionReview = nil
            promptActionReviewMessage = nil
        }
    }

    /// Clears review and returns the original user prompt for reprompting.
    func discardPromptActionReviewReturningPrompt() -> String? {
        let prompt = promptActionReview?.originalPrompt
        finishPromptActionReview()
        return prompt
    }

    func approveCurrentPromptAction() {
        guard var session = promptActionReview else { return }
        guard let action = session.currentAction, action.isPromptSequenceReviewable else { return }

        promptActionReviewMessage = nil
        session.promptColorReview = nil
        if !applyActions([action]) {
            promptActionReviewMessage = "This edit could not be applied. Skipping."
        }

        session.currentIndex += 1
        if session.currentIndex >= session.actions.count {
            finishPromptActionReview()
            return
        }

        promptActionReview = session
        flushNonReviewableApplyingAll()
        focusIfStillReviewing()
    }

    func rejectCurrentPromptAction() {
        guard var session = promptActionReview else { return }
        guard let action = session.currentAction, action.isPromptSequenceReviewable else { return }

        promptActionReviewMessage = nil
        session.promptColorReview = nil
        session.currentIndex += 1
        if session.currentIndex >= session.actions.count {
            finishPromptActionReview()
            return
        }

        promptActionReview = session
        flushNonReviewableApplyingAll()
        focusIfStillReviewing()
    }

    /// Advances one color field after the user taps the checkmark, or finishes the color action after the last field.
    func confirmCurrentPromptColorSubstep() {
        guard var session = promptActionReview else { return }
        guard var colorState = session.promptColorReview else { return }
        guard session.currentAction?.isPromptColorReviewable == true else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if colorState.fieldIndex < colorState.orderedFieldKeys.count - 1 {
                colorState.fieldIndex += 1
                session.promptColorReview = colorState
                promptActionReview = session
            } else {
                session.promptColorReview = nil
                session.currentIndex += 1
                promptActionReview = session
                flushNonReviewableApplyingAll()
                syncPromptReviewPresentation()
            }
        }
    }

    /// Restores the active color field to its value before the current `updateClipColorFilter` was applied.
    func resetCurrentPromptColorReviewField() {
        guard let session = promptActionReview,
              let colorState = session.promptColorReview,
              case let .updateClipColorFilter(clipId, _) = session.currentAction?.payload
        else { return }
        let key = colorState.orderedFieldKeys[colorState.fieldIndex]
        guard let field = ClipColorFilterPromptField(patchKey: key) else { return }
        var filter = clipColorFilter(for: clipId)
        let baselineValue = field.floatValue(in: colorState.baselineFilter)
        field.set(baselineValue, on: &filter)
        setClipColorFilter(clipId: clipId, filter: filter)
    }

    private func flushNonReviewableApplyingAll() {
        guard var session = promptActionReview else { return }
        while session.currentIndex < session.actions.count {
            let action = session.actions[session.currentIndex]
            guard !action.isPromptSequenceReviewable, !action.isPromptColorReviewable else { break }
            _ = applyActions([action])
            session.currentIndex += 1
        }

        if session.currentIndex >= session.actions.count {
            finishPromptActionReview()
        } else {
            promptActionReview = session
        }
    }

    private func focusIfStillReviewing() {
        syncPromptReviewPresentation()
    }

    private func syncPromptReviewPresentation() {
        guard promptActionReview != nil else { return }
        ensurePromptColorReviewActivated()
        guard let session = promptActionReview, let action = session.currentAction else { return }

        if action.isPromptColorReviewable, session.promptColorReview != nil {
            if case let .updateClipColorFilter(clipId, _) = action.payload {
                state.selectedClipId = clipId
            }
            return
        }

        if action.isPromptSequenceReviewable {
            focusCurrentPromptActionPreview()
        }
    }

    private func ensurePromptColorReviewActivated() {
        guard var session = promptActionReview,
              let action = session.currentAction,
              action.isPromptColorReviewable,
              session.promptColorReview == nil
        else { return }

        guard case let .updateClipColorFilter(clipId, patch) = action.payload else { return }
        let keys = patch.reviewOrderedKeys
        guard !keys.isEmpty else { return }

        let baseline = clipColorFilter(for: clipId)
        promptActionReviewMessage = nil

        if !applyActions([action]) {
            promptActionReviewMessage = "This edit could not be applied. Skipping."
            session.promptColorReview = nil
            session.currentIndex += 1
            promptActionReview = session
            flushNonReviewableApplyingAll()
            syncPromptReviewPresentation()
            return
        }

        session.promptColorReview = PromptColorReviewState(
            orderedFieldKeys: keys,
            fieldIndex: 0,
            baselineFilter: baseline
        )
        state.selectedClipId = clipId
        promptActionReview = session
    }

    private func focusCurrentPromptActionPreview() {
        guard let session = promptActionReview,
              let action = session.currentAction,
              action.isPromptSequenceReviewable
        else { return }

        if let preview = TimelinePromptActionPreviewBuilder.makePreview(state: state, action: action) {
            state.selectedClipId = nil
            state.currentTimeAtCenter = preview.scrollFocusTimeUs
            state.requestScrollTo(timeUs: preview.scrollFocusTimeUs)
        } else {
            promptActionReviewMessage = "This edit could not be previewed."
        }
    }

    /// Applies timeline commands, persists clip changes, and records an undo group.
    @discardableResult
    func applyActions(_ actions: [Action], recordUndo: Bool = true) -> Bool {
        guard !actions.isEmpty else { return false }
        Self.logger.info(
            "[TimelineActions] Applying count=\(actions.count, privacy: .public) timeline=\(self.state.timelineId, privacy: .public) selectedClip=\(self.state.selectedClipId ?? "nil", privacy: .public) currentTimeUs=\(self.state.currentTimeAtCenter, privacy: .public) clipCount=\(self.state.clips.count, privacy: .public)"
        )

        guard let application = editingService.applyActions(actions, to: &state, recordUndo: recordUndo) else {
            return false
        }
        let snapshot = application.snapshot
        let diff = clipDiff(before: snapshot.beforeClips, after: snapshot.afterClips)
        let effectDiffResult = effectDiff(before: snapshot.beforeEffects, after: snapshot.afterEffects)
        let captionCueDiffResult = captionCueDiff(before: snapshot.beforeCaptionCues, after: snapshot.afterCaptionCues)
        let didChangeClips = !diff.added.isEmpty || !diff.updated.isEmpty || !diff.deletedIds.isEmpty
        let didChangeEffects = !effectDiffResult.created.isEmpty
            || !effectDiffResult.updated.isEmpty
            || !effectDiffResult.deletedIds.isEmpty
        let didChangeCaptionCues = !captionCueDiffResult.created.isEmpty
            || !captionCueDiffResult.updated.isEmpty
            || !captionCueDiffResult.deletedIds.isEmpty
        let didChange = didChangeClips || didChangeEffects || didChangeCaptionCues

        if didChange {
            Self.logger.info(
                "[TimelineActions] Applied count=\(actions.count, privacy: .public) added=\(diff.added.count, privacy: .public) updated=\(diff.updated.count, privacy: .public) deleted=\(diff.deletedIds.count, privacy: .public) effectsCreated=\(effectDiffResult.created.count, privacy: .public) effectsUpdated=\(effectDiffResult.updated.count, privacy: .public) effectsDeleted=\(effectDiffResult.deletedIds.count, privacy: .public) captionCuesCreated=\(captionCueDiffResult.created.count, privacy: .public) captionCuesUpdated=\(captionCueDiffResult.updated.count, privacy: .public) captionCuesDeleted=\(captionCueDiffResult.deletedIds.count, privacy: .public) inverseCount=\(application.inverseActions.count, privacy: .public)"
            )
        } else {
            Self.logger.error(
                "[TimelineActions] No-op applying actions count=\(actions.count, privacy: .public) inverseCount=\(application.inverseActions.count, privacy: .public) summary=\(Self.actionSummary(actions), privacy: .public) timelineClipSummary=\(Self.clipSummary(snapshot.beforeClips), privacy: .public)"
            )
        }

        persistClipChanges(diff)
        persistEffectChanges(
            created: effectDiffResult.created,
            updated: effectDiffResult.updated,
            deletedIds: effectDiffResult.deletedIds
        )
        persistCaptionCueChanges(
            created: captionCueDiffResult.created,
            updated: captionCueDiffResult.updated,
            deletedIds: captionCueDiffResult.deletedIds
        )

        objectWillChange.send()
        return didChange
    }

    func undoLastActionGroup() {
        guard let snapshot = editingService.undoLastActionGroup(in: &state) else { return }
        persistMutation(snapshot)
        objectWillChange.send()
    }

    func redoLastActionGroup() {
        guard let snapshot = editingService.redoLastActionGroup(in: &state) else { return }
        persistMutation(snapshot)
        objectWillChange.send()
    }

    func handleAddSelection(kind: TrackKind, source: ImportSource) {
        switch source {
        case .photos:
            state.beginImport(kind: kind, source: source)
            Task {
                let status = await importService.requestPhotoLibraryAccess()
                await MainActor.run {
                    state.handlePhotoAuthorization(status: status)
                }
            }
        case .files:
            state.beginImport(kind: kind, source: source)
        case .textBox, .caption:
            break
        }
    }

    @MainActor
    func finalizeCaptionGeneration(
        rangeStartUs: Int64,
        rangeEndUs: Int64,
        cues: [CaptionCue],
        style: CaptionStyle
    ) throws -> String {
        let timelineId = state.timelineId
        if state.tracks.first(where: { $0.kind == .captions }) == nil {
            let newTrack = Track(timelineId: timelineId, kind: .captions, sortIndex: state.tracks.count)
            state.tracks.append(newTrack)
        }
        persistNewTracks()
        guard let track = state.tracks.first(where: { $0.kind == .captions }) else {
            throw NSError(domain: "Captions", code: 1, userInfo: [NSLocalizedDescriptionKey: "No captions track"])
        }

        let groupId = UUID().uuidString
        let group = CaptionGroup(
            groupId: groupId,
            trackId: track.trackId,
            timelineId: timelineId,
            style: style,
            hasBackground: false,
            textColor: "#FFFFFF",
            rangeStartUs: rangeStartUs,
            rangeEndUs: rangeEndUs
        )
        try persistence.createCaptionGroup(group)

        var saved: [CaptionCue] = []
        for c in cues {
            let cue = CaptionCue(
                groupId: groupId,
                clipId: c.clipId,
                text: c.text,
                timelineStartUs: c.timelineStartUs,
                timelineEndUs: c.timelineEndUs,
                sourceStartUs: c.sourceStartUs,
                sourceEndUs: c.sourceEndUs
            )
            try persistence.createCaptionCue(cue)
            saved.append(cue)
        }
        state.captionGroups.append(group)
        state.captionCues.append(contentsOf: saved)
        objectWillChange.send()
        return groupId
    }

    func captionGroup(withId groupId: String) -> CaptionGroup? {
        state.captionGroups.first { $0.groupId == groupId }
    }

    @MainActor
    func applyCaptionGroupStyleUpdate(_ group: CaptionGroup) throws {
        try persistence.updateCaptionGroup(group)
        guard let idx = state.captionGroups.firstIndex(where: { $0.groupId == group.groupId }) else { return }
        state.captionGroups[idx] = group
        objectWillChange.send()
    }

    @MainActor
    func deleteCaptionGroup(groupId: String) throws {
        try persistence.deleteCaptionGroup(groupId: groupId)
        state.captionGroups.removeAll { $0.groupId == groupId }
        state.captionCues.removeAll { $0.groupId == groupId }
        objectWillChange.send()
    }

    func moveClip(clipId: String, toStartTimeUs timeUs: Int64, orderedClipIds: [String]) {
        _ = timeUs
        applyActions(editingService.moveClipActions(
            timelineId: state.timelineId,
            clipId: clipId,
            orderedClipIds: orderedClipIds
        ))
    }

    func trimClip(clipId: String, sourceRange: TimeRange, timelineRange: TimeRange, commit: Bool) {
        if !commit {
            editingService.previewTrimClip(
                clipId: clipId,
                sourceRange: sourceRange,
                timelineRange: timelineRange,
                in: &state
            )
            objectWillChange.send()
            return
        }
        applyActions(editingService.trimClipActions(
            timelineId: state.timelineId,
            clipId: clipId,
            sourceRange: sourceRange
        ))
    }

    func clipColorFilter(for clipId: String) -> ClipColorFilter {
        editingService.clipColorFilter(for: clipId, in: state)
    }

    func setClipColorFilter(clipId: String, filter: ClipColorFilter) {
        guard let actions = editingService.setClipColorFilterActions(clipId: clipId, filter: filter, in: state) else { return }
        applyActions(actions)
    }

    func resetClipColorFilter(clipId: String) {
        applyActions(editingService.resetClipColorFilterActions(clipId: clipId, in: state))
    }

    func clipVolume(for clipId: String) -> ClipVolume {
        editingService.clipVolume(for: clipId, in: state)
    }

    func setClipVolume(clipId: String, volume: ClipVolume) {
        guard let mutation = editingService.setClipVolume(clipId: clipId, volume: volume, in: &state) else { return }
        persistEffectChanges(created: mutation.created, updated: mutation.updated, deletedIds: mutation.deletedIds)
    }

    func resetClipVolume(clipId: String) {
        guard let mutation = editingService.resetClipVolume(clipId: clipId, in: &state) else { return }
        persistEffectChanges(created: mutation.created, updated: mutation.updated, deletedIds: mutation.deletedIds)
    }

    func deleteSelectedClip() {
        guard let actions = editingService.deleteSelectedClipActions(in: state) else { return }
        applyActions(actions)
    }

    func splitSelectedClip() {
        guard let actions = editingService.splitSelectedClipActions(in: state) else { return }
        applyActions(actions)
    }

    func updateCurrentTime(_ timeUs: Int64) {
        state.currentTimeAtCenter = timeUs
    }

    func ingestMedia(_ media: [Media], kind: TrackKind) {
        let before = state.clips
        let beforeOutputSize = state.effectiveOutputPixelSize
        Self.logger.info(
            "[TimelineImport] ingest start timeline=\(self.state.timelineId, privacy: .public) kind=\(kind.rawValue, privacy: .public) mediaCount=\(media.count, privacy: .public) beforeClipCount=\(before.count, privacy: .public) beforeOutput=\(Self.outputSizeSummary(beforeOutputSize), privacy: .public)"
        )
        state.ingestImportedMedia(imported: media, matching: media, kind: kind)
        persistClipChanges(before: before, after: state.clips)
        logImportStateTransition(before: before, after: state.clips, previousOutputSize: beforeOutputSize)
        objectWillChange.send()
    }

    func updateMedia(_ media: Media) {
        state.mediaById[media.mediaId] = media
        state.refreshDerivedOutputAspect()
    }

    /// Re-loads one `Media` row from the database when transcript (or other spec) was updated elsewhere (e.g. import browser background task).
    @MainActor
    func refreshMediaFromDatabaseIfOnTimeline(mediaId: String) {
        guard state.clips.contains(where: { $0.mediaId == mediaId }) else { return }
        do {
            guard let fresh = try db.getMedia(mediaId: mediaId) else {
                Self.logger.warning("refreshMediaFromDatabase: no media row for id=\(mediaId, privacy: .public)")
                return
            }
            updateMedia(fresh)
            Self.logger.info(
                "refreshMediaFromDatabase: merged mediaId=\(mediaId, privacy: .public) transcriptID=\(fresh.spec.transcriptID ?? "nil", privacy: .public) sentences=\(fresh.spec.transcriptSentences?.count ?? 0, privacy: .public)"
            )
        } catch {
            Self.logger.error("refreshMediaFromDatabase failed: \(String(describing: error), privacy: .public)")
        }
    }

    func generateThumbnailStrips(for media: [Media]) {
        for item in media where item.kind == .video {
            Task(priority: .utility) {
                let updated = await importService.generateThumbnailStrip(for: item)
                await MainActor.run { updateMedia(updated) }
            }
        }
    }

    func syncSemanticIndexForImportedMedia() {
        let media = Array(state.mediaById.values)
        SemanticSearchViewModel.shared.setImportSearchTimelineId(state.timelineId)
        guard AppConfiguration.enablesLocalSemanticIndexing else {
            SemanticSearchViewModel.shared.queueImportedMediaSync(media, autoBuildIndex: false)
            return
        }
        SemanticSearchViewModel.shared.queueImportedMediaSync(media, autoBuildIndex: true)
    }

    func insertClipSegment(mediaId: String, sourceRange: TimeRange, at timeUs: Int64, kind: TrackKind = .video) {
        guard let media = state.mediaById[mediaId] else { return }
        let before = state.clips
        EditorDebugTrace.log(
            "TimelineController",
            "about to add semantic clip mediaId=\(mediaId) kind=\(kind.rawValue) source=[\(formatDebugTime(sourceRange.start)), \(formatDebugTime(sourceRange.end))] held-at=\(formatDebugTime(timeUs)) existing-clip-count=\(before.count)"
        )
        state.addClipSegment(of: kind, at: timeUs, media: media, sourceRange: sourceRange)
        let previousClipIds = Set(before.map(\.clipId))
        if let insertedClip = state.clips.first(where: { clip in
            !previousClipIds.contains(clip.clipId)
        }) {
            EditorDebugTrace.log(
                "TimelineController",
                "semantic clip added clipId=\(insertedClip.clipId) timeline=[\(formatDebugTime(insertedClip.timelineRange.start)), \(formatDebugTime(insertedClip.timelineRange.end))] source=[\(formatDebugTime(insertedClip.sourceRange.start)), \(formatDebugTime(insertedClip.sourceRange.end))]"
            )
        } else if let insertedClip = state.clips.last {
            EditorDebugTrace.log(
                "TimelineController",
                "semantic clip add complete fallback-last-clip clipId=\(insertedClip.clipId) timeline=[\(formatDebugTime(insertedClip.timelineRange.start)), \(formatDebugTime(insertedClip.timelineRange.end))]"
            )
        }
        persistClipChanges(before: before, after: state.clips)
    }

    func importPickerItems(_ items: [PhotosPickerItem], kind: TrackKind) {
        guard let library = state.mediaLibrary else { return }
        let preferredKind = state.mediaKind(for: kind)
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let fileManager = FileManager.default
                let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let importsURL = documentsURL.appendingPathComponent("Imports", isDirectory: true)
                try? fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
                let fileName = "\(UUID().uuidString).mov"
                let fileURL = importsURL.appendingPathComponent(fileName)
                try? data.write(to: fileURL)

                do {
                    let media = try await importService.importFileURLsQuick(
                        [fileURL], to: library.id, preferredKind: preferredKind
                    )
                    if !media.isEmpty {
                        await MainActor.run {
                            ingestMedia(media, kind: kind)
                            syncSemanticIndexForImportedMedia()
                        }
                        generateThumbnailStrips(for: media)
                    }
                } catch {
                    print("Failed to import picker item: \(error)")
                }
            }
        }
    }

    func importAssets(_ assets: [PHAsset]) async {
        guard let request = state.pendingImport else { return }
        guard let library = state.mediaLibrary else { return }
        guard !assets.isEmpty else {
            await MainActor.run { state.clearPendingImport() }
            return
        }

        do {
            let imported = try await importService.importAssets(assets, to: library.id)
            let matching = imported.filter { state.mediaKinds(for: request.kind).contains($0.kind) }
            await MainActor.run {
                let before = state.clips
                let beforeOutputSize = state.effectiveOutputPixelSize
                state.ingestImportedMedia(imported: imported, matching: matching, kind: request.kind)
                persistClipChanges(before: before, after: state.clips)
                syncSemanticIndexForImportedMedia()
                logImportStateTransition(before: before, after: state.clips, previousOutputSize: beforeOutputSize)
                objectWillChange.send()
            }
            generateThumbnailStrips(for: imported)
        } catch {
            await MainActor.run { state.clearPendingImport() }
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard let request = state.pendingImport else { return }
        guard let library = state.mediaLibrary else { return }
        guard !urls.isEmpty else {
            await MainActor.run { state.clearPendingImport() }
            return
        }

        let preferredKind = state.mediaKind(for: request.kind)
        do {
            let imported = try await importService.importFileURLsQuick(urls, to: library.id, preferredKind: preferredKind)
            await MainActor.run {
                let before = state.clips
                let beforeOutputSize = state.effectiveOutputPixelSize
                state.ingestImportedMedia(imported: imported, matching: imported, kind: request.kind)
                persistClipChanges(before: before, after: state.clips)
                syncSemanticIndexForImportedMedia()
                logImportStateTransition(before: before, after: state.clips, previousOutputSize: beforeOutputSize)
                objectWillChange.send()
            }
            generateThumbnailStrips(for: imported)
        } catch {
            await MainActor.run { state.clearPendingImport() }
        }
    }

    private func logImportStateTransition(before: [Clip], after: [Clip], previousOutputSize: CGSize) {
        let emptyToNonempty = before.isEmpty && !after.isEmpty
        Self.logger.info(
            "[TimelineImport] ingest complete timeline=\(self.state.timelineId, privacy: .public) beforeClipCount=\(before.count, privacy: .public) afterClipCount=\(after.count, privacy: .public) emptyToNonempty=\(emptyToNonempty, privacy: .public) aspect=\(Self.outputAspectSummary(self.state.effectiveOutputAspect), privacy: .public) output=\(Self.outputSizeSummary(self.state.effectiveOutputPixelSize), privacy: .public) previousOutput=\(Self.outputSizeSummary(previousOutputSize), privacy: .public)"
        )
    }

    private static func outputAspectSummary(_ aspect: OutputAspectRatio?) -> String {
        guard let aspect else { return "nil" }
        return "\(aspect.width):\(aspect.height)"
    }

    private static func outputSizeSummary(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    // MARK: - Persistence

    private func persistClipChanges(before: [Clip], after: [Clip]) {
        persistenceCoordinator.persistClipChanges(
            before: before,
            after: after,
            tracks: state.tracks,
            timeline: state.timeline
        )
    }

    private func persistClipChanges(_ diff: TimelinePersistenceCoordinator.ClipDiff) {
        persistenceCoordinator.persistClipChanges(
            diff,
            tracks: state.tracks,
            timeline: state.timeline
        )
    }

    private func persistEffectChanges(created: [Effect], updated: [Effect], deletedIds: [String]) {
        persistenceCoordinator.persistEffectChanges(
            created: created,
            updated: updated,
            deletedIds: deletedIds,
            timeline: state.timeline
        )
    }

    private func persistCaptionCueChanges(created: [CaptionCue], updated: [CaptionCue], deletedIds: [String]) {
        persistenceCoordinator.persistCaptionCueChanges(
            created: created,
            updated: updated,
            deletedIds: deletedIds,
            timeline: state.timeline
        )
    }

    private func persistMutation(_ snapshot: TimelineEditingService.MutationSnapshot) {
        persistClipChanges(before: snapshot.beforeClips, after: snapshot.afterClips)
        let effectDiffResult = effectDiff(before: snapshot.beforeEffects, after: snapshot.afterEffects)
        persistEffectChanges(
            created: effectDiffResult.created,
            updated: effectDiffResult.updated,
            deletedIds: effectDiffResult.deletedIds
        )
        let captionCueDiffResult = captionCueDiff(before: snapshot.beforeCaptionCues, after: snapshot.afterCaptionCues)
        persistCaptionCueChanges(
            created: captionCueDiffResult.created,
            updated: captionCueDiffResult.updated,
            deletedIds: captionCueDiffResult.deletedIds
        )
    }

    private func persistNewTracks() {
        persistenceCoordinator.persistNewTracks(state.tracks)
    }

    private func clipDiff(before: [Clip], after: [Clip]) -> TimelinePersistenceCoordinator.ClipDiff {
        persistenceCoordinator.clipDiff(before: before, after: after)
    }

    private func effectDiff(before: [Effect], after: [Effect]) -> TimelinePersistenceCoordinator.EffectDiff {
        persistenceCoordinator.effectDiff(before: before, after: after)
    }

    private func captionCueDiff(before: [CaptionCue], after: [CaptionCue]) -> TimelinePersistenceCoordinator.CaptionCueDiff {
        persistenceCoordinator.captionCueDiff(before: before, after: after)
    }

    private static func actionSummary(_ actions: [Action]) -> String {
        actions.map { action in
            "id=\(action.actionId) timeline=\(action.timelineId) type=\(action.type.rawValue) payload=\(String(describing: action.payload))"
        }
        .joined(separator: " | ")
    }

    private static func clipSummary(_ clips: [Clip]) -> String {
        clips.map { clip in
            "id=\(clip.clipId) track=\(clip.trackId) timeline=[\(clip.timelineRange.start),\(clip.timelineRange.end)] source=[\(clip.sourceRange.start),\(clip.sourceRange.end)]"
        }
        .joined(separator: " | ")
    }

    private func formatDebugTime(_ timeUs: Int64) -> String {
        String(format: "%.3fs", Double(timeUs) / 1_000_000)
    }

    @MainActor
    private func applyImportedTimelineSeed(_ seed: ImportedTimelineSeed) async {
        guard let mediaLibrary = state.mediaLibrary else { return }

        persistBackendProjectMappingFromImportedSeedIfPresent(seed)

        do {
            let resolution = try await resolveSeedMedia(
                for: seed.sourceVideos,
                mediaLibraryID: mediaLibrary.id
            )
            let rebuiltClips = rebuildSeedClips(
                from: seed.segments,
                mediaByLocalKey: resolution.mediaByLocalKey
            )
            guard !rebuiltClips.isEmpty else { return }

            let before = state.clips
            replaceTrackClips(trackId: rebuiltClips[0].trackId, with: rebuiltClips)
            state.selectedClipId = nil
            state.jumpToStart()
            persistClipChanges(before: before, after: state.clips)

            if !resolution.newlyImportedMedia.isEmpty {
                generateThumbnailStrips(for: resolution.newlyImportedMedia)
            }
            if !resolution.newlyImportedMedia.isEmpty || resolution.didPersistBackendUploadKeys {
                syncSemanticIndexForImportedMedia()
            }
        } catch {
            print("Failed to apply imported timeline seed: \(error)")
        }
    }

    @MainActor
    private func persistBackendProjectMappingFromImportedSeedIfPresent(_ seed: ImportedTimelineSeed) {
        guard let bid = seed.backendProjectID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else { return }
        guard let timeline = state.timeline else {
            Self.logger.error("[TimelineController] skip seed backend mapping: timeline not loaded timelineId=\(self.state.timelineId, privacy: .public)")
            return
        }
        let existing = state.backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !existing.isEmpty, existing != bid {
            Self.logger.warning(
                "[TimelineController] seed backend project \(bid, privacy: .public) differs from loaded \(existing, privacy: .public); keeping loaded"
            )
            return
        }
        let localProjectId = timeline.projectId
        let displayName = seed.backendProjectName ?? state.projectTitle
        do {
            try db.saveBackendProjectMapping(
                localProjectId: localProjectId,
                backendProjectId: bid,
                backendProjectName: displayName
            )
            state.backendProjectId = bid
            Self.logger.notice(
                "[TimelineController] persisted backend project from import seed localProject=\(localProjectId, privacy: .public) backend=\(bid, privacy: .public)"
            )
        } catch {
            Self.logger.error(
                "[TimelineController] persist backend mapping from seed failed error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Persists `Media.spec.clipUploadLocalKey` so cloud semantic/transcript rows (keyed by upload `local_key`) map to timeline media.
    @MainActor
    private func ensureClipUploadLocalKeyPersistedIfNeeded(
        for video: SelectedVideoAsset,
        media: Media
    ) throws -> (Media, didChange: Bool) {
        let trimmedKey = video.localKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return (media, false) }
        let existing = media.spec.clipUploadLocalKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing.caseInsensitiveCompare(trimmedKey) == .orderedSame {
            return (media, false)
        }
        var updated = media
        updated.spec.clipUploadLocalKey = trimmedKey
        updated.updatedAt = Date()
        try db.update(updated)
        return (updated, true)
    }

    @MainActor
    private func resolveSeedMedia(
        for sourceVideos: [SelectedVideoAsset],
        mediaLibraryID: String
    ) async throws -> SeedMediaResolution {
        let libraryMedia = try db.getAllMedia(forLibraryId: mediaLibraryID)
        let existingMediaByID = Dictionary(uniqueKeysWithValues: libraryMedia.map { ($0.mediaId, $0) })
        let existingMediaByAssetIdentifier = try existingVideoMediaByAssetIdentifier(in: libraryMedia)
        let missingVideos = sourceVideos.filter { video in
            if importedMediaBySeedLocalKey[video.localKey] != nil {
                return false
            }
            if let localMediaID = video.localMediaID,
               let existingMedia = existingMediaByID[localMediaID] {
                importedMediaBySeedLocalKey[video.localKey] = existingMedia
                state.mediaById[existingMedia.mediaId] = existingMedia
                return false
            }
            return true
        }
        let videosNeedingImport = missingVideos.filter { video in
            guard let assetLocalIdentifier = video.assetLocalIdentifier,
                  let existingMedia = existingMediaByAssetIdentifier[assetLocalIdentifier] else {
                return true
            }

            importedMediaBySeedLocalKey[video.localKey] = existingMedia
            state.mediaById[existingMedia.mediaId] = existingMedia
            return false
        }
        let newlyImportedMedia: [Media]

        if videosNeedingImport.isEmpty {
            newlyImportedMedia = []
        } else {
            newlyImportedMedia = try await importService.importFileURLsQuick(
                videosNeedingImport.map(\.originalURL),
                to: mediaLibraryID,
                preferredKind: .video
            )

            for (video, media) in zip(videosNeedingImport, newlyImportedMedia) {
                importedMediaBySeedLocalKey[video.localKey] = media
                state.mediaById[media.mediaId] = media
            }
        }

        var didPersistBackendUploadKeys = false
        for video in sourceVideos {
            guard let media = importedMediaBySeedLocalKey[video.localKey] else { continue }
            let (updated, didChange) = try ensureClipUploadLocalKeyPersistedIfNeeded(for: video, media: media)
            if didChange {
                didPersistBackendUploadKeys = true
            }
            importedMediaBySeedLocalKey[video.localKey] = updated
            state.mediaById[updated.mediaId] = updated
        }

        let mediaByLocalKey = sourceVideos.reduce(into: [String: Media]()) { result, video in
            guard let media = importedMediaBySeedLocalKey[video.localKey] else { return }
            result[video.localKey] = media
        }

        return SeedMediaResolution(
            mediaByLocalKey: mediaByLocalKey,
            newlyImportedMedia: newlyImportedMedia,
            didPersistBackendUploadKeys: didPersistBackendUploadKeys
        )
    }

    private func rebuildSeedClips(
        from segments: [ImportedTimelineSeedSegment],
        mediaByLocalKey: [String: Media]
    ) -> [Clip] {
        let videoTrack = ensureVideoTrack()
        var cursor: Int64 = 0
        var rebuiltClips: [Clip] = []

        for segment in segments {
            guard let media = mediaByLocalKey[segment.sourceLocalKey] else { continue }
            let duration = max(segment.sourceRange.duration, 1)
            rebuiltClips.append(
                Clip(
                    trackId: videoTrack.trackId,
                    mediaId: media.mediaId,
                    sourceRange: segment.sourceRange,
                    timelineRange: TimeRange(start: cursor, end: cursor + duration)
                )
            )
            cursor += duration
        }

        return rebuiltClips
    }

    private func existingVideoMediaByAssetIdentifier(in libraryMedia: [Media]) throws -> [String: Media] {
        var mediaByAssetIdentifier: [String: Media] = [:]

        for media in libraryMedia where media.kind == .video {
            guard let assetReference = try db.getAssetReference(assetRefId: media.assetRefId) else { continue }
            mediaByAssetIdentifier[assetReference.uri] = media
        }

        return mediaByAssetIdentifier
    }

    private func ensureVideoTrack() -> Track {
        if let existingTrack = state.tracks.first(where: { $0.kind == .video }) {
            return existingTrack
        }

        let newTrack = Track(
            timelineId: state.timelineId,
            kind: .video,
            sortIndex: state.tracks.count
        )
        state.tracks.append(newTrack)
        return newTrack
    }

    private func replaceTrackClips(trackId: String, with updatedTrackClips: [Clip]) {
        let otherClips = state.clips.filter { $0.trackId != trackId }
        state.clips = otherClips + updatedTrackClips
        state.refreshDerivedOutputAspect()
    }

    private func rebuildCutReview(startingAt preferredIndex: Int) {
        let items = buildCutReviewItems()
        guard !items.isEmpty else {
            finishCutReview()
            return
        }

        let clampedIndex = min(max(0, preferredIndex), items.count - 1)
        cutReview = TimelineCutReviewSession(items: items, currentIndex: clampedIndex)
        focusCurrentCutReview()
    }

    private func focusCurrentCutReview() {
        guard let currentItem = cutReview?.currentItem else { return }
        state.selectedClipId = nil
        state.currentTimeAtCenter = currentItem.cutTimeUs
        state.requestScrollTo(timeUs: currentItem.cutTimeUs)
    }

    private func buildCutReviewItems() -> [TimelineCutReviewItem] {
        let trackClips = currentVideoTrackClips()
        guard trackClips.count >= 2 else { return [] }

        return zip(trackClips, trackClips.dropFirst()).map { leftClip, rightClip in
            TimelineCutReviewItem(
                leftClipId: leftClip.clipId,
                rightClipId: rightClip.clipId,
                leftMediaId: leftClip.mediaId,
                rightMediaId: rightClip.mediaId,
                startTimeUs: leftClip.timelineRange.start,
                cutTimeUs: leftClip.timelineRange.end,
                endTimeUs: rightClip.timelineRange.end
            )
        }
    }

    private func currentVideoTrackClips() -> [Clip] {
        guard let videoTrack = state.tracks.first(where: { $0.kind == .video }) else { return [] }
        return state.orderedClips(for: videoTrack.trackId)
    }
}

private struct SeedMediaResolution {
    let mediaByLocalKey: [String: Media]
    let newlyImportedMedia: [Media]
    /// True when any timeline `Media` had `clipUploadLocalKey` written for cloud search mapping.
    let didPersistBackendUploadKeys: Bool
}

@MainActor
protocol TimelineUndoRedoControlling: AnyObject {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    func undoLastActionGroup()
    func redoLastActionGroup()
}

extension TimelineController: TimelineUndoRedoControlling {}

@MainActor
protocol TimelineStateMutating: AnyObject {
    func setPlaybackState(_ playbackState: TimelinePlaybackState)
    func jumpToStart()
    func jumpToEnd()
}

extension TimelineController: TimelineStateMutating {
    func setPlaybackState(_ playbackState: TimelinePlaybackState) {
        state.setPlaybackState(playbackState)
    }

    func jumpToStart() {
        state.jumpToStart()
    }

    func jumpToEnd() {
        state.jumpToEnd()
    }
}
