import SwiftUI

struct EditorPromptBarView: View {
    @ObservedObject var viewModel: EditorPromptBarViewModel
    let isClipSelected: Bool
    let micNamespace: Namespace.ID

    @FocusState private var isPromptFocused: Bool
    @State private var isMicPressed = false

    private let compactSize: CGFloat = 42
    private let expandedSize: CGFloat = 66

    var body: some View {
        // Single stable ZStack. Each layer keeps its own view identity across
        // phase changes, so the mic's DragGesture is preserved (true
        // hold-to-talk). Layout shifts happen via alignment / opacity, never
        // by swapping subtrees.
        ZStack {
            // Layer A — phase-specific full-row content (typing field /
            // status / error). Mic is in its own layer so it isn't disturbed.
            phaseRowContent
                .frame(maxWidth: .infinity)

            // Layer B — right-anchored chat button (no-clip idle).
            chatButton
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(showsRightChat ? 1 : 0)
                .allowsHitTesting(showsRightChat)

            // Layer C — mic group. Stays geometrically centered for the
            // no-clip idle and recording layouts, slides to the leading edge
            // only for the clip-selected idle layout.
            micGroup
                .frame(maxWidth: .infinity, alignment: micAlignment)
                .opacity(showsMic ? 1 : 0)
                .allowsHitTesting(showsMic)
        }
        .frame(minHeight: barMinHeight)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isClipSelected)
        .onChange(of: viewModel.phase) { _, phase in
            isPromptFocused = (phase == .typing)
        }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - Layout state

    /// We grow the bar height when there's room for the caption text under
    /// the mic so the layout doesn't feel cramped.
    private var barMinHeight: CGFloat {
        // Compact (clip-selected idle) stays short; everything else makes
        // room for the caption line under the mic.
        if isClipSelected, viewModel.phase == .idle { return expandedSize }
        return 96
    }

    private var micAlignment: Alignment {
        // Only slide to the left when the clip-selected compact layout
        // applies. Recording keeps the mic centered.
        if isClipSelected, viewModel.phase == .idle { return .leading }
        return .center
    }

    private var showsMic: Bool {
        switch viewModel.phase {
        case .idle, .recording: return true
        case .typing, .submitting, .error: return false
        }
    }

    private var showsRightChat: Bool {
        if case .idle = viewModel.phase, !isClipSelected { return true }
        return false
    }

    private var showsCompactChat: Bool {
        if case .idle = viewModel.phase, isClipSelected { return true }
        return false
    }

    private var micButtonSize: CGFloat {
        switch viewModel.phase {
        case .recording: return expandedSize
        case .idle: return isClipSelected ? compactSize : expandedSize
        case .typing, .submitting, .error: return compactSize
        }
    }

    // MARK: - Mic group (mic + caption + compact chat companion)

    private var micGroup: some View {
        HStack(alignment: .top, spacing: .spacing(.sp2)) {
            VStack(spacing: 6) {
                micButton
                captionLine
            }

            // Inline chat button only shown in the compact, clip-selected
            // idle layout. Always rendered (collapsed when hidden) so the
            // mic's position in the view tree stays stable.
            chatButton
                .opacity(showsCompactChat ? 1 : 0)
                .frame(width: showsCompactChat ? compactSize : 0)
                .allowsHitTesting(showsCompactChat)
                .padding(.top, isClipSelected ? 0 : 0)
        }
    }

    private var captionLine: some View {
        Text(captionText)
            .typographyStyle(.bodySmall)
            .foregroundStyle(captionColor)
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .opacity(captionText.isEmpty ? 0 : 1)
            .frame(height: captionText.isEmpty ? 0 : nil)
            .animation(.easeOut(duration: 0.15), value: captionText.isEmpty)
            .transaction { transaction in
                // Keep the live transcript text crisp; don't let the outer
                // spring animate every character mutation.
                if viewModel.phase == .recording {
                    transaction.animation = nil
                }
            }
    }

    private var captionText: String {
        switch viewModel.phase {
        case .idle:
            return isClipSelected ? "" : "Hold to talk · tap chat to type"
        case .recording:
            return viewModel.liveTranscript.isEmpty
                ? "Listening…"
                : viewModel.liveTranscript
        case .typing, .submitting, .error:
            return ""
        }
    }

    private var captionColor: Color {
        switch viewModel.phase {
        case .recording where viewModel.liveTranscript.isEmpty:
            return Color.ds.accentFg
        case .recording:
            return Color.ds.text
        default:
            return Color.ds.textMuted
        }
    }

    // MARK: - Mic button

