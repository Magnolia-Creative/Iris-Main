import SwiftUI

struct EditorJITRenderView: View {
    let state: EditorJITRenderState
    let transitionPlans: [EditorJITTransitionPlan]
    var timelineContext: EditorTimelineContext?
    var timelineActions: EditorTimelineActions = .noop
    var playbackContext: EditorPlaybackContext?
    var playbackActions: EditorPlaybackActions = .noop
    var renderEngine: VideoLabRenderEngine?
    var dockContentOverride: AnyView?

    @Binding var currentTimeUs: Int64
    @Binding var timelinePixelsPerSecond: CGFloat
    @Binding var selectedSegmentId: String?
    @Binding var isAddMenuOpen: Bool
    @Binding var isPlaying: Bool
    @Binding var showAspectSettings: Bool
    @Binding var activeParameterGroupId: String
    @Binding var parameterValues: [String: EditorParameterValue]
    @Binding var activeNavItemId: String
    @Binding var promptPhase: IntelligencePromptPhase
    @Binding var promptDraft: String
    @Binding var clipColorFilter: ClipColorFilter
    @Binding var clipVolume: ClipVolume

    var body: some View {
        VStack(spacing: 0) {
            if state.playback.isVisible {
                playbackRegion
                    .transition(transition(for: state.playback.componentId))
            }

            if state.timeline.isVisible {
                timelineRegion
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(transition(for: state.timeline.componentId))
            } else {
                Spacer(minLength: 0)
            }

            if !state.chromePlan.visibleTiers.isEmpty || showsClipTools {
                chromeRegion
                    .transition(transition(for: "chrome.bottomStack"))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.id)
        .background(Color.ds.bg)
    }

    private var timelineOrganizerModel: TimelineOrganizerModel {
        TimelineOrganizerModel(context: effectiveTimelineContext)
    }

    private var effectiveTimelineContext: EditorTimelineContext {
        if let timelineContext {
            return contextWithLayoutSize(timelineContext, size: state.timeline.size)
        }

        return EditorComponentShowcaseSamples.makeTimelineContext(
            size: state.timeline.size,
            currentTime: $currentTimeUs,
            selectedClipId: selectedSegmentBinding,
            selectedCaptionCueId: selectedSegmentBinding,
            isAddMenuOpen: $isAddMenuOpen
        )
    }

    private func contextWithLayoutSize(
        _ context: EditorTimelineContext,
        size: EditorComponentSize
    ) -> EditorTimelineContext {
        EditorTimelineContext(
            tracks: context.tracks,
            clipsByTrackId: context.clipsByTrackId,
            mediaById: context.mediaById,
            captionGroups: context.captionGroups,
            captionCues: context.captionCues,
            layoutSize: size,
            pixelsPerSecond: context.pixelsPerSecond,
            timelineDurationUs: context.timelineDurationUs,
            scrollableDurationUs: context.scrollableDurationUs,
            playbackState: context.playbackState,
            reviewFocusedClipIds: context.reviewFocusedClipIds,
            isReviewInteractionDisabled: context.isReviewInteractionDisabled,
            captionHighlightRangeUs: context.captionHighlightRangeUs,
            playheadTint: context.playheadTint,
            showAddButton: context.showAddButton,
            currentTimeAtCenter: context.$currentTimeAtCenter,
            scrollTargetTimeUs: context.$scrollTargetTimeUs,
            selectedClipId: context.$selectedClipId,
            selectedCaptionCueId: context.$selectedCaptionCueId,
            isAddMenuOpen: context.$isAddMenuOpen
        )
    }

    private var effectiveTimelineActions: EditorTimelineActions {
        guard timelineContext == nil else { return timelineActions }
        var actions = EditorTimelineActions.noop
        actions.onAddSelection = { _, _ in isAddMenuOpen = false }
        return actions
    }

    private var effectivePlaybackContext: EditorPlaybackContext {
        if var playbackContext {
            playbackContext.viewerSize = state.playback.size
            return playbackContext
        }

        return EditorComponentShowcaseSamples.makePlaybackContext(
            size: state.playback.size,
            isPlaying: isPlaying,
            showAspectSettings: $showAspectSettings
        )
    }

    private var effectivePlaybackActions: EditorPlaybackActions {
        guard playbackContext == nil else { return playbackActions }
        return EditorPlaybackActions(
            onPlay: { isPlaying = true },
            onPause: { isPlaying = false },
            onJumpToStart: { currentTimeUs = 0 },
            onJumpToEnd: { currentTimeUs = 7_000_000 },
            onUndo: {},
            onRedo: {},
            onToggleAspectSettings: { showAspectSettings.toggle() }
        )
    }

    private var selectedSegmentBinding: Binding<String?> {
        Binding(
            get: { selectedSegmentId },
            set: { selectedSegmentId = $0 }
        )
    }

    private var activeSelectedSegmentId: String? {
        if let timelineContext {
            return timelineContext.selectedClipId ?? timelineContext.selectedCaptionCueId
        }
        return selectedSegmentId
    }

    private var showsClipTools: Bool {
        guard let selectedSegmentId = activeSelectedSegmentId else { return false }
        return EditorJITTimelineSelection.isClipSelection(
            selectedSegmentId,
            in: timelineOrganizerModel.tracks
        )
    }

    @ViewBuilder
    private var playbackRegion: some View {
        PlaybackSectionComponent(
            context: effectivePlaybackContext,
            actions: effectivePlaybackActions,
            renderEngine: renderEngine
        )
        .padding(.top, .spacing(.sp2))
    }

    @ViewBuilder
    private var timelineRegion: some View {
        switch state.timeline.componentId.rawValue {
        case "timeline.track":
            trackOnlyTimeline
        default:
            fullTimeline
        }
    }

    private var fullTimeline: some View {
        TimelineSurfaceComponent(
            context: effectiveTimelineContext,
            actions: effectiveTimelineActions
        )
        .padding(.horizontal, .spacing(.sp3))
    }

    @ViewBuilder
    private var trackOnlyTimeline: some View {
        if let trackModel = timelineOrganizerModel.tracks.first {
            ScrollView(.horizontal, showsIndicators: false) {
                TimelineTrackComponent(
                    model: trackModel,
                    pixelsPerSecond: timelineOrganizerModel.pixelsPerSecond,
                    selectedSegmentId: selectedSegmentBinding,
                    onSelectSegment: handleSegmentSelection
                )
            }
            .padding(.horizontal, .spacing(.sp3))
        } else {
            Color.clear
        }
    }

    private var chromeRegion: some View {
        EditorBottomChromeStack(
            plan: effectiveChromePlan,
            activeParameterGroupId: $activeParameterGroupId,
            parameterValues: $parameterValues,
            onAction: handleChromeAction,
            onDismiss: { clearSelection() },
            dock: { dockContent }
        )
        .padding(.horizontal, .spacing(.sp3))
        .padding(.bottom, .spacing(.sp2))
    }

    private var effectiveChromePlan: EditorBottomChromePlan {
        guard showsClipTools else { return state.chromePlan }
        var plan = state.chromePlan
        plan.actions = clipSelectionActions
        plan.isDismissable = true
        return plan
    }

    private var clipSelectionActions: [EditorChromeActionItem] {
        [
            EditorChromeActionItem(
                id: "delete",
                title: "Delete",
                systemImage: "trash",
                role: .destructive
            ),
            EditorChromeActionItem(
                id: "split",
                title: "Split",
                systemImage: "scissors"
            ),
            EditorChromeActionItem(
                id: "color",
                title: "Color",
                systemImage: "circle.lefthalf.filled"
            ),
            EditorChromeActionItem(
                id: "volume",
                title: "Volume",
                systemImage: "speaker.wave.2"
            )
        ]
    }

    @ViewBuilder
    private var dockContent: some View {
        if let dockContentOverride {
            dockContentOverride
        } else {
            IntelligenceComponent(
                navigationItems: IntelligenceComponent.defaultShowcaseItems,
                activeNavigationItemId: $activeNavItemId,
                promptPhase: $promptPhase,
                promptDraft: $promptDraft,
                liveTranscript: "",
                voiceLevel: 0,
                onIntelligenceTap: {},
                onVoiceHoldStart: {},
                onVoiceHoldEnd: {},
                onSubmitText: {},
                onCancelText: {},
                onCancelProcessing: {}
            )
            .frame(width: IntelligenceComponent.containerWidth())
        }
    }

    private func handleSegmentSelection(_ segmentId: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedSegmentId = segmentId
            applyLiveSelection(segmentId)
        }
    }

