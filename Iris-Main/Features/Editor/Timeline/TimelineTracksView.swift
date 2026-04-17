import SwiftUI

struct TimelineTracksContent: View {
    let tracks: [Track]
    let clipsByTrackId: [String: [Clip]]
    let mediaById: [String: Media]
    let layout: TimelineLayout
    let pixelsPerSecond: CGFloat
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    let viewportWidth: CGFloat
    let contentWidth: CGFloat
    @Binding var scrollOffset: CGFloat
    @Binding var selectedClipId: String?
    let onAutoScroll: (CGFloat) -> Void
    let isUserScrolling: Bool
    let reviewFocusedClipIds: Set<String>
    let isReviewInteractionDisabled: Bool

    var body: some View {
        VStack(spacing: layout.trackSpacing) {
            ForEach(tracks) { track in
                TimelineTrackRow(
                    track: track,
                    clips: clipsByTrackId[track.trackId] ?? [],
                    mediaById: mediaById,
                    layout: layout,
                    pixelsPerSecond: pixelsPerSecond,
                    onMoveClip: onMoveClip,
                    onTrimClip: onTrimClip,
                    viewportWidth: viewportWidth,
                    scrollOffset: scrollOffset,
                    selectedClipId: $selectedClipId,
                    onAutoScroll: onAutoScroll,
                    isUserScrolling: isUserScrolling,
                    reviewFocusedClipIds: reviewFocusedClipIds,
                    isReviewInteractionDisabled: isReviewInteractionDisabled
                )
            }
        }
        .frame(minWidth: max(viewportWidth, contentWidth))
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}