    private var micButton: some View {
        ZStack {
            if viewModel.phase == .recording {
                micGlow(size: micButtonSize)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            micCore(size: micButtonSize)

            Image(systemName: "mic.fill")
                .font(.system(size: micButtonSize >= expandedSize ? 26 : 18, weight: .bold))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                .scaleEffect(isMicPressed ? 0.92 : 1.0)
        }
        .frame(width: micButtonSize, height: micButtonSize)
        .matchedGeometryEffect(id: "editor-prompt-mic", in: micNamespace)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isMicPressed else { return }
                    isMicPressed = true
                    Task { await viewModel.beginVoicePrompt() }
                }
                .onEnded { _ in
                    guard isMicPressed else { return }
                    isMicPressed = false
                    Task { await viewModel.endVoicePrompt() }
                }
        )
        .accessibilityLabel(Text("Hold to talk"))
        .accessibilityHint(Text("Press and hold to record a voice prompt."))
    }

    private func micCore(size: CGFloat) -> some View {
        let recording = viewModel.phase == .recording

        return Circle()
            .fill(
                LinearGradient(
                    colors: recording
                        ? [Color.ds.accentBg, Color.ds.accentFg]
                        : [Color.white.opacity(0.20), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: recording
                                ? [Color.white.opacity(0.95), Color.ds.accentFg.opacity(0.55)]
                                : [Color.ds.accentFg.opacity(0.55), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: recording ? 1.6 : 1
                    )
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    .blur(radius: 0.5)
                    .blendMode(.plusLighter)
            }
            .shadow(
                color: recording ? Color.ds.accentBg.opacity(0.55) : .clear,
                radius: 14,
                x: 0,
                y: 4
            )
            .frame(width: size, height: size)
            .scaleEffect(recording ? (1.0 + CGFloat(viewModel.voiceLevel) * 0.06) : 1.0)
            .animation(.easeOut(duration: 0.12), value: viewModel.voiceLevel)
    }

    /// Reactive Siri-like halo: soft radial glow plus three concentric
    /// expanding rings whose intensity tracks the audio level.
    private func micGlow(size: CGFloat) -> some View {
        let level = CGFloat(viewModel.voiceLevel)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.ds.accentBg.opacity(0.50 + level * 0.35),
                            Color.ds.accentFg.opacity(0.20 + level * 0.30),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.20,
                        endRadius: size * (1.05 + level * 0.55)
                    )
                )
                .frame(width: size * 2.4, height: size * 2.4)
                .blur(radius: 14)

            ForEach(0..<3, id: \.self) { i in
                ReactiveRing(
                    baseSize: size,
                    levelBoost: level,
                    delay: Double(i) * 0.45
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Chat / send / cancel

    private var chatButton: some View {
        Button {
            viewModel.openTextPrompt()
        } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ds.textMuted)
                .frame(width: compactSize, height: compactSize)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Type a prompt"))
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.submitTextPrompt() }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: compactSize, height: compactSize)
                .background(
                    LinearGradient(
                        colors: [Color.ds.accentBg, Color.ds.accentFg],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Send prompt"))
    }

    private var cancelButton: some View {
        Button {
            viewModel.cancelTextPrompt()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ds.textMuted)
                .frame(width: compactSize, height: compactSize)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Cancel"))
    }

    // MARK: - Phase row content (typing / submitting / error)

    @ViewBuilder
    private var phaseRowContent: some View {
        switch viewModel.phase {
        case .typing:
            HStack(spacing: .spacing(.sp2)) {
                typingField
                cancelButton
                sendButton
            }
            .transition(.opacity)
        case .submitting(let status):
            statusContent(status)
                .transition(.opacity)
        case .error(let message):
            errorContent(message)
                .transition(.opacity)
        case .idle, .recording:
            Color.clear
        }
    }

    private var typingField: some View {
        TextField("Describe your edit…", text: $viewModel.promptDraft, axis: .vertical)
            .typographyStyle(.body)
            .foregroundStyle(Color.ds.text)
            .tint(Color.ds.accentFg)
            .lineLimit(1...3)
            .focused($isPromptFocused)
            .submitLabel(.send)
            .onSubmit {
                Task { await viewModel.submitTextPrompt() }
            }
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp2))
            .background(
                RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func statusContent(_ status: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.ds.accentFg)
            Text(status)
                .typographyStyle(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, .spacing(.sp3))
    }

    private func errorContent(_ message: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .typographyStyle(.bodySmall)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.ds.danger)
        .padding(.horizontal, .spacing(.sp3))
    }
}

// MARK: - Reactive pulsing ring

private struct ReactiveRing: View {
    let baseSize: CGFloat
    let levelBoost: CGFloat
    let delay: Double

    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.ds.accentBg.opacity(0.85),
                        Color.ds.accentFg.opacity(0.55),
                        Color.ds.accentBg.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.6
            )
            .frame(
                width: baseSize * (animate ? 1.55 + levelBoost * 0.6 : 1.05),
                height: baseSize * (animate ? 1.55 + levelBoost * 0.6 : 1.05)
            )
            .opacity(animate ? 0 : 0.7)
            .animation(
                .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(delay),
                value: animate
            )
            .onAppear { animate = true }
    }
}
