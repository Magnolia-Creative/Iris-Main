import SwiftUI

struct TimelineOrganizerComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.organizer"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let model: TimelineOrganizerModel
    @Binding var currentTimeUs: Int64
    @Binding var scrollTargetTimeUs: Int64?
    @Binding var pixelsPerSecond: CGFloat
    @Binding var selectedSegmentId: String?
    var playbackState: TimelinePlaybackState
    var playheadTint: Color
    var reviewFocusedSegmentIds: Set<String>
    var isReviewInteractionDisabled: Bool
    var promptFocusSegmentIds: Set<String>
    var captionHighlightRangeUs: ClosedRange<Int64>?
    var onSelectSegment: ((String) -> Void)?
    var onAddSelection: ((TrackKind, ImportSource) -> Void)?
    var onPreviewScrub: ((Int64, Double) -> Void)?
    @Binding var isAddMenuOpen: Bool

    @State private var gestureStartPixelsPerSecond: CGFloat?
    @State private var localPixelsPerSecond: CGFloat
    @State private var lastScrollOffsetX: CGFloat = 0
    @State private var lastScrollTime: Date = Date()
    @State private var lastScrollUpdate: Date = Date()
    @State private var isJumpingToTarget = false
    @State private var jumpResetWorkItem: DispatchWorkItem?
    @State private var sharedScrollOffset: CGFloat = 0
    @State private var isScrollingFast = false
    @State private var scrollIdleWorkItem: DispatchWorkItem?
    private let usesExternalPixelsPerSecond: Bool

    init(
        model: TimelineOrganizerModel,
        currentTimeUs: Binding<Int64>? = nil,
        scrollTargetTimeUs: Binding<Int64?> = .constant(nil),
        pixelsPerSecond: Binding<CGFloat>? = nil,
        selectedSegmentId: Binding<String?> = .constant(nil),
        playbackState: TimelinePlaybackState = .idle,
        playheadTint: Color = Color.ds.text,
        reviewFocusedSegmentIds: Set<String> = [],
        isReviewInteractionDisabled: Bool = false,
        promptFocusSegmentIds: Set<String> = [],
        captionHighlightRangeUs: ClosedRange<Int64>? = nil,
        onSelectSegment: ((String) -> Void)? = nil,
        onAddSelection: ((TrackKind, ImportSource) -> Void)? = nil,
        onPreviewScrub: ((Int64, Double) -> Void)? = nil,
        isAddMenuOpen: Binding<Bool> = .constant(false)
    ) {
        self.model = model
        self._currentTimeUs = currentTimeUs ?? .constant(model.currentTimeUs)
        self._scrollTargetTimeUs = scrollTargetTimeUs
        self._selectedSegmentId = selectedSegmentId
        self.playbackState = playbackState
        self.playheadTint = playheadTint
        self.reviewFocusedSegmentIds = reviewFocusedSegmentIds
        self.isReviewInteractionDisabled = isReviewInteractionDisabled
        self.promptFocusSegmentIds = promptFocusSegmentIds
        self.captionHighlightRangeUs = captionHighlightRangeUs
        self.onSelectSegment = onSelectSegment
        self.onPreviewScrub = onPreviewScrub
        if let pixelsPerSecond {
            self._pixelsPerSecond = pixelsPerSecond
            self.usesExternalPixelsPerSecond = true
        } else {
            self._pixelsPerSecond = .constant(model.pixelsPerSecond)
            self.usesExternalPixelsPerSecond = false
        }
        self.onAddSelection = onAddSelection
        self._isAddMenuOpen = isAddMenuOpen
        self._localPixelsPerSecond = State(initialValue: model.pixelsPerSecond)
    }

    private var resolvedPixelsPerSecond: CGFloat {
        min(
            TimelineComponentLayout.maximumPixelsPerSecond,
            max(TimelineComponentLayout.minimumPixelsPerSecond, activePixelsPerSecond)
        )
    }

    private var activePixelsPerSecond: CGFloat {
        usesExternalPixelsPerSecond ? pixelsPerSecond : localPixelsPerSecond
    }

    private var layout: TimelineComponentLayout {
        model.tracks.map { TimelineComponentLayout.preset($0.size) }.max(by: { left, right in
            left.sectionHeight(for: model.tracks) < right.sectionHeight(for: model.tracks)
        }) ?? .standard
    }

    private var contentWidth: CGFloat {
        let modelEnd = model.tracks.flatMap(\.segments).map(\.rangeUs.end).max() ?? model.durationUs
        let duration = max(model.scrollableDurationUs, model.durationUs, modelEnd)
        return max(1, CGFloat(duration) / 1_000_000 * resolvedPixelsPerSecond)
    }

    private var rulerDurationUs: Int64 {
        max(model.durationUs, Int64(contentWidth / resolvedPixelsPerSecond * 1_000_000))
    }

    private var addButtonSize: EditorComponentSize {
        model.tracks.first(where: { $0.kind == .video })?.size.componentSize
            ?? model.tracks.first?.size.componentSize
            ?? .standard
    }

    var body: some View {
        GeometryReader { geometry in
            let organizerHeight = max(
                layout.sectionHeight(for: model.tracks),
                layout.rulerHeight + layout.organizerTrackTopOffset + .spacing(.sp8)
            )
            let playheadCenterX = geometry.size.width / 2
            let scrollContentWidth = max(geometry.size.width, contentWidth + playheadCenterX * 2)
            let rulerTicksWidth = max(1, contentWidth)
            let rulerModel = TimelineRulerModel(
                currentTimeUs: currentTimeUs,
                durationUs: rulerDurationUs,
                pixelsPerSecond: resolvedPixelsPerSecond
            )
            let addButtonTopOffset = addButtonTopOffset(for: model.tracks)

            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            if let captionHighlightRangeUs {
                                TimelineCaptionRangeHighlight(
                                    rangeUs: captionHighlightRangeUs,
                                    pixelsPerSecond: resolvedPixelsPerSecond,
                                    height: layout.trackStackHeight(for: model.tracks)
                                )
                                .offset(
                                    x: playheadCenterX,
                                    y: layout.rulerHeight + layout.organizerTrackTopOffset
                                )
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                TimelineRulerTicksComponent(model: rulerModel, layout: layout)
                                    .frame(width: rulerTicksWidth, height: layout.rulerHeight, alignment: .topLeading)
                                    .padding(.leading, playheadCenterX)

                                VStack(alignment: .leading, spacing: layout.trackSpacing) {
                                    ForEach(model.tracks) { track in
                                        TimelineTrackComponent(
                                            model: track,
                                            pixelsPerSecond: resolvedPixelsPerSecond,
                                            selectedSegmentId: $selectedSegmentId,
                                            reviewFocusedSegmentIds: reviewFocusedSegmentIds,
                                            isReviewInteractionDisabled: isReviewInteractionDisabled,
                                            promptFocusSegmentIds: promptFocusSegmentIds,
                                            onSelectSegment: onSelectSegment
                                        )
                                    }
                                }
                                .padding(.top, layout.organizerTrackTopOffset)
                                .padding(.leading, playheadCenterX)
                            }
                            TimelineOrganizerScrollMarker(
                                targetTimeUs: activeScrollTargetTimeUs,
                                pixelsPerSecond: resolvedPixelsPerSecond,
                                centerX: playheadCenterX
                            )
                        }
                        .frame(width: scrollContentWidth, alignment: .leading)
                    }
                    .background(Color.ds.bg)
                    .scrollDisabled(isAddMenuOpen)
                    .simultaneousGesture(zoomGesture)
                    .onScrollGeometryChange(for: CGFloat.self) { geo in
                        geo.contentOffset.x
                    } action: { _, x in
                        updateCurrentTimeFromScrollOffset(x)
                    }
                    .onAppear {
                        scrollToPlayhead(with: proxy)
                    }
                    .onChange(of: scrollTargetTimeUs) { _, targetTimeUs in
                        guard targetTimeUs != nil else { return }
                        beginJumpToTarget()
                        scrollToPlayhead(with: proxy, animated: true)
                    }
                    .onChange(of: currentTimeUs) { _, _ in
                        guard playbackState == .playing else { return }
                        scrollToPlayhead(with: proxy)
                    }
                    .onChange(of: playbackState) { _, newState in
                        guard newState == .playing else { return }
                        scrollToPlayhead(with: proxy)
                    }
                    .onChange(of: resolvedPixelsPerSecond) { _, _ in
                        scrollToPlayhead(with: proxy)
                    }
                }

                TimelineFixedRulerReadoutComponent(model: rulerModel, layout: layout)
                    .frame(width: layout.readoutWidth + layout.rulerFadeWidth, height: layout.rulerHeight, alignment: .leading)
                    .allowsHitTesting(false)
                    .zIndex(20)

                ZStack(alignment: .topLeading) {
                    ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                        trackIconView(for: track.kind, height: layout.trackHeight(for: track.kind))
                            .position(
                                x: trackIconX(for: geometry.size.width),
                                y: iconYPosition(for: index)
                            )
                    }
                }
                .padding(.top, layout.rulerHeight + layout.organizerTrackTopOffset)
                .frame(height: layout.trackStackHeight(for: model.tracks), alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .zIndex(15)

                if isAddMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                isAddMenuOpen = false
                            }
                        }
                }

                if let onAddSelection {
                    TimelineAddMediaButtonComponent(
                        size: addButtonSize,
                        onSelect: onAddSelection,
                        isMenuOpen: $isAddMenuOpen
                    )
                    .padding(.top, addButtonTopOffset)
                    .padding(.trailing, .spacing(.sp4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: isScrollingFast ? .spacing(.sp8) : 0)
                    .opacity(isScrollingFast ? 0 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrollingFast)
                }

                PlayheadView(tint: playheadTint)
                    .frame(width: geometry.size.width, height: organizerHeight, alignment: .top)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
            .frame(height: organizerHeight)
        }
        .frame(height: max(layout.sectionHeight(for: model.tracks), layout.rulerHeight + layout.organizerTrackTopOffset + .spacing(.sp8)))
        .onDisappear {
            jumpResetWorkItem?.cancel()
            scrollIdleWorkItem?.cancel()
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if gestureStartPixelsPerSecond == nil {
                    gestureStartPixelsPerSecond = resolvedPixelsPerSecond
                }
                let start = gestureStartPixelsPerSecond ?? resolvedPixelsPerSecond
                setPixelsPerSecond(min(
                    TimelineComponentLayout.maximumPixelsPerSecond,
                    max(TimelineComponentLayout.minimumPixelsPerSecond, start * value)
                ))
            }
            .onEnded { _ in
                gestureStartPixelsPerSecond = nil
            }
    }

    private func setPixelsPerSecond(_ value: CGFloat) {
        if usesExternalPixelsPerSecond {
            pixelsPerSecond = value
        } else {
            localPixelsPerSecond = value
        }
    }

    private func addButtonTopOffset(for tracks: [TimelineTrackModel]) -> CGFloat {
        let trackStackCenterY = layout.trackStackHeight(for: tracks) / 2

        return max(
            0,
            layout.rulerHeight + layout.organizerTrackTopOffset + trackStackCenterY - addButtonSize.buttonDimension / 2
        )
    }

    private func trackIconView(for kind: TimelineTrackContentKind, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .fill(Color.ds.bg.opacity(0.75))
            .frame(width: layout.iconSize, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.textMuted.opacity(0.75), lineWidth: 1)
            )
            .overlay(
                Image(systemName: kind.systemImageName)
                    .font(.system(size: min(14, height * 0.7), weight: .semibold))
                    .foregroundStyle(Color.ds.textMuted.opacity(0.75))
            )
    }

    private func trackIconX(for width: CGFloat) -> CGFloat {
        let centerX = width / 2
        let desiredCenter = centerX - .spacing(.sp3) - layout.iconSize / 2 - sharedScrollOffset
        let minCenter: CGFloat = .spacing(.sp3) + layout.iconSize / 2
        let maxCenter = centerX - .spacing(.sp3) - layout.iconSize / 2
        return min(maxCenter, max(minCenter, desiredCenter))
    }

    private func iconYPosition(for index: Int) -> CGFloat {
        let priorHeights = model.tracks.prefix(index).map { layout.trackHeight(for: $0.kind) }.reduce(0, +)
        let spacingTotal = CGFloat(index) * layout.trackSpacing
        let trackHeight = layout.trackHeight(for: model.tracks[index].kind)
        return priorHeights + spacingTotal + trackHeight / 2
    }

    private func scrollToPlayhead(with proxy: ScrollViewProxy, animated: Bool = false) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    proxy.scrollTo(TimelineOrganizerScrollMarker.markerId, anchor: .center)
                }
            } else {
                proxy.scrollTo(TimelineOrganizerScrollMarker.markerId, anchor: .center)
            }
        }
    }

    private func updateCurrentTimeFromScrollOffset(_ offsetX: CGFloat) {
        sharedScrollOffset = offsetX

        if isProgrammaticScrolling {
            lastScrollOffsetX = offsetX
            lastScrollTime = Date()
            return
        }

        if scrollTargetTimeUs != nil {
            scrollTargetTimeUs = nil
        }

        let now = Date()
        let deltaX = offsetX - lastScrollOffsetX
        let deltaT = now.timeIntervalSince(lastScrollTime)
        let velocity = deltaT > 0 ? abs(deltaX) / deltaT : 0
        let minInterval: TimeInterval = 1.0 / 120.0

        if now.timeIntervalSince(lastScrollUpdate) >= minInterval {
            let timeUs = Int64((offsetX / resolvedPixelsPerSecond) * 1_000_000)
            let clampedTimeUs = min(max(0, timeUs), model.scrollableDurationUs)
            currentTimeUs = clampedTimeUs
            lastScrollUpdate = now
            DispatchQueue.main.async {
                onPreviewScrub?(clampedTimeUs, velocity)
            }
        }

        if deltaT > 0 {
            if velocity > 450 && !isScrollingFast {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isScrollingFast = true
                }
            }
            scheduleShowAddButton()
            lastScrollOffsetX = offsetX
            lastScrollTime = now
        }
    }

    private var activeScrollTargetTimeUs: Int64 {
        clampScrollTime(scrollTargetTimeUs ?? currentTimeUs)
    }

    private var isProgrammaticScrolling: Bool {
        isJumpingToTarget || playbackState == .playing
    }

    private func beginJumpToTarget() {
        isJumpingToTarget = true
        jumpResetWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isJumpingToTarget = false
        }
        jumpResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func clampScrollTime(_ timeUs: Int64) -> Int64 {
        min(max(0, timeUs), model.scrollableDurationUs)
    }

    private func scheduleShowAddButton() {
        scrollIdleWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isScrollingFast = false
            }
        }
        scrollIdleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }
}

