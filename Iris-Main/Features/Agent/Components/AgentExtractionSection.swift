import SwiftUI

struct AgentExtractionSectionView: View {
    let clips: [AgentExtractionClip]

    var body: some View {
        if !clips.isEmpty {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text("Clip cleanup")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)

                AgentSurfaceCard(minHeight: 0) {
                    LazyVStack(alignment: .leading, spacing: .spacing(.sp4)) {
                        ForEach(clips) { clip in
                            AgentExtractionClipView(clip: clip)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            }
            .animation(.spring(response: 0.52, dampingFraction: 0.88), value: clips)
        }
    }
}

private struct AgentExtractionClipView: View {
    let clip: AgentExtractionClip

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            HStack(alignment: .firstTextBaseline, spacing: .spacing(.sp2)) {
                Text("Clip \(clip.order + 1)")
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)

                Spacer(minLength: 0)

                AgentExtractionStatusLabel(clip: clip)
            }

            AgentClipRangePreview(clip: clip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentExtractionStatusLabel: View {
    let clip: AgentExtractionClip

    var body: some View {
        Text(label)
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.textMuted)
    }

    private var label: String {
        if clip.isDropped {
            return "Dropped"
        }

        if clip.isAnalyzing {
            return "Analyzing"
        }

        if clip.usesFullClip {
            return "Full clip"
        }

        return "\(clip.ranges.count) range\(clip.ranges.count == 1 ? "" : "s")"
    }
}

private struct AgentClipRangePreview: View {
    let clip: AgentExtractionClip
    @State private var thumbnail: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                thumbnailBackground

                if clip.isDropped {
                    Rectangle()
                        .fill(Color.black.opacity(0.72))
                } else if selectedIntervals.isEmpty {
                    Rectangle()
                        .fill(Color.black.opacity(0.48))
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
                }

                ForEach(selectedIntervals) { interval in
                    let intervalWidth = width(for: interval, totalWidth: geometry.size.width)

                    if intervalWidth >= 42 {
                        Text(interval.formattedTimeRange)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                            .frame(
                                width: intervalWidth,
                                height: geometry.size.height,
                                alignment: .center
                            )
                            .offset(x: offsetX(for: interval, totalWidth: geometry.size.width))
                    }
                }
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
        guard effectiveDuration > 0, !selectedIntervals.isEmpty else { return [] }

        let sortedRanges = selectedIntervals.sorted(by: { $0.start < $1.start })
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
        max(clip.durationSeconds, selectedIntervals.map(\.end).max() ?? 0)
    }

    private var selectedIntervals: [ClosedRangeInterval] {
        if clip.usesFullClip {
            guard clip.durationSeconds > 0 else { return [] }
            return [ClosedRangeInterval(start: 0, end: clip.durationSeconds)]
        }

        return clip.ranges
            .map(\.asInterval)
            .sorted(by: { $0.start < $1.start })
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

    var formattedTimeRange: String {
        "\(start.formattedClipTimestamp) - \(end.formattedClipTimestamp)"
    }
}

private extension AgentClipRange {
    var asInterval: ClosedRangeInterval {
        ClosedRangeInterval(start: inSec, end: outSec)
    }
}

private extension Double {
    var formattedClipTimestamp: String {
        let roundedValue = (max(self, 0) * 10).rounded() / 10
        let wholeSeconds = Int(roundedValue)
        let fractionalTenth = Int((roundedValue - Double(wholeSeconds)) * 10)
        let minutes = wholeSeconds / 60
        let seconds = wholeSeconds % 60

        if fractionalTenth == 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }

        return String(format: "%d:%02d.%d", minutes, seconds, fractionalTenth)
    }
}
