import SwiftUI
internal import Combine

struct EditorCanvasView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    let activeSpace: EditorSpace
    var onAddSelection: ((TrackKind, ImportSource) -> Void)? = nil
    var reviewFocusedClipIds: Set<String> = []
    var isReviewInteractionDisabled = false

    private var showsPlaybackControls: Bool {
        activeSpace == .edit || activeSpace == .export
    }

    private var expandsVertically: Bool {
        activeSpace == .edit || activeSpace == .export
    }

    private var previewHeight: CGFloat {
        switch activeSpace {    
        case .importMedia, .chat:
            140
        case .edit, .export:
            220
        }
    }

    private var previewBottomSpacing: CGFloat {
        showsPlaybackControls ? .spacing(.sp6) : .spacing(.sp2)
    }

    private var timelineTopInset: CGFloat {
        previewHeight + previewBottomSpacing + (showsPlaybackControls ? 32 : 0)
    }

    private var timelineLayout: TimelineLayout {
        activeSpace == .edit ? .expanded : .compressed
    }

    private var allowsTimelineAdditions: Bool {
        activeSpace == .edit && !isReviewInteractionDisabled
    }

    private var rulerVerticalOffset: CGFloat {
        0
    }

    var body: some View {
        let state = controller.state
        let playback = playbackController ?? PlaybackController(
            statePublisher: controller.$state.eraseToAnyPublisher(),
            actions: controller
        )

        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                timelineTopSection(playback: playback)

                if activeSpace == .export {
                    ExportTimelineOverview(state: state)
                        .frame(height: 60)
                        .padding(.horizontal, .sp3)
                        .transition(.opacity)
                } else {
                    Color.clear
                        .frame(height: timelineLayout.sectionHeight(for: state.orderedTracks))
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }

            if activeSpace != .export {
                timelineViewContainer(state: state)
                    .padding(.top, timelineTopInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: expandsVertically ? .infinity : nil, alignment: .top)
        .onChange(of: activeSpace) { _, newSpace in
            EditorDebugTrace.log(
                "EditorCanvasView",
                "canvas updated activeSpace=\(newSpace.rawValue) previewHeight=\(Int(previewHeight)) layout=\(timelineLayout == .expanded ? "expanded" : "compressed")"
            )
        }
    }

    private func timelineViewContainer(state: TimelineState) -> some View {
        timelineView(state: state, layout: timelineLayout)
            .padding(.bottom, .spacing(.sp2))
            .animation(nil, value: activeSpace)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private func timelineTopSection(playback: PlaybackController) -> some View {
        VStack(spacing: 0) {
            PreviewSection(controller: playback, renderBridge: renderBridge)
                .frame(height: previewHeight)
                .padding(.horizontal, .sp3)
                .padding(.bottom, previewBottomSpacing)

            if showsPlaybackControls {
                PlaybackControls(controller: playback)
                    .padding(.horizontal, .sp4)
            }
        }
    }

    private func timelineView(state: TimelineState, layout: TimelineLayout) -> some View {
        let allowsTimelineAdditions = layout == .expanded
        let addSelection: (TrackKind, ImportSource) -> Void
        if allowsTimelineAdditions {
            addSelection = onAddSelection ?? controller.handleAddSelection(kind:source:)
        } else {
            addSelection = { _, _ in }
        }

        return TimelineSectionView(
            tracks: state.orderedTracks,
            clipsByTrackId: state.clipsByTrackId,
            mediaById: state.mediaById,
            layout: layout,
            pixelsPerSecond: state.pixelsPerSecond,
            timelineDurationUs: state.calculatedTimelineDurationUs,
            scrollableDurationUs: state.scrollableDurationUs,
            currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
            scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
            selectedClipId: controller.binding(\.selectedClipId),
            playbackState: state.playbackState,
            onAddSelection: addSelection,
            onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
            onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
            onDropImportedSegmentAtTime: activeSpace == .importMedia ? { item, timeUs in
                controller.insertClipSegment(
                    mediaId: item.mediaId,
                    sourceRange: item.sourceRange,
                    at: timeUs
                )
            } : nil,
            showAddButton: allowsTimelineAdditions,
            rulerVerticalOffset: rulerVerticalOffset,
            reviewFocusedClipIds: reviewFocusedClipIds,
            isReviewInteractionDisabled: isReviewInteractionDisabled
        )
        .frame(height: layout.sectionHeight(for: state.orderedTracks))
        .animation(nil, value: layout.sectionHeight(for: state.orderedTracks))
    }

}

private struct ExportTimelineOverview: View {
    let state: TimelineState

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let durationUs = max(1, state.calculatedTimelineDurationUs)
            let pxPerUs = totalWidth / CGFloat(durationUs)

            ZStack(alignment: .leading) {
                ForEach(state.clips) { clip in
                    let startX = CGFloat(clip.timelineRange.start) * pxPerUs
                    let clipWidth = CGFloat(clip.duration) * pxPerUs

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.ds.accentBg)
                        .frame(width: max(clipWidth, 2), height: 24)
                        .offset(x: startX)
                }
                .frame(height: 24)
                .offset(y: 20)

                let playheadX = CGFloat(state.currentTimeAtCenter) * pxPerUs
                Rectangle()
                    .fill(Color.ds.text)
                    .frame(width: 1, height: geometry.size.height)
                    .offset(x: playheadX)

                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        let timeUs = Int64(Double(i) / 4.0 * Double(durationUs))
                        VStack {
                            Rectangle().fill(Color.ds.border).frame(width: 1, height: 8)
                            Text(TimeFormatter.formatTime(timeUs))
                                .typography(.bodySmall)
                                .foregroundColor(Color.ds.textMuted)
                                .fixedSize()
                        }
                        if i < 4 { Spacer() }
                    }
                }
            }
        }
    }
}
