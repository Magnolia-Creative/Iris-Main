import SwiftUI

struct PlaybackSectionView: View {
    let controller: PlaybackController
    let renderBridge: TimelineRenderBridge?

    init(controller: PlaybackController, renderBridge: TimelineRenderBridge? = nil) {
        self.controller = controller
        self.renderBridge = renderBridge
    }

    var body: some View {
        VStack(spacing: .spacing(.sp4)) {
            PreviewSection(controller: controller, renderBridge: renderBridge)
                .padding(.horizontal, .sp3)
            PlaybackControls(controller: controller)
                .padding(.horizontal, .sp2)
        }
    }
}