private struct TimelineOrganizerScrollMarker: View {
    static let markerId = "timelineOrganizerScrollMarker"
    let targetTimeUs: Int64
    let pixelsPerSecond: CGFloat
    let centerX: CGFloat

    var body: some View {
        let targetX = max(0, CGFloat(targetTimeUs) / 1_000_000 * pixelsPerSecond)
        let markerPosition = targetX + centerX

        Color.clear
            .frame(width: markerPosition + 1, height: 1)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: markerPosition, height: 1)
                    Color.clear.frame(width: 1, height: 1).id(Self.markerId)
                }
            }
    }
}

private extension TimelineTrackDisplaySize {
    var componentSize: EditorComponentSize {
        switch self {
        case .compressed: .compressed
        case .standard: .standard
        case .expanded: .expanded
        }
    }
}

private extension EditorComponentSize {
    var buttonDimension: CGFloat {
        switch self {
        case .compressed: .spacing(.sp7)
        case .standard, .expanded: .spacing(.sp8)
        }
    }
}

struct TimelineRulerComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.ruler"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let model: TimelineRulerModel
    private let layout = TimelineComponentLayout.standard

    init(model: TimelineRulerModel) {
        self.model = model
    }

    init(size _: EditorComponentSize, pixelsPerSecond: CGFloat, durationUs: Int64, currentTime: Binding<Int64>) {
        self.model = TimelineRulerModel(
            currentTimeUs: currentTime.wrappedValue,
            durationUs: durationUs,
            pixelsPerSecond: pixelsPerSecond
        )
    }

    private var timeMarkers: [Int64] {
        let totalSeconds = max(0, Int(ceil(Double(model.durationUs) / 1_000_000.0)))
        return (0...max(0, totalSeconds)).map { Int64($0) * 1_000_000 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                readout
                    .frame(width: layout.readoutWidth, height: layout.rulerHeight, alignment: .topLeading)
                    .background(Color.ds.bg)

                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(Array(timeMarkers.enumerated()), id: \.element) { index, time in
                            TimelineRulerMarker(
                                timeUs: time,
                                isLast: index == timeMarkers.count - 1,
                                pixelsPerSecond: model.pixelsPerSecond
                            )
                        }
                    }
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.ds.bg, location: 0),
                            .init(color: Color.ds.bg.opacity(0), location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: layout.rulerFadeWidth, height: layout.rulerHeight)
                }
            }
        }
        .frame(height: layout.rulerHeight, alignment: .topLeading)
    }

    private var readout: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(TimeFormatter.formatTime(model.currentTimeUs))
                .typography(.body)
                .foregroundStyle(Color.ds.text)
                .frame(width: 41)
            Text(TimeFormatter.calcCentiSeconds(model.currentTimeUs))
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.text)
                .padding(.bottom, 0.5)
                .frame(width: 15)
            Text(" / ")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
            Text(TimeFormatter.formatTime(model.durationUs))
                .typography(.body)
                .foregroundStyle(Color.ds.textMuted)
                .frame(width: 41)
        }
        .padding(.top, 2)
    }
}