    private func clearSelection() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedSegmentId = nil
            clearLiveSelection()
        }
    }

    private func applyLiveSelection(_ segmentId: String) {
        guard var context = timelineContext else { return }
        context.selectedClipId = nil
        context.selectedCaptionCueId = nil
        switch EditorJITTimelineSelection.trackKind(for: segmentId, in: timelineOrganizerModel.tracks) {
        case .caption:
            context.selectedCaptionCueId = segmentId
        case .video, .audio:
            context.selectedClipId = segmentId
        case nil:
            break
        }
    }

    private func clearLiveSelection() {
        guard var context = timelineContext else { return }
        context.selectedClipId = nil
        context.selectedCaptionCueId = nil
    }

    private func handleChromeAction(_ action: EditorChromeActionItem) {
        switch action.id {
        case "delete":
            clearSelection()
        case "color":
            clipColorFilter = clipColorFilter == .neutral ? ClipColorFilter(temperature: 0.25) : .neutral
        case "volume":
            clipVolume = clipVolume == .neutral ? ClipVolume(gain: 1.25) : .neutral
        default:
            break
        }
    }

    private func transition(for componentId: EditorComponentID) -> AnyTransition {
        transition(for: componentId.rawValue)
    }

    private func transition(for componentKey: String) -> AnyTransition {
        guard let plan = transitionPlans.first(where: { $0.componentId.rawValue == componentKey }) else {
            return .opacity
        }
        switch plan.style {
        case .persist, .resize:
            return .opacity
        case .replace:
            return .opacity.combined(with: .scale(scale: 0.98))
        case .enter:
            return .opacity.combined(with: .move(edge: .bottom))
        case .exit:
            return .opacity
        }
    }
}
