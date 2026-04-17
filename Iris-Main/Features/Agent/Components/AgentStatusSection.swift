import SwiftUI

struct AgentStatusSectionView: View {
    let statusMessage: String
    let isAnimating: Bool
    let reasoningNotes: [AgentReasoningNote]
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Current status")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            AgentAnimatedStatusMessageView(
                message: statusMessage,
                isAnimating: isAnimating
            )
            .id(statusMessage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            if !reasoningNotes.isEmpty {
                AgentReasoningNotesView(notes: reasoningNotes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let errorMessage {
                Text(errorMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: statusMessage)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: reasoningNotes.count)
    }
}

private struct AgentReasoningNotesView: View {
    let notes: [AgentReasoningNote]

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                AgentReasoningLineView(
                    note: note,
                    startDelayNanoseconds: UInt64(index) * 90_000_000
                )
            }
        }
    }
}

private struct AgentReasoningLineView: View {
    let note: AgentReasoningNote
    let startDelayNanoseconds: UInt64

    @State private var visibleWordCount = 0

    var body: some View {
        HStack(alignment: .top, spacing: .spacing(.sp2)) {
            Circle()
                .fill(Color.ds.textMuted.opacity(0.58))
                .frame(width: 4, height: 4)
                .padding(.top, 7)

            Text(revealedText)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: note.id) {
            await animateReveal()
        }
    }

    private var words: [String] {
        note.text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private var revealedText: String {
        words.prefix(visibleWordCount).joined(separator: " ")
    }

    private func animateReveal() async {
        await MainActor.run {
            visibleWordCount = 0
        }

        guard !words.isEmpty else { return }

        if startDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: startDelayNanoseconds)
        }

        for index in 1...words.count {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                visibleWordCount = index
            }

            if index < words.count {
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
        }
    }
}

private struct AgentAnimatedStatusMessageView: View {
    let message: String
    let isAnimating: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var animationStartDate = Date()

    var body: some View {
        Text(message)
            .typographyStyle(.body)
            .foregroundStyle(isAnimating ? Color.ds.text.opacity(0.76) : Color.ds.text)
            .overlay {
                if isAnimating {
                    GeometryReader { geometry in
                        TimelineView(.animation) { context in
                            let phase = AgentStatusSweepPhase(
                                elapsedTime: context.date.timeIntervalSince(animationStartDate),
                                containerWidth: geometry.size.width
                            )

                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: highlightColor.opacity(0.15), location: 0.24),
                                    .init(color: highlightColor, location: 0.5),
                                    .init(color: highlightColor.opacity(0.15), location: 0.76),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: phase.highlightWidth, height: geometry.size.height)
                            .offset(x: phase.offsetX)
                            .blendMode(colorScheme == .dark ? .screen : .plusLighter)
                        }
                    }
                    .mask {
                        Text(message)
                            .typographyStyle(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                resetAnimationIfNeeded()
            }
            .onChange(of: isAnimating) { _, newValue in
                guard newValue else { return }
                animationStartDate = .now
            }
            .onChange(of: message) { _, _ in
                resetAnimationIfNeeded()
            }
    }

    private var highlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.white.opacity(0.82)
    }

    private func resetAnimationIfNeeded() {
        guard isAnimating else { return }
        animationStartDate = .now
    }
}

private struct AgentStatusSweepPhase {
    let highlightWidth: CGFloat
    let offsetX: CGFloat

    init(elapsedTime: TimeInterval, containerWidth: CGFloat) {
        let width = max(containerWidth, 1)
        highlightWidth = min(max(width * 0.55, 120), max(width, 120))

        let cycleDuration = 1.75
        let progress = CGFloat((elapsedTime.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration)
        let travelDistance = width + highlightWidth

        offsetX = (travelDistance * progress) - highlightWidth
    }
}
