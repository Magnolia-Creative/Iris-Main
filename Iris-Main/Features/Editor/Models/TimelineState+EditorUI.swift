import Photos
import SwiftUI
import UniformTypeIdentifiers

extension TimelineState {
    var editorDisplayTracks: [Track] {
        let hasOverlayClips = tracks.contains { track in
            track.kind == .overlay && !(clipsByTrackId[track.trackId] ?? []).isEmpty
        }
        var displayTracks = orderedTracks.filter { track in
            track.kind != .overlay || hasOverlayClips
        }
        if !displayTracks.contains(where: { $0.kind == .captions }) {
            displayTracks.insert(
                Track(
                    trackId: "\(timelineId)-captions-display-track",
                    timelineId: timelineId,
                    kind: .captions,
                    sortIndex: Int.min
                ),
                at: 0
            )
        }
        return displayTracks
    }

    mutating func clearSelection() {
        guard selectedClipId != nil else { return }
        selectedClipId = nil
    }

    mutating func setPlaybackState(_ playbackState: TimelinePlaybackState) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            self.playbackState = playbackState
        }
    }

}

struct TimelineImportPresentationState {
    var pendingImport: ImportRequest?
    var showingMediaPicker = false
    var showingFilePicker = false
    var photoAuthStatus: PHAuthorizationStatus = .notDetermined

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

    func filePickerTypes() -> [UTType] {
        guard let request = pendingImport else {
            return [.data]
        }
        switch request.kind {
        case .video: return [.movie]
        case .audio: return [.audio]
        case .overlay: return [.data]
        case .captions: return [.data]
        }
    }
}
