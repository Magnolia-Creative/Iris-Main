import SwiftUI

/// Standalone timeline surface for the component library and showcase.
/// Does not include live scroll/drag physics from `TimelineSectionView`.
struct TimelineSurfaceComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.full"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let context: EditorTimelineContext
    let actions: EditorTimelineActions

    @State private var scrollOffset: CGFloat = 0

    private var layout: TimelineComponentLayout {
        TimelineComponentLayout.preset(context.layoutSize)
    }

    private var displayTracks: [Track] {
        let hasOverlayClips = context.tracks.contains { track in
            track.kind == .overlay && !(context.clipsByTrackId[track.trackId] ?? []).isEmpty
        }
        return context.tracks.filter { track in
            track.kind != .overlay || hasOverlayClips
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let timelineWidth = CGFloat(max(0, context.scrollableDurationUs)) / 1_000_000 * context.pixelsPerSecond
            let stackHeight = layout.trackStackHeight(for: displayTracks)

            ZStack(alignment: .topLeading) {
                Color.ds.bg

                HStack(spacing: 0) {
                    Spacer().frame(width: geometry.size.width / 2)
                    VStack(alignment: .leading, spacing: 0) {
                        TimelineRulerComponent(
                            size: context.layoutSize,
                            pixelsPerSecond: context.pixelsPerSecond,
                            durationUs: context.scrollableDurationUs,
                            currentTime: context.$currentTimeAtCenter
                        )

                        TimelineTrackStackComponent(
                            config: TimelineTrackComponentConfig(size: context.layoutSize),
                            tracks: context.tracks,
                            clipsByTrackId: context.clipsByTrackId,
                            mediaById: context.mediaById,
                            captionGroups: context.captionGroups,
                            captionCues: context.captionCues,
                            pixelsPerSecond: context.pixelsPerSecond,
                            viewportWidth: geometry.size.width,
                            scrollOffset: scrollOffset,
                            selectedClipId: context.$selectedClipId,
                            selectedCaptionCueId: context.$selectedCaptionCueId,
                            onMoveClip: actions.onMoveClip,
                            onTrimClip: actions.onTrimClip,
                            onAutoScroll: { _ in },
                            isUserScrolling: false,
                            reviewFocusedClipIds: context.reviewFocusedClipIds,
                            onSelectCaptionCue: actions.onCaptionCueSelected,
                            onClipSelected: actions.onClipSelected
                        )
                        .padding(.top, layout.trackTopOffset)
                    }
                    .frame(minWidth: timelineWidth)
                    Spacer().frame(width: geometry.size.width / 2)
                }

                TimelineTimeReadoutComponent(
                    size: context.layoutSize,
                    currentTimeUs: context.currentTimeAtCenter,
                    timelineDurationUs: context.timelineDurationUs
                )

                TimelinePlayheadComponent(tint: context.playheadTint)

                if context.showAddButton, let onAdd = actions.onAddSelection {
                    HStack {
                        Spacer()
                        TimelineAddMediaButtonComponent(
                            size: context.layoutSize,
                            onSelect: onAdd,
                            isMenuOpen: context.$isAddMenuOpen
                        )
                        .padding(.trailing, .spacing(.sp6))
                    }
                    .padding(.top, layout.rulerHeight + layout.trackTopOffset + layout.videoTrackHeight / 2)
                }
            }
            .frame(height: layout.sectionHeight(for: displayTracks))
        }
        .frame(height: layout.sectionHeight(for: displayTracks))
    }
}
