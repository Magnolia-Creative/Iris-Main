import SwiftUI

struct TimelineLayout: Equatable {
    let rulerHeight: CGFloat
    let trackTopOffset: CGFloat
    let iconSize: CGFloat
    let trackSpacing: CGFloat
    let videoTrackHeight: CGFloat
    let audioTrackHeight: CGFloat
    let overlayTrackHeight: CGFloat

    static let expanded = TimelineLayout(
        rulerHeight: 32,
        trackTopOffset: 24,
        iconSize: 24,
        trackSpacing: .spacing(.sp2),
        videoTrackHeight: .spacing(.sp10),
        audioTrackHeight: .spacing(.sp8),
        overlayTrackHeight: .spacing(.sp8)
    )

    static let compressed = TimelineLayout(
        rulerHeight: 28,
        trackTopOffset: 16,
        iconSize: 20,
        trackSpacing: .spacing(.sp1),
        videoTrackHeight: .spacing(.sp5),
        audioTrackHeight: .spacing(.sp4),
        overlayTrackHeight: .spacing(.sp4)
    )

    func trackHeight(for kind: TrackKind) -> CGFloat {
        switch kind {
        case .video:
            videoTrackHeight
        case .audio:
            audioTrackHeight
        case .overlay:
            overlayTrackHeight
        }
    }

    func trackStackHeight(for tracks: [Track]) -> CGFloat {
        let heights = tracks.map { trackHeight(for: $0.kind) }.reduce(0, +)
        let spacing = CGFloat(max(0, tracks.count - 1)) * trackSpacing
        return heights + spacing
    }

    func sectionHeight(for tracks: [Track]) -> CGFloat {
        rulerHeight + trackTopOffset + trackStackHeight(for: tracks)
    }
}
