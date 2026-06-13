import SwiftUI

struct EditorComponentShowcaseView: View {
    @State private var selectedCategory: EditorComponentCategory = .timeline
    @State private var selectedSize: EditorComponentSize = .standard

    @State private var currentTimeUs: Int64 = 1_500_000
    @State private var selectedClipId: String?
    @State private var selectedCaptionCueId: String?
    @State private var isAddMenuOpen = false
    @State private var expandedClipToolId: Int?
    @State private var expandedShowcaseToolId: String?
    @State private var showcaseSplitCount = 0
    @State private var isPlaying = false
    @State private var showAspectSettings = false
    @State private var activeNavItemId = EditorSpace.edit.rawValue
    @State private var temperatureValue = 0.0
    @State private var volumeValue = 1.0
    @State private var colorPropertyId = LibraryClipColorPropertyPreview.temperature.rawValue
    @State private var toolbarShowsClipTools = true
    @State private var toolbarShowsParameters = true
    @State private var clipColorFilter = ClipColorFilter.neutral
    @State private var clipVolume = ClipVolume.neutral

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
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.displayTitle)
                            .typography(.bodySmall)
                            .foregroundColor(selectedCategory == category ? Color.ds.accentFg : Color.ds.textMuted)
                            .padding(.horizontal, .spacing(.sp3))
                            .padding(.vertical, .spacing(.sp2))
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.ds.accentBg.opacity(0.35) : Color.ds.surface.opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, .spacing(.sp4))
        }
        .padding(.bottom, .spacing(.sp2))
    }

    private var sizePicker: some View {
        Picker("Size", selection: $selectedSize) {
            ForEach(EditorComponentSize.allCases) { size in
                Text(size.displayTitle).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, .spacing(.sp4))
        .padding(.bottom, .spacing(.sp3))
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
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            showcaseSectionTitle("Timeline Surface")
            TimelineSurfaceComponent(
                context: EditorComponentShowcaseSamples.makeTimelineContext(
                    size: selectedSize,
                    currentTime: $currentTimeUs,
                    selectedClipId: $selectedClipId,
                    selectedCaptionCueId: $selectedCaptionCueId,
                    isAddMenuOpen: $isAddMenuOpen
                ),
                actions: EditorTimelineActions(
                    onAddSelection: { _, _ in isAddMenuOpen = false },
                    onMoveClip: { _, _, _ in },
                    onTrimClip: { _, _, _, _ in }
                )
            )

            showcaseSectionTitle("Timeline Primitives")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacing(.sp4)) {
                    VStack(alignment: .leading) {
                        Text("Ruler").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                        TimelineRulerComponent(
                            size: selectedSize,
                            pixelsPerSecond: 100,
                            durationUs: 8_000_000,
                            currentTime: $currentTimeUs
                        )
                        .frame(width: 280)
                    }
                    VStack(alignment: .leading) {
                        Text("Time Readout").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                        TimelineTimeReadoutComponent(
                            size: selectedSize,
                            currentTimeUs: currentTimeUs,
                            timelineDurationUs: 7_000_000
                        )
                    }
                    VStack(alignment: .leading) {
                        Text("Add Button").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                        TimelineAddMediaButtonComponent(
                            size: selectedSize,
                            onSelect: { _, _ in },
                            isMenuOpen: $isAddMenuOpen
                        )
                    }
                }
            }
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
            EditorToolControlRowComponent {
                EditorToolButtonComponent(
                    systemImage: "trash",
                    title: "Delete",
                    role: .destructive,
                    action: {}
                )
                EditorToolButtonComponent(
                    systemImage: "scissors",
                    title: "Split",
                    action: { showcaseSplitCount += 1 }
                )
                EditorToolButtonComponent(
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
            EditorExpandableToolTrayComponent(
                expandedToolId: $expandedShowcaseToolId,
                showsLeadingWhenExpanded: expandedShowcaseToolId != LibraryShowcaseExpandableToolID.volume.rawValue,
                leading: {
                    EditorToolCloseButtonComponent(title: "Dismiss tool selection") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            expandedShowcaseToolId = nil
                        }
                    }
                },
                collapsed: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: .spacing(.sp1)) {
                            EditorToolButtonComponent(
                                systemImage: "camera.filters",
                                title: "Color",
                                action: { toggleShowcaseTool(LibraryShowcaseExpandableToolID.color) }
                            )
                            EditorToolButtonComponent(
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
        HStack(alignment: .top, spacing: .spacing(.sp2)) {
            EditorToolBackButtonComponent(accessibilityLabel: "Back to tool buttons") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expandedShowcaseToolId = nil
                }
            }

            if toolId == LibraryShowcaseExpandableToolID.color.rawValue {
                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    EditorSegmentedPillControlComponent(
                        title: nil,
                        options: LibraryClipColorPropertyPreview.allCases.map {
                            EditorSegmentedPillOption(id: $0.rawValue, title: $0.title)
                        },
                        selectionId: $colorPropertyId
                    )
                    EditorSliderControlComponent(
                        title: "Temperature",
                        value: $temperatureValue,
                        bounds: EditorParameterBounds(lower: -1, upper: 1),
                        display: .inlineValue,
                        valueFormatter: { String(format: "%.2f", $0) }
                    )
                    .frame(minWidth: 220)
                }
            } else if toolId == LibraryShowcaseExpandableToolID.volume.rawValue {
                EditorSliderControlComponent(
                    title: "Volume",
                    value: $volumeValue,
                    bounds: EditorParameterBounds(lower: 0, upper: 2),
                    display: .inlineValue,
                    valueFormatter: { "\(Int(($0 * 100).rounded()))%" }
                )
            }
        }
    }

    private var parameterControlsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            showcaseSectionTitle("Parameter Controls")
            Text("Standalone controls used inside expanded tool subviews.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            EditorToolControlRowComponent(axis: .vertical) {
                EditorSliderControlComponent(
                    title: "Temperature",
                    value: $temperatureValue,
                    bounds: EditorParameterBounds(lower: -1, upper: 1),
                    display: .inlineValue,
                    valueFormatter: { String(format: "%.2f", $0) }
                )
                EditorSliderControlComponent(
                    title: "Volume",
                    value: $volumeValue,
                    bounds: EditorParameterBounds(lower: 0, upper: 2),
                    display: .inlineValue,
                    valueFormatter: { "\(Int(($0 * 100).rounded()))%" }
                )
                EditorSegmentedPillControlComponent(
                    title: "Color Property",
                    options: LibraryClipColorPropertyPreview.allCases.map {
                        EditorSegmentedPillOption(id: $0.rawValue, title: $0.title)
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
            showcaseSectionTitle("Bottom Navigation")
            EditorBottomNavigationComponent(
                size: selectedSize,
                style: .glass,
                items: EditorBottomNavigationComponent.defaultEditorItems,
                activeItemId: $activeNavItemId
            )
        }
    }

    private var chromeSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            showcaseSectionTitle("Toolbar Collection")
            Toggle(isOn: $toolbarShowsClipTools) {
                Text("Show clip tools")
                    .typography(.bodySmall)
            }
            Toggle(isOn: $toolbarShowsParameters) {
                Text("Show parameter cards")
                    .typography(.bodySmall)
            }

            let toolContext = EditorToolContext(
                isClipSelected: true,
                selectedClipColorFilter: clipColorFilter,
                selectedClipVolume: clipVolume,
                expandedToolId: $expandedClipToolId,
                isReviewActive: false
            )
            let items = EditorComponentShowcaseSamples.demoToolbarItems(
                showsClipTools: toolbarShowsClipTools,
                showsParameters: toolbarShowsParameters,
                toolContext: toolContext,
                toolActions: .noop,
                temperature: $temperatureValue,
                volume: $volumeValue
            )

            EditorBottomChromeAssemblyComponent(
                showsNavigation: true,
                toolbarItems: items,
                navigation: {
                    EditorBottomNavigationComponent(
                        size: selectedSize,
                        style: .glass,
                        items: EditorBottomNavigationComponent.defaultEditorItems,
                        activeItemId: $activeNavItemId
                    )
                }
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
}

private enum LibraryShowcaseExpandableToolID: String {
    case color, volume
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