struct TimelineTimeReadoutComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.timeReadout"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let size: EditorComponentSize
    let currentTimeUs: Int64
    let timelineDurationUs: Int64

    var body: some View {
        TimelineRulerComponent(
            model: TimelineRulerModel(
                currentTimeUs: currentTimeUs,
                durationUs: timelineDurationUs,
                pixelsPerSecond: TimelineComponentLayout.defaultPixelsPerSecond
            )
        )
        .frame(width: TimelineComponentLayout.preset(size).readoutWidth, alignment: .leading)
        .clipped()
    }
}

struct TimelineAddMediaButtonComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.addButton"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let size: EditorComponentSize
    let onSelect: (TrackKind, ImportSource) -> Void
    @Binding var isMenuOpen: Bool
    var visibleOptions: [TimelineAddMediaOption] = TimelineAddMediaOption.allCases

    private var buttonSize: CGFloat {
        switch size {
        case .compressed: .spacing(.sp7)
        case .standard, .expanded: .spacing(.sp8)
        }
    }

    var body: some View {
        Button {
            guard !isMenuOpen else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                isMenuOpen = true
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: .spacing(.sp2))
                    .fill(Color.ds.bg.opacity(0.75))
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.accentFg, lineWidth: 2))
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.ds.accentFg)
            }
            .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize)
        .opacity(isMenuOpen ? 0 : 1)
        .allowsHitTesting(!isMenuOpen)
        .overlay(alignment: .trailing) {
            if isMenuOpen {
                optionsPanel
            }
        }
    }

    private var optionsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleOptions.enumerated()), id: \.element.id) { index, option in
                Button {
                    onSelect(option.selection.0, option.selection.1)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        isMenuOpen = false
                    }
                } label: {
                    HStack {
                        Image(systemName: option.iconName)
                            .font(.system(size: 14, weight: .medium))
                        Text(option.label)
                            .typography(.action)
                    }
                    .foregroundStyle(Color.ds.accentFg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .sp3)
                    .padding(.vertical, .sp2)
                    .background(Color.ds.bg.opacity(0.5))
                }
                .buttonStyle(.plain)

                if index < visibleOptions.count - 1 {
                    Divider().background(Color.ds.border)
                }
            }
        }
        .frame(width: .spacing(.sp7) * 4)
        .background(Color.ds.bg.opacity(0.75))
        .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.accentFg, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

