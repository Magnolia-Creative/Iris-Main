import SwiftUI
import UIKit

struct TimelineTrackComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.track"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let model: TimelineTrackModel
    let pixelsPerSecond: CGFloat
    @Binding var selectedSegmentId: String?
    var reviewFocusedSegmentIds: Set<String>
    var isReviewInteractionDisabled: Bool
    var promptFocusSegmentIds: Set<String>
    var onSelectSegment: ((String) -> Void)?

    init(
        model: TimelineTrackModel,
        pixelsPerSecond: CGFloat,
        selectedSegmentId: Binding<String?> = .constant(nil),
        reviewFocusedSegmentIds: Set<String> = [],
        isReviewInteractionDisabled: Bool = false,
        promptFocusSegmentIds: Set<String> = [],
        onSelectSegment: ((String) -> Void)? = nil
    ) {
        self.model = model
        self.pixelsPerSecond = pixelsPerSecond
        self._selectedSegmentId = selectedSegmentId
        self.reviewFocusedSegmentIds = reviewFocusedSegmentIds
        self.isReviewInteractionDisabled = isReviewInteractionDisabled
        self.promptFocusSegmentIds = promptFocusSegmentIds
        self.onSelectSegment = onSelectSegment
    }

    private var layout: TimelineComponentLayout {
        TimelineComponentLayout.preset(model.size)
    }

    private var trackHeight: CGFloat {
        layout.trackHeight(for: model.kind)
    }

    private var contentWidth: CGFloat {
        let maxEnd = model.segments.map(\.rangeUs.end).max() ?? 0
        return max(1, CGFloat(maxEnd) / 1_000_000 * pixelsPerSecond)
    }

    private var laidOutSegments: [LaidOutTimelineSegment] {
        var cursorX: CGFloat = 0
        return model.segments
            .sorted { $0.rangeUs.start < $1.rangeUs.start }
            .map { segment in
                let x = segmentX(segment)
                let width = segmentWidth(segment)
                let gap = max(0, x - cursorX)
                cursorX = max(cursorX, x + width)
                return LaidOutTimelineSegment(segment: segment, leadingGap: gap, width: width)
            }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .fill(Color.ds.surface.opacity(0.18))
                .frame(width: max(contentWidth, 1), height: trackHeight)

            HStack(spacing: 0) {
                ForEach(laidOutSegments) { laidOut in
                    Color.clear
                        .frame(width: laidOut.leadingGap)
                        .allowsHitTesting(false)

                    segmentView(laidOut.segment)
                        .frame(width: laidOut.width, height: trackHeight)
                        .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
                        .onTapGesture {
                            guard !isReviewInteractionDisabled else { return }
                            selectedSegmentId = laidOut.segment.id
                            onSelectSegment?(laidOut.segment.id)
                        }
                    }
                Spacer(minLength: 0)
            }
            .frame(width: contentWidth, height: trackHeight, alignment: .leading)
        }
        .frame(width: contentWidth, height: trackHeight, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func segmentView(_ segment: TimelineSegmentModel) -> some View {
        let isSelected = selectedSegmentId == segment.id
        let isReviewDimmed = !reviewFocusedSegmentIds.isEmpty && !reviewFocusedSegmentIds.contains(segment.id)
        let isPromptFocused = promptFocusSegmentIds.contains(segment.id)
        switch model.kind {
        case .video:
            TimelineVideoSegmentView(
                segment: segment,
                isSelected: isSelected,
                isReviewDimmed: isReviewDimmed,
                isPromptFocused: isPromptFocused
            )
        case .audio:
            TimelineAudioSegmentView(
                segment: segment,
                isSelected: isSelected,
                isReviewDimmed: isReviewDimmed,
                isPromptFocused: isPromptFocused
            )
        case .caption:
            TimelineCaptionSegmentView(
                segment: segment,
                isSelected: isSelected,
                isReviewDimmed: isReviewDimmed,
                isPromptFocused: isPromptFocused
            )
        }
    }

    private func segmentX(_ segment: TimelineSegmentModel) -> CGFloat {
        CGFloat(segment.rangeUs.start) / 1_000_000 * pixelsPerSecond
    }

    private func segmentWidth(_ segment: TimelineSegmentModel) -> CGFloat {
        max(layout.minimumSegmentWidth, CGFloat(segment.durationUs) / 1_000_000 * pixelsPerSecond)
    }
}

