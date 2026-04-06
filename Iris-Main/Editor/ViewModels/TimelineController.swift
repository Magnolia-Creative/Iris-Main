import Foundation
import Photos
import PhotosUI
import SwiftUI
internal import Combine

final class TimelineController: ObservableObject {
    @Published private(set) var state: TimelineState
    private let persistence: TimelinePersistence
    private let importService: MediaImportService
    private var persistedTrackIds: Set<String> = []
    private var debouncedSaveTask: Task<Void, Never>?

    init(
        timelineId: String,
        db: DatabaseManager = .shared,
        importService: MediaImportService = .shared
    ) {
        self.state = TimelineState(timelineId: timelineId)
        self.persistence = TimelinePersistence(db: db)
        self.importService = importService
    }

    func binding<Value>(_ keyPath: WritableKeyPath<TimelineState, Value>) -> Binding<Value> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { self.state[keyPath: keyPath] = $0 }
        )
    }

    func loadTimelineData() async {
        do {
            let loaded = try persistence.loadTimelineData(timelineId: state.timelineId)
            await MainActor.run {
                state.applyLoadedData(
                    timeline: loaded.timeline,
                    tracks: loaded.tracks,
                    clips: loaded.clips,
                    effects: loaded.effects,
                    mediaLibrary: loaded.mediaLibrary,
                    mediaById: loaded.mediaById,
                    projectTitle: loaded.projectTitle
                )
                persistedTrackIds = Set(loaded.tracks.map(\.trackId))
            }
        } catch {
            print("Failed to load timeline data: \(error)")
        }
    }

    func clearSelection() {
        state.clearSelection()
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

    func moveClip(clipId: String, toStartTimeUs timeUs: Int64, orderedClipIds: [String]) {
        let before = state.clips
        state.moveClip(clipId: clipId, toStartTimeUs: timeUs, orderedClipIds: orderedClipIds)
        persistClipChanges(before: before, after: state.clips)
    }

    func trimClip(clipId: String, sourceRange: TimeRange, timelineRange: TimeRange, commit: Bool) {
        let before = state.clips
        state.trimClip(clipId: clipId, sourceRange: sourceRange, timelineRange: timelineRange, commit: commit)
        guard commit else { return }
        persistClipChanges(before: before, after: state.clips)
    }

    func deleteSelectedClip() {
        let before = state.clips
        state.deleteSelectedClip()
        persistClipChanges(before: before, after: state.clips)
    }

    func splitSelectedClip() {
        let before = state.clips
        state.splitSelectedClip()
        persistClipChanges(before: before, after: state.clips)
    }

    func updateCurrentTime(_ timeUs: Int64) {
        state.currentTimeAtCenter = timeUs
    }

    func ingestMedia(_ media: [Media], kind: TrackKind) {
        let before = state.clips
        state.ingestImportedMedia(imported: media, matching: media, kind: kind)
        persistClipChanges(before: before, after: state.clips)
    }

    func updateMedia(_ media: Media) {
        state.mediaById[media.mediaId] = media
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
                        }
                        for m in media {
                            Task {
                                let updated = await importService.generateThumbnailStrip(for: m)
                                await MainActor.run { updateMedia(updated) }
                            }
                        }
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
                state.ingestImportedMedia(imported: imported, matching: matching, kind: request.kind)
                persistClipChanges(before: before, after: state.clips)
            }
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
                state.ingestImportedMedia(imported: imported, matching: imported, kind: request.kind)
                persistClipChanges(before: before, after: state.clips)
            }
            for media in imported {
                Task {
                    let updated = await importService.generateThumbnailStrip(for: media)
                    await MainActor.run { updateMedia(updated) }
                }
            }
        } catch {
            await MainActor.run { state.clearPendingImport() }
        }
    }

    // MARK: - Persistence

    private struct ClipDiff {
        let added: [Clip]
        let updated: [Clip]
        let deletedIds: [String]
    }

    private func persistClipChanges(before: [Clip], after: [Clip]) {
        let diff = clipDiff(before: before, after: after)
        guard !diff.added.isEmpty || !diff.updated.isEmpty || !diff.deletedIds.isEmpty else { return }

        persistNewTracks()

        do {
            for clip in diff.added { try persistence.createClip(clip) }
            for clip in diff.updated { try persistence.updateClip(clip) }
            for clipId in diff.deletedIds { try persistence.deleteClip(clipId: clipId) }
        } catch {
            print("Failed to persist clip changes: \(error)")
        }

        scheduleDebouncedMetadataSave()
    }

    private func persistNewTracks() {
        for track in state.tracks where !persistedTrackIds.contains(track.trackId) {
            do {
                try persistence.createTrack(track)
                persistedTrackIds.insert(track.trackId)
            } catch {
                // Track may already exist from initial load
                persistedTrackIds.insert(track.trackId)
            }
        }
    }

    private func scheduleDebouncedMetadataSave() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            if var timeline = state.timeline {
                timeline.updatedAt = Date()
                try? persistence.updateTimeline(timeline)
            }
        }
    }

    private func clipDiff(before: [Clip], after: [Clip]) -> ClipDiff {
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

    private func didClipChange(before: Clip, after: Clip) -> Bool {
        before.trackId != after.trackId || before.mediaId != after.mediaId
            || before.sourceRange.start != after.sourceRange.start
            || before.sourceRange.end != after.sourceRange.end
            || before.timelineRange.start != after.timelineRange.start
            || before.timelineRange.end != after.timelineRange.end
    }
}

@MainActor
protocol TimelineStateMutating: AnyObject {
    func setPlaybackState(_ playbackState: TimelineState.PlaybackState)
    func jumpToStart()
    func jumpToEnd()
}

extension TimelineController: TimelineStateMutating {
    func setPlaybackState(_ playbackState: TimelineState.PlaybackState) {
        state.setPlaybackState(playbackState)
    }

    func jumpToStart() {
        state.jumpToStart()
    }

    func jumpToEnd() {
        state.jumpToEnd()
    }
}
