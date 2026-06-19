import SwiftUI

struct EditorComponentShowcaseView: View {
    @State private var selectedCategory: EditorComponentCategory = .timeline
    @State private var selectedSize: EditorComponentSize = .standard
    @Namespace private var connectedOptionSelectionNamespace

    @State private var currentTimeUs: Int64 = 1_500_000
    @State private var timelinePixelsPerSecond: CGFloat = TimelineComponentLayout.defaultPixelsPerSecond
    @State private var selectedClipId: String?
    @State private var selectedCaptionCueId: String?
    @State private var isAddMenuOpen = false
    @State private var expandedClipToolId: Int?
    @State private var expandedShowcaseToolId: String?
    @State private var showcaseSplitCount = 0
    @State private var isPlaying = false
    @State private var showAspectSettings = false
    @State private var activeNavItemId = "Edit"
    @State private var intelligencePromptPhase: IntelligencePromptPhase = .idle
    @State private var intelligencePromptDraft = ""
    @State private var intelligenceLiveTranscript = ""
    @State private var intelligenceVoiceLevel: Float = 0
    @State private var intelligenceVoiceSimulationTask: Task<Void, Never>?
    @State private var temperatureValue = 0.0
    @State private var volumeValue = 1.0
    @State private var colorPropertyId = LibraryClipColorPropertyPreview.temperature.rawValue
    @State private var clipColorFilter = ClipColorFilter.neutral
    @State private var clipVolume = ClipVolume.neutral
    @State private var timelineTrackSizesById: [String: TimelineTrackDisplaySize] = [:]

