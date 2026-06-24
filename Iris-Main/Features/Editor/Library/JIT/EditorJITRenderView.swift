import SwiftUI

struct EditorJITRenderView: View {
    let state: EditorJITRenderState
    let transitionPlans: [EditorJITTransitionPlan]

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
        EditorComponentShowcaseSamples.makeTimelineOrganizerModel(
            size: state.timeline.size,
            currentTimeUs: currentTimeUs,
            pixelsPerSecond: timelinePixelsPerSecond
        )
    }

    private var showsClipTools: Bool {
        guard let selectedSegmentId else { return false }
        return EditorJITTimelineSelection.isClipSelection(
            selectedSegmentId,
            in: timelineOrganizerModel.tracks
        )
    }

    @ViewBuilder
    private var playbackRegion: some View {
        PlaybackSectionComponent(
            context: EditorComponentShowcaseSamples.makePlaybackContext(
                size: state.playback.size,
                isPlaying: isPlaying,
                showAspectSettings: $showAspectSettings
            ),
            actions: EditorPlaybackActions(
                onPlay: { isPlaying = true },
                onPause: { isPlaying = false },
                onJumpToStart: { currentTimeUs = 0 },
                onJumpToEnd: { currentTimeUs = 7_000_000 },
                onUndo: {},
                onRedo: {},
                onToggleAspectSettings: { showAspectSettings.toggle() }
            )
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
        TimelineOrganizerComponent(
            model: timelineOrganizerModel,
            pixelsPerSecond: $timelinePixelsPerSecond,
            selectedSegmentId: $selectedSegmentId,
            onSelectSegment: handleSegmentSelection,
            onAddSelection: { _, _ in isAddMenuOpen = false },
            isAddMenuOpen: $isAddMenuOpen
        )
        .padding(.horizontal, .spacing(.sp3))
    }

    private var trackOnlyTimeline: some View {
        let trackModel = EditorComponentShowcaseSamples.sampleTimelineTrackModels(
            size: TimelineTrackDisplaySize(state.timeline.size)
        ).first!

        return ScrollView(.horizontal, showsIndicators: false) {
            TimelineTrackComponent(
                model: trackModel,
                pixelsPerSecond: timelinePixelsPerSecond,
                selectedSegmentId: $selectedSegmentId,
                onSelectSegment: handleSegmentSelection
            )
        }
        .padding(.horizontal, .spacing(.sp3))
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

    private var dockContent: some View {
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

    private func handleSegmentSelection(_ segmentId: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedSegmentId = segmentId
        }
    }

    private func clearSelection() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedSegmentId = nil
        }
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
