import Photos
import SwiftUI
import UniformTypeIdentifiers

extension TimelineState {
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

    mutating func clearSelection() {
        guard selectedClipId != nil else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedClipId = nil
        }
    }

    mutating func setPlaybackState(_ playbackState: TimelinePlaybackState) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            self.playbackState = playbackState
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
}
