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
        .padding(.horizontal, .sp4)
        .padding(.top, .sp2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.startIfNeeded()
        }
    }

    private var secondaryContent: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp6)) {
            statusSection
            extractionSection
            timelineSection
        }
        .opacity(secondaryContentOpacity)
        .offset(y: CGFloat(1 - secondaryContentOpacity) * 18)
        .animation(.easeOut(duration: 0.24), value: secondaryContentOpacity)
    }

    private var promptSection: some View {
        PromptCardContainer {
            Text(viewModel.model.promptText)
                .typography(.body)
                .foregroundStyle(Color.ds.text)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ImportPromptCardMetrics.minHeight,
                    alignment: .topLeading
                )
        }
        .importPromptCardTransition(in: transitionNamespace, isSource: promptIsSource)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            HStack(spacing: .spacing(.sp2)) {
                AgentStatusPulse(stage: viewModel.model.stage)

                Text("Current status")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            ZStack(alignment: .leading) {
                Text(viewModel.model.statusMessage)
                    .id(viewModel.model.statusMessage)
                    .typographyStyle(.body)
                    .foregroundStyle(Color.ds.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .frame(minHeight: 52, alignment: .topLeading)
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: viewModel.model.statusMessage)
    }

    private var extractionSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Clip extraction")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            AgentSurfaceCard(minHeight: 176) {
                if viewModel.model.extractionLanes.isEmpty {
                    Color.clear
                } else {
                    VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                        ForEach(viewModel.model.extractionLanes) { lane in
                            AgentExtractionLaneView(lane: lane)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.88), value: viewModel.model.extractionLanes)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Timeline assembly")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            AgentSurfaceCard(minHeight: 124) {
                if viewModel.model.timelineClips.isEmpty {
                    Color.clear
                } else {
                    HStack(alignment: .bottom, spacing: .spacing(.sp2)) {
                        ForEach(viewModel.model.timelineClips) { clip in
                            AgentTimelineClipView(clip: clip)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.88), value: viewModel.model.timelineClips)
    }
}

private struct AgentStatusPulse: View {
    let stage: AgentStage

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let scale = 0.84 + (0.22 * pulse(progress))
            let opacity = 0.42 + (0.5 * pulse(progress))

            Circle()
                .fill(Color.ds.accentFg)
                .frame(width: 10, height: 10)
                .scaleEffect(scale)
                .opacity(stage == .idle ? 0.28 : opacity)
        }
    }

    private func pulse(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped < 0.5 ? (clamped * 2) : ((1 - clamped) * 2)
    }
}

private struct AgentExtractionLaneView: View {
    let lane: AgentExtractionLane

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(max(lane.segments.count - 1, 0)) * .spacing(.sp1)
            let availableWidth = max(geometry.size.width - totalSpacing, 0)

            HStack(spacing: .spacing(.sp1)) {
                ForEach(lane.segments) { segment in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(segmentFill(for: segment))
                        .frame(
                            width: max(CGFloat(segment.widthRatio) * availableWidth, 12),
                            height: 24
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(segmentStroke(for: segment), lineWidth: segment.isHighlighted ? 1 : 0.5)
                        )
                        .shadow(
                            color: segment.isHighlighted ? Color.ds.accentFg.opacity(0.12) : .clear,
                            radius: 12,
                            x: 0,
                            y: 6
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 24)
        .padding(6)
        .background(Color.ds.bg.opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func segmentFill(for segment: AgentExtractionSegment) -> LinearGradient {
        LinearGradient(
            colors: segment.isHighlighted
                ? [
                    Color.ds.accentBg.opacity(0.88),
                    Color.ds.accentFg.opacity(0.98)
                ]
                : [
                    Color.ds.text.opacity(0.1),
                    Color.ds.text.opacity(0.18)
                ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func segmentStroke(for segment: AgentExtractionSegment) -> Color {
        segment.isHighlighted ? Color.white.opacity(0.22) : Color.ds.border.opacity(0.22)
    }
}

private struct AgentTimelineClipView: View {
    let clip: AgentTimelineClip

    var body: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp3))
            .fill(
                LinearGradient(
                    colors: [
                        Color.ds.accentBg.opacity(0.28 + (0.34 * clip.emphasis)),
                        Color.ds.accentFg.opacity(0.2 + (0.6 * clip.emphasis))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.white.opacity(0.08 + (0.16 * clip.emphasis)), lineWidth: 1)
            )
            .frame(width: max(CGFloat(clip.widthRatio) * 220, 44), height: 56)
    }
}
