import SwiftUI
internal import Combine

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

    private var contextFactory: EditorJITContextFactory {
        EditorJITContextFactory(
            activeSpace: activeSpace,
            reviewFocusedClipIds: reviewFocusedClipIds,
            isReviewInteractionDisabled: isReviewInteractionDisabled,
            promptActionPreview: promptActionPreview,
            onAddSelection: onAddSelection
        )
    }

    @ViewBuilder
    private func jitCanvasBody(state: TimelineState, playback: PlaybackController) -> some View {
        let presentation = JITTimelinePresentation.full
        let factory = contextFactory
        let layout = factory.timelineLayout(for: presentation)
        ZStack(alignment: .topLeading) {
            EditorJITRenderView(
                state: canvasJITRenderState(presentation: presentation),
                transitionPlans: transitionPlans,
                timelineContext: factory.timelineContext(
                    state: state,
                    controller: controller,
                    captionsFlow: captionsFlow,
                    isAddMenuOpen: $isTimelineAddMenuOpen,
                    selectedCaptionCueId: $captionsFlow.selectedCaptionCueId,
                    presentation: presentation
                ),
                timelineActions: factory.timelineActions(
                    controller: controller,
                    captionsFlow: captionsFlow,
                    renderBridge: renderBridge,
                    layout: layout,
                    presentation: presentation
                ),
                playbackContext: factory.playbackContext(
                    controller: controller,
                    playback: playback,
                    showAspectSettings: $showPlaybackAspectSettings
                ),
                playbackActions: factory.playbackActions(
                    controller: controller,
                    playback: playback,
                    showAspectSettings: $showPlaybackAspectSettings
                ),
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

}