struct TimelineSurfaceComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.full"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let context: EditorTimelineContext
    let actions: EditorTimelineActions
    @State private var livePixelsPerSecond: CGFloat?

    private var pixelsPerSecond: Binding<CGFloat> {
        Binding(
            get: { livePixelsPerSecond ?? context.pixelsPerSecond },
            set: { livePixelsPerSecond = $0 }
        )
    }

    var body: some View {
        TimelineOrganizerComponent(
            model: TimelineOrganizerModel(context: context),
            currentTimeUs: context.$currentTimeAtCenter,
            scrollTargetTimeUs: context.$scrollTargetTimeUs,
            pixelsPerSecond: pixelsPerSecond,
            selectedSegmentId: selectedSegmentId,
            playbackState: context.playbackState,
            playheadTint: context.playheadTint,
            reviewFocusedSegmentIds: context.reviewFocusedClipIds,
            isReviewInteractionDisabled: context.isReviewInteractionDisabled,
            promptFocusSegmentIds: promptActionFocusSegmentIds,
            captionHighlightRangeUs: context.captionHighlightRangeUs,
            onSelectSegment: handleSegmentSelection,
            onAddSelection: context.showAddButton ? actions.onAddSelection : nil,
            onPreviewScrub: actions.onPreviewScrub,
            isAddMenuOpen: context.$isAddMenuOpen
        )
        .onChange(of: context.pixelsPerSecond) { _, newValue in
            livePixelsPerSecond = newValue
        }
    }

    private var promptActionFocusSegmentIds: Set<String> {
        Set(context.reviewFocusedClipIds)
    }

    private var selectedSegmentId: Binding<String?> {
        Binding(
            get: { context.selectedClipId ?? context.selectedCaptionCueId },
            set: { newValue in
                guard let newValue else {
                    context.selectedClipId = nil
                    context.selectedCaptionCueId = nil
                    return
                }
                applySelection(segmentId: newValue)
            }
        )
    }

    private func handleSegmentSelection(_ segmentId: String) {
        applySelection(segmentId: segmentId)

        for track in TimelineOrganizerModel(context: context).tracks {
            guard track.segments.contains(where: { $0.id == segmentId }) else { continue }
            switch track.kind {
            case .caption:
                actions.onCaptionCueSelected?(segmentId)
            case .video, .audio:
                actions.onClipSelected?()
            }
            return
        }
    }

    private func applySelection(segmentId: String) {
        let tracks = TimelineOrganizerModel(context: context).tracks
        context.selectedClipId = nil
        context.selectedCaptionCueId = nil

        for track in tracks {
            guard track.segments.contains(where: { $0.id == segmentId }) else { continue }
            switch track.kind {
            case .caption:
                context.selectedCaptionCueId = segmentId
            case .video, .audio:
                context.selectedClipId = segmentId
            }
            return
        }
    }
}

