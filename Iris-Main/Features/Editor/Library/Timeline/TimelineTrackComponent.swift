import SwiftUI
import UIKit

struct TimelineTrackComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.track"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let model: TimelineTrackModel
    let pixelsPerSecond: CGFloat
    @Binding var selectedSegmentId: String?
    var onSelectSegment: ((String) -> Void)?

    init(
        model: TimelineTrackModel,
        pixelsPerSecond: CGFloat,
        selectedSegmentId: Binding<String?> = .constant(nil),
        onSelectSegment: ((String) -> Void)? = nil
    ) {
        self.model = model
        self.pixelsPerSecond = pixelsPerSecond
        self._selectedSegmentId = selectedSegmentId
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

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .fill(Color.ds.surface.opacity(0.18))
                .frame(width: max(contentWidth, 1), height: trackHeight)

            ForEach(model.segments) { segment in
                segmentView(segment)
                    .frame(width: segmentWidth(segment), height: trackHeight)
                    .clipped()
                    .offset(x: segmentX(segment))
                    .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
                    .onTapGesture {
                        selectedSegmentId = segment.id
                        onSelectSegment?(segment.id)
                    }
            }
        }
        .frame(minWidth: contentWidth, minHeight: trackHeight, alignment: .leading)
        .frame(height: trackHeight, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func segmentView(_ segment: TimelineSegmentModel) -> some View {
        let isSelected = selectedSegmentId == segment.id
        switch model.kind {
        case .video:
            TimelineVideoSegmentView(segment: segment, isSelected: isSelected)
        case .audio:
            TimelineAudioSegmentView(segment: segment, isSelected: isSelected)
        case .caption:
            TimelineCaptionSegmentView(segment: segment, isSelected: isSelected)
        }
    }

    private func segmentX(_ segment: TimelineSegmentModel) -> CGFloat {
        CGFloat(segment.rangeUs.start) / 1_000_000 * pixelsPerSecond
    }

    private func segmentWidth(_ segment: TimelineSegmentModel) -> CGFloat {
        max(layout.minimumSegmentWidth, CGFloat(segment.durationUs) / 1_000_000 * pixelsPerSecond)
    }
}

private struct TimelineVideoSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool

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
        .overlay(selectionStroke)
        .task(id: segment.thumbnailStripPath) {
            thumbnailStrip = loadImage(storedPath: segment.thumbnailStripPath)
        }
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .stroke(isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: isSelected ? 2 : 1)
    }
}

private struct TimelineAudioSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool

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
                .stroke(isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: isSelected ? 2 : 1)
        )
        .task(id: segment.waveformPath) {
            waveformImage = loadImage(storedPath: segment.waveformPath)
        }
    }
}

private struct TimelineCaptionSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool

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
                    .stroke(isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: isSelected ? 2 : 1)
            )
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
