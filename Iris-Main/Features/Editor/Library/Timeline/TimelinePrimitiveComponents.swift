import SwiftUI

struct TimelineRulerComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.ruler"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let size: EditorComponentSize
    let pixelsPerSecond: CGFloat
    let durationUs: Int64
    @Binding var currentTime: Int64

    var body: some View {
        TimelineRuler(
            pixelsPerSecond: pixelsPerSecond,
            durationUs: durationUs,
            currentTime: $currentTime
        )
        .frame(height: TimelineComponentLayout.preset(size).rulerHeight)
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
        let layout = TimelineComponentLayout.preset(size)
        HStack(alignment: .bottom, spacing: 0) {
            Text(TimeFormatter.formatTime(currentTimeUs))
                .typography(.body)
                .foregroundColor(Color.ds.text)
                .frame(width: 41)
            Text(TimeFormatter.calcCentiSeconds(currentTimeUs))
                .typography(.bodySmall)
                .foregroundColor(Color.ds.text)
                .padding(.bottom, 0.5)
                .frame(width: 15)
            Text(" / ")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            Text(TimeFormatter.formatTime(timelineDurationUs))
                .typography(.body)
                .foregroundColor(Color.ds.textMuted)
                .frame(width: 41)
        }
        .padding(.leading, .sp3)
        .padding(.top, 2)
        .frame(height: layout.rulerHeight, alignment: .topLeading)
        .background(Color.ds.bg)
    }
}

struct TimelinePlayheadComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.playhead"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    var tint: Color = Color.ds.text
    var topPadding: CGFloat = 27

    var body: some View {
        PlayheadView(tint: tint)
            .padding(.top, topPadding)
    }
}

struct TimelineTrackKindBadge: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.trackBadge"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let kind: TrackKind
    let size: EditorComponentSize
    let trackHeight: CGFloat

    var body: some View {
        let layout = TimelineComponentLayout.preset(size)
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .fill(Color.ds.bg.opacity(0.75))
            .frame(width: layout.iconSize, height: trackHeight)
            .overlay(RoundedRectangle(cornerRadius: .spacing(.sp1)).stroke(Color.ds.textMuted.opacity(0.75), lineWidth: 1))
            .overlay(
                Image(systemName: iconName)
                    .font(.system(size: min(14, trackHeight * 0.7), weight: .semibold))
                    .foregroundColor(Color.ds.textMuted.opacity(0.75))
            )
    }

    private var iconName: String {
        switch kind {
        case .video: "video.fill"
        case .audio: "waveform"
        case .overlay: "square.on.square"
        case .captions: "textformat"
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
        case .videoPhotos: "Video · Photos"
        case .videoFiles: "Video · Files"
        case .audioPhotos: "Audio · Photos"
        case .audioFiles: "Audio · Files"
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
        case .captions: (.overlay, .caption)
        case .videoPhotos: (.video, .photos)
        case .videoFiles: (.video, .files)
        case .audioPhotos: (.audio, .photos)
        case .audioFiles: (.audio, .files)
        }
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
        case .standard: .spacing(.sp8)
        case .expanded: .spacing(.sp8)
        }
    }

    var body: some View {
        Button {
            guard !isMenuOpen else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { isMenuOpen = true }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: .spacing(.sp2))
                    .fill(Color.ds.bg.opacity(0.75))
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.accentFg, lineWidth: 2))
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.ds.accentFg)
            }
            .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize)
        .opacity(isMenuOpen ? 0 : 1)
        .allowsHitTesting(!isMenuOpen)
        .overlay(alignment: .trailing) {
            if isMenuOpen {
                flatOptionsPanel
            }
        }
        .onChange(of: isMenuOpen) { _, isOpen in
            if !isOpen { }
        }
    }

    private var flatOptionsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleOptions.enumerated()), id: \.element.id) { index, option in
                Button {
                    onSelect(option.selection.0, option.selection.1)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        isMenuOpen = false
                    }
                } label: {
                    HStack {
                        Image(systemName: option.iconName).font(.system(size: 14, weight: .medium))
                        Text(option.label).typography(.action)
                    }
                    .foregroundColor(Color.ds.accentFg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .sp3).padding(.vertical, .sp2)
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
        .cornerRadius(.spacing(.sp2))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