enum TimelineAddMediaOption: String, CaseIterable, Identifiable {
    case captions
    case videoPhotos
    case videoFiles
    case audioPhotos
    case audioFiles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .captions: "Captions"
        case .videoPhotos: "Video Photos"
        case .videoFiles: "Video Files"
        case .audioPhotos: "Audio Photos"
        case .audioFiles: "Audio Files"
        }
    }

    var iconName: String {
        switch self {
        case .captions: "textformat"
        case .videoPhotos, .videoFiles: "video"
        case .audioPhotos, .audioFiles: "waveform"
        }
    }

    var selection: (TrackKind, ImportSource) {
        switch self {
        case .captions: (.captions, .caption)
        case .videoPhotos: (.video, .photos)
        case .videoFiles: (.video, .files)
        case .audioPhotos: (.audio, .photos)
        case .audioFiles: (.audio, .files)
        }
    }
}

private struct TimelineRulerMarker: View {
    let timeUs: Int64
    let isLast: Bool
    let pixelsPerSecond: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .center, spacing: 0) {
                Rectangle()
                    .fill(Color.ds.border)
                    .frame(width: 1, height: 12)
                Text(TimeFormatter.formatTime(timeUs))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .padding(.top, 1)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(width: 0)

            if !isLast {
                let spacingWidth = pixelsPerSecond / 5
                HStack(spacing: 0) {
                    Spacer().frame(width: spacingWidth)
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 0) {
                            Rectangle()
                                .fill(Color.ds.border)
                                .frame(width: 1, height: 4)
                            Spacer()
                        }
                        .frame(width: 0, height: 4)
                        Spacer().frame(width: spacingWidth)
                    }
                }
                .frame(width: pixelsPerSecond)
            }
        }
    }
}

