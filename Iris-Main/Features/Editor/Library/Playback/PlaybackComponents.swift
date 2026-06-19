import SwiftUI

enum PlaybackViewerFitMode: String, CaseIterable {
    case fitAspect
    case fillFrame
}

struct PlaybackViewerComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "playback.viewer"
    static let category: EditorComponentCategory = .playback
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let size: EditorComponentSize
    var previewAspect: CGFloat?
    var renderEngine: VideoLabRenderEngine?
    var fitMode: PlaybackViewerFitMode = .fitAspect
    var placeholderTitle: String = "Preview"

    private var minHeight: CGFloat {
        switch size {
        case .compressed: 140
        case .standard: 220
        case .expanded: 340
        }
    }

    var body: some View {
        ZStack {
            Color.clear
            Group {
                if fitMode == .fitAspect, let previewAspect {
                    previewContent.aspectRatio(previewAspect, contentMode: .fit)
                } else {
                    previewContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: minHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var previewContent: some View {
        if let renderEngine {
            VideoLabPreviewView(engine: renderEngine)
                .background(Color.black)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.ds.surface)
                .overlay(
                    VStack(spacing: .spacing(.sp2)) {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 28))
                            .foregroundColor(Color.ds.textMuted)
                        Text(placeholderTitle)
                            .typography(.body)
                            .foregroundColor(Color.ds.text)
                    }
                )
        }
    }
}

struct PlaybackTransportBarComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "playback.transport"
    static let category: EditorComponentCategory = .playback
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let context: EditorPlaybackContext
    let actions: EditorPlaybackActions

    var body: some View {
        ZStack {
            HStack {
                PlaybackAspectSettingsButtonComponent(
                    showAspectSettings: context.showAspectSettings,
                    action: actions.onToggleAspectSettings
                )
                Spacer()
                PlaybackUndoRedoClusterComponent(
                    canUndo: context.canUndo,
                    canRedo: context.canRedo,
                    onUndo: actions.onUndo,
                    onRedo: actions.onRedo
                )
            }

            HStack(spacing: .spacing(.sp2)) {
                transportButton(systemImage: "backward", label: "Jump to start", action: actions.onJumpToStart)
                transportButton(
                    systemImage: context.isPlaying ? "pause" : "play",
                    label: context.isPlaying ? "Pause" : "Play",
                    action: context.isPlaying ? actions.onPause : actions.onPlay
                )
                transportButton(systemImage: "forward", label: "Jump to end", action: actions.onJumpToEnd)
            }
        }
    }

    private func transportButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundColor(Color.ds.text)
                .padding(.spacing(.sp1))
        }
        .accessibilityLabel(Text(label))
    }
}

struct PlaybackUndoRedoClusterComponent: View {
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16))
                    .foregroundColor(canUndo ? Color.ds.text : Color.ds.textMuted)
                    .padding(.spacing(.sp1))
            }
            .disabled(!canUndo)

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 16))
                    .foregroundColor(canRedo ? Color.ds.text : Color.ds.textMuted)
                    .padding(.spacing(.sp1))
            }
            .disabled(!canRedo)
        }
    }
}

struct PlaybackAspectSettingsButtonComponent: View {
    @Binding var showAspectSettings: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundColor(Color.ds.text)
                .padding(.spacing(.sp1))
        }
        .accessibilityLabel(Text("Aspect settings"))
    }
}
