import Foundation
import SwiftUI

struct AgentView: View {
    @ObservedObject var viewModel: AgentViewModel
    let transitionNamespace: Namespace.ID
    let secondaryContentOpacity: Double
    var promptIsSource = true

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp6)) {
            promptSection

            ScrollView(showsIndicators: false) {
                secondaryContent
                    .padding(.bottom, .sp6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden(true)
        .padding(.horizontal, .sp4)
        .padding(.top, .sp2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.startIfNeeded()
        }
        .onDisappear {
            Task {
                await viewModel.closeIfNeeded()
            }
        }
    }

    private var secondaryContent: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp6)) {
            statusSection
            timelineSection
        }
        .opacity(secondaryContentOpacity)
        .offset(y: CGFloat(1 - secondaryContentOpacity) * 18)
        .animation(.easeOut(duration: 0.24), value: secondaryContentOpacity)
    }

    private var promptSection: some View {
        ImportPromptDisplayCard(text: viewModel.model.promptText)
            .importPromptCardTransition(in: transitionNamespace, isSource: promptIsSource)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Current status")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            Text(viewModel.model.statusMessage)
                .id(viewModel.model.statusMessage)
                .typographyStyle(.body)
                .foregroundStyle(Color.ds.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            if let errorMessage = viewModel.model.errorMessage {
                Text(errorMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: viewModel.model.statusMessage)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Timeline assembly")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            AgentSurfaceCard(minHeight: 0) {
                VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                    if viewModel.model.timelineClips.isEmpty {
                        AgentPlaceholderStateView(
                            text: "The proposed timeline will appear here once the first draft is assembled."
                        )
                    } else {
                        AgentTimelineStripView(clips: viewModel.model.timelineClips)
                    }
                }
            }
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.88), value: viewModel.model.timelineClips)
    }
}

private struct AgentPlaceholderStateView: View {
    let text: String

    var body: some View {
        Text(text)
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.textMuted)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
    }
}

private struct AgentExtractionClipView: View {
    let clip: AgentExtractionClip

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            HStack(alignment: .top, spacing: .spacing(.sp2)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.displayName)
                        .typography(.body)
                        .foregroundStyle(Color.ds.text)
                        .lineLimit(1)

                    if let summary = clip.summary, !summary.trimmedForTransport.isEmpty {
                        Text(summary)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.textMuted)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                AgentExtractionStatusPill(clip: clip)
            }

            AgentClipRangePreview(clip: clip)

            if !clip.ranges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .spacing(.sp2)) {
                        ForEach(clip.ranges) { range in
                            Text(range.reason)
                                .typography(.bodySmall)
                                .foregroundStyle(Color.ds.text)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.ds.bg.opacity(0.55))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.ds.border.opacity(0.8), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.sp2)
        .background(Color.ds.bg.opacity(0.16))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }
}

private struct AgentExtractionStatusPill: View {
    let clip: AgentExtractionClip

    var body: some View {
        Text(label)
            .typography(.bodySmall)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var label: String {
        if clip.isDropped {
            return "Dropped"
        }

        if clip.isAnalyzing {
            return "Analyzing"
        }

        return "\(clip.ranges.count) cut\(clip.ranges.count == 1 ? "" : "s")"
    }

    private var foregroundColor: Color {
        if clip.isDropped {
            return Color.ds.textMuted
        }

        return clip.isAnalyzing ? Color.ds.text : Color.ds.accentFg
    }

    private var backgroundColor: Color {
        if clip.isDropped {
            return Color.ds.surface.opacity(0.72)
        }

        return clip.isAnalyzing ? Color.ds.surface.opacity(0.82) : Color.ds.accentBg.opacity(0.18)
    }
}

private struct AgentClipRangePreview: View {
    let clip: AgentExtractionClip
    @State private var thumbnail: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                thumbnailBackground

