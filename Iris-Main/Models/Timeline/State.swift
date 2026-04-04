import Foundation
import Photos
import SwiftUI
import UniformTypeIdentifiers

struct TimelineState {
    enum PlaybackState: String {
        case idle
        case playing
        case scrubbing
    }

    let timelineId: String

    var timeline: Timeline?
    var tracks: [Track]
    var clips: [Clip]
    var effects: [Effect]
    var mediaLibrary: MediaLibrary?
    var mediaById: [String: Media]
    var projectTitle: String

    var pixelsPerSecond: CGFloat
    var currentTimeAtCenter: Int64
    var pendingImport: ImportRequest?
    var showingMediaPicker: Bool
    var showingFilePicker: Bool
    var photoAuthStatus: PHAuthorizationStatus
    var scrollTargetTimeUs: Int64?
    var selectedClipId: String?
    var playbackState: PlaybackState

    let defaultClipDurationUs: Int64
    let scrollBufferUs: Int64

    init(timelineId: String) {
        self.timelineId = timelineId
        self.timeline = nil
        self.tracks = []
        self.clips = []
        self.effects = []
        self.mediaLibrary = nil
        self.mediaById = [:]
        self.projectTitle = "Project"
        self.pixelsPerSecond = 100
        self.currentTimeAtCenter = 0
        self.pendingImport = nil
        self.showingMediaPicker = false
        self.showingFilePicker = false
        self.photoAuthStatus = .notDetermined
        self.scrollTargetTimeUs = nil
        self.selectedClipId = nil
        self.playbackState = .idle
        self.defaultClipDurationUs = 2_000_000
        self.scrollBufferUs = 1_000_000
    }

    var clipsByTrackId: [String: [Clip]] {
        Dictionary(grouping: clips, by: { $0.trackId })
    }

    var orderedTracks: [Track] {
        tracks.sorted {
            Self.trackDisplayOrder(for: $0.kind) == Self.trackDisplayOrder(for: $1.kind)
                ? $0.sortIndex < $1.sortIndex
                : Self.trackDisplayOrder(for: $0.kind) < Self.trackDisplayOrder(for: $1.kind)
        }
    }

    var calculatedTimelineDurationUs: Int64 {
        clips.map { $0.timelineRange.end }.max() ?? 0
    }

    var scrollableDurationUs: Int64 {
        max(0, calculatedTimelineDurationUs) + scrollBufferUs
    }

    var currentTimeSeconds: Double {
        Double(currentTimeAtCenter) / 1_000_000.0
    }

    var timelineDurationSeconds: Double {
        Double(calculatedTimelineDurationUs) / 1_000_000.0
    }

    mutating func applyLoadedData(
        timeline: Timeline,
        tracks: [Track],
        clips: [Clip],
        effects: [Effect],
        mediaLibrary: MediaLibrary?,
        mediaById: [String: Media],
        projectTitle: String
    ) {
        self.timeline = timeline
        self.tracks = tracks
        self.clips = clips
        self.effects = effects
        self.mediaLibrary = mediaLibrary
        self.mediaById = mediaById
        self.projectTitle = projectTitle
    }

    mutating func beginImport(kind: TrackKind, source: ImportSource) {
        pendingImport = ImportRequest(kind: kind, source: source)
        switch source {
        case .files:
            showingFilePicker = true
        case .photos:
            showingFilePicker = false
        case .textBox, .caption:
            break
        }
    }

    mutating func handlePhotoAuthorization(status: PHAuthorizationStatus) {
        photoAuthStatus = status
        if status == .authorized || status == .limited {
            showingMediaPicker = true
        }
    }

    mutating func clearPendingImport() {
        pendingImport = nil
    }

    mutating func ingestImportedMedia(
        imported: [Media],
        matching: [Media],
        kind: TrackKind
    ) {
        for media in imported {
            mediaById[media.mediaId] = media
        }
        addClips(from: matching, kind: kind, startingAt: currentTimeAtCenter)
        pendingImport = nil
    }

