import SwiftUI

struct ImportProcessingView: View {
    @ObservedObject var viewModel: ImportViewModel
    let gridColumns: [GridItem]
    let transitionNamespace: Namespace.ID
    let promptIsSource: Bool
    let showsPrompt: Bool
    let isTransitioningOut: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp6)) {
            processingVideoSection
                .offset(y: isTransitioningOut ? -20 : 0)
                .opacity(isTransitioningOut ? 0 : 1)

            Group {
                if showsPrompt {
                    processingPromptSection
                } else {
                    processingPromptPlaceholder
                }
            }

            Spacer(minLength: .spacing(.sp6))

            processingStatusSection
                .offset(y: isTransitioningOut ? 16 : 0)
                .opacity(isTransitioningOut ? 0 : 1)
        }
        .padding(.horizontal, .sp4)
        .padding(.top, .sp5)
        .padding(.bottom, .sp6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.startProcessingIfNeeded()
        }
        .transition(.identity)
    }

    private var processingVideoSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Imported clips")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(viewModel.model.videos) { video in
                    ImportedVideoTile(videoURL: video.originalURL)
                }
            }
        }
        .matchedGeometryEffect(id: "videos-section", in: transitionNamespace)
    }

    private var processingPromptSection: some View {
        ImportPromptDisplayCard(text: viewModel.model.prompt.trimmedText)
            .importPromptCardTransition(in: transitionNamespace, isSource: promptIsSource)
    }

    private var processingPromptPlaceholder: some View {
        ImportPromptDisplayCard(text: viewModel.model.prompt.trimmedText)
            .hidden()
    }

    private var processingStatusSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text(viewModel.model.isUploading ? "Processing clips, please wait." : viewModel.model.uploadStatusMessage)
                .typography(.body)
                .foregroundStyle(viewModel.model.uploadDidComplete ? Color.ds.text : Color.ds.textMuted)

            ProcessingStatusBar(isComplete: viewModel.model.uploadDidComplete)
                .frame(height: 14)
        }
    }
}

private struct ProcessingStatusBar: View {
    let isComplete: Bool
    @State private var animationStartDate = Date()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.ds.surface)
                    .overlay(
                        Capsule()
                            .stroke(Color.ds.border, lineWidth: 1)
                    )

                if isComplete {
                    Capsule()
                        .fill(Color.ds.accentBg)
                        .frame(width: geometry.size.width)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                } else {
                    TimelineView(.animation) { context in
                        let phase = ProcessingIndicatorPhase(
                            elapsedTime: context.date.timeIntervalSince(animationStartDate),
                            containerWidth: geometry.size.width,
                            containerHeight: geometry.size.height
                        )

                        ProcessingStatusIndicator(phase: phase)
                            .frame(width: phase.width, height: geometry.size.height)
                            .offset(x: phase.offsetX)
                    }
                }
            }
        }
        .clipShape(Capsule())
        .onAppear {
            guard !isComplete else { return }
            animationStartDate = .now
        }
        .onChange(of: isComplete) { _, newValue in
            guard !newValue else { return }
            animationStartDate = .now
        }
    }
}

private struct ProcessingIndicatorPhase {
    let width: CGFloat
    let offsetX: CGFloat
    let opacity: Double
    let glowOpacity: Double

    init(elapsedTime: TimeInterval, containerWidth: CGFloat, containerHeight: CGFloat) {
        let cycleDuration = 2.8
        let edgeHoldDuration = 0.18
        let travelDuration = (cycleDuration - (edgeHoldDuration * 2)) / 2

        let indicatorDiameter = max(containerHeight, 8)
        let maxIndicatorWidth = min(
            max(containerWidth * 0.32, indicatorDiameter * 3.4),
            max(containerWidth, indicatorDiameter)
        )

        let cycleTime = elapsedTime.truncatingRemainder(dividingBy: cycleDuration)
        let positionProgress: CGFloat
        let stretchProgress: CGFloat

        switch cycleTime {
        case 0..<edgeHoldDuration:
            positionProgress = 0
            stretchProgress = 0
        case edgeHoldDuration..<(edgeHoldDuration + travelDuration):
            let progress = (cycleTime - edgeHoldDuration) / travelDuration
            positionProgress = Self.easeInOut(progress)
            stretchProgress = Self.stretch(for: progress)
        case (edgeHoldDuration + travelDuration)..<(edgeHoldDuration * 2 + travelDuration):
            positionProgress = 1
            stretchProgress = 0
        default:
            let progress = (cycleTime - ((edgeHoldDuration * 2) + travelDuration)) / travelDuration
            positionProgress = 1 - Self.easeInOut(progress)
            stretchProgress = Self.stretch(for: progress)
        }

        width = indicatorDiameter + ((maxIndicatorWidth - indicatorDiameter) * stretchProgress)

        let leftCenter = indicatorDiameter / 2
        let rightCenter = max(containerWidth - leftCenter, leftCenter)
        let centerX = leftCenter + ((rightCenter - leftCenter) * positionProgress)
        offsetX = min(max(centerX - (width / 2), 0), max(containerWidth - width, 0))

        opacity = 0.88 + (Double(stretchProgress) * 0.12)
        glowOpacity = 0.24 + (Double(stretchProgress) * 0.18)
    }

    private static func easeInOut(_ progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return CGFloat(0.5 - (cos(clamped * .pi) * 0.5))
    }

    private static func stretch(for progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return CGFloat(sin(clamped * .pi))
    }
}

private struct ProcessingStatusIndicator: View {
    let phase: ProcessingIndicatorPhase

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.ds.accentBg.opacity(phase.glowOpacity))
                .blur(radius: 8)
                .padding(.vertical, 1)

            Capsule()
                .fill(Color.ds.accentBg)

            Capsule()
                .stroke(Color.white.opacity(0.28), lineWidth: 0.9)
        }
        .opacity(phase.opacity)
    }
}