                if clip.ranges.isEmpty {
                    Rectangle()
                        .fill(Color.black.opacity(clip.isDropped ? 0.72 : 0.48))
                } else {
                    ForEach(excludedIntervals, id: \.id) { interval in
                        Rectangle()
                            .fill(Color.black.opacity(0.68))
                            .frame(
                                width: width(for: interval, totalWidth: geometry.size.width),
                                height: geometry.size.height
                            )
                            .offset(x: offsetX(for: interval, totalWidth: geometry.size.width))
                    }

                    ForEach(clip.ranges) { range in
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.52), lineWidth: 1)
                            .frame(
                                width: max(width(for: range.asInterval, totalWidth: geometry.size.width) - 2, 8),
                                height: max(geometry.size.height - 10, 20)
                            )
                            .offset(
                                x: offsetX(for: range.asInterval, totalWidth: geometry.size.width) + 1,
                                y: 5
                            )
                    }
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.46)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(height: 78)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .task(id: clip.videoURL) {
            thumbnail = await VideoAssetPreviewLoader.generateThumbnail(for: clip.videoURL)
        }
    }

    private var thumbnailBackground: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color.ds.surface,
                        Color.ds.bg.opacity(0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var excludedIntervals: [ClosedRangeInterval] {
        guard effectiveDuration > 0, !clip.ranges.isEmpty else { return [] }

        let sortedRanges = clip.ranges
            .map(\.asInterval)
            .sorted(by: { $0.start < $1.start })
        var intervals: [ClosedRangeInterval] = []
        var cursor = 0.0

        for range in sortedRanges {
            if range.start > cursor {
                intervals.append(ClosedRangeInterval(start: cursor, end: range.start))
            }
            cursor = max(cursor, range.end)
        }

        if cursor < effectiveDuration {
            intervals.append(ClosedRangeInterval(start: cursor, end: effectiveDuration))
        }

        return intervals
    }

    private func width(for interval: ClosedRangeInterval, totalWidth: CGFloat) -> CGFloat {
        guard effectiveDuration > 0 else { return totalWidth }
        return max(CGFloat(interval.duration / effectiveDuration) * totalWidth, 0)
    }

    private func offsetX(for interval: ClosedRangeInterval, totalWidth: CGFloat) -> CGFloat {
        guard effectiveDuration > 0 else { return 0 }
        return CGFloat(interval.start / effectiveDuration) * totalWidth
    }

    private var effectiveDuration: Double {
        max(clip.durationSeconds, clip.ranges.map(\.outSec).max() ?? 0)
    }
}

private struct AgentTimelineStripView: View {
    let clips: [AgentTimelineClip]

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let spacing = CGFloat(max(clips.count - 1, 0)) * .spacing(.sp2)
            let usableWidth = max(availableWidth - spacing, 1)
            let weights = clips.map { sqrt(max($0.segmentDurationSeconds, 0.15)) }
            let weightSum = max(weights.reduce(0, +), 0.01)
            let widths = weights.map { weight in
                max((CGFloat(weight) / CGFloat(weightSum)) * usableWidth, 72)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: .spacing(.sp2)) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        AgentTimelineClipView(
                            clip: clip,
                            width: widths[index]
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(minWidth: availableWidth, alignment: .leading)
            }
        }
        .frame(height: 108)
    }
}

private struct AgentTimelineClipView: View {
    let clip: AgentTimelineClip
    let width: CGFloat
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack {
            background

            LinearGradient(
                colors: [
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: width, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .task(id: clip.videoURL) {
            guard let videoURL = clip.videoURL else {
                thumbnail = nil
                return
            }

            thumbnail = await VideoAssetPreviewLoader.generateThumbnail(for: videoURL)
        }
    }

    private var background: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color.ds.accentBg.opacity(0.38),
                        Color.ds.bg.opacity(0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

private struct ClosedRangeInterval: Identifiable {
    let start: Double
    let end: Double

    var id: String {
        "\(start)-\(end)"
    }

    var duration: Double {
        max(end - start, 0)
    }
}

private extension AgentClipRange {
    var asInterval: ClosedRangeInterval {
        ClosedRangeInterval(start: inSec, end: outSec)
    }
}