    // Bottom chrome preview lab
    @State private var chromeShowsDock = true
    @State private var chromeShowsActions = true
    @State private var chromeShowsParameterGroups = true
    @State private var chromeShowsSpatialControls = false
    @State private var chromeCompressTimeline = false
    @State private var chromeShowsOverflowChips = true
    @State private var chromeGroupScenario: EditorChromePreviewGroupScenario = .fourPlusGroups
    @State private var chromeActiveGroup: EditorChromePreviewActiveGroup = .color
    @State private var chromeDensity: EditorBottomChromeDensity = .standard
    @State private var chromeActiveParameterGroupId = EditorChromePreviewActiveGroup.color.groupId
    @State private var chromeParameterValues: [String: EditorParameterValue] = EditorChromePreviewFixtures.seedValues(
        for: EditorChromePreviewFixtures.parameterGroups(for: .fourPlusGroups)
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            categoryPicker
            sizePicker

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: .spacing(.sp6)) {
                    categoryContent
                }
                .padding(.horizontal, .spacing(.sp4))
                .padding(.vertical, .spacing(.sp4))
            }
        }
        .background(Color.ds.bg.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack {
            Text("Editor Component Library")
                .typography(.heading)
                .foregroundColor(Color.ds.text)
            Spacer()
        }
        .padding(.horizontal, .spacing(.sp4))
        .padding(.top, .spacing(.sp4))
        .padding(.bottom, .spacing(.sp2))
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(EditorComponentCategory.allCases) { category in
                    showcaseChipButton(
                        category.displayTitle,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, .spacing(.sp4))
        }
        .padding(.bottom, .spacing(.sp2))
    }

    private var sizePicker: some View {
        Group {
            if selectedCategory != .chrome {
                HStack(spacing: 0) {
                    ForEach(EditorComponentSize.allCases) { size in
                        showcaseConnectedOptionButton(
                            size.displayTitle,
                            isSelected: selectedSize == size,
                            selectionPillID: "showcase-size-picker"
                        ) {
                            withAnimation(connectedOptionSelectionAnimation) {
                                selectedSize = size
                            }
                        }
                    }
                }
                .irisConnectedOptionGroupBackground()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, .spacing(.sp4))
                .padding(.bottom, .spacing(.sp3))
            }
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .timeline:
            timelineSection
        case .tools:
            toolsSection
        case .playback:
            playbackSection
        case .navigation:
            navigationSection
        case .chrome:
            chromeSection
        case .panels:
            panelsSection
        }
    }

    private var timelineSection: some View {
        let organizerModel = EditorComponentShowcaseSamples.makeTimelineOrganizerModel(
            size: selectedSize,
            currentTimeUs: currentTimeUs,
            pixelsPerSecond: timelinePixelsPerSecond,
            trackSizesById: timelineTrackSizesById
        )
        let trackModels = EditorComponentShowcaseSamples.sampleTimelineTrackModels(
            size: TimelineTrackDisplaySize(selectedSize)
        )

        return VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            showcaseSectionTitle("Timeline Organizer")
            Text("Pinch the organizer to inspect shared horizontal scale across the ruler and every track.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            timelineTrackSizeControls(trackModels: organizerModel.tracks)
            TimelineOrganizerComponent(
                model: organizerModel,
                pixelsPerSecond: $timelinePixelsPerSecond,
                onAddSelection: { _, _ in isAddMenuOpen = false },
                isAddMenuOpen: $isAddMenuOpen
            )

            showcaseSectionTitle("Timeline Components")
            timelineComponentPreview("Ruler + Readout") {
                let layout = TimelineComponentLayout.preset(selectedSize)
                let contentWidth = max(1, CGFloat(organizerModel.durationUs) / 1_000_000 * timelinePixelsPerSecond)
                let rulerModel = TimelineRulerModel(
                    currentTimeUs: currentTimeUs,
                    durationUs: organizerModel.durationUs,
                    pixelsPerSecond: timelinePixelsPerSecond
                )

                GeometryReader { geometry in
                    let playheadCenterX = geometry.size.width / 2
                    let scrollContentWidth = max(geometry.size.width, contentWidth + playheadCenterX * 2)

                    ZStack(alignment: .topLeading) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            TimelineRulerTicksComponent(model: rulerModel, layout: layout)
                                .frame(width: contentWidth, height: layout.rulerHeight, alignment: .topLeading)
                                .padding(.leading, playheadCenterX)
                                .frame(width: scrollContentWidth, alignment: .leading)
                        }
                        .background(Color.ds.bg)

                        TimelineFixedRulerReadoutComponent(model: rulerModel, layout: layout)
                            .frame(width: layout.readoutWidth + layout.rulerFadeWidth, height: layout.rulerHeight, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                    .frame(height: layout.rulerHeight)
                }
                .frame(height: layout.rulerHeight)
            }

            ForEach(trackModels) { trackModel in
                timelineComponentPreview("\(trackModel.kind.displayTitle) Track") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        TimelineTrackComponent(
                            model: trackModel,
                            pixelsPerSecond: timelinePixelsPerSecond
                        )
                    }
                }
            }

            timelineComponentPreview("Add Button") {
                TimelineAddMediaButtonComponent(
                    size: selectedSize,
                    onSelect: { _, _ in isAddMenuOpen = false },
                    isMenuOpen: $isAddMenuOpen
                )
            }
        }
    }

    private func timelineTrackSizeControls(trackModels: [TimelineTrackModel]) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Track sizes")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(trackModels) { track in
                    HStack(spacing: .spacing(.sp2)) {
                        Text(track.kind.displayTitle)
                            .typography(.bodySmall)
                            .foregroundColor(Color.ds.text)
                            .frame(width: 72, alignment: .leading)

                        HStack(spacing: 0) {
                            ForEach(TimelineTrackDisplaySize.allCases) { size in
                                let isSelected = resolvedTrackSize(for: track.id) == size
                                showcaseConnectedOptionButton(
                                    size.displayTitle,
                                    isSelected: isSelected,
                                    selectionPillID: "track-size-\(track.id)"
                                ) {
                                    withAnimation(connectedOptionSelectionAnimation) {
                                        timelineTrackSizesById[track.id] = size
                                    }
                                }
                            }
                        }
                        .irisConnectedOptionGroupBackground()
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func resolvedTrackSize(for trackId: String) -> TimelineTrackDisplaySize {
        timelineTrackSizesById[trackId] ?? TimelineTrackDisplaySize(selectedSize)
    }

    private func timelineComponentPreview<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(title)
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            content()
                .padding(.spacing(.sp3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ds.surface.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            toolActionsSection
            expandableToolButtonSection
            parameterControlsSection
        }
    }

    private var toolActionsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            showcaseSectionTitle("Tool Actions")
            Text("Buttons that directly change timeline state without opening a subview.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            ToolControlRowComponent {
                ToolButtonComponent(
                    systemImage: "trash",
                    title: "Delete",
                    role: .destructive,
                    action: {}
                )
                ToolButtonComponent(
                    systemImage: "scissors",
                    title: "Split",
                    action: { showcaseSplitCount += 1 }
                )
                ToolButtonComponent(
                    systemImage: "textformat",
                    title: "Style",
                    action: {}
                )
            }
            if showcaseSplitCount > 0 {
                Text("Split tapped \(showcaseSplitCount) time\(showcaseSplitCount == 1 ? "" : "s")")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }
        }
    }

    private var expandableToolButtonSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            showcaseSectionTitle("Expandable Tool Button")
            Text("A tool button opens a subview with parameter controls; the close button dismisses selection.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            ExpandableToolTrayComponent(
                expandedToolId: $expandedShowcaseToolId,
                showsLeadingWhenExpanded: false,
                leading: {
                    ToolCloseButtonComponent(title: "Dismiss tool selection") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            expandedShowcaseToolId = nil
                        }
                    }
                },
                collapsed: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: .spacing(.sp1)) {
                            ToolButtonComponent(
                                systemImage: "camera.filters",
                                title: "Color",
                                action: { toggleShowcaseTool(LibraryShowcaseExpandableToolID.color) }
                            )
                            ToolButtonComponent(
                                systemImage: "speaker.wave.2",
                                title: "Volume",
                                action: { toggleShowcaseTool(LibraryShowcaseExpandableToolID.volume) }
                            )
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                },
                expanded: { toolId in
                    showcaseExpandedToolContent(for: toolId)
                }
            )
        }
    }

    @ViewBuilder
    private func showcaseExpandedToolContent(for toolId: String) -> some View {
        if toolId == LibraryShowcaseExpandableToolID.color.rawValue {
            VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                HStack(alignment: .top, spacing: .spacing(.sp2)) {
                    ToolBackButtonComponent(accessibilityLabel: "Back to tool buttons") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            expandedShowcaseToolId = nil
                        }
                    }

                    ParameterSegmentedPillControlComponent(
                        title: nil,
                        options: LibraryClipColorPropertyPreview.allCases.map {
                            ParameterSegmentedPillOption(id: $0.rawValue, title: $0.title)
                        },
                        selectionId: $colorPropertyId
                    )
                }

                ParameterSliderControlComponent(
                    title: "Temperature",
                    value: $temperatureValue,
                    bounds: EditorParameterBounds(lower: -1, upper: 1),
                    display: .inlineValue,
                    valueFormatter: { String(format: "%.2f", $0) }
                )
                .frame(minWidth: 220)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if toolId == LibraryShowcaseExpandableToolID.volume.rawValue {
            HStack(alignment: .top, spacing: .spacing(.sp2)) {
                ToolBackButtonComponent(accessibilityLabel: "Back to tool buttons") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        expandedShowcaseToolId = nil
                    }
                }

                ParameterSliderControlComponent(
                    title: "Volume",
                    value: $volumeValue,
                    bounds: EditorParameterBounds(lower: 0, upper: 2),
                    display: .inlineValue,
                    valueFormatter: { "\(Int(($0 * 100).rounded()))%" }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var parameterControlsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            showcaseSectionTitle("Parameter Controls")
            Text("Standalone controls used inside expanded tool subviews.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            ToolControlRowComponent(axis: .vertical) {
                ParameterSliderControlComponent(
                    title: "Temperature",
                    value: $temperatureValue,
                    bounds: EditorParameterBounds(lower: -1, upper: 1),
                    display: .inlineValue,
                    valueFormatter: { String(format: "%.2f", $0) }
                )
                ParameterSliderControlComponent(
                    title: "Volume",
                    value: $volumeValue,
                    bounds: EditorParameterBounds(lower: 0, upper: 2),
                    display: .inlineValue,
                    valueFormatter: { "\(Int(($0 * 100).rounded()))%" }
                )
                ParameterSegmentedPillControlComponent(
                    title: "Color Property",
                    options: LibraryClipColorPropertyPreview.allCases.map {
                        ParameterSegmentedPillOption(id: $0.rawValue, title: $0.title)
                    },
                    selectionId: $colorPropertyId
                )
            }
        }
    }

    private func toggleShowcaseTool(_ tool: LibraryShowcaseExpandableToolID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            let current = expandedShowcaseToolId
            expandedShowcaseToolId = current == tool.rawValue ? nil : tool.rawValue
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            showcaseSectionTitle("Playback Section")
            PlaybackSectionComponent(
                context: EditorComponentShowcaseSamples.makePlaybackContext(
                    size: selectedSize,
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
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            showcaseSectionTitle("NavigationComponent")
            NavigationComponent(
                style: .glass,
                items: NavigationComponent.defaultShowcaseItems,
                activeItemId: $activeNavItemId
            )

            showcaseSectionTitle("IntelligenceComponent")
            Text("Tap opens a keyboard overlay. Hold simulates voice capture. Use the phase picker to inspect takeover states.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            intelligencePhasePicker

            HStack {
                Spacer(minLength: 0)
                IntelligenceComponent(
                    navigationItems: IntelligenceComponent.defaultShowcaseItems,
                    activeNavigationItemId: $activeNavItemId,
                    promptPhase: $intelligencePromptPhase,
                    promptDraft: $intelligencePromptDraft,
                    liveTranscript: intelligenceLiveTranscript,
                    voiceLevel: intelligenceVoiceLevel,
                    onIntelligenceTap: handleIntelligenceTap,
                    onVoiceHoldStart: handleIntelligenceVoiceHoldStart,
                    onVoiceHoldEnd: handleIntelligenceVoiceHoldEnd,
                    onSubmitText: handleIntelligenceSubmitText,
                    onCancelText: handleIntelligenceCancelText,
                    onCancelProcessing: handleIntelligenceCancelProcessing
                )
                Spacer(minLength: 0)
            }
        }
    }

    private var intelligencePhasePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(LibraryIntelligencePhasePreview.allCases) { preview in
                    showcaseChipButton(
                        preview.title,
                        isSelected: intelligencePromptPhase == preview.phase
                    ) {
                        applyIntelligencePhasePreview(preview)
                    }
                }
            }
        }
    }

    private var chromeSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            showcaseSectionTitle("Bottom Chrome Preview Lab")
            Text("Toggle tiers, parameter group scenarios, dock phases, and density to inspect how the bottom chrome behaves before live editor wiring.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            EditorChromePreviewLab(
                showsDock: $chromeShowsDock,
                showsActions: $chromeShowsActions,
                showsParameterGroups: $chromeShowsParameterGroups,
                showsSpatialControls: $chromeShowsSpatialControls,
                compressTimeline: $chromeCompressTimeline,
                showsOverflowChips: $chromeShowsOverflowChips,
                groupScenario: $chromeGroupScenario,
                activeGroup: $chromeActiveGroup,
                density: $chromeDensity,
                promptPhase: $intelligencePromptPhase,
                activeNavItemId: $activeNavItemId,
                promptDraft: $intelligencePromptDraft,
                parameterValues: $chromeParameterValues,
                activeParameterGroupId: $chromeActiveParameterGroupId,
                liveTranscript: intelligenceLiveTranscript,
                voiceLevel: intelligenceVoiceLevel,
                onIntelligenceTap: handleIntelligenceTap,
                onVoiceHoldStart: handleIntelligenceVoiceHoldStart,
                onVoiceHoldEnd: handleIntelligenceVoiceHoldEnd,
                onSubmitText: handleIntelligenceSubmitText,
                onCancelText: handleIntelligenceCancelText,
                onCancelProcessing: handleIntelligenceCancelProcessing
            )
        }
    }

    private var panelsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            showcaseSectionTitle("Panels")
            Text("Panel components are deferred until import/export library primitives are added.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
        }
    }

    private func showcaseSectionTitle(_ title: String) -> some View {
        Text(title)
            .typography(.body)
            .foregroundColor(Color.ds.text)
    }

    private var connectedOptionSelectionAnimation: Animation {
        .spring(response: 0.30, dampingFraction: 0.78, blendDuration: 0.04)
    }

    private func showcaseChipButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.irisChipPicker(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func showcaseConnectedOptionButton(
        _ title: String,
        isSelected: Bool,
        selectionPillID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(
            .irisConnectedOption(
                isSelected: isSelected,
                selectionPillID: selectionPillID,
                in: connectedOptionSelectionNamespace
            )
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func handleIntelligenceTap() {
        intelligenceVoiceSimulationTask?.cancel()
        intelligenceVoiceLevel = 0
        intelligenceLiveTranscript = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            intelligencePromptPhase = .typing
        }
    }

    private func handleIntelligenceVoiceHoldStart() {
        intelligenceVoiceSimulationTask?.cancel()
        intelligenceLiveTranscript = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            intelligencePromptPhase = .recording
        }
        intelligenceVoiceSimulationTask = Task { @MainActor in
            var tick = 0
            while !Task.isCancelled, intelligencePromptPhase == .recording {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, intelligencePromptPhase == .recording else { return }
                tick += 1
                intelligenceVoiceLevel = Float((sin(Double(tick) * 0.35) + 1) * 0.45)
                if tick == 6 {
                    intelligenceLiveTranscript = "Trim the intro"
                } else if tick == 12 {
                    intelligenceLiveTranscript = "Trim the intro and add captions"
                }
            }
        }
    }

    private func handleIntelligenceVoiceHoldEnd() {
        intelligenceVoiceSimulationTask?.cancel()
        intelligenceVoiceSimulationTask = nil
        let transcript = intelligenceLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                intelligencePromptPhase = .error("I did not catch any speech.")
            }
            scheduleIntelligenceReset(after: 2)
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            intelligencePromptPhase = .submitting("Starting backend intent run.")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard intelligencePromptPhase.isSubmitting else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                intelligencePromptPhase = .idle
            }
            intelligenceVoiceLevel = 0
            intelligenceLiveTranscript = ""
        }
    }

    private func handleIntelligenceSubmitText() {
        let draft = intelligencePromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        intelligencePromptDraft = ""
        guard !draft.isEmpty else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                intelligencePromptPhase = .error("Enter a prompt to compile.")
            }
            scheduleIntelligenceReset(after: 2)
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            intelligencePromptPhase = .submitting("Compiling \"\(draft)\"")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard intelligencePromptPhase.isSubmitting else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                intelligencePromptPhase = .idle
            }
        }
    }

    private func handleIntelligenceCancelText() {
        intelligenceVoiceSimulationTask?.cancel()
        intelligencePromptDraft = ""
        intelligenceVoiceLevel = 0
        intelligenceLiveTranscript = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            intelligencePromptPhase = .idle
        }
    }

    private func handleIntelligenceCancelProcessing() {
        intelligenceVoiceSimulationTask?.cancel()
        intelligenceVoiceLevel = 0
        intelligenceLiveTranscript = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            intelligencePromptPhase = .idle
        }
    }

    private func applyIntelligencePhasePreview(_ preview: LibraryIntelligencePhasePreview) {
        intelligenceVoiceSimulationTask?.cancel()
        intelligencePromptDraft = preview.sampleDraft
        intelligenceLiveTranscript = preview.sampleTranscript
        intelligenceVoiceLevel = preview.sampleVoiceLevel
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            intelligencePromptPhase = preview.phase
        }
        if preview.autoResetsToIdle {
            scheduleIntelligenceReset(after: 2)
        }
    }

    private func scheduleIntelligenceReset(after seconds: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard case .error = intelligencePromptPhase else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                intelligencePromptPhase = .idle
            }
            intelligenceVoiceLevel = 0
            intelligenceLiveTranscript = ""
        }
    }
}

