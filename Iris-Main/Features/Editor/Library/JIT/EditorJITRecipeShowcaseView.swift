import SwiftUI

struct EditorJITRecipeShowcaseView: View {
    @StateObject private var viewModel = EditorJITRecipeShowcaseViewModel()

    @State private var currentTimeUs: Int64 = 1_500_000
    @State private var timelinePixelsPerSecond: CGFloat = TimelineComponentLayout.defaultPixelsPerSecond
    @State private var selectedSegmentId: String?
    @State private var clipColorFilter = ClipColorFilter.neutral
    @State private var clipVolume = ClipVolume.neutral
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

    var body: some View {
        VStack(spacing: 0) {
            header
            recipePicker

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                    validationPanel
                    resolvedStatePanel
                    renderStage
                }
                .padding(.horizontal, .spacing(.sp4))
                .padding(.vertical, .spacing(.sp4))
            }
        }
        .background(Color.ds.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .onChange(of: viewModel.renderState.id) { _, _ in
            syncParameterValuesForCurrentRecipe()
            selectedSegmentId = nil
        }
        .onAppear {
            syncParameterValuesForCurrentRecipe()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text("JIT Renderer Lab")
                .typography(.heading)
                .foregroundColor(Color.ds.text)
            Text("Library-native recipes validated against the component registry, then rendered with existing primitives.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, .spacing(.sp4))
        .padding(.top, .spacing(.sp4))
        .padding(.bottom, .spacing(.sp2))
    }

    private var recipePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(viewModel.recipes) { recipe in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectRecipe(id: recipe.id)
                        }
                    } label: {
                        Text(recipe.title)
                    }
                    .buttonStyle(.irisChipPicker(isSelected: viewModel.selectedRecipeId == recipe.id))
                }
            }
            .padding(.horizontal, .spacing(.sp4))
        }
        .padding(.bottom, .spacing(.sp3))
    }

    private var validationPanel: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            HStack {
                Text("Validation")
                    .typography(.body)
                    .foregroundColor(Color.ds.text)
                Spacer()
                statusBadge
            }

            Text("Prompt: \"\(viewModel.renderState.promptExample)\"")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            Text("Category: \(viewModel.renderState.resolutionCategory.displayTitle)")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            if !viewModel.validationResult.errors.isEmpty {
                ForEach(viewModel.validationResult.errors, id: \.self) { error in
                    Text(error)
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.danger)
                }
            }

            if !viewModel.validationResult.warnings.isEmpty {
                ForEach(viewModel.validationResult.warnings, id: \.self) { warning in
                    Text(warning)
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.textMuted)
                }
            }
        }
        .padding(.spacing(.sp3))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ds.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private var statusBadge: some View {
        Text(viewModel.validationResult.isValid ? "Valid" : "Invalid")
            .typography(.bodySmall)
            .foregroundColor(viewModel.validationResult.isValid ? Color.ds.accentFg : Color.ds.danger)
            .padding(.horizontal, .spacing(.sp2))
            .padding(.vertical, .spacing(.sp1))
            .background(
                (viewModel.validationResult.isValid ? Color.ds.accentFg : Color.ds.danger).opacity(0.12)
            )
            .clipShape(Capsule())
    }

    private var resolvedStatePanel: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Resolved state")
                .typography(.body)
                .foregroundColor(Color.ds.text)

            ForEach(viewModel.renderState.summaryLines, id: \.self) { line in
                Text(line)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }
        }
        .padding(.spacing(.sp3))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ds.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private var renderStage: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Live render")
                .typography(.body)
                .foregroundColor(Color.ds.text)

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
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)
                        .strokeBorder(Color.ds.border.opacity(0.35), lineWidth: 1)
                )
            } else {
                invalidRenderPlaceholder
            }
        }
    }

    private var invalidRenderPlaceholder: some View {
        VStack(spacing: .spacing(.sp3)) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(Color.ds.danger)
            Text("This recipe cannot render until validation passes.")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.spacing(.sp4))
        .background(Color.ds.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
    }

    private func syncParameterValuesForCurrentRecipe() {
        let groups = viewModel.renderState.chromePlan.parameterGroups
        parameterValues = EditorChromePreviewFixtures.seedValues(for: groups)
        if let activeId = viewModel.renderState.chromePlan.activeParameterGroupId,
           groups.contains(where: { $0.id == activeId }) {
            activeParameterGroupId = activeId
        } else if let first = groups.first {
            activeParameterGroupId = first.id
        } else {
            activeParameterGroupId = ""
        }
    }
}
