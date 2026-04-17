import SwiftUI

struct AgentTimelineSectionView: View {
    let clips: [AgentTimelineClip]

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Timeline assembly")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            AgentSurfaceCard(minHeight: 0) {
                VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                    if clips.isEmpty {
                        AgentPlaceholderStateView(
                            text: "The proposed timeline will appear here once the first draft is assembled."
                        )
                    } else {
                        AgentTimelineStripView(clips: clips)
                    }
                }
            }
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.88), value: clips)
    }
}

private struct AgentPlaceholderStateView: View {
    let text: String

    var body: some View {
        Text(text)
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.textMuted)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
    }
}

private struct AgentTimelineStripView: View {
    let clips: [AgentTimelineClip]

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let spacing = CGFloat(max(clips.count - 1, 0)) * .spacing(.sp2)
            let usableWidth = max(availableWidth - spacing, 1)
            let weights = clips.map { sqrt(max($0.segmentDurationSeconds, 0.15)) }
            let weightSum = max(weights.reduce(0, +), 0.01)
            let widths = weights.map { weight in
                max((CGFloat(weight) / CGFloat(weightSum)) * usableWidth, 72)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: .spacing(.sp2)) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        AgentTimelineClipView(
                            clip: clip,
                            width: widths[index]
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(minWidth: availableWidth, alignment: .leading)
            }
        }
        .frame(height: 108)
    }
}

private struct AgentTimelineClipView: View {
    let clip: AgentTimelineClip
    let width: CGFloat
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack {
            background

            LinearGradient(
                colors: [
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: width, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .task(id: clip.videoURL) {
            guard let videoURL = clip.videoURL else {
                thumbnail = nil
                return
            }

            thumbnail = await VideoAssetPreviewLoader.generateThumbnail(for: videoURL)
        }
    }

    private var background: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color.ds.accentBg.opacity(0.38),
                        Color.ds.bg.opacity(0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}
