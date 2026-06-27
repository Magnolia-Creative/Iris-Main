import SwiftUI

struct EditorIntentCompilerDiagnosticsView: View {
    @StateObject private var viewModel = EditorIntentCompilerDiagnosticsViewModel()

    @State private var currentTimeUs: Int64 = 1_500_000
    @State private var timelinePixelsPerSecond: CGFloat = TimelineComponentLayout.defaultPixelsPerSecond
    @State private var selectedSegmentId: String?
    @State private var isAddMenuOpen = false
    @State private var isPlaying = false
    @State private var showAspectSettings = false
    @State private var activeNavItemId = "Edit"
    @State private var promptPhase: IntelligencePromptPhase = .idle
    @State private var promptDraft = ""
    @State private var activeParameterGroupId = EditorChromePreviewFixtures.colorGroup.id
    @State private var parameterValues: [String: EditorParameterValue] = EditorChromePreviewFixtures.seedValues(
        for: EditorChromePreviewFixtures.parameterGroups(for: .fourPlusGroups)
    )
    @State private var expandedClipToolId: Int?
    @State private var clipColorFilter: ClipColorFilter = .neutral
    @State private var clipVolume: ClipVolume = .neutral

    var body: some View {
        ZStack {
            Color.ds.bg.ignoresSafeArea()

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                    header
                    promptSection
                    contextSection
                    outputSection
                    renderSection
                }
                .padding(.horizontal, .spacing(.sp5))
                .padding(.vertical, .spacing(.sp5))
            }
        }
        .navigationTitle("UI Intent Compiler")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.selectedContextId) { _, _ in
            viewModel.resetToSelectedContext()
            syncParameterValues()
        }
        .onChange(of: viewModel.renderState.id) { _, _ in
            syncParameterValues()
        }
        .onAppear {
            syncParameterValues()
        }
    }
}

typealias UIIntentDemoView = EditorIntentCompilerDiagnosticsView

private extension EditorIntentCompilerDiagnosticsView {
    var header: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Natural-Language UI Compiler")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)
            Text("Type a workspace request and inspect the local compiler's pseudo schema before anything touches the live editor.")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
    }

    var promptSection: some View {
        surfaceSection {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text("Prompt")
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)

                TextEditor(text: $viewModel.prompt)
                    .font(.body)
                    .foregroundStyle(Color.ds.text)
                    .frame(minHeight: 96)
                    .padding(.spacing(.sp3))
                    .background(Color.ds.bg.opacity(0.5))
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
                        Image(systemName: "arrow.triangle.branch")
                        Text("Compile Locally")
                            .typography(.action)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .spacing(.sp3))
                    .foregroundStyle(Color.white)
                    .background(Color.ds.accentBg)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                }
                .buttonStyle(.plain)

                HStack {
                    resultBadge
                    Text(viewModel.statusMessage)
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.textMuted)
                        .lineLimit(2)
                }
            }
        }
    }

    var contextSection: some View {
        surfaceSection {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text("Sample Context")
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)

                Picker("Context", selection: $viewModel.selectedContextId) {
                    ForEach(viewModel.contexts) { context in
                        Text(context.title).tag(context.id)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.sampleContextSummary)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.ds.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var outputSection: some View {
        surfaceSection {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text("Compiler Output")
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)

                if viewModel.outputText.isEmpty {
                    Text("Compile a prompt to see normalization, candidate scores, selected pseudo schema, validation warnings, or remote handoff data.")
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.textMuted)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(viewModel.outputText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.ds.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.spacing(.sp3))
                    }
                    .background(Color.ds.bg.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                }
            }
        }
    }

    var renderSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            HStack {
                Text("Pseudo UI Render")
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)
                Spacer()
                Text(viewModel.validationResult.isValid ? "Valid" : "Invalid")
                    .typography(.bodySmall)
                    .foregroundStyle(viewModel.validationResult.isValid ? Color.ds.accentFg : Color.ds.danger)
            }

            if viewModel.validationResult.isValid {
                EditorJITRenderView(
                    state: viewModel.renderState,
                    transitionPlans: viewModel.transitionPlans,
                    currentTimeUs: $currentTimeUs,
                    timelinePixelsPerSecond: $timelinePixelsPerSecond,
                    selectedSegmentId: $selectedSegmentId,
                    isAddMenuOpen: $isAddMenuOpen,
                    isPlaying: $isPlaying,
                    showAspectSettings: $showAspectSettings,
                    activeParameterGroupId: $activeParameterGroupId,
                    parameterValues: $parameterValues,
                    activeNavItemId: $activeNavItemId,
                    promptPhase: $promptPhase,
                    promptDraft: $promptDraft,
                    clipColorFilter: $clipColorFilter,
                    clipVolume: $clipVolume
                )
                .frame(minHeight: 520)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)
                        .stroke(Color.ds.border.opacity(0.35), lineWidth: 1)
                }
            } else {
                Text(viewModel.validationResult.errors.joined(separator: "\n"))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                    .background(Color.ds.surface.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
            }
        }
    }

    var resultBadge: some View {
        Text(viewModel.resultKind)
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.accentFg)
            .padding(.horizontal, .spacing(.sp2))
            .padding(.vertical, .spacing(.sp1))
            .background(Color.ds.accentFg.opacity(0.12))
            .clipShape(Capsule())
    }

    func surfaceSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.spacing(.sp4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ds.surface.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)
                    .stroke(Color.ds.border.opacity(0.35), lineWidth: 1)
            }
    }

    func syncParameterValues() {
        let groups = viewModel.renderState.chromePlan.parameterGroups
        parameterValues = EditorChromePreviewFixtures.seedValues(for: groups)
        if let activeId = viewModel.renderState.chromePlan.activeParameterGroupId,
           groups.contains(where: { $0.id == activeId }) {
            activeParameterGroupId = activeId
        } else {
            activeParameterGroupId = groups.first?.id ?? ""
        }
    }
}

#Preview {
    NavigationStack {
        EditorIntentCompilerDiagnosticsView()
    }
}
