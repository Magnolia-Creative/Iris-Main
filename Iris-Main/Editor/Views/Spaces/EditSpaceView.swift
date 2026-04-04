import SwiftUI
internal import Combine

struct EditSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID

    private let rulerHeight: CGFloat = 32
    private let trackTopOffset: CGFloat = 40
    private let iconSize: CGFloat = 24

    var body: some View {
        let state = controller.state

        HStack(spacing: 0) {
            // Left toolbar (vertical)
            VStack(spacing: .spacing(.sp3)) {
                Spacer()

                VerticalToolButton(
                    systemImage: "scissors",
                    label: "Cut",
                    isEnabled: state.selectedClipId != nil
                ) {
                    controller.splitSelectedClip()
                }

                VerticalToolButton(
                    systemImage: "trash",
                    label: "Delete",
                    isEnabled: state.selectedClipId != nil,
                    tint: Color.ds.danger
                ) {
                    controller.deleteSelectedClip()
                }

                Spacer()
            }
            .frame(width: 56)
            .background(Color.ds.surface.opacity(0.5))

            // Main content
            VStack(spacing: .spacing(.sp4)) {
                // Large preview
                PreviewSection(
                    controller: playbackController ?? PlaybackController(
                        statePublisher: controller.$state.eraseToAnyPublisher(),
                        actions: controller
                    ),
                    renderBridge: renderBridge
                )
                .matchedGeometryEffect(id: "preview", in: namespace)
                .padding(.horizontal, .sp3)

                if let pc = playbackController {
                    PlaybackControls(controller: pc)
                        .padding(.horizontal, .sp4)
                }

                // Large timeline
                TimelineSectionView(
                    tracks: state.orderedTracks,
                    clipsByTrackId: state.clipsByTrackId,
                    mediaById: state.mediaById,
                    pixelsPerSecond: state.pixelsPerSecond,
                    rulerHeight: rulerHeight,
                    trackTopOffset: trackTopOffset,
                    iconSize: iconSize,
                    timelineDurationUs: state.calculatedTimelineDurationUs,
                    scrollableDurationUs: state.scrollableDurationUs,
                    currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
                    scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
                    selectedClipId: controller.binding(\.selectedClipId),
                    onAddSelection: controller.handleAddSelection(kind:source:),
                    onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
                    onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:)
                )
                .frame(maxHeight: .infinity)
                .matchedGeometryEffect(id: "timeline", in: namespace)
            }
        }
    }
}

private struct VerticalToolButton: View {
    let systemImage: String
    let label: String
    var isEnabled: Bool = true
    var tint: Color = Color.ds.text
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            VStack(spacing: .spacing(.sp1)) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .typography(.bodySmall)
            }
            .foregroundColor(isEnabled ? tint : Color.ds.textMuted.opacity(0.5))
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
