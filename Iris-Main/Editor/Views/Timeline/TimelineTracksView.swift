import SwiftUI

struct TimelineTracksContent: View {
    let tracks: [Track]
    let clipsByTrackId: [String: [Clip]]
    let mediaById: [String: Media]
    let pixelsPerSecond: CGFloat
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    let viewportWidth: CGFloat
    let contentWidth: CGFloat
    @Binding var scrollOffset: CGFloat
    @Binding var selectedClipId: String?
    let onAutoScroll: (CGFloat) -> Void
    let isUserScrolling: Bool

    var body: some View {
        VStack(spacing: .spacing(.sp2)) {
            ForEach(tracks) { track in
                TimelineTrackRow(
                    track: track,
                    clips: clipsByTrackId[track.trackId] ?? [],
                    mediaById: mediaById,
                    pixelsPerSecond: pixelsPerSecond,
                    onMoveClip: onMoveClip,
                    onTrimClip: onTrimClip,
                    viewportWidth: viewportWidth,
                    scrollOffset: scrollOffset,
                    selectedClipId: $selectedClipId,
                    onAutoScroll: onAutoScroll,
                    isUserScrolling: isUserScrolling
                )
            }
        }
        .frame(minWidth: max(viewportWidth, contentWidth))
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}
