import Foundation

@MainActor
struct TimelineImportCoordinator {
    struct ClipMutation {
        let beforeClips: [Clip]
        let afterClips: [Clip]
        let previousOutputSize: OutputPixelSize
    }

    func beginAddSelection(
        kind: TrackKind,
        source: ImportSource,
        in presentationState: inout TimelineImportPresentationState
    ) -> Bool {
        switch source {
        case .photos:
            presentationState.beginImport(kind: kind, source: source)
            return true
        case .files:
            presentationState.beginImport(kind: kind, source: source)
            return false
        case .textBox, .caption:
            return false
        }
    }

    func ingestMedia(
        imported: [Media],
        matching: [Media],
        kind: TrackKind,
        in state: inout TimelineState
    ) -> ClipMutation {
        let before = state.clips
        let previousOutputSize = state.effectiveOutputPixelSize
        state.ingestImportedMedia(imported: imported, matching: matching, kind: kind)
        return ClipMutation(
            beforeClips: before,
            afterClips: state.clips,
            previousOutputSize: previousOutputSize
        )
    }

    func insertClipSegment(
        mediaId: String,
        sourceRange: TimeRange,
        at timeUs: Int64,
        kind: TrackKind,
        in state: inout TimelineState
    ) -> ClipMutation? {
        guard let media = state.mediaById[mediaId] else { return nil }
        let before = state.clips
        let previousOutputSize = state.effectiveOutputPixelSize
        state.addClipSegment(of: kind, at: timeUs, media: media, sourceRange: sourceRange)
        return ClipMutation(
            beforeClips: before,
            afterClips: state.clips,
            previousOutputSize: previousOutputSize
        )
    }
}
