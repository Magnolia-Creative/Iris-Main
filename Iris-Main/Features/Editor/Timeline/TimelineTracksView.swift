import SwiftUI

struct TimelineTracksContent: View {
    let tracks: [Track]
    let clipsByTrackId: [String: [Clip]]
    let mediaById: [String: Media]
    let captionGroups: [CaptionGroup]
    let captionCues: [CaptionCue]
    let layout: TimelineLayout
    let pixelsPerSecond: CGFloat
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    let viewportWidth: CGFloat
    let contentWidth: CGFloat
    @Binding var scrollOffset: CGFloat
    @Binding var selectedClipId: String?
    @Binding var selectedCaptionCueId: String?
    let onAutoScroll: (CGFloat) -> Void
    let isUserScrolling: Bool
    let reviewFocusedClipIds: Set<String>
    let isReviewInteractionDisabled: Bool
    var promptActionPreview: TimelinePromptActionPreview? = nil
    var captionHighlightRangeUs: ClosedRange<Int64>? = nil
    var onSelectCaptionCue: ((String) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let captionHighlightRangeUs {
                TimelineCaptionRangeHighlight(
                    rangeUs: captionHighlightRangeUs,
                    pixelsPerSecond: pixelsPerSecond,
                    height: layout.trackStackHeight(for: tracks)
                )
            }

            VStack(spacing: layout.trackSpacing) {
                ForEach(tracks) { track in
                    if track.kind == .captions {
                        let groupIds = Set(captionGroups.filter { $0.trackId == track.trackId }.map(\.groupId))
                        let cues = captionCues.filter { groupIds.contains($0.groupId) }
                        TimelineCaptionsTrackRow(
                            track: track,
                            cues: cues,
                            layout: layout,
                            pixelsPerSecond: pixelsPerSecond,
                            selectedCaptionCueId: $selectedCaptionCueId,
                            onSelectCue: { id in
                                onSelectCaptionCue?(id)
                            }
                        )
                    } else {
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
                            isReviewInteractionDisabled: isReviewInteractionDisabled,
                            promptActionPreview: promptActionPreview
                        )
                    }
                }
            }
        }
        .frame(minWidth: max(viewportWidth, contentWidth))
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}