private enum LibraryIntelligencePhasePreview: String, CaseIterable, Identifiable {
    case idle
    case typing
    case recording
    case submitting
    case clarification
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "Idle"
        case .typing: "Typing"
        case .recording: "Recording"
        case .submitting: "Submitting"
        case .clarification: "Clarify"
        case .error: "Error"
        }
    }

    var phase: IntelligencePromptPhase {
        switch self {
        case .idle: .idle
        case .typing: .typing
        case .recording: .recording
        case .submitting: .submitting("Starting backend intent run.")
        case .clarification: .clarification("Which clip should I trim — the intro montage or the interview segment on track two?")
        case .error: .error("Could not reach the intent compiler. Check your connection and try again.")
        }
    }

    var sampleDraft: String {
        self == .typing ? "Make the colors warmer" : ""
    }

    var sampleTranscript: String {
        self == .recording
            ? "Trim the intro and add captions to the interview segment on track two"
            : ""
    }

    var sampleVoiceLevel: Float {
        self == .recording ? 0.62 : 0
    }

    var autoResetsToIdle: Bool {
        self == .error
    }
}

private extension IntelligencePromptPhase {
    var isSubmitting: Bool {
        if case .submitting = self { return true }
        return false
    }
}

private enum LibraryShowcaseExpandableToolID: String {
    case color, volume
}

private extension TimelineTrackDisplaySize {
    var displayTitle: String {
        switch self {
        case .compressed: "Compressed"
        case .standard: "Standard"
        case .expanded: "Expanded"
        }
    }
}

private enum LibraryClipColorPropertyPreview: String, CaseIterable {
    case temperature, saturation, exposure

    var title: String {
        switch self {
        case .temperature: "Temperature"
        case .saturation: "Saturation"
        case .exposure: "Exposure"
        }
    }
}
