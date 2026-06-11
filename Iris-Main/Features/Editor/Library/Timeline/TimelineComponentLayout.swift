import SwiftUI

struct TimelineComponentLayout: Equatable {
    let rulerHeight: CGFloat
    let trackTopOffset: CGFloat
    let iconSize: CGFloat
    let trackSpacing: CGFloat
    let videoTrackHeight: CGFloat
    let audioTrackHeight: CGFloat
    let overlayTrackHeight: CGFloat
    let captionsTrackHeight: CGFloat

    static func preset(_ size: EditorComponentSize) -> TimelineComponentLayout {
        switch size {
        case .compressed:
            return TimelineComponentLayout(
                rulerHeight: 28,
                trackTopOffset: 16,
                iconSize: 20,
                trackSpacing: .spacing(.sp1),
                videoTrackHeight: .spacing(.sp7),
                audioTrackHeight: .spacing(.sp4),
                overlayTrackHeight: .spacing(.sp4),
                captionsTrackHeight: .spacing(.sp4)
            )
        case .standard:
            return TimelineComponentLayout(
                rulerHeight: 30,
                trackTopOffset: 20,
                iconSize: 22,
                trackSpacing: .spacing(.sp2),
                videoTrackHeight: .spacing(.sp8),
                audioTrackHeight: .spacing(.sp6),
                overlayTrackHeight: .spacing(.sp6),
                captionsTrackHeight: .spacing(.sp5)
            )
        case .expanded:
            return TimelineComponentLayout(
                rulerHeight: 32,
                trackTopOffset: 24,
                iconSize: 24,
                trackSpacing: .spacing(.sp2),
                videoTrackHeight: .spacing(.sp10),
                audioTrackHeight: .spacing(.sp8),
                overlayTrackHeight: .spacing(.sp8),
                captionsTrackHeight: .spacing(.sp7)
            )
        }
    }

    func trackHeight(for kind: TrackKind) -> CGFloat {
        switch kind {
        case .video: videoTrackHeight
        case .audio: audioTrackHeight
        case .overlay: overlayTrackHeight
        case .captions: captionsTrackHeight
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

    var legacyLayout: TimelineLayout {
        TimelineLayout(
            rulerHeight: rulerHeight,
            trackTopOffset: trackTopOffset,
            iconSize: iconSize,
            trackSpacing: trackSpacing,
            videoTrackHeight: videoTrackHeight,
            audioTrackHeight: audioTrackHeight,
            overlayTrackHeight: overlayTrackHeight,
            captionsTrackHeight: captionsTrackHeight
        )
    }
}

extension TimelineLayout {
    init(from componentLayout: TimelineComponentLayout) {
        self.init(
            rulerHeight: componentLayout.rulerHeight,
            trackTopOffset: componentLayout.trackTopOffset,
            iconSize: componentLayout.iconSize,
            trackSpacing: componentLayout.trackSpacing,
            videoTrackHeight: componentLayout.videoTrackHeight,
            audioTrackHeight: componentLayout.audioTrackHeight,
            overlayTrackHeight: componentLayout.overlayTrackHeight,
            captionsTrackHeight: componentLayout.captionsTrackHeight
        )
    }
}