private struct LaidOutTimelineSegment: Identifiable {
    let segment: TimelineSegmentModel
    let leadingGap: CGFloat
    let width: CGFloat

    var id: String { segment.id }
}

private struct TimelineVideoSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool
    let isReviewDimmed: Bool
    let isPromptFocused: Bool

    @State private var thumbnailStrip: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let thumbnailStrip {
                Image(uiImage: thumbnailStrip)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color.ds.surface.opacity(0.95), Color.ds.bg.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: segment.mediaKind == .photo ? "photo.fill" : "video.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ds.accentFg)
                    .padding(.spacing(.sp2))
            }

            if let title = segment.title, !title.isEmpty {
                Text(title)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(1)
                    .padding(.horizontal, .spacing(.sp2))
                    .padding(.vertical, .spacing(.sp1))
                    .background(Color.ds.bg.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
                    .padding(.spacing(.sp1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
        .overlay(baseStroke)
        .overlay(promptFocusStroke)
        .overlay(selectionStroke)
        .opacity(isReviewDimmed ? 0.32 : 1)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isReviewDimmed)
        .task(id: segment.thumbnailStripPath) {
            thumbnailStrip = loadImage(storedPath: segment.thumbnailStripPath)
        }
    }

    private var baseStroke: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .stroke(Color.ds.border, lineWidth: 1)
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .stroke(Color.ds.accentFg, lineWidth: 2)
            .opacity(isSelected ? 1 : 0)
    }

    private var promptFocusStroke: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .stroke(Color.ds.accentFg.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .opacity(isPromptFocused ? 1 : 0)
    }
}

private struct TimelineAudioSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool
    let isReviewDimmed: Bool
    let isPromptFocused: Bool

    @State private var waveformImage: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .fill(Color.ds.surface.opacity(0.72))

            if let waveformImage {
                Image(uiImage: waveformImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.8)
                    .clipped()
            } else {
                TimelineWaveformPlaceholder(seed: segment.id)
                    .padding(.horizontal, .spacing(.sp2))
                    .padding(.vertical, .spacing(.sp1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .stroke(Color.ds.accentFg.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .opacity(isPromptFocused ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .stroke(Color.ds.accentFg, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .opacity(isReviewDimmed ? 0.32 : 1)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isReviewDimmed)
        .task(id: segment.waveformPath) {
            waveformImage = loadImage(storedPath: segment.waveformPath)
        }
    }
}

private struct TimelineCaptionSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool
    let isReviewDimmed: Bool
    let isPromptFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .fill(Color.ds.surface.opacity(0.95))
            .overlay(
                Text(segment.captionText ?? segment.title ?? "")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.border, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.accentFg.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .opacity(isPromptFocused ? 1 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.accentFg, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
            .opacity(isReviewDimmed ? 0.32 : 1)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .animation(.easeInOut(duration: 0.18), value: isReviewDimmed)
    }
}

private struct TimelineWaveformPlaceholder: View {
    let seed: String

    private let barCount = 22

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = max(1, geometry.size.height)

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.ds.accentFg.opacity(0.72))
                        .frame(width: 2, height: barHeight(at: index, availableHeight: availableHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barHeight(at index: Int, availableHeight: CGFloat) -> CGFloat {
        let scalar = abs(sin(Double(index + seed.count) * 0.73))
        return max(2, availableHeight * (0.25 + CGFloat(scalar) * 0.75))
    }
}

private func loadImage(storedPath: String?) -> UIImage? {
    guard
        let storedPath,
        let url = AppSandboxFileURI.resolveFileURL(storedURI: storedPath)
    else {
        return nil
    }
    return UIImage(contentsOfFile: url.path)
}
