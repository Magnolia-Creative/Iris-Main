import SwiftUI

struct PreviewSection: View {
    @ObservedObject var controller: PlaybackController
    var renderBridge: TimelineRenderBridge?
    var previewAspect: CGFloat?

    var body: some View {
        let preview = Group {
            if let bridge = renderBridge {
                VideoLabPreviewView(engine: bridge.engine)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.ds.surface)
                    .overlay(
                        VStack(spacing: .spacing(.sp2)) {
                            Text("Preview")
                                .typography(.body)
                                .foregroundColor(Color.ds.text)
                            Text("Playhead: \(controller.state?.currentTimeAtCenter ?? 0) us")
                                .typography(.bodySmall)
                                .foregroundColor(Color.ds.textMuted)
                        }
                    )
            }
        }

        ZStack {
            Color.clear
            if let previewAspect {
                preview.aspectRatio(previewAspect, contentMode: .fit)
            } else {
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 2, minHeight: 2)
    }
}
