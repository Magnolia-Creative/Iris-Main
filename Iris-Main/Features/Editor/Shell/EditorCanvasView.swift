import SwiftUI
internal import Combine

private enum JITTimelinePresentation {
    case full
    case primaryTrackOnly
    case focusedClipStrip
    case hidden
}

struct EditorCanvasView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    let activeSpace: EditorSpace
    @ObservedObject var captionsFlow: CaptionsFlowController
    var onAddSelection: ((TrackKind, ImportSource) -> Void)? = nil
    @State private var isTimelineAddMenuOpen = false
    var reviewFocusedClipIds: Set<String> = []
    var isReviewInteractionDisabled = false
    var promptActionPreview: TimelinePromptActionPreview? = nil
    @Binding var showPlaybackAspectSettings: Bool

    init(
        controller: TimelineController,
        playbackController: PlaybackController?,
        renderBridge: TimelineRenderBridge,
        activeSpace: EditorSpace,
        captionsFlow: CaptionsFlowController,
        showPlaybackAspectSettings: Binding<Bool> = .constant(false),
        onAddSelection: ((TrackKind, ImportSource) -> Void)? = nil,
        reviewFocusedClipIds: Set<String> = [],
        isReviewInteractionDisabled: Bool = false,
        promptActionPreview: TimelinePromptActionPreview? = nil
    ) {
        self.controller = controller
        self.playbackController = playbackController
        self.renderBridge = renderBridge
        self.activeSpace = activeSpace
        self.captionsFlow = captionsFlow
        self._showPlaybackAspectSettings = showPlaybackAspectSettings
        self.onAddSelection = onAddSelection
        self.reviewFocusedClipIds = reviewFocusedClipIds
        self.isReviewInteractionDisabled = isReviewInteractionDisabled
        self.promptActionPreview = promptActionPreview
    }

    private var showsPlaybackControls: Bool {
        activeSpace == .edit || activeSpace == .export
    }

    private var expandsVertically: Bool {
        activeSpace == .edit || activeSpace == .export
    }

    private var effectivePreviewHeight: CGFloat {
        switch activeSpace {
        case .importMedia:
            return 140
        case .edit, .export:
            return 220
        }
    }

    private var previewBottomSpacing: CGFloat {
        showsPlaybackControls ? .spacing(.sp6) : .spacing(.sp2)
    }

    private func timelineTopInset(for presentation: JITTimelinePresentation) -> CGFloat {
        effectivePreviewHeight + previewBottomSpacing + (showsPlaybackControls ? 32 : 0)
    }

    private func effectiveTimelineLayout(for presentation: JITTimelinePresentation) -> TimelineLayout {
        switch presentation {
        case .focusedClipStrip, .primaryTrackOnly:
            return .compressed
        case .full:
            return activeSpace == .edit ? .expanded : .compressed
        case .hidden:
            return .compressed
        }
    }

    private var allowsTimelineAdditions: Bool {
        activeSpace == .edit && !isReviewInteractionDisabled
    }

    private var rulerVerticalOffset: CGFloat {
        0
    }

    var body: some View {
        let state = controller.state
        let playback = resolvedPlaybackController()

        legacyCanvasBody(state: state, playback: playback)
        .frame(maxWidth: .infinity, maxHeight: expandsVertically ? .infinity : nil, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showPlaybackAspectSettings)
        .onChange(of: activeSpace) { _, newSpace in
            EditorDebugTrace.log(
                "EditorCanvasView",
                "canvas updated activeSpace=\(newSpace.rawValue) previewHeight=\(Int(effectivePreviewHeight))"
            )
        }
    }

    private func resolvedPlaybackController() -> PlaybackController {
        playbackController ?? PlaybackController(
            statePublisher: controller.$state.eraseToAnyPublisher(),
            actions: controller
        )
    }

    @ViewBuilder
    private func legacyCanvasBody(state: TimelineState, playback: PlaybackController) -> some View {
        let presentation = JITTimelinePresentation.full
        let layout = effectiveTimelineLayout(for: presentation)
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                timelineTopSection(playback: playback)

                Color.clear
                    .frame(height: layout.sectionHeight(for: displayTracks(state: state, presentation: presentation)))
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }

            if presentation != .hidden {
                timelineViewContainer(state: state, presentation: presentation)
                    .padding(.top, timelineTopInset(for: presentation))
            }

            aspectSettingsOverlayIfNeeded
        }
    }

    @ViewBuilder
    private var aspectSettingsOverlayIfNeeded: some View {
        if showPlaybackAspectSettings {
            aspectSettingsOverlay
                .zIndex(90)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: 8)),
                        removal: .scale(scale: 0.96)
                            .combined(with: .opacity)
                    )
                )
        }
    }

    private func timelineViewContainer(state: TimelineState, presentation: JITTimelinePresentation) -> some View {
        timelineView(state: state, presentation: presentation)
            .padding(.bottom, .spacing(.sp2))
            .animation(nil, value: activeSpace)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private func timelineTopSection(playback: PlaybackController) -> some View {
        VStack(spacing: 0) {
            PreviewSection(
                controller: playback,
                renderBridge: renderBridge,
                previewAspect: controller.state.effectiveOutputAspect?.aspectCGFloat
            )
                .frame(height: effectivePreviewHeight)
                .padding(.horizontal, .sp3)
                .padding(.bottom, previewBottomSpacing)

            if showsPlaybackControls {
                PlaybackControls(
                    playback: playback,
                    timeline: controller,
                    showAspectSettings: $showPlaybackAspectSettings
                )
                    .padding(.horizontal, .sp4)
            }
        }
    }

    private var aspectSettingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showPlaybackAspectSettings = false
                    }
                }

            PlaybackAspectSettingsPanel(
                timeline: controller,
                isPresented: $showPlaybackAspectSettings
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func makeTimelineContext(
        state: TimelineState,
        presentation: JITTimelinePresentation
    ) -> EditorTimelineContext {
        let layout = effectiveTimelineLayout(for: presentation)
        let displayTracks = displayTracks(state: state, presentation: presentation)
        let clipsByTrackId = clipsByTrackId(state: state, presentation: presentation)
        let canAddToTimeline = layout == .expanded && allowsTimelineAdditions
        let highlight = captionsFlow.highlightRangeUs(playheadUs: state.currentTimeAtCenter)
        let playheadTint = captionsFlow.playheadUsesAccentTint ? Color.ds.accentFg : Color.ds.text

        return EditorTimelineContext(
            tracks: displayTracks,
            clipsByTrackId: clipsByTrackId,
            mediaById: state.mediaById,
            captionGroups: state.captionGroups,
            captionCues: state.captionCues,
            layoutSize: layout.componentSize,
            pixelsPerSecond: state.pixelsPerSecond,
            timelineDurationUs: state.calculatedTimelineDurationUs,
            scrollableDurationUs: state.scrollableDurationUs,
            playbackState: state.playbackState,
            reviewFocusedClipIds: reviewFocusedClipIds,
            isReviewInteractionDisabled: isReviewInteractionDisabled,
            captionHighlightRangeUs: highlight,
            playheadTint: playheadTint,
            showAddButton: canAddToTimeline,
            currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
            scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
            selectedClipId: controller.binding(\.selectedClipId),
            selectedCaptionCueId: $captionsFlow.selectedCaptionCueId,
            isAddMenuOpen: $isTimelineAddMenuOpen
        )
    }

    private func makeTimelineActions(
        layout: TimelineLayout,
        presentation: JITTimelinePresentation
    ) -> EditorTimelineActions {
        let canAddToTimeline = layout == .expanded && allowsTimelineAdditions
        let addSelection: (TrackKind, ImportSource) -> Void
        if allowsTimelineAdditions {
            addSelection = onAddSelection ?? controller.handleAddSelection(kind:source:)
        } else {
            addSelection = { _, _ in }
        }

        return EditorTimelineActions(
            onAddSelection: canAddToTimeline ? addSelection : nil,
            onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
            onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
            onDropImportedSegmentAtTime: activeSpace == .importMedia ? { item, timeUs in
                controller.insertClipSegment(
                    mediaId: item.mediaId,
                    sourceRange: item.sourceRange,
                    at: timeUs
                )
            } : nil,
            onPreviewScrub: { timeUs, velocity in
                renderBridge.handleScroll(timeUs: timeUs, velocity: velocity)
            },
            onCaptionCueSelected: { cueId in
                controller.clearSelection()
                captionsFlow.openStyleEditor(forCueId: cueId)
            },
            onClipSelected: {
                captionsFlow.cancelStyleEditing()
            }
        )
    }

    private func makePlaybackContext(playback: PlaybackController) -> EditorPlaybackContext {
        EditorPlaybackContext(
            isPlaying: playback.isPlaying(),
            canUndo: controller.canUndo,
            canRedo: controller.canRedo,
            previewAspect: controller.state.effectiveOutputAspect?.aspectCGFloat,
            viewerSize: previewComponentSize,
            showAspectSettings: $showPlaybackAspectSettings
        )
    }

    private func makePlaybackActions(playback: PlaybackController) -> EditorPlaybackActions {
        EditorPlaybackActions(
            onPlay: { playback.play() },
            onPause: { playback.pause() },
            onJumpToStart: { playback.jumpToStart() },
            onJumpToEnd: { playback.jumpToEnd() },
            onUndo: { controller.undoLastActionGroup() },
            onRedo: { controller.redoLastActionGroup() },
            onToggleAspectSettings: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showPlaybackAspectSettings.toggle()
                }
            }
        )
    }

    private func timelineView(state: TimelineState, presentation: JITTimelinePresentation) -> some View {
        let layout = effectiveTimelineLayout(for: presentation)
        let canAddToTimeline = layout == .expanded && allowsTimelineAdditions
        let displayTracks = displayTracks(state: state, presentation: presentation)
        let clipsByTrackId = clipsByTrackId(state: state, presentation: presentation)
        let addSelection: (TrackKind, ImportSource) -> Void
        if allowsTimelineAdditions {
            addSelection = onAddSelection ?? controller.handleAddSelection(kind:source:)
        } else {
            addSelection = { _, _ in }
        }

        let highlight = captionsFlow.highlightRangeUs(playheadUs: state.currentTimeAtCenter)
        let playheadTint = captionsFlow.playheadUsesAccentTint ? Color.ds.accentFg : Color.ds.text

        return TimelineSectionView(
            tracks: displayTracks,
            clipsByTrackId: clipsByTrackId,
            mediaById: state.mediaById,
            layout: layout,
            pixelsPerSecond: state.pixelsPerSecond,
            timelineDurationUs: state.calculatedTimelineDurationUs,
            scrollableDurationUs: state.scrollableDurationUs,
            currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
            scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
            selectedClipId: controller.binding(\.selectedClipId),
            playbackState: state.playbackState,
            onAddSelection: canAddToTimeline ? addSelection : nil,
            isAddMenuOpen: $isTimelineAddMenuOpen,
            onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
            onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
            onDropImportedSegmentAtTime: activeSpace == .importMedia ? { item, timeUs in
                controller.insertClipSegment(
                    mediaId: item.mediaId,
                    sourceRange: item.sourceRange,
                    at: timeUs
                )
            } : nil,
            showAddButton: canAddToTimeline,
            rulerVerticalOffset: rulerVerticalOffset,
            reviewFocusedClipIds: reviewFocusedClipIds,
            isReviewInteractionDisabled: isReviewInteractionDisabled,
            promptActionPreview: promptActionPreview,
            onPreviewScrub: { timeUs, velocity in
                renderBridge.handleScroll(timeUs: timeUs, velocity: velocity)
            },
            captionHighlightRangeUs: highlight,
            playheadTint: playheadTint,
            captionGroups: state.captionGroups,
            captionCues: state.captionCues,
            selectedCaptionCueId: $captionsFlow.selectedCaptionCueId,
            onCaptionCueSelected: { cueId in
                controller.clearSelection()
                captionsFlow.openStyleEditor(forCueId: cueId)
            },
            onClipSelected: {
                captionsFlow.cancelStyleEditing()
            }
        )
        .frame(height: layout.sectionHeight(for: displayTracks))
        .animation(nil, value: layout.sectionHeight(for: displayTracks))
    }

    private func focusedClipIds(state: TimelineState) -> Set<String> {
        if !reviewFocusedClipIds.isEmpty {
            return reviewFocusedClipIds
        }
        if let selectedClipId = state.selectedClipId {
            return [selectedClipId]
        }
        return []
    }

    private func displayTracks(state: TimelineState, presentation: JITTimelinePresentation) -> [Track] {
        let tracks = state.editorDisplayTracks
        switch presentation {
        case .focusedClipStrip, .primaryTrackOnly:
            return tracks.filter { $0.kind == .video || $0.kind == .captions }
        case .full, .hidden:
            return tracks
        }
    }

    private func clipsByTrackId(state: TimelineState, presentation: JITTimelinePresentation) -> [String: [Clip]] {
        switch presentation {
        case .focusedClipStrip, .primaryTrackOnly:
            let focusIds = focusedClipIds(state: state)
            guard !focusIds.isEmpty else { return state.clipsByTrackId }
            var filtered: [String: [Clip]] = [:]
            for (trackId, clips) in state.clipsByTrackId {
                let kept = clips.filter { focusIds.contains($0.clipId) }
                if !kept.isEmpty {
                    filtered[trackId] = kept
                }
            }
            return filtered.isEmpty ? state.clipsByTrackId : filtered
        case .full, .hidden:
            return state.clipsByTrackId
        }
    }

}

private extension TimelineLayout {
    var componentSize: EditorComponentSize {
        self == .expanded ? .expanded : .compressed
    }
}

private extension EditorCanvasView {
    var previewComponentSize: EditorComponentSize {
        switch activeSpace {
        case .importMedia:
            return .compressed
        case .edit, .export:
            return .standard
        }
    }
}
