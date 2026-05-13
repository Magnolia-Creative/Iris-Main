import SwiftUI
import Inject

struct EditorPromptBarView: View {
    @ObservedObject var viewModel: 
    EditorPromptBarViewModel
    @ObserveInjection var inject
    let isClipSelected: Bool
    let micNamespace: Namespace.ID
    /// Clip-selected idle chrome: tap collapses expanded clip tools in the tab
    /// bar; prompts are not started from this control.
    let onClipChromeTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isPromptFocused: Bool
    @State private var isMicPressed = false
    /// After the pill finishes widening, reveal the thick accent border.
    @State private var showRecordingAccentBorder = false

    private let compactSize: CGFloat = 38
    private let expandedSize: CGFloat = 60

    /// Reserve pill width so the idle circle stays centered and horizontal
    /// growth is symmetric (avoids a leading-edge “slide in from the right”).
    private var micSlotMaxWidth: CGFloat {
        min(220, max(expandedSize * 2.75, 148))
    }

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

            // Layer C — mic group. Centered without a clip; with a clip,
            // leading-aligned so the control can widen in place beside tools.
            micGroup
                .frame(maxWidth: .infinity, alignment: micAlignment)
                .opacity(showsMic ? 1 : 0)
                .allowsHitTesting(showsMic)
        }
        // Hug vertical content (mic + caption / typing row); then enforce a
        // sensible floor so hold-to-talk stays tappable when phases are short.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: barMinHeight)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isClipSelected)
        .onChange(of: viewModel.phase) { _, phase in
            isPromptFocused = (phase == .typing)
            if phase == .recording {
                showRecordingAccentBorder = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard viewModel.phase == .recording else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showRecordingAccentBorder = true
                    }
                }
            } else {
                showRecordingAccentBorder = false
            }
        }
        .onDisappear { viewModel.tearDown() }
        .enableInjection()
    }

    // MARK: - Layout state

    /// We grow the bar height when there's room for the caption text under
    /// the mic so the layout doesn't feel cramped.
    private var barMinHeight: CGFloat {
        // Compact (clip-selected idle) stays short; everything else makes
        // room for the caption line under the mic.
        if isClipSelected, viewModel.phase == .idle { return 48 }
        return 84
    }

    private var micAlignment: Alignment {
        // Clip layout keeps this column pinned to the leading edge across idle /
        // recording so only the control’s width animates (no whole-column
        // slide when the inline chat hides). Without a clip, stay centered.
        if isClipSelected { return .leading }
        return .center
    }

    private var showsMic: Bool {
        switch viewModel.phase {
        case .idle, .recording, .submitting: return true
        case .typing, .clarification, .error: return false
        }
    }

    private var isProcessing: Bool {
        if case .submitting = viewModel.phase { return true }
        return false
    }

    private var showsRightChat: Bool {
        if case .idle = viewModel.phase, !isClipSelected { return true }
        return false
    }

    private var showsClipChromeStub: Bool {
        isClipSelected && viewModel.phase == .idle
    }

    private var micButtonSize: CGFloat {
        switch viewModel.phase {
        case .recording, .submitting: return expandedSize
        case .idle: return isClipSelected ? compactSize : expandedSize
        case .typing, .clarification, .error: return compactSize
        }
    }

    /// Horizontal extent grows into a capsule while recording so the live
    /// waveform has room; idle / submitting stay circular.
    private var micButtonWidth: CGFloat {
        if viewModel.phase == .recording {
            return min(220, max(micButtonSize * 2.75, 148))
        }
        return micButtonSize
    }

    private var micButtonHeight: CGFloat { micButtonSize }

    private var micUsesCapsuleShape: Bool {
        viewModel.phase == .recording
    }

    private var waveformInnerWidth: CGFloat {
        let inset = micUsesCapsuleShape ? 14.0 : 10.0
        return max(10, micButtonWidth - inset * 2)
    }

    // MARK: - Mic group (mic + caption, or clip-only chrome pill)

    private var micGroup: some View {
        Group {
            if showsClipChromeStub {
                VStack(spacing: 4) {
                    clipChromePill
                    captionLine
                }
            } else {
                VStack(spacing: 4) {
                    micButton
                        .frame(width: micSlotMaxWidth, alignment: .center)
                    captionLine
                }
            }
        }
    }

    /// Decorative waveform + message in one pill; does not start voice/text prompts.
    private var clipChromePill: some View {
        Button {
            onClipChromeTap()
        } label: {
            HStack(spacing: .spacing(.sp2)) {
                VoiceMemoPillWaveform(
                    isLive: false,
                    voiceLevel: 0,
                    timelineDate: .now,
                    totalWidth: 50,
                    maxBarHeight: 15,
                    gradient: idleWaveformGradient
                )
                Image(systemName: "message.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ds.textMuted)
            }
            .padding(.horizontal, .spacing(.sp3))
            .frame(height: compactSize)
            .background {
                Capsule(style: .continuous)
                    .fill(micButtonFill)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Selected clip"))
        .accessibilityHint(Text("Tap to show the default edit tools."))
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
            return isClipSelected ? "" : "Hold to talk"
        case .recording:
            return viewModel.liveTranscript.isEmpty
                ? "Listening…"
                : viewModel.liveTranscript
        case .submitting(let status):
            return status
        case .typing, .clarification, .error:
            return ""
        }
    }

    private var captionColor: Color {
        switch viewModel.phase {
        case .recording where viewModel.liveTranscript.isEmpty:
            return Color.ds.accentFg
        case .recording:
            return Color.ds.text
        case .submitting:
            return Color.ds.text
        default:
            return Color.ds.textMuted
        }
    }

    // MARK: - Mic button

    private var micButton: some View {
        ZStack {
            micCore(width: micButtonWidth, height: micButtonHeight)
                .animation(.easeInOut(duration: 0.22), value: showRecordingAccentBorder)

            if isProcessing {
                ProcessingRing(size: micButtonHeight + 12)
                    .transition(.opacity)
            }

            Group {
                if viewModel.phase == .recording {
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                        VoiceMemoPillWaveform(
                            isLive: true,
                            voiceLevel: CGFloat(viewModel.voiceLevel),
                            timelineDate: context.date,
                            totalWidth: waveformInnerWidth,
                            maxBarHeight: micButtonHeight * 0.44,
                            gradient: recordingWaveformGradient
                        )
                    }
                } else {
                    VoiceMemoPillWaveform(
                        isLive: false,
                        voiceLevel: 0,
                        timelineDate: .now,
                        totalWidth: waveformInnerWidth,
                        maxBarHeight: micButtonHeight * 0.44,
                        gradient: idleWaveformGradient
                    )
                }
            }
            .scaleEffect(isMicPressed ? 0.94 : 1.0)
            .allowsHitTesting(false)
        }
        .frame(width: micButtonWidth, height: micButtonHeight)
        .matchedGeometryEffect(id: "editor-prompt-mic", in: micNamespace)
        .contentShape(
            RoundedRectangle(cornerRadius: micButtonHeight / 2, style: .continuous)
        )
        .allowsHitTesting(!isProcessing)
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
        .accessibilityLabel(Text(isProcessing ? "Processing prompt" : "Hold to talk"))
        .accessibilityHint(Text("Press and hold to record a voice prompt."))
    }

    private var idleWaveformGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.72),
                Color.white.opacity(0.38)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var recordingWaveformGradient: LinearGradient {
        let v = CGFloat(viewModel.voiceLevel)
        return LinearGradient(
            colors: [
                Color.ds.accentBg,
                Color.ds.accentFg.opacity(0.72 + 0.22 * Double(v)),
                Color.white.opacity(0.42 + 0.22 * Double(v)),
                Color.ds.accentFg
            ],
            startPoint: UnitPoint(x: 0.02 + v * 0.1, y: 0.02),
            endPoint: UnitPoint(x: 0.98 - v * 0.06, y: 0.98)
        )
    }

    /// Border while recording: same diagonal flow as the waveform, but only
    /// accent stops (no white), so it reads as the primary chrome.
    private var recordingPrimaryBorderGradient: LinearGradient {
        let v = CGFloat(viewModel.voiceLevel)
        return LinearGradient(
            colors: [
                Color.ds.accentBg,
                Color.ds.accentFg,
                Color.ds.accentBg.opacity(0.92)
            ],
            startPoint: UnitPoint(x: 0.02 + v * 0.1, y: 0.02),
            endPoint: UnitPoint(x: 0.98 - v * 0.06, y: 0.98)
        )
    }

    /// Flat fill so the control reads slightly above the glass shell without
    /// a faux-3D gradient (a touch stronger than the chat companion).
    private var micButtonFill: Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.07)
        default:
            return Color.white.opacity(0.12)
        }
    }

    private func micCore(width: CGFloat, height: CGFloat) -> some View {
        let recording = viewModel.phase == .recording
        let accentChrome = recording && showRecordingAccentBorder
        let corner = height / 2

        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(micButtonFill)
            .overlay {
                Group {
                    if accentChrome {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                recordingPrimaryBorderGradient,
                                lineWidth: 2.35
                            )
                    } else if recording {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.1)
                    } else {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
                }
            }
            .frame(width: width, height: height)
            .scaleEffect(
                recording ? (1.0 + CGFloat(viewModel.voiceLevel) * (micUsesCapsuleShape ? 0.03 : 0.06)) : 1.0
            )
            .animation(.easeOut(duration: 0.12), value: viewModel.voiceLevel)
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
        case .submitting:
            // The mic itself shows the processing ring and the caption
            // surfaces the status text, so no extra row content is needed.
            phaseRowSpacer
        case .clarification(let message):
            HStack(spacing: .spacing(.sp2)) {
                clarificationContent(message)
                cancelButton
                chatButton
            }
            .transition(.opacity)
        case .error(let message):
            errorContent(message)
                .transition(.opacity)
        case .idle, .recording:
            phaseRowSpacer
        }
    }

    /// `Color.clear` alone expands to fill all vertical space offered by the
    /// parent `ZStack`, stretching the whole prompt bar; a zero-height spacer
    /// keeps layout hugging the mic and caption.
    private var phaseRowSpacer: some View {
        Color.clear.frame(height: 0)
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

    private func clarificationContent(_ message: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .typographyStyle(.bodySmall)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.ds.text)
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

// MARK: - Voice Memos–style pill waveform (idle silhouette / live levels)

/// Vertical pill bars in a Voice Memos–like silhouette when idle; during
/// recording, bar heights follow `voiceLevel` plus subtle motion from
/// `timelineDate`. Color comes only from `gradient`, clipped to the bars via
/// `.mask`, so the glass-style capsule behind stays translucent.
private struct VoiceMemoPillWaveform: View {
    private static let idleHeights: [CGFloat] = [
        0.14, 0.36, 0.55, 0.74, 0.90, 1.0, 0.90, 0.74, 0.55, 0.36, 0.14
    ]

    let isLive: Bool
    let voiceLevel: CGFloat
    let timelineDate: Date
    let totalWidth: CGFloat
    let maxBarHeight: CGFloat
    let gradient: LinearGradient

    private var barCount: Int {
        if isLive {
            let n = Int(totalWidth / 5.2)
            return min(36, max(18, n))
        }
        return totalWidth < 32 ? 7 : 11
    }

    var body: some View {
        let count = barCount
        let spacing: CGFloat = isLive ? 2 : 2.5
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let barWidth = max(1.5, (totalWidth - totalSpacing) / CGFloat(count))

        let barMask = HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: barWidth, height: barHeight(index: i, count: count))
            }
        }
        .frame(width: totalWidth, height: maxBarHeight)

        gradient
            .frame(width: totalWidth, height: maxBarHeight)
            .mask { barMask }
    }

    private func barHeight(index i: Int, count: Int) -> CGFloat {
        let h: CGFloat = if isLive {
            liveBarHeight(index: i, count: count)
        } else {
            idleBarHeight(index: i, count: count)
        }
        return max(2, min(maxBarHeight, h))
    }

    private func idleBarHeight(index i: Int, count: Int) -> CGFloat {
        let pattern = Self.idleHeights
        guard count > 1 else { return maxBarHeight * pattern[pattern.count / 2] }
        let t = CGFloat(i) / CGFloat(count - 1)
        let idx = t * CGFloat(pattern.count - 1)
        let i0 = Int(floor(idx))
        let i1 = min(i0 + 1, pattern.count - 1)
        let f = idx - CGFloat(i0)
        let u = pattern[i0] * (1 - f) + pattern[i1] * f
        return maxBarHeight * u * 0.9
    }

    private func liveBarHeight(index i: Int, count: Int) -> CGFloat {
        let t = Double(i) / Double(max(1, count - 1))
        let envelope = sin(Double.pi * t)
        let time = timelineDate.timeIntervalSinceReferenceDate
        let wobbleA = sin(time * 7.2 + Double(i) * 0.55)
        let wobbleB = sin(time * 5.1 - Double(i) * 0.4)
        let wobble = 0.52 + 0.48 * ((wobbleA + wobbleB) * 0.5)
        let v = max(0.03, min(1, voiceLevel))
        let floorH = 0.07 + v * 0.11
        let amp = floorH + v * CGFloat(envelope) * CGFloat(0.28 + 0.72 * wobble)
        return maxBarHeight * amp
    }
}

// MARK: - Processing ring (spins around the mic while the backend works)

private struct ProcessingRing: View {
    let size: CGFloat

    @State private var rotates = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.ds.accentFg.opacity(0.0), location: 0.0),
                        .init(color: Color.ds.accentFg.opacity(0.4), location: 0.4),
                        .init(color: Color.ds.accentFg, location: 1.0)
                    ]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotates ? 360 : 0))
            .animation(
                .linear(duration: 1.0).repeatForever(autoreverses: false),
                value: rotates
            )
            .onAppear { rotates = true }
            .accessibilityHidden(true)
    }
}
