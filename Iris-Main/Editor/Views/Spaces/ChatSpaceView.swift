import SwiftUI
internal import Combine

struct ChatSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID

    @State private var promptText = ""
    @State private var selectedClipIds: Set<String> = []
    @State private var isAgentActive = false
    @State private var showDiffView = false
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            // Compressed preview
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

            // Compressed timeline with tappable clips
            TimelineSectionView(
                tracks: state.orderedTracks,
                clipsByTrackId: state.clipsByTrackId,
                mediaById: state.mediaById,
                pixelsPerSecond: state.pixelsPerSecond,
                rulerHeight: 28,
                trackTopOffset: 32,
                iconSize: 20,
                timelineDurationUs: state.calculatedTimelineDurationUs,
                scrollableDurationUs: state.scrollableDurationUs,
                currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
                scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
                selectedClipId: controller.binding(\.selectedClipId),
                onAddSelection: { _, _ in },
                onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
                onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
                showAddButton: false
            )
            .frame(height: 100)
            .matchedGeometryEffect(id: "timeline", in: namespace)

            // Chat section
            VStack(spacing: 0) {
                // Context clips
                if !selectedClipIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: .spacing(.sp2)) {
                            ForEach(Array(selectedClipIds), id: \.self) { clipId in
                                if let clip = state.clips.first(where: { $0.clipId == clipId }) {
                                    clipContextPill(clip: clip, media: state.mediaById[clip.mediaId])
                                }
                            }
                        }
                        .padding(.horizontal, .sp4)
                        .padding(.vertical, .sp3)
                    }

                    Divider().background(Color.ds.border)
                }

                // Instructions
                if selectedClipIds.isEmpty && promptText.isEmpty {
                    VStack(spacing: .spacing(.sp3)) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 32))
                            .foregroundColor(Color.ds.textMuted)
                        Text("Tap clips in the timeline to add context")
                            .typography(.body)
                            .foregroundColor(Color.ds.textMuted)
                        Text("Then describe what changes you'd like")
                            .typography(.bodySmall)
                            .foregroundColor(Color.ds.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer()

                // Prompt input
                HStack(spacing: .spacing(.sp3)) {
                    // Clip add button
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
                        .background(Color.ds.bg)
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                        .overlay(RoundedRectangle(cornerRadius: .spacing(.sp3)).stroke(Color.ds.border, lineWidth: 1))

                    Button { submitPrompt() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(
                                promptText.isEmpty ? Color.ds.textMuted : Color.ds.accentFg
                            )
                    }
                    .disabled(promptText.isEmpty)
                }
                .padding(.horizontal, .sp4)
                .padding(.vertical, .sp3)
            }
            .frame(maxHeight: .infinity)
            .background(Color.ds.surface)
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
            .padding(.horizontal, .sp3)
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
        .background(Color.ds.bg)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.ds.accentFg.opacity(0.3), lineWidth: 1))
    }

    private func submitPrompt() {
        guard !promptText.isEmpty else { return }
        showDiffView = true
    }
}
