import SwiftUI

struct PlaybackControls: View {
    @ObservedObject var controller: PlaybackController

    var body: some View {
        ZStack {
            HStack {
                Button {} label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }

                Spacer()

                HStack(spacing: 0) {
                    Button {} label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16))
                            .foregroundColor(Color.ds.text)
                            .padding(.spacing(.sp1))
                    }
                    Button {} label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16))
                            .foregroundColor(Color.ds.text)
                            .padding(.spacing(.sp1))
                    }
                }
            }

            HStack(spacing: .spacing(.sp2)) {
                Button { controller.jumpToStart() } label: {
                    Image(systemName: "backward")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }

                Button {
                    if controller.isPlaying() { controller.pause() }
                    else { controller.play() }
                } label: {
                    Image(systemName: controller.isPlaying() ? "pause" : "play")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }

                Button { controller.jumpToEnd() } label: {
                    Image(systemName: "forward")
                        .font(.system(size: 16))
                        .foregroundColor(Color.ds.text)
                        .padding(.spacing(.sp1))
                }
            }
        }
    }
}
