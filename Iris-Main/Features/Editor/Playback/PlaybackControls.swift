import SwiftUI

struct PlaybackControls: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var timeline: TimelineController
    @Binding var showAspectSettings: Bool

    init(
        playback: PlaybackController,
        timeline: TimelineController,
        showAspectSettings: Binding<Bool> = .constant(false)
    ) {
        self.playback = playback
        self.timeline = timeline
        self._showAspectSettings = showAspectSettings
    }

    var body: some View {
        ZStack {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showAspectSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }

                Spacer()

                HStack(spacing: 0) {
                    Button {
                        timeline.undoLastActionGroup()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16))
                            .foregroundColor(timeline.canUndo ? Color.ds.text : Color.ds.textMuted)
                            .padding(.spacing(.sp1))
                    }
                    .disabled(!timeline.canUndo)

                    Button {
                        timeline.redoLastActionGroup()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16))
                            .foregroundColor(timeline.canRedo ? Color.ds.text : Color.ds.textMuted)
                            .padding(.spacing(.sp1))
                    }
                    .disabled(!timeline.canRedo)
                }
            }

            HStack(spacing: .spacing(.sp2)) {
                Button { playback.jumpToStart() } label: {
                    Image(systemName: "backward")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }

                Button {
                    if playback.isPlaying() { playback.pause() }
                    else { playback.play() }
                } label: {
                    Image(systemName: playback.isPlaying() ? "pause" : "play")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }

                Button { playback.jumpToEnd() } label: {
                    Image(systemName: "forward")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }
            }
        }
    }
}
