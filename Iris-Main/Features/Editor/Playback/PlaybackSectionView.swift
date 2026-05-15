import SwiftUI

struct PlaybackSectionView: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var timeline: TimelineController
    let renderBridge: TimelineRenderBridge?

    init(
        playback: PlaybackController,
        timeline: TimelineController,
        renderBridge: TimelineRenderBridge? = nil
    ) {
        self.playback = playback
        self.timeline = timeline
        self.renderBridge = renderBridge
    }

    var body: some View {
        VStack(spacing: .spacing(.sp4)) {
            PreviewSection(controller: playback, renderBridge: renderBridge)
                .padding(.horizontal, .sp3)
            PlaybackControls(playback: playback, timeline: timeline)
                .padding(.horizontal, .sp2)
        }
    }
}