    mutating func clearSelection() {
        guard selectedClipId != nil else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedClipId = nil
        }
    }

    mutating func setPlaybackState(_ playbackState: PlaybackState) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            self.playbackState = playbackState
        }
    }

    mutating func jumpToStart() {
        currentTimeAtCenter = 0
        scrollTargetTimeUs = 0
    }

    mutating func jumpToEnd() {
        let endTimeUs = calculatedTimelineDurationUs
        currentTimeAtCenter = endTimeUs
        scrollTargetTimeUs = endTimeUs
    }

    mutating func moveClip(clipId: String, toStartTimeUs _: Int64, orderedClipIds: [String]) {
        guard let movingClip = clips.first(where: { $0.clipId == clipId }) else { return }
        let trackId = movingClip.trackId
        let trackClips = orderedClips(for: trackId)
        guard !trackClips.isEmpty else { return }

        let clipById = Dictionary(uniqueKeysWithValues: trackClips.map { ($0.clipId, $0) })
        var ordered = orderedClipIds.compactMap { clipById[$0] }
        let missing = trackClips.filter { !orderedClipIds.contains($0.clipId) }
        ordered.append(contentsOf: missing)

        let packed = packedClips(from: ordered)
        applyTrackUpdates(trackId: trackId, updatedClips: packed, animate: false)
    }

    mutating func trimClip(
        clipId: String,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        commit: Bool
    ) {
        guard let index = clips.firstIndex(where: { $0.clipId == clipId }) else { return }
        let originalClip = clips[index]
        var updatedClip = originalClip
        updatedClip.sourceRange = sourceRange
        updatedClip.timelineRange = timelineRange
        updatedClip.updatedAt = Date()
        if commit {
            let updatedClips = rippleTrimmedClips(
                trackId: updatedClip.trackId,
                updatedClip: updatedClip,
                orderingStartUs: originalClip.timelineRange.start
            )
            applyTrackUpdates(trackId: updatedClip.trackId, updatedClips: updatedClips, animate: true)
        } else {
            applySingleClipTrimState(updatedClip, animate: false)
        }
    }

    mutating func deleteSelectedClip() {
        guard let clipId = selectedClipId else { return }
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return }
        clips.removeAll { $0.clipId == clipId }
        packTrackClips(trackId: clip.trackId, animate: true)
        let maxScrollTimeUs = max(0, calculatedTimelineDurationUs) + scrollBufferUs
        if currentTimeAtCenter > maxScrollTimeUs {
            requestScrollTo(timeUs: maxScrollTimeUs)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedClipId = nil
        }
    }

    mutating func splitSelectedClip() {
        guard let clipId = selectedClipId else { return }
        guard let index = clips.firstIndex(where: { $0.clipId == clipId }) else { return }
        let clip = clips[index]
        let cutTimeUs = currentTimeAtCenter
        guard cutTimeUs > clip.timelineRange.start, cutTimeUs < clip.timelineRange.end else {
            return
        }

        let leftDuration = cutTimeUs - clip.timelineRange.start
        let rightDuration = clip.timelineRange.end - cutTimeUs
        guard leftDuration > 0, rightDuration > 0 else { return }

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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedClipId = nil
        }
    }

    mutating func addClip(of kind: TrackKind, at timeUs: Int64, media: Media? = nil) {
        let resolvedMedia: Media
        if let media {
            resolvedMedia = media
        } else if let fallback = mediaById.values.first {
            resolvedMedia = fallback
        } else {
            return
        }

        let track = ensureTrack(for: kind, timelineId: timelineId)
        let mediaDuration = resolvedDurationUs(for: resolvedMedia)
        let desiredStartUs = magneticStartTime(
            desiredStartUs: max(0, timeUs),
            existingClips: clips.filter { $0.trackId == track.trackId }
        )
        let startUs = resolvedStartTime(
            desiredStartUs: desiredStartUs,
            durationUs: mediaDuration,
            existingClips: clips.filter { $0.trackId == track.trackId }
        )
        if startUs != desiredStartUs {
            requestScrollTo(timeUs: startUs)
        }
        let newClip = Clip(
            trackId: track.trackId,
            mediaId: resolvedMedia.mediaId,
            sourceRange: TimeRange(start: 0, end: mediaDuration),
            timelineRange: TimeRange(start: startUs, end: startUs + mediaDuration)
        )
        clips.append(newClip)
    }

    mutating func addClips(from mediaItems: [Media], kind: TrackKind, startingAt timeUs: Int64) {
        let track = ensureTrack(for: kind, timelineId: timelineId)
        var existingClips = clips.filter { $0.trackId == track.trackId }
        var cursor = magneticStartTime(desiredStartUs: max(0, timeUs), existingClips: existingClips)
        var didRequestScroll = false
        for media in mediaItems {
            let mediaDuration = resolvedDurationUs(for: media)
            let desiredStartUs = max(0, cursor)
            let startUs = resolvedStartTime(
                desiredStartUs: desiredStartUs,
                durationUs: mediaDuration,
                existingClips: existingClips
            )
            if !didRequestScroll && startUs != desiredStartUs {
                requestScrollTo(timeUs: startUs)
                didRequestScroll = true
            }
            let newClip = Clip(
                trackId: track.trackId,
                mediaId: media.mediaId,
                sourceRange: TimeRange(start: 0, end: mediaDuration),
                timelineRange: TimeRange(start: startUs, end: startUs + mediaDuration)
            )
            clips.append(newClip)
            existingClips.append(newClip)
            cursor = startUs + mediaDuration
        }
    }

    func clipDurationUs(for media: Media) -> Int64? {
        guard let seconds = media.spec.duration, seconds > 0 else {
            return nil
        }
        return Int64(seconds * 1_000_000)
    }

    func resolvedDurationUs(for media: Media) -> Int64 {
        clipDurationUs(for: media) ?? defaultClipDurationUs
    }

    func resolvedStartTime(desiredStartUs: Int64, durationUs: Int64, existingClips: [Clip]) -> Int64 {
        let clampedStart = max(0, desiredStartUs)
        guard durationUs > 0 else { return clampedStart }

        let sortedClips = existingClips.sorted { $0.timelineRange.start < $1.timelineRange.start }
        let desiredEnd = clampedStart + durationUs
        let overlapsExisting = sortedClips.contains {
            clampedStart < $0.timelineRange.end && desiredEnd > $0.timelineRange.start
        }
        guard overlapsExisting else { return clampedStart }

        var candidateStart = clampedStart
        for clip in sortedClips {
            if candidateStart + durationUs <= clip.timelineRange.start {
                return candidateStart
            }
            if candidateStart < clip.timelineRange.end {
                candidateStart = clip.timelineRange.end
            }
        }
        return candidateStart
    }

    func orderedClips(for trackId: String) -> [Clip] {
        clips
            .filter { $0.trackId == trackId }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
    }

    func packedClips(from orderedClips: [Clip]) -> [Clip] {
        var cursor: Int64 = 0
        return orderedClips.map { clip in
            var updated = clip
            let duration = clip.duration
            updated.timelineRange = TimeRange(start: cursor, end: cursor + duration)
            cursor += duration
            return updated
        }
    }

    mutating func packTrackClips(trackId: String, animate: Bool) {
        let ordered = orderedClips(for: trackId)
        let packed = packedClips(from: ordered)
        applyTrackUpdates(trackId: trackId, updatedClips: packed, animate: animate)
    }

    mutating func applyTrackUpdates(trackId: String, updatedClips: [Clip], animate: Bool) {
        let updatedById = Dictionary(uniqueKeysWithValues: updatedClips.map { ($0.clipId, $0) })
        let now = Date()
        let updatedClipsState = clips.map { clip in
            guard let updated = updatedById[clip.clipId] else { return clip }
            let didChange = clip.timelineRange.start != updated.timelineRange.start
                || clip.timelineRange.end != updated.timelineRange.end
                || clip.sourceRange.start != updated.sourceRange.start
                || clip.sourceRange.end != updated.sourceRange.end
            var final = updated
            final.updatedAt = didChange ? now : clip.updatedAt
            return final
        }
        clips = updatedClipsState
    }

    mutating func applySingleClipTrimState(_ updatedClip: Clip, animate: Bool) {
        let now = Date()
        clips = clips.map { clip in
            guard clip.clipId == updatedClip.clipId else { return clip }
            let didChange = clip.timelineRange.start != updatedClip.timelineRange.start
                || clip.timelineRange.end != updatedClip.timelineRange.end
                || clip.sourceRange.start != updatedClip.sourceRange.start
                || clip.sourceRange.end != updatedClip.sourceRange.end
            var final = updatedClip
            final.updatedAt = didChange ? now : clip.updatedAt
            return final
        }
    }

    func rippleTrimmedClips(
        trackId: String,
        updatedClip: Clip,
        orderingStartUs: Int64? = nil
    ) -> [Clip] {
        let trackClips = clips.filter { $0.trackId == trackId }
        let indexed = trackClips.enumerated().map { (index: $0.offset, clip: $0.element) }
        let ordered = indexed.sorted { left, right in
            let leftStart = left.clip.clipId == updatedClip.clipId
                ? (orderingStartUs ?? left.clip.timelineRange.start)
                : left.clip.timelineRange.start
            let rightStart = right.clip.clipId == updatedClip.clipId
                ? (orderingStartUs ?? right.clip.timelineRange.start)
                : right.clip.timelineRange.start
            if leftStart == rightStart {
                return left.index < right.index
            }
            return leftStart < rightStart
        }.map(\.clip)
        guard let index = ordered.firstIndex(where: { $0.clipId == updatedClip.clipId }) else {
            return ordered
        }

        var updated = ordered
        updated[index] = updatedClip
        let leadingEnd = index > 0 ? updated[index - 1].timelineRange.end : 0
        var cursor = leadingEnd
        for i in index..<updated.count {
            let duration = updated[i].duration
            updated[i].timelineRange = TimeRange(start: cursor, end: cursor + duration)
            cursor += duration
        }
        return updated
    }

    func magneticStartTime(desiredStartUs: Int64, existingClips: [Clip]) -> Int64 {
        let lastEnd = existingClips.map { $0.timelineRange.end }.max() ?? 0
        return min(desiredStartUs, lastEnd)
    }

    mutating func requestScrollTo(timeUs: Int64) {
        scrollTargetTimeUs = nil
        scrollTargetTimeUs = timeUs
    }

    func mediaKinds(for kind: TrackKind) -> Set<MediaKind> {
        switch kind {
        case .video: return [.video, .photo]
        case .audio: return [.video]
        case .overlay: return []
        }
    }

    func mediaKind(for kind: TrackKind) -> MediaKind {
        switch kind {
        case .video: return .video
        case .audio: return .audio
        case .overlay: return .photo
        }
    }

    func filePickerTypes() -> [UTType] {
        guard let request = pendingImport else {
            return [.data]
        }
        switch request.kind {
        case .video: return [.movie]
        case .audio: return [.audio]
        case .overlay: return [.data]
        }
    }

    private static func trackDisplayOrder(for kind: TrackKind) -> Int {
        switch kind {
        case .overlay: return 0
        case .video: return 1
        case .audio: return 2
        }
    }

    private mutating func ensureTrack(for kind: TrackKind, timelineId: String) -> Track {
        if let existing = tracks.first(where: { $0.kind == kind }) {
            return existing
        }
        let sortIndex = tracks.count
        let newTrack = Track(timelineId: timelineId, kind: kind, sortIndex: sortIndex)
        tracks.append(newTrack)
        return newTrack
    }
}

struct ImportRequest: Equatable {
    let kind: TrackKind
    let source: ImportSource
}

enum ImportSource: Equatable {
    case photos
    case files
    case textBox
    case caption
}
