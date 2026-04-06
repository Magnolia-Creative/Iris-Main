import SwiftUI
internal import Combine

struct EditorCanvasView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    let activeSpace: EditorSpace

    @State private var isTimelineDropTargeted = false

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
        showsPlaybackControls ? .spacing(.sp6) : 0
    }

    private var timelineLayout: TimelineLayout {
        activeSpace == .edit ? .expanded : .compressed
    }

    private var allowsTimelineAdditions: Bool {
        activeSpace == .edit
    }

    private var rulerVerticalOffset: CGFloat {
        switch activeSpace {
        case .importMedia, .chat:
            -12
        case .edit, .export:
            0
        }
    }

    var body: some View {
        let state = controller.state
        let playback = playbackController ?? PlaybackController(
            statePublisher: controller.$state.eraseToAnyPublisher(),
            actions: controller
        )

        VStack(spacing: 0) {
            PreviewSection(controller: playback, renderBridge: renderBridge)
                .frame(height: previewHeight)
                .padding(.horizontal, .sp3)
                .padding(.bottom, previewBottomSpacing)

            if showsPlaybackControls {
                PlaybackControls(controller: playback)
                    .padding(.horizontal, .sp4)
            }

            if activeSpace == .export {
                ExportTimelineOverview(state: state)
                    .frame(height: 60)
                    .padding(.horizontal, .sp3)
                    .transition(.opacity)
            } else {
                regularTimelineView(state: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: expandsVertically ? .infinity : nil, alignment: .top)
    }

    @ViewBuilder
    private func regularTimelineView(state: TimelineState) -> some View {
        if activeSpace == .importMedia {
            importTimelineView(state: state)
        } else {
            standardTimelineView(state: state)
        }
    }

    private func standardTimelineView(state: TimelineState) -> some View {
        let addSelection: (TrackKind, ImportSource) -> Void
        if allowsTimelineAdditions {
            addSelection = controller.handleAddSelection(kind:source:)
        } else {
            addSelection = { _, _ in }
        }

        return TimelineSectionView(
            tracks: state.orderedTracks,
            clipsByTrackId: state.clipsByTrackId,
            mediaById: state.mediaById,
            layout: timelineLayout,
            pixelsPerSecond: state.pixelsPerSecond,
            timelineDurationUs: state.calculatedTimelineDurationUs,
            scrollableDurationUs: state.scrollableDurationUs,
            currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
            scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
            selectedClipId: controller.binding(\.selectedClipId),
            onAddSelection: addSelection,
            onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
            onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
            showAddButton: allowsTimelineAdditions,
            rulerVerticalOffset: rulerVerticalOffset
        )
        .frame(height: timelineLayout.sectionHeight(for: state.orderedTracks))
    }

    private func importTimelineView(state: TimelineState) -> some View {
        TimelineSectionView(
            tracks: state.orderedTracks,
            clipsByTrackId: state.clipsByTrackId,
            mediaById: state.mediaById,
            layout: timelineLayout,
            pixelsPerSecond: state.pixelsPerSecond,
            timelineDurationUs: state.calculatedTimelineDurationUs,
            scrollableDurationUs: state.scrollableDurationUs,
            currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
            scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
            selectedClipId: controller.binding(\.selectedClipId),
            onAddSelection: { _, _ in },
            onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
            onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
            showAddButton: false,
            rulerVerticalOffset: rulerVerticalOffset
        )
        .frame(height: timelineLayout.sectionHeight(for: state.orderedTracks))
        .overlay {
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(
                    isTimelineDropTargeted ? Color.ds.accentFg : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .padding(.horizontal, .sp3)
                .animation(.easeOut(duration: 0.18), value: isTimelineDropTargeted)
        }
        .dropDestination(for: ImportedTimelineSegment.self) { items, _ in
            guard let item = items.first else { return false }
            controller.insertClipSegment(
                mediaId: item.mediaId,
                sourceRange: item.sourceRange,
                at: controller.state.currentTimeAtCenter
            )
            return true
        } isTargeted: { isTargeted in
            isTimelineDropTargeted = isTargeted
        }
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
