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
    let renderState: EditorJITRenderState
    let transitionPlans: [EditorJITTransitionPlan]
    var onAddSelection: ((TrackKind, ImportSource) -> Void)? = nil
    var bottomChromeContent: AnyView? = nil
    @State private var isTimelineAddMenuOpen = false
    @State private var jitSelectedSegmentId: String?
    @State private var activeParameterGroupId = EditorChromePreviewFixtures.colorGroup.id
    @State private var parameterValues: [String: EditorParameterValue] = EditorChromePreviewFixtures.seedValues(
        for: EditorChromePreviewFixtures.parameterGroups(for: .fourPlusGroups)
    )
    @State private var activeNavItemId = EditorSpace.edit.rawValue
    @State private var promptPhase: IntelligencePromptPhase = .idle
    @State private var promptDraft = ""
    @State private var clipColorFilter = ClipColorFilter.neutral
    @State private var clipVolume = ClipVolume.neutral
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
        renderState: EditorJITRenderState,
        transitionPlans: [EditorJITTransitionPlan] = [],
        showPlaybackAspectSettings: Binding<Bool> = .constant(false),
        onAddSelection: ((TrackKind, ImportSource) -> Void)? = nil,
        bottomChromeContent: AnyView? = nil,
        reviewFocusedClipIds: Set<String> = [],
        isReviewInteractionDisabled: Bool = false,
        promptActionPreview: TimelinePromptActionPreview? = nil
    ) {
        self.controller = controller
        self.playbackController = playbackController
        self.renderBridge = renderBridge
        self.activeSpace = activeSpace
        self.captionsFlow = captionsFlow
        self.renderState = renderState
        self.transitionPlans = transitionPlans
        self._showPlaybackAspectSettings = showPlaybackAspectSettings
        self.onAddSelection = onAddSelection
        self.bottomChromeContent = bottomChromeContent
        self.reviewFocusedClipIds = reviewFocusedClipIds
        self.isReviewInteractionDisabled = isReviewInteractionDisabled
        self.promptActionPreview = promptActionPreview
    }

    private var expandsVertically: Bool {
        activeSpace == .edit || activeSpace == .export
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

    var body: some View {
        let state = controller.state
        let playback = resolvedPlaybackController()

        jitCanvasBody(state: state, playback: playback)
        .frame(maxWidth: .infinity, maxHeight: expandsVertically ? .infinity : nil, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showPlaybackAspectSettings)
        .onChange(of: activeSpace) { _, newSpace in
            EditorDebugTrace.log(
                "EditorCanvasView",
                "canvas updated activeSpace=\(newSpace.rawValue)"
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
    private func jitCanvasBody(state: TimelineState, playback: PlaybackController) -> some View {
        let presentation = JITTimelinePresentation.full
        let layout = effectiveTimelineLayout(for: presentation)
        ZStack(alignment: .topLeading) {
            EditorJITRenderView(
                state: canvasJITRenderState(presentation: presentation),
                transitionPlans: transitionPlans,
                timelineContext: makeTimelineContext(state: state, presentation: presentation),
                timelineActions: makeTimelineActions(layout: layout, presentation: presentation),
                playbackContext: makePlaybackContext(playback: playback),
                playbackActions: makePlaybackActions(playback: playback),
                renderEngine: renderBridge.engine,
                dockContentOverride: bottomChromeContent,
                onChromeAction: handleJITChromeAction(_:),
                onChromeDismiss: {
                    controller.clearSelection()
                },
                currentTimeUs: controller.binding(\.currentTimeAtCenter),
                timelinePixelsPerSecond: controller.binding(\.pixelsPerSecond),
                selectedSegmentId: $jitSelectedSegmentId,
                isAddMenuOpen: $isTimelineAddMenuOpen,
                isPlaying: playbackPlayingBinding(playback: playback),
                showAspectSettings: $showPlaybackAspectSettings,
                activeParameterGroupId: $activeParameterGroupId,
                parameterValues: $parameterValues,
                activeNavItemId: $activeNavItemId,
                promptPhase: $promptPhase,
                promptDraft: $promptDraft,
                clipColorFilter: $clipColorFilter,
                clipVolume: $clipVolume
            )

            aspectSettingsOverlayIfNeeded
        }
    }

    private func canvasJITRenderState(presentation: JITTimelinePresentation) -> EditorJITRenderState {
        var state = renderState
        state.chromePlan = EditorBottomChromePlan(showsDock: bottomChromeContent != nil)
        return state
    }

    private func playbackPlayingBinding(playback: PlaybackController) -> Binding<Bool> {
        Binding(
            get: { playback.isPlaying() },
            set: { isPlaying in
                isPlaying ? playback.play() : playback.pause()
            }
        )
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
            promptActionPreview: promptActionPreview,
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

    private func handleJITChromeAction(_ action: EditorChromeActionItem) {
        guard let clipId = controller.state.selectedClipId else { return }
        switch action.id {
        case "delete":
            controller.applyActions([
                Action.removeClip(timelineId: controller.state.timelineId, clipId: clipId)
            ])
        case "split":
            controller.applyActions([
                Action.splitClip(
                    timelineId: controller.state.timelineId,
                    clipId: clipId,
                    atTimeUs: controller.state.currentTimeAtCenter
                )
            ])
        case "color":
            let current = controller.clipColorFilter(for: clipId)
            controller.setClipColorFilter(
                clipId: clipId,
                filter: current == .neutral ? ClipColorFilter(temperature: 0.25) : .neutral
            )
        case "volume":
            let current = controller.clipVolume(for: clipId)
            controller.setClipVolume(
                clipId: clipId,
                volume: current == .neutral ? ClipVolume(gain: 1.25) : .neutral
            )
        default:
            break
        }
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
