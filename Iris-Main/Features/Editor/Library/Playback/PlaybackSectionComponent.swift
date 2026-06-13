import SwiftUI

struct PlaybackSectionComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "playback.section"
    static let category: EditorComponentCategory = .playback
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let context: EditorPlaybackContext
    let actions: EditorPlaybackActions
    var fitMode: PlaybackViewerFitMode = .fitAspect
    var placeholderTitle: String = "Preview"

    var body: some View {
        VStack(spacing: .spacing(.sp2)) {
            PlaybackViewerComponent(
                size: context.viewerSize,
                previewAspect: context.previewAspect,
                fitMode: fitMode,
                placeholderTitle: placeholderTitle
            )
            .padding(.horizontal, .sp3)

            PlaybackTransportBarComponent(context: context, actions: actions)
                .padding(.horizontal, .sp4)
        }
    }
}