struct TimelineRulerTicksComponent: View {
    let model: TimelineRulerModel
    let layout: TimelineComponentLayout

    private var timeMarkers: [Int64] {
        let totalSeconds = max(0, Int(ceil(Double(model.durationUs) / 1_000_000.0)))
        return (0...max(0, totalSeconds)).map { Int64($0) * 1_000_000 }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(timeMarkers.enumerated()), id: \.element) { index, time in
                TimelineRulerMarker(
                    timeUs: time,
                    isLast: index == timeMarkers.count - 1,
                    pixelsPerSecond: model.pixelsPerSecond
                )
            }
        }
        .frame(height: layout.rulerHeight, alignment: .topLeading)
    }
}

struct TimelineFixedRulerReadoutComponent: View {
    let model: TimelineRulerModel
    let layout: TimelineComponentLayout

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            readout
                .frame(width: layout.readoutWidth, height: layout.rulerHeight, alignment: .topLeading)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.ds.bg, location: 0),
                    .init(color: Color.ds.bg, location: 0.72),
                    .init(color: Color.ds.bg.opacity(0), location: 1)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: layout.rulerFadeWidth, height: layout.rulerHeight)
        }
        .frame(height: layout.rulerHeight, alignment: .topLeading)
        .background(Color.ds.bg)
    }

    private var readout: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(TimeFormatter.formatTime(model.currentTimeUs))
                .typography(.body)
                .foregroundStyle(Color.ds.text)
                .frame(width: 41)
            Text(TimeFormatter.calcCentiSeconds(model.currentTimeUs))
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.text)
                .padding(.bottom, 0.5)
                .frame(width: 15)
            Text(" / ")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
            Text(TimeFormatter.formatTime(model.durationUs))
                .typography(.body)
                .foregroundStyle(Color.ds.textMuted)
                .frame(width: 41)
        }
        .padding(.top, 2)
        .padding(.leading, .spacing(.sp1))
    }
}
