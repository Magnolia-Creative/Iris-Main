import SwiftUI

struct VoiceIntentCompilerView: View {
    @StateObject private var viewModel = VoiceIntentCompilerViewModel()

    var body: some View {
        ZStack {
            Color.ds.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                    microphoneButton
                    transcriptSection
                    outputSection
                }
                .padding(.horizontal, .sp6)
                .padding(.vertical, .sp6)
            }
        }
        .navigationTitle("Voice Intent")
        .navigationBarTitleDisplayMode(.inline)
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
            HStack(spacing: .spacing(.sp3)) {
                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                Text(viewModel.isRecording ? "Finish Prompt" : "Start Voice Prompt")
                    .typography(.action)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .sp4)
            .foregroundStyle(Color.white)
            .background(viewModel.isRecording ? Color.red.opacity(0.85) : Color.ds.accentBg)
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        }
        .buttonStyle(.plain)
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Spoken Prompt")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            Text(viewModel.statusMessage)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            if viewModel.audioChunkCount > 0 {
                Text("\(viewModel.audioChunkCount) audio chunks sent")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                if !viewModel.finalizedTranscript.isEmpty {
                    Text(viewModel.finalizedTranscript)
                        .typography(.body)
                        .foregroundStyle(Color.ds.text)
                }

                if !viewModel.partialTranscript.isEmpty {
                    Text(viewModel.partialTranscript)
                        .typography(.body)
                        .foregroundStyle(Color.ds.text.opacity(0.85))
                }

                if viewModel.finalizedTranscript.isEmpty, viewModel.partialTranscript.isEmpty {
                    Text("Try saying: make this clip feel more vintage.")
                        .typography(.body)
                        .foregroundStyle(Color.ds.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.sp4)
            .background(Color.ds.surface)
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Effect Result")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if viewModel.outputText.isEmpty {
                Text("Final IntentCompileResult JSON appears here after processing.")
                    .typography(.body)
                    .foregroundStyle(Color.ds.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.sp4)
                    .background(Color.ds.surface)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(viewModel.outputText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.ds.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.sp4)
                }
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
            }
        }
    }
}

#Preview {
    NavigationStack {
        VoiceIntentCompilerView()
    }
}

