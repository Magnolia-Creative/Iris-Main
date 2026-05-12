import SwiftUI

struct EditorPromptBarView: View {
    @ObservedObject var viewModel: EditorPromptBarViewModel
    let isClipSelected: Bool
    let micNamespace: Namespace.ID

    @FocusState private var isPromptFocused: Bool
    @State private var isPressingMic = false

    private let compactButtonSize: CGFloat = 42
    private let expandedButtonSize: CGFloat = 64

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle:
                idleLayout
            case .recording:
                recordingLayout
            case .typing:
                typingLayout
            case .submitting(let status):
                statusLayout(status)
            case .error(let message):
                errorLayout(message)
            }
        }
        .frame(minHeight: expandedButtonSize)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.phase)
        .onChange(of: viewModel.phase) { _, phase in
            isPromptFocused = phase == .typing
        }
        .onDisappear {
            viewModel.tearDown()
        }
    }

    @ViewBuilder
    private var idleLayout: some View {
        if isClipSelected {
            HStack(spacing: .spacing(.sp2)) {
                micButton(size: compactButtonSize, isExpanded: false)
                chatButton(size: compactButtonSize)
            }
        } else {
            ZStack {
                micButton(size: expandedButtonSize, isExpanded: true)
                    .frame(maxWidth: .infinity, alignment: .center)

                chatButton(size: compactButtonSize)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var recordingLayout: some View {
        ZStack {
            micButton(size: expandedButtonSize, isExpanded: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var typingLayout: some View {
        HStack(spacing: .spacing(.sp2)) {
            TextField("Describe your edit...", text: $viewModel.promptDraft, axis: .vertical)
                .typography(.body)
                .foregroundStyle(Color.ds.text)
                .lineLimit(1...3)
                .focused($isPromptFocused)
                .submitLabel(.send)
                .onSubmit {
                    Task { await viewModel.submitTextPrompt() }
                }
                .padding(.horizontal, .spacing(.sp3))
                .padding(.vertical, .spacing(.sp2))
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))

            Button {
                Task { await viewModel.submitTextPrompt() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.ds.accentFg)
                    .frame(width: compactButtonSize, height: compactButtonSize)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.cancelTextPrompt()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.ds.textMuted)
                    .frame(width: compactButtonSize, height: compactButtonSize)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusLayout(_ status: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            ProgressView()
                .controlSize(.small)
            Text(status)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorLayout(_ message: String) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .typography(.bodySmall)
                .lineLimit(2)
        }
        .foregroundStyle(Color.ds.danger)
        .frame(maxWidth: .infinity)
    }

    private func micButton(size: CGFloat, isExpanded: Bool) -> some View {
        ZStack {
            if viewModel.phase == .recording {
                micGlow(size: size)
            }

            Circle()
                .fill(Color.white.opacity(isExpanded ? 0.14 : 0.08))
                .overlay {
                    Circle()
                        .stroke(Color.ds.accentFg.opacity(isExpanded ? 0.85 : 0.35), lineWidth: isExpanded ? 2 : 1)
                }
                .frame(width: size, height: size)

            Image(systemName: "mic.fill")
                .font(.system(size: isExpanded ? 28 : 18, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: size + glowOutset, height: size + glowOutset)
        .matchedGeometryEffect(id: "editor-prompt-mic", in: micNamespace)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressingMic else { return }
                    isPressingMic = true
                    Task { await viewModel.beginVoicePrompt() }
                }
                .onEnded { _ in
                    isPressingMic = false
                    Task { await viewModel.endVoicePrompt() }
                }
        )
        .accessibilityLabel(Text("Voice prompt"))
    }

    private func chatButton(size: CGFloat) -> some View {
        Button {
            viewModel.openTextPrompt()
        } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ds.textMuted)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Type prompt"))
    }

    private func micGlow(size: CGFloat) -> some View {
        let level = CGFloat(viewModel.voiceLevel)
        return ZStack {
            Circle()
                .fill(Color.ds.accentBg.opacity(0.20 + level * 0.24))
                .frame(width: size + 12 + level * 34, height: size + 12 + level * 34)
                .blur(radius: 10 + level * 8)
            Circle()
                .stroke(Color.ds.accentFg.opacity(0.28 + level * 0.35), lineWidth: 2)
                .frame(width: size + 8 + level * 24, height: size + 8 + level * 24)
        }
        .animation(.easeOut(duration: 0.08), value: viewModel.voiceLevel)
    }

    private var glowOutset: CGFloat {
        viewModel.phase == .recording ? 42 : 0
    }
}
