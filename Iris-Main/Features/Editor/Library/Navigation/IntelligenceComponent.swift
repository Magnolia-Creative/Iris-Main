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

    var isTakingOver: Bool {
        if case .idle = self { return false }
        return true
    }
}

// MARK: - IntelligenceComponent

struct IntelligenceComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "navigation.intelligence"
    static let category: EditorComponentCategory = .navigation
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let size: EditorComponentSize
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

    static func intelligenceDiameter(for size: EditorComponentSize) -> CGFloat {
        switch size {
        case .compressed: 48
        case .standard: 60
        case .expanded: 68
        }
    }

    static func containerWidth(for size: EditorComponentSize, itemCount: Int = 3) -> CGFloat {
        intelligenceDiameter(for: size)
            + interControlGap
            + NavigationComponent.containerWidth(for: size, itemCount: itemCount)
    }

    static func totalHeight(for size: EditorComponentSize) -> CGFloat {
        NavigationComponent.totalHeight(for: size)
    }

    static var defaultShowcaseItems: [NavigationItem] {
        NavigationComponent.defaultShowcaseItems
    }

    private var intelligenceDiameter: CGFloat { Self.intelligenceDiameter(for: size) }
    private var takeoverWidth: CGFloat {
        Self.containerWidth(for: size, itemCount: navigationItems.count)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: Self.interControlGap) {
                intelligenceControl
                    .frame(maxWidth: .infinity, alignment: .leading)

                NavigationComponent(
                    size: size,
                    style: .glass,
                    items: navigationItems,
                    activeItemId: $activeNavigationItemId,
                    isSuppressedByIntelligence: promptPhase.isTakingOver
                )
            }
            captionLine
        }
        .frame(width: takeoverWidth)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: promptPhase)
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

    // MARK: - Layout

    private func targetPillWidth(for phase: IntelligencePromptPhase) -> CGFloat {
        switch phase {
        case .idle:
            return intelligenceDiameter
        case .recording, .typing, .submitting, .clarification, .error:
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

    private var processingRevealCancelThreshold: CGFloat { pillHeight + 8 }

    private var showWaveformInChrome: Bool {
        switch promptPhase {
        case .recording:
            return true
        case .submitting:
            return animatedPillWidth > processingRevealCancelThreshold
        default:
            return false
        }
    }

    private var showProcessingCancelButton: Bool {
        isProcessing && animatedPillWidth <= processingRevealCancelThreshold
    }

    // MARK: - Intelligence control

    private var intelligenceControl: some View {
        Group {
            switch promptPhase {
            case .typing:
                typingRow
            case .clarification(let message):
                clarificationRow(message)
            case .error(let message):
                errorRow(message)
            case .idle, .recording, .submitting:
                intelligenceButton
            }
        }
        .frame(width: animatedPillWidth, alignment: .leading)
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

            if showProcessingCancelButton {
                processingCancelButton
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: showProcessingCancelButton)
        .frame(width: animatedPillWidth, height: pillHeight)
        .contentShape(RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous))

        return Group {
            if isProcessing {
                core
            } else if case .idle = promptPhase {
                core
                    .gesture(intelligenceGesture)
                    .accessibilityLabel(Text("Intelligence"))
                    .accessibilityHint(Text("Tap to type a prompt. Press and hold to record a voice prompt."))
            } else if case .recording = promptPhase {
                core
                    .gesture(intelligenceGesture)
                    .accessibilityLabel(Text("Recording"))
            } else {
                core
            }
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
        switch size {
        case .compressed: 20
        case .standard: 24
        case .expanded: 26
        }
    }

    private var intelligenceGesture: some Gesture {
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
                } else if case .idle = promptPhase {
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

    private var processingCancelButton: some View {
        Button(action: onCancelProcessing) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.ds.textMuted)
                .frame(width: animatedPillWidth, height: pillHeight)
                .contentShape(RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Cancel processing"))
    }

    // MARK: - Expanded phase rows

    private var typingRow: some View {
        HStack(spacing: .spacing(.sp2)) {
            typingField
            compactIconButton(systemName: "xmark", action: onCancelText)
            compactIconButton(systemName: "arrow.up", accent: true, action: onSubmitText)
        }
        .frame(width: takeoverWidth, alignment: .leading)
    }

    private func clarificationRow(_ message: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .typographyStyle(.bodySmall)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            compactIconButton(systemName: "xmark", action: onCancelText)
            compactIconButton(systemName: "message.fill", action: onIntelligenceTap)
        }
        .foregroundStyle(Color.ds.text)
        .padding(.horizontal, .spacing(.sp2))
        .frame(width: takeoverWidth, height: pillHeight, alignment: .leading)
        .background(pillFill)
        .clipShape(RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous))
        .overlay(rotatingAccentBorder(cornerRadius: pillHeight / 2, lineWidth: 1.5, opacity: 0.55))
    }

    private func errorRow(_ message: String) -> some View {
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
        .frame(width: takeoverWidth, height: pillHeight, alignment: .leading)
        .background(pillFill)
        .clipShape(RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous))
        .overlay(rotatingAccentBorder(cornerRadius: pillHeight / 2, lineWidth: 1.5, opacity: 0.45))
    }

    private var typingField: some View {
        TextField("Describe your edit…", text: $promptDraft, axis: .vertical)
            .typographyStyle(.body)
            .foregroundStyle(Color.ds.text)
            .tint(Color.ds.accentFg)
            .lineLimit(1...2)
            .focused($isPromptFocused)
            .submitLabel(.send)
            .onSubmit(onSubmitText)
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
        switch size {
        case .compressed: 32
        case .standard: 38
        case .expanded: 42
        }
    }

    // MARK: - Caption

    private var captionLine: some View {
        Text(captionText)
            .typographyStyle(.bodySmall)
            .foregroundStyle(captionColor)
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .frame(maxWidth: takeoverWidth)
            .opacity(captionText.isEmpty ? 0 : 1)
            .frame(height: captionText.isEmpty ? 0 : nil)
            .animation(.easeOut(duration: 0.15), value: captionText.isEmpty)
            .transaction { transaction in
                if promptPhase == .recording {
                    transaction.animation = nil
                }
            }
    }

    private var captionText: String {
        switch promptPhase {
        case .idle:
            return "Tap to type · Hold to talk"
        case .recording:
            return liveTranscript.isEmpty ? "Listening…" : liveTranscript
        case .submitting(let status):
            return status
        case .typing, .clarification, .error:
            return ""
        }
    }

    private var captionColor: Color {
        switch promptPhase {
        case .recording where liveTranscript.isEmpty:
            return Color.ds.accentFg
        case .recording, .submitting:
            return Color.ds.text
        default:
            return Color.ds.textMuted
        }
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
                    } else if isProcessing {
                        rotatingAccentBorder(cornerRadius: corner, lineWidth: 2.35, opacity: 1.0)
                    } else if recording {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.1)
                    } else {
                        rotatingAccentBorder(cornerRadius: corner, lineWidth: 1.8, opacity: 0.72)
                    }
                }
            }
            .frame(width: width, height: height)
            .scaleEffect(
                recording ? (1.0 + CGFloat(voiceLevel) * (pillUsesCapsuleShape ? 0.03 : 0.06)) : 1.0
            )
            .animation(.easeOut(duration: 0.12), value: voiceLevel)
    }

    private func rotatingAccentBorder(cornerRadius: CGFloat, lineWidth: CGFloat, opacity: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { context in
            let degrees = context.date.timeIntervalSinceReferenceDate * (360.0 / 2.6)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(processingAngularBorderGradient, lineWidth: lineWidth)
                .rotationEffect(.degrees(degrees))
                .opacity(opacity)
        }
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

    private var processingAngularBorderGradient: AngularGradient {
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
            angle: .degrees(0)
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
