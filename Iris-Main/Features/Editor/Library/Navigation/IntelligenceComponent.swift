import SwiftUI

// Library-only navigation dock: intelligence prompt entry + bottom navigation.
// Shell integration is intentionally deferred — adapt app state into the bindings
// and callbacks below from `EditorContainerView` in a later slice without changing
// this component's API or imports.

// MARK: - Models

enum IntelligencePromptPhase: Equatable {
    case idle
    case recording
    case typing
    case submitting(String)
    case clarification(String)
    case error(String)

    /// Dock stays visually idle during typing; the keyboard overlay owns that phase.
    var isDockExpanded: Bool {
        switch self {
        case .idle, .typing:
            return false
        default:
            return true
        }
    }
}

// MARK: - IntelligenceComponent

struct IntelligenceComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "navigation.intelligence"
    static let category: EditorComponentCategory = .navigation
    static let supportedSizes: Set<EditorComponentSize> = [.standard]

    let navigationItems: [NavigationItem]
    @Binding var activeNavigationItemId: String
    @Binding var promptPhase: IntelligencePromptPhase
    @Binding var promptDraft: String
    let liveTranscript: String
    let voiceLevel: Float

    let onIntelligenceTap: () -> Void
    let onVoiceHoldStart: () -> Void
    let onVoiceHoldEnd: () -> Void
    let onSubmitText: () -> Void
    let onCancelText: () -> Void
    let onCancelProcessing: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isPromptFocused: Bool

    @State private var isIntelligencePressed = false
    @State private var didActivateVoiceHold = false
    @State private var voiceHoldTask: Task<Void, Never>?
    @State private var showRecordingAccentBorder = false
    @State private var animatedPillWidth: CGFloat = 60

    private static let interControlGap: CGFloat = .spacing(.sp3)
    private static let voiceHoldThresholdMs: UInt64 = 250

    static let intelligenceDiameter: CGFloat = 60

    static func containerWidth(itemCount: Int = 3) -> CGFloat {
        intelligenceDiameter
            + interControlGap
            + NavigationComponent.containerWidth(itemCount: itemCount)
    }

    static func totalHeight() -> CGFloat {
        NavigationComponent.totalHeight()
    }

    static var defaultShowcaseItems: [NavigationItem] {
        NavigationComponent.defaultShowcaseItems
    }

    private var intelligenceDiameter: CGFloat { Self.intelligenceDiameter }
    private var takeoverWidth: CGFloat {
        Self.containerWidth(itemCount: navigationItems.count)
    }

    private var isTypingPresented: Binding<Bool> {
        Binding(
            get: { promptPhase == .typing },
            set: { isPresented in
                if !isPresented, promptPhase == .typing {
                    onCancelText()
                }
            }
        )
    }

    var body: some View {
        dockRow
            .frame(width: takeoverWidth, alignment: .leading)
            .frame(height: pillHeight, alignment: .center)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: promptPhase)
            .fullScreenCover(isPresented: isTypingPresented) {
                typingOverlay
                    .presentationBackground(.clear)
            }
            .onAppear {
                animatedPillWidth = targetPillWidth(for: promptPhase)
            }
            .onChange(of: promptPhase) { _, phase in
                isPromptFocused = (phase == .typing)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                    animatedPillWidth = targetPillWidth(for: phase)
                }
                if phase == .recording {
                    showRecordingAccentBorder = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        guard promptPhase == .recording else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showRecordingAccentBorder = true
                        }
                    }
                } else {
                    showRecordingAccentBorder = false
                }
            }
    }

    // MARK: - Dock row

    private var dockRow: some View {
        HStack(spacing: Self.interControlGap) {
            intelligenceControl
                .frame(width: animatedPillWidth, alignment: .leading)

            if !promptPhase.isDockExpanded {
                NavigationComponent(
                    style: .glass,
                    items: navigationItems,
                    activeItemId: $activeNavigationItemId
                )
            }
        }
        .frame(height: pillHeight, alignment: .center)
    }

    // MARK: - Layout

    private func targetPillWidth(for phase: IntelligencePromptPhase) -> CGFloat {
        switch phase {
        case .idle, .typing:
            return intelligenceDiameter
        case .recording, .submitting, .clarification, .error:
            return takeoverWidth
        }
    }

    private var pillHeight: CGFloat { intelligenceDiameter }

    private var pillUsesCapsuleShape: Bool {
        animatedPillWidth > pillHeight + 2
    }

    private var waveformInnerWidth: CGFloat {
        let inset = pillUsesCapsuleShape ? 14.0 : 10.0
        return max(10, animatedPillWidth - inset * 2)
    }

    private var isProcessing: Bool {
        if case .submitting = promptPhase { return true }
        return false
    }

    private var expandedContentOpacity: Double {
        animatedPillWidth > pillHeight + 24 ? 1 : 0
    }

    private var showWaveformInChrome: Bool {
        switch promptPhase {
        case .recording:
            return true
        default:
            return false
        }
    }

    // MARK: - Intelligence control

    @ViewBuilder
    private var intelligenceControl: some View {
        intelligenceButton
    }

    private var intelligenceButton: some View {
        let core = ZStack {
            pillCore(width: animatedPillWidth, height: pillHeight)
                .animation(.easeInOut(duration: 0.22), value: showRecordingAccentBorder)

            if showWaveformInChrome {
                waveformContent
                    .transition(.opacity)
            } else if case .idle = promptPhase {
                idleIcon
                    .transition(.opacity)
            }

            if promptPhase == .recording {
                recordingTranscriptOverlay
            }

            if case .submitting(let status) = promptPhase {
                submittingStatusOverlay(status)
            }

            if case .clarification(let message) = promptPhase {
                clarificationContent(message)
            }

            if case .error(let message) = promptPhase {
                errorContent(message)
            }
        }
        .frame(width: animatedPillWidth, height: pillHeight)
        .clipShape(RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous))

        return Group {
            if isProcessing {
                core
            } else if allowsIntelligenceGesture {
                core
                    .gesture(intelligenceGesture(allowsTap: allowsTapInCurrentPhase))
                    .accessibilityLabel(Text(accessibilityLabelForPhase))
                    .accessibilityHint(Text(accessibilityHintForPhase))
            } else {
                core
            }
        }
    }

    private var allowsIntelligenceGesture: Bool {
        switch promptPhase {
        case .idle, .recording, .clarification:
            return true
        default:
            return false
        }
    }

    private var allowsTapInCurrentPhase: Bool {
        switch promptPhase {
        case .idle, .clarification:
            return true
        case .recording:
            return false
        default:
            return false
        }
    }

    private var accessibilityLabelForPhase: String {
        switch promptPhase {
        case .recording: "Recording"
        case .clarification: "Clarification"
        default: "Intelligence"
        }
    }

    private var accessibilityHintForPhase: String {
        switch promptPhase {
        case .clarification:
            return "Tap to type a response. Press and hold to record a response."
        default:
            return "Tap to type a prompt. Press and hold to record a voice prompt."
        }
    }

    private var idleIcon: some View {
        Image(systemName: "wand.and.stars")
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.88))
            .scaleEffect(isIntelligencePressed ? 0.94 : 1.0)
            .allowsHitTesting(false)
    }

    private var iconSize: CGFloat {
        24
    }

    private func intelligenceGesture(allowsTap: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isIntelligencePressed else { return }
                isIntelligencePressed = true
                voiceHoldTask?.cancel()
                voiceHoldTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.voiceHoldThresholdMs * 1_000_000)
                    guard !Task.isCancelled, isIntelligencePressed else { return }
                    didActivateVoiceHold = true
                    onVoiceHoldStart()
                }
            }
            .onEnded { _ in
                isIntelligencePressed = false
                voiceHoldTask?.cancel()
                voiceHoldTask = nil
                if didActivateVoiceHold {
                    didActivateVoiceHold = false
                    onVoiceHoldEnd()
                } else if allowsTap {
                    onIntelligenceTap()
                }
            }
    }

    private var waveformContent: some View {
        Group {
            if promptPhase == .recording {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    IntelligencePillWaveform(
                        isLive: true,
                        voiceLevel: CGFloat(voiceLevel),
                        timelineDate: context.date,
                        totalWidth: waveformInnerWidth,
                        maxBarHeight: pillHeight * 0.44,
                        gradient: recordingWaveformGradient
                    )
                }
            } else {
                IntelligencePillWaveform(
                    isLive: false,
                    voiceLevel: 0,
                    timelineDate: .now,
                    totalWidth: waveformInnerWidth,
                    maxBarHeight: pillHeight * 0.44,
                    gradient: idleWaveformGradient
                )
            }
        }
        .scaleEffect(isIntelligencePressed ? 0.94 : 1.0)
        .allowsHitTesting(false)
    }

    private var recordingTranscriptOverlay: some View {
        let text = liveTranscript.isEmpty ? "Listening…" : liveTranscript
        let isPlaceholder = liveTranscript.isEmpty

        return Text(text)
            .typographyStyle(.bodySmall)
            .foregroundStyle(isPlaceholder ? Color.ds.accentFg : Color.ds.text)
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .padding(.horizontal, .spacing(.sp2))
            .padding(.vertical, .spacing(.sp1))
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.42 : 0.28))
            )
            .padding(.horizontal, pillUsesCapsuleShape ? 12 : 8)
            .allowsHitTesting(false)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private func submittingStatusOverlay(_ status: String) -> some View {
        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = transcript.isEmpty ? status : transcript

        return Text(text)
            .typographyStyle(.bodySmall)
            .foregroundStyle(Color.ds.text)
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .padding(.horizontal, .spacing(.sp2))
            .padding(.horizontal, 12)
            .opacity(expandedContentOpacity)
            .allowsHitTesting(false)
    }

    // MARK: - Clarify / error pills

    private func clarificationContent(_ message: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            leadingIntelligenceIcon
            Text(message)
                .typographyStyle(.bodySmall)
                .foregroundStyle(Color.ds.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .opacity(expandedContentOpacity)
            Spacer(minLength: 0)
        }
        .frame(width: animatedPillWidth, height: pillHeight, alignment: .leading)
        .padding(.trailing, .spacing(.sp2))
        .allowsHitTesting(false)
    }

    private func errorContent(_ message: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            leadingErrorIcon
            Text(message)
                .typographyStyle(.bodySmall)
                .foregroundStyle(Color.ds.danger)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .opacity(expandedContentOpacity)
            Spacer(minLength: 0)
        }
        .frame(width: animatedPillWidth, height: pillHeight, alignment: .leading)
        .padding(.trailing, .spacing(.sp2))
        .allowsHitTesting(false)
    }

    private var leadingIntelligenceIcon: some View {
        Image(systemName: "wand.and.stars")
            .font(.system(size: iconSize * 0.85, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.88))
            .scaleEffect(isIntelligencePressed ? 0.94 : 1.0)
            .frame(width: pillHeight, height: pillHeight)
            .allowsHitTesting(false)
    }

    private var leadingErrorIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.ds.danger)
            .frame(width: pillHeight, height: pillHeight)
            .allowsHitTesting(false)
    }

    // MARK: - Typing overlay

    private var typingOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18)
                .ignoresSafeArea()
                .onTapGesture { onCancelText() }

            typingGlowBackdrop
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)

            typingComposerBar
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var typingGlowBackdrop: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.ds.accentBg.opacity(colorScheme == .dark ? 0.18 : 0.12),
                Color.ds.accentFg.opacity(colorScheme == .dark ? 0.28 : 0.2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .allowsHitTesting(false)
    }

    private var typingComposerBar: some View {
        HStack(spacing: .spacing(.sp2)) {
            TextField("Describe your edit…", text: $promptDraft, axis: .vertical)
                .typographyStyle(.body)
                .foregroundStyle(Color.ds.text)
                .tint(Color.ds.accentFg)
                .lineLimit(1...4)
                .focused($isPromptFocused)
                .submitLabel(.send)
                .onSubmit(onSubmitText)

            compactIconButton(systemName: "xmark", action: onCancelText)
            compactIconButton(systemName: "arrow.up", accent: true, action: onSubmitText)
        }
        .padding(.horizontal, .spacing(.sp3))
        .padding(.vertical, .spacing(.sp2))
        .background(
            RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)
                .fill(Color.ds.bg.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.22), lineWidth: 1)
        )
        .padding(.horizontal, .spacing(.sp3))
        .padding(.bottom, .spacing(.sp2))
    }

    private func compactIconButton(
        systemName: String,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: accent ? 18 : 14, weight: .bold))
                .foregroundStyle(accent ? Color.white : Color.ds.textMuted)
                .frame(width: compactButtonSize, height: compactButtonSize)
                .background {
                    if accent {
                        LinearGradient(
                            colors: [Color.ds.accentBg, Color.ds.accentFg],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var compactButtonSize: CGFloat {
        38
    }

    // MARK: - Pill chrome

    private var pillFill: Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.07)
        default:
            return Color.white.opacity(0.12)
        }
    }

    private func pillCore(width: CGFloat, height: CGFloat) -> some View {
        let recording = promptPhase == .recording
        let accentChrome = recording && showRecordingAccentBorder
        let corner = height / 2

        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(pillFill)
            .overlay {
                Group {
                    if accentChrome {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(recordingBorderGradient, lineWidth: 2.35)
                    } else if case .error = promptPhase {
                        errorBorderOverlay(cornerRadius: corner, lineWidth: 2.2)
                    } else if isProcessing {
                        accentBorderOverlay(cornerRadius: corner, lineWidth: 2.35, opacity: 1.0, animated: true)
                    } else if recording {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.1)
                    } else {
                        accentBorderOverlay(cornerRadius: corner, lineWidth: 1.8, opacity: 0.72, animated: true)
                    }
                }
            }
            .frame(width: width, height: height)
    }

    private func accentBorderOverlay(
        cornerRadius: CGFloat,
        lineWidth: CGFloat,
        opacity: Double,
        animated: Bool = false
    ) -> some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { context in
                    let degrees = context.date.timeIntervalSinceReferenceDate * (360.0 / 2.6)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(processingAngularBorderGradient(angle: .degrees(degrees)), lineWidth: lineWidth)
                        .opacity(opacity)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(processingAngularBorderGradient(angle: .degrees(0)), lineWidth: lineWidth)
                    .opacity(opacity)
            }
        }
    }

    private func errorBorderOverlay(cornerRadius: CGFloat, lineWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.ds.danger.opacity(0.95),
                        Color.ds.danger.opacity(0.55),
                        Color.ds.danger.opacity(0.95)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: lineWidth
            )
            .shadow(color: Color.ds.danger.opacity(0.45), radius: 6, x: 0, y: 0)
    }

    private var idleWaveformGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.72), Color.white.opacity(0.38)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var recordingWaveformGradient: LinearGradient {
        let v = CGFloat(voiceLevel)
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

    private var recordingBorderGradient: LinearGradient {
        let v = CGFloat(voiceLevel)
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

    private func processingAngularBorderGradient(angle: Angle) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: Color.ds.accentBg, location: 0.0),
                .init(color: Color.ds.accentBg.opacity(0.55), location: 0.18),
                .init(color: Color.ds.accentFg, location: 0.32),
                .init(color: Color.ds.accentBg.opacity(0.92), location: 0.46),
                .init(color: Color.ds.accentBg, location: 0.62),
                .init(color: Color.ds.accentBg.opacity(0.45), location: 0.78),
                .init(color: Color.ds.accentBg, location: 1.0)
            ]),
            center: .center,
            angle: angle
        )
    }
}

// MARK: - Waveform

private struct IntelligencePillWaveform: View {
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
