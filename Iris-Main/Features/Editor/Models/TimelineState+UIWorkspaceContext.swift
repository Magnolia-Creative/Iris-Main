import Foundation

extension TimelineState {
    func makeUIEditorContext(
        activeSpace: EditorSpace,
        isReviewActive: Bool,
        isPromptActionReviewActive: Bool,
        isCaptionsChromeActive: Bool
    ) -> UIEditorContext {
        let hasVideo = clips.contains { clip in
            guard let media = mediaById[clip.mediaId] else { return false }
            return media.kind == .video
        }
        let hasAudio = clips.contains { clip in
            guard let media = mediaById[clip.mediaId] else { return false }
            return media.kind == .video || media.kind == .audio
        }
        return UIEditorContext(
            activeSpace: activeSpace.rawValue,
            hasSelectedClip: selectedClipId != nil,
            hasSelectedCaption: false,
            hasVideoClips: hasVideo,
            hasAudioClips: hasAudio,
            isReviewActive: isReviewActive,
            isPromptActionReviewActive: isPromptActionReviewActive,
            isCaptionsChromeActive: isCaptionsChromeActive,
            clientCatalogVersion: UIWorkspaceCatalog.version
        )
    }

    /// Numeric Iris backend project id for `POST /projects/{id}/ui-workspace-plan` (not the local UUID).
    var backendProjectIdForUIPlanning: String? {
        let pid = backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return pid.isEmpty ? nil : pid
    }
}
