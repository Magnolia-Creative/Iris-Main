import SwiftUI
import MetalKit

struct PreviewSection: View {
    @ObservedObject var controller: PlaybackController
    var renderBridge: TimelineRenderBridge?

    var body: some View {
        Group {
            if let bridge = renderBridge {
                MetalPreviewView(engine: bridge.engine)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.ds.surface)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
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
    }
}
