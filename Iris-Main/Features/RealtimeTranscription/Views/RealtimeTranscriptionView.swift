import SwiftUI

struct RealtimeTranscriptionView: View {
    @StateObject private var viewModel = RealtimeTranscriptionViewModel()

    var body: some View {
        ZStack {
            Color.ds.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: .spacing(.sp6))

                microphoneButton

                Spacer(minLength: .spacing(.sp5))

                transcriptSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, .sp6)
            .padding(.bottom, .sp6)
        }
        .onDisappear {
            viewModel.tearDown()
        }
    }

    private var microphoneButton: some View {
        Button {
            Task {
                await viewModel.toggleRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.isRecording ? Color.red.opacity(0.22) : Color.ds.surface)
                    .frame(width: 120, height: 120)
                    .overlay {
                        Circle()
                            .stroke(
                                viewModel.isRecording ? Color.red.opacity(0.55) : Color.ds.border,
                                lineWidth: 2
                            )
                    }

                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(viewModel.isRecording ? Color.red : Color.ds.accentFg)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isRecording ? "Stop transcription" : "Start transcription")
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Transcription")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            Text(viewModel.statusMessage)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            if let error = viewModel.errorMessage {
                Text(error)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    if !viewModel.finalizedTranscript.isEmpty {
                        Text(viewModel.finalizedTranscript)
                            .typography(.body)
                            .foregroundStyle(Color.ds.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !viewModel.partialTranscript.isEmpty {
                        Text(viewModel.partialTranscript)
                            .typography(.body)
                            .foregroundStyle(Color.ds.text.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if viewModel.finalizedTranscript.isEmpty, viewModel.partialTranscript.isEmpty {
                        Text("Live text appears here as you speak.")
                            .typography(.body)
                            .foregroundStyle(Color.ds.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160)
        }
        .padding(.sp5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ds.surface)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
        .overlay {
            RoundedRectangle(cornerRadius: .spacing(.sp4))
                .stroke(Color.ds.border, lineWidth: 1)
        }
    }
}

#Preview {
    NavigationStack {
        RealtimeTranscriptionView()
            .navigationTitle("Live transcription")
    }
}
