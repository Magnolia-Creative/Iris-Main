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

    var backendProjectIdForUIPlanning: String? {
        let pid = timeline?.projectId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return pid.isEmpty ? nil : pid
    }
}
