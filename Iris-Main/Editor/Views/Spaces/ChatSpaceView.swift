import SwiftUI
internal import Combine

// MARK: - Canvas (preview + timeline only)

struct ChatSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID
    private let timelineLayout = TimelineLayout.compressed

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            PreviewSection(
                controller: playbackController ?? PlaybackController(
                    statePublisher: controller.$state.eraseToAnyPublisher(),
                    actions: controller
                ),
                renderBridge: renderBridge
            )
            .frame(height: 140)
            .matchedGeometryEffect(id: "preview", in: namespace)
            .padding(.horizontal, .sp3)

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
                playbackState: state.playbackState,
                onAddSelection: { _, _ in },
                onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
                onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
                showAddButton: false
            )
            .frame(height: timelineLayout.sectionHeight(for: state.orderedTracks))
            .matchedGeometryEffect(id: "timeline", in: namespace)
        }
    }
}

// MARK: - Panel (extends from nav bar)

struct ChatPanelContent: View {
    @ObservedObject var controller: TimelineController

    @State private var promptText = ""
    @State private var selectedClipIds: Set<String> = []
    @FocusState private var isPromptFocused: Bool
    @State private var showDiffView = false

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            if !selectedClipIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .spacing(.sp2)) {
                        ForEach(Array(selectedClipIds), id: \.self) { clipId in
                            if let clip = state.clips.first(where: { $0.clipId == clipId }) {
                                clipContextPill(clip: clip, media: state.mediaById[clip.mediaId])
                            }
                        }
                    }
                    .padding(.horizontal, .sp2)
                    .padding(.vertical, .sp2)
                }

                Divider().overlay(Color.ds.border.opacity(0.4))
            }

            if selectedClipIds.isEmpty && promptText.isEmpty {
                VStack(spacing: .spacing(.sp3)) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28))
                        .foregroundColor(Color.ds.textMuted)
                    Text("Tap clips to add context")
                        .typography(.body)
                        .foregroundColor(Color.ds.textMuted)
                    Text("Then describe your edit")
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)

            HStack(spacing: .spacing(.sp3)) {
                Button {
                    if let selectedId = state.selectedClipId {
                        if selectedClipIds.contains(selectedId) {
                            selectedClipIds.remove(selectedId)
                        } else {
                            selectedClipIds.insert(selectedId)
                        }
                    }
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 18))
                        .foregroundColor(Color.ds.accentFg)
                }

                TextField("Describe your edit...", text: $promptText, axis: .vertical)
                    .typographyStyle(.body)
                    .lineLimit(1...4)
                    .focused($isPromptFocused)
                    .padding(.spacing(.sp3))
                    .background(Color.ds.bg.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                    .overlay(
                        RoundedRectangle(cornerRadius: .spacing(.sp3))
                            .stroke(Color.ds.border.opacity(0.5), lineWidth: 1)
                    )

                Button { submitPrompt() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(promptText.isEmpty ? Color.ds.textMuted : Color.ds.accentFg)
                }
                .disabled(promptText.isEmpty)
            }
            .padding(.horizontal, .sp2)
            .padding(.vertical, .sp2)
        }
        .sheet(isPresented: $showDiffView) {
            ChatDiffView(
                controller: controller,
                onApprove: { showDiffView = false },
                onReprompt: { showDiffView = false }
            )
        }
    }

    private func clipContextPill(clip: Clip, media: Media?) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            Image(systemName: media?.kind == .video ? "video.fill" : "photo.fill")
                .font(.system(size: 12))
                .foregroundColor(Color.ds.accentFg)

            Text(TimeFormatter.formatTime(clip.duration))
                .typography(.bodySmall)
                .foregroundColor(Color.ds.text)

            Button {
                selectedClipIds.remove(clip.clipId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color.ds.textMuted)
            }
        }
        .padding(.horizontal, .sp3)
        .padding(.vertical, .sp2)
        .background(Color.ds.bg.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.ds.accentFg.opacity(0.3), lineWidth: 1))
    }

    private func submitPrompt() {
        guard !promptText.isEmpty else { return }
        showDiffView = true
    }
}
