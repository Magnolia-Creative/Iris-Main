import SwiftUI

struct EditorPromptBarView: View {
    @ObservedObject var viewModel: EditorPromptBarViewModel
    let isClipSelected: Bool
    let micNamespace: Namespace.ID

    @FocusState private var isPromptFocused: Bool
    @State private var isMicPressed = false
    @State private var pulse = false

    private let compactSize: CGFloat = 42
    private let expandedSize: CGFloat = 66

    var body: some View {
        // A single stable HStack. Conditional behavior is expressed via
        // opacity / frame modifiers rather than swapping the view tree, so
        // the mic button keeps its identity (and its in-flight gesture)
        // across phase changes — that's what makes hold-to-talk actually hold.
        HStack(spacing: .spacing(.sp2)) {
            // Leading flexible space — expands so the mic centers when there
            // is no clip selected and we're idle.
            Color.clear
                .frame(maxWidth: leadingFlexMax, maxHeight: 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: leadingFlexMax)

            // The mic. Always rendered, sized + animated based on phase.
            micButton
                .opacity(showsMic ? 1 : 0)
                .frame(
                    width: showsMic ? micButtonSize : 0,
                    height: showsMic ? expandedSize : 0
                )
                .allowsHitTesting(showsMic)

            // Middle adaptive area (transcript / status / error / text field).
            // It only takes flexible width when there is meaningful content
            // to render. In the clip-selected idle layout it collapses so the
            // prompt bar sits tightly next to the divider.
            middleArea
                .frame(maxWidth: middleMaxWidth, alignment: middleAlignment)

            // Trailing slot (chat / send+cancel).
            trailingSlot
        }
        .frame(minHeight: expandedSize)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isClipSelected)
        .onChange(of: viewModel.phase) { _, phase in
            isPromptFocused = (phase == .typing)
            pulse = (phase == .recording)
        }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - Layout helpers

    private var showsMic: Bool {
        switch viewModel.phase {
        case .idle, .recording: return true
        case .typing, .submitting, .error: return false
        }
    }

    private var micButtonSize: CGFloat {
        switch viewModel.phase {
        case .recording: return expandedSize
        case .idle: return isClipSelected ? compactSize : expandedSize
        default: return compactSize
        }
    }

    /// When there is no clip and we're idle, the leading flex space expands
    /// so the mic sits visually centered. In every other case it collapses.
    private var leadingFlexMax: CGFloat? {
        guard viewModel.phase == .idle, !isClipSelected else { return 0 }
        return .infinity
    }

    private var middleMaxWidth: CGFloat? {
        switch viewModel.phase {
        case .idle:
            // Collapse the middle slot when no content lives there; otherwise
            // expand to push the trailing slot to the right.
            return isClipSelected ? 0 : .infinity
        case .recording, .typing, .submitting, .error:
            return .infinity
        }
    }

    private var middleAlignment: Alignment {
        switch viewModel.phase {
        case .idle:
            return isClipSelected ? .leading : .trailing
        case .recording:
            return .leading
        case .typing, .submitting, .error:
            return .leading
        }
    }

    // MARK: - Slots

    @ViewBuilder
    private var middleArea: some View {
        switch viewModel.phase {
        case .idle:
            Color.clear.frame(height: 1)
        case .recording:
            liveTranscriptView
        case .typing:
            typingField
        case .submitting(let status):
            statusContent(status)
        case .error(let message):
            errorContent(message)
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        switch viewModel.phase {
        case .idle:
            chatButton
        case .typing:
            HStack(spacing: .spacing(.sp2)) {
                cancelButton
                sendButton
            }
        default:
            EmptyView()
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
                        ? [
                            Color(red: 0.60, green: 0.42, blue: 1.00),
                            Color(red: 0.85, green: 0.30, blue: 0.78)
                          ]
                        : [
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.06)
                          ],
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
                color: recording ? Color(red: 0.60, green: 0.42, blue: 1.00).opacity(0.55) : .clear,
                radius: 14,
                x: 0,
                y: 4
            )
            .frame(width: size, height: size)
            .scaleEffect(recording ? (1.0 + CGFloat(viewModel.voiceLevel) * 0.06) : 1.0)
            .animation(.easeOut(duration: 0.12), value: viewModel.voiceLevel)
    }

    /// Reactive Siri-like halo: three concentric expanding rings layered over
    /// a soft radial glow whose intensity tracks the mic level.
    private func micGlow(size: CGFloat) -> some View {
        let level = CGFloat(viewModel.voiceLevel)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.50 + level * 0.35),
                            Color(red: 0.85, green: 0.30, blue: 0.78).opacity(0.20 + level * 0.30),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.20,
                        endRadius: size * (1.05 + level * 0.55)
                    )
                )
                .frame(width: size * 2.4, height: size * 2.4)
                .blur(radius: 14)

            // Pulsing rings — three of them, scheduled with phase offsets.
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

    // MARK: - Chat / Send / Cancel

    private var chatButton: some View {
        Button {
            viewModel.openTextPrompt()
        } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ds.textMuted)
                .frame(width: compactSize, height: compactSize)
                .background(
                    Circle().fill(Color.white.opacity(0.08))
                )
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
                        colors: [
                            Color(red: 0.60, green: 0.42, blue: 1.00),
                            Color(red: 0.85, green: 0.30, blue: 0.78)
                        ],
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

    // MARK: - Middle content variants

    private var liveTranscriptView: some View {
        let text = viewModel.liveTranscript
        return HStack(spacing: 0) {
            if text.isEmpty {
                Text("Listening…")
                    .typographyStyle(.body)
                    .foregroundStyle(Color.ds.textMuted)
                    .opacity(0.9)
            } else {
                Text(text)
                    .typographyStyle(.body)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .multilineTextAlignment(.leading)
                    .animation(nil, value: text)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, .spacing(.sp2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
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
        .padding(.horizontal, .spacing(.sp2))
        .transition(.opacity)
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
        .padding(.horizontal, .spacing(.sp2))
        .transition(.opacity)
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
                        Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.85),
                        Color(red: 0.85, green: 0.30, blue: 0.78).opacity(0.55),
                        Color(red: 0.30, green: 0.55, blue: 1.00).opacity(0.45)
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
