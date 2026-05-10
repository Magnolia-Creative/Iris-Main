import SwiftUI

struct TimelineCompilerTestView: View {
    @StateObject private var viewModel = TimelineCompilerTestViewModel()

    var body: some View {
        ZStack {
            Color.ds.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                    promptSection
                    contextSection
                    outputSection
                }
                .padding(.horizontal, .sp6)
                .padding(.vertical, .sp6)
            }
        }
        .navigationTitle("Timeline Compiler")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension TimelineCompilerTestView {
    var promptSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Prompt")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if viewModel.canConfigureLLMBackend {
                Picker("LLM backend", selection: $viewModel.llmBackend) {
                    ForEach(TimelineLLMBackend.selectableCases) { backend in
                        Text(backend.title).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
            }

            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .foregroundStyle(Color.ds.text)
                .frame(minHeight: 108)
                .padding(.sp3)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                .overlay {
                    RoundedRectangle(cornerRadius: .spacing(.sp3))
                        .stroke(Color.ds.border, lineWidth: 1)
                }

            Button {
                Task {
                    await viewModel.compilePrompt()
                }
            } label: {
                HStack(spacing: .spacing(.sp2)) {
                    if viewModel.isCompiling {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.branch")
                    }

                    Text(viewModel.isCompiling ? "Compiling..." : "Compile Prompt")
                        .typography(.action)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, .sp3)
                .foregroundStyle(Color.white)
                .background(Color.ds.accentBg)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCompiling)
        }
    }

    var contextSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Sample Context")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            Text(viewModel.sampleContextSummary)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.ds.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.sp4)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                .overlay {
                    RoundedRectangle(cornerRadius: .spacing(.sp3))
                        .stroke(Color.ds.border, lineWidth: 1)
                }
        }
    }

    var outputSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Compiler Output")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .typography(.body)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.sp4)
                    .background(Color.ds.surface)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
            } else if viewModel.outputText.isEmpty {
                Text("Compile a prompt to see generated actions, confidence, source, warnings, and clarification state.")
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
                .overlay {
                    RoundedRectangle(cornerRadius: .spacing(.sp3))
                        .stroke(Color.ds.border, lineWidth: 1)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TimelineCompilerTestView()
    }
}
