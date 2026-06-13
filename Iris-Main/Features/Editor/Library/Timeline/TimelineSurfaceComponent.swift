import SwiftUI

struct TimelineOrganizerComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.organizer"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let model: TimelineOrganizerModel
    @Binding var pixelsPerSecond: CGFloat
    var onAddSelection: ((TrackKind, ImportSource) -> Void)?
    @Binding var isAddMenuOpen: Bool

    @State private var selectedSegmentId: String?
    @State private var gestureStartPixelsPerSecond: CGFloat?
    @State private var localPixelsPerSecond: CGFloat
    private let usesExternalPixelsPerSecond: Bool

    init(
        model: TimelineOrganizerModel,
        pixelsPerSecond: Binding<CGFloat>? = nil,
        onAddSelection: ((TrackKind, ImportSource) -> Void)? = nil,
        isAddMenuOpen: Binding<Bool> = .constant(false)
    ) {
        self.model = model
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
        let duration = max(model.durationUs, modelEnd)
        return max(1, CGFloat(duration) / 1_000_000 * resolvedPixelsPerSecond)
    }

    private var rulerDurationUs: Int64 {
        max(model.durationUs, Int64(contentWidth / resolvedPixelsPerSecond * 1_000_000))
    }

    var body: some View {
        GeometryReader { geometry in
            let organizerHeight = max(
                layout.sectionHeight(for: model.tracks),
                layout.rulerHeight + layout.organizerTrackTopOffset + .spacing(.sp8)
            )
            let scrollContentWidth = max(geometry.size.width, contentWidth + layout.readoutWidth)
            let rulerTicksWidth = max(1, scrollContentWidth - layout.readoutWidth)
            let rulerModel = TimelineRulerModel(
                currentTimeUs: model.currentTimeUs,
                durationUs: rulerDurationUs,
                pixelsPerSecond: resolvedPixelsPerSecond
            )
            let playheadTopInset = max(0, layout.rulerHeight - 5)

            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TimelineRulerTicksComponent(model: rulerModel, layout: layout)
                            .frame(width: rulerTicksWidth, height: layout.rulerHeight, alignment: .topLeading)
                            .padding(.leading, layout.readoutWidth)

                        VStack(alignment: .leading, spacing: layout.trackSpacing) {
                            ForEach(model.tracks) { track in
                                TimelineTrackComponent(
                                    model: track,
                                    pixelsPerSecond: resolvedPixelsPerSecond,
                                    selectedSegmentId: $selectedSegmentId
                                )
                            }
                        }
                        .padding(.top, layout.organizerTrackTopOffset)
                        .padding(.leading, layout.readoutWidth)
                    }
                    .frame(width: scrollContentWidth, alignment: .leading)
                }
                .background(Color.ds.bg)
                .simultaneousGesture(zoomGesture)

                TimelineRulerComponent(model: rulerModel)
                    .frame(width: layout.readoutWidth + layout.rulerFadeWidth, height: layout.rulerHeight, alignment: .leading)
                    .clipped()
                    .allowsHitTesting(false)

                if let onAddSelection {
                    TimelineAddMediaButtonComponent(
                        size: .standard,
                        onSelect: onAddSelection,
                        isMenuOpen: $isAddMenuOpen
                    )
                    .padding(.top, layout.rulerHeight + layout.organizerTrackTopOffset)
                    .padding(.trailing, .spacing(.sp4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                PlayheadView(tint: Color.ds.text)
                    .frame(width: geometry.size.width, height: max(0, organizerHeight - playheadTopInset), alignment: .top)
                    .padding(.top, playheadTopInset)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
            .frame(height: organizerHeight)
        }
        .frame(height: max(layout.sectionHeight(for: model.tracks), layout.rulerHeight + layout.organizerTrackTopOffset + .spacing(.sp8)))
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
            pixelsPerSecond: pixelsPerSecond,
            onAddSelection: context.showAddButton ? actions.onAddSelection : nil,
            isAddMenuOpen: context.$isAddMenuOpen
        )
        .onChange(of: context.pixelsPerSecond) { _, newValue in
            livePixelsPerSecond = newValue
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

private struct TimelineRulerTicksComponent: View {
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
