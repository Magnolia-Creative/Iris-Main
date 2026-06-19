import SwiftUI

struct EditorChromePreviewLab: View {
    @Binding var showsDock: Bool
    @Binding var showsActions: Bool
    @Binding var showsParameterGroups: Bool
    @Binding var showsSpatialControls: Bool
    @Binding var compressTimeline: Bool
    @Binding var showsOverflowChips: Bool
    @Binding var groupScenario: EditorChromePreviewGroupScenario
    @Binding var activeGroup: EditorChromePreviewActiveGroup
    @Binding var density: EditorBottomChromeDensity
    @Binding var promptPhase: IntelligencePromptPhase
    @Binding var activeNavItemId: String
    @Binding var promptDraft: String
    @Binding var parameterValues: [String: EditorParameterValue]
    @Binding var activeParameterGroupId: String

    let liveTranscript: String
    let voiceLevel: Float
    let onIntelligenceTap: () -> Void
    let onVoiceHoldStart: () -> Void
    let onVoiceHoldEnd: () -> Void
    let onSubmitText: () -> Void
    let onCancelText: () -> Void
    let onCancelProcessing: () -> Void

    @State private var lastActionLabel = "No action tapped"

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            ChromePreviewControls(
                showsDock: $showsDock,
                showsActions: $showsActions,
                showsParameterGroups: $showsParameterGroups,
                showsSpatialControls: $showsSpatialControls,
                compressTimeline: $compressTimeline,
                showsOverflowChips: $showsOverflowChips,
                groupScenario: $groupScenario,
                activeGroup: $activeGroup,
                density: $density,
                promptPhase: $promptPhase,
                onGroupScenarioChange: syncParameterState
            )

            Text(lastActionLabel)
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            ChromePreviewStage(
                plan: previewPlan,
                compressTimeline: compressTimeline,
                activeParameterGroupId: $activeParameterGroupId,
                parameterValues: $parameterValues,
                onAction: { action in
                    lastActionLabel = "Action: \(action.title)"
                },
                dock: { dockContent }
            )
        }
        .onAppear(perform: syncParameterState)
        .onChange(of: groupScenario) { _, _ in syncParameterState() }
        .onChange(of: showsParameterGroups) { _, _ in syncParameterState() }
        .onChange(of: activeGroup) { _, newValue in
            activeParameterGroupId = newValue.groupId
        }
    }

    private var previewPlan: EditorBottomChromePlan {
        var plan = EditorChromePreviewFixtures.makePlan(
            showsDock: showsDock,
            showsActions: showsActions,
            showsParameterGroups: showsParameterGroups,
            showsSpatialControls: showsSpatialControls,
            showsOverflowChips: showsOverflowChips,
            groupScenario: groupScenario,
            density: density
        )
        plan.activeParameterGroupId = activeParameterGroupId
        return plan
    }

    @ViewBuilder
    private var dockContent: some View {
        IntelligenceComponent(
            navigationItems: IntelligenceComponent.defaultShowcaseItems,
            activeNavigationItemId: $activeNavItemId,
            promptPhase: $promptPhase,
            promptDraft: $promptDraft,
            liveTranscript: liveTranscript,
            voiceLevel: voiceLevel,
            onIntelligenceTap: onIntelligenceTap,
            onVoiceHoldStart: onVoiceHoldStart,
            onVoiceHoldEnd: onVoiceHoldEnd,
            onSubmitText: onSubmitText,
            onCancelText: onCancelText,
            onCancelProcessing: onCancelProcessing
        )
        .frame(width: IntelligenceComponent.containerWidth())
    }

    private func syncParameterState() {
        let groups = EditorChromePreviewFixtures.parameterGroups(for: groupScenario)
        parameterValues = EditorChromePreviewFixtures.seedValues(for: groups)
        if groups.contains(where: { $0.id == activeGroup.groupId }) {
            activeParameterGroupId = activeGroup.groupId
        } else if let first = groups.first {
            activeParameterGroupId = first.id
        } else {
            activeParameterGroupId = ""
        }
    }
}

// MARK: - Controls

private struct ChromePreviewControls: View {
    @Binding var showsDock: Bool
    @Binding var showsActions: Bool
    @Binding var showsParameterGroups: Bool
    @Binding var showsSpatialControls: Bool
    @Binding var compressTimeline: Bool
    @Binding var showsOverflowChips: Bool
    @Binding var groupScenario: EditorChromePreviewGroupScenario
    @Binding var activeGroup: EditorChromePreviewActiveGroup
    @Binding var density: EditorBottomChromeDensity
    @Binding var promptPhase: IntelligencePromptPhase
    let onGroupScenarioChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Preview controls")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            toggleRow("Show dock", isOn: $showsDock)
            toggleRow("Show immediate actions", isOn: $showsActions)
            toggleRow("Show parameter groups", isOn: $showsParameterGroups)
            toggleRow("Show spatial controls", isOn: $showsSpatialControls)
            toggleRow("Compress timeline", isOn: $compressTimeline)
            toggleRow("Show overflow chips", isOn: $showsOverflowChips)

            pickerSection(title: "Dock phase") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .spacing(.sp2)) {
                        phaseChip("Idle", phase: .idle)
                        phaseChip("Recording", phase: .recording)
                        phaseChip("Typing", phase: .typing)
                        phaseChip("Submitting", phase: .submitting("Thinking…"))
                        phaseChip("Clarify", phase: .clarification("Which clip?"))
                        phaseChip("Error", phase: .error("Could not apply edit"))
                    }
                }
            }

            pickerSection(title: "Parameter group scenario") {
                scenarioPicker
            }

            if showsParameterGroups, groupScenario != .none {
                pickerSection(title: "Active parameter group") {
                    activeGroupPicker
                }
            }

            pickerSection(title: "Density") {
                densityPicker
            }
        }
        .padding(.spacing(.sp3))
        .background(Color.ds.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .typography(.bodySmall)
        }
    }

    private func pickerSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(title)
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            content()
        }
    }

    private func phaseChip(_ title: String, phase: IntelligencePromptPhase) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                promptPhase = phase
            }
        } label: {
            Text(title)
        }
        .buttonStyle(.irisChipPicker(isSelected: promptPhase == phase))
    }

    private var scenarioPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(EditorChromePreviewGroupScenario.allCases) { scenario in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            groupScenario = scenario
                            onGroupScenarioChange()
                        }
                    } label: {
                        Text(scenario.displayTitle)
                    }
                    .buttonStyle(.irisChipPicker(isSelected: groupScenario == scenario))
                }
            }
        }
    }

    private var activeGroupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(availableActiveGroups) { group in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            activeGroup = group
                        }
                    } label: {
                        Text(group.displayTitle)
                    }
                    .buttonStyle(.irisChipPicker(isSelected: activeGroup == group))
                }
            }
        }
    }

    private var densityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(EditorBottomChromeDensity.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            density = option
                        }
                    } label: {
                        Text(option.displayTitle)
                    }
                    .buttonStyle(.irisChipPicker(isSelected: density == option))
                }
            }
        }
    }

    private var availableActiveGroups: [EditorChromePreviewActiveGroup] {
        let groups = EditorChromePreviewFixtures.parameterGroups(for: groupScenario)
        let ids = Set(groups.map(\.id))
        return EditorChromePreviewActiveGroup.allCases.filter { ids.contains($0.groupId) }
    }
}

// MARK: - Stage

private struct ChromePreviewStage: View {
    let plan: EditorBottomChromePlan
    let compressTimeline: Bool
    @Binding var activeParameterGroupId: String
    @Binding var parameterValues: [String: EditorParameterValue]
    let onAction: (EditorChromeActionItem) -> Void
    let dock: () -> AnyView

    init<Dock: View>(
        plan: EditorBottomChromePlan,
        compressTimeline: Bool,
        activeParameterGroupId: Binding<String>,
        parameterValues: Binding<[String: EditorParameterValue]>,
        onAction: @escaping (EditorChromeActionItem) -> Void,
        @ViewBuilder dock: @escaping () -> Dock
    ) {
        self.plan = plan
        self.compressTimeline = compressTimeline
        self._activeParameterGroupId = activeParameterGroupId
        self._parameterValues = parameterValues
        self.onAction = onAction
        self.dock = { AnyView(dock()) }
    }

    private var timelineHeight: CGFloat {
        let base: CGFloat = compressTimeline ? 120 : 220
        let compression = CGFloat(plan.tierCountAboveDock) * 28
        return max(72, base - compression)
    }

    var body: some View {
        VStack(spacing: 0) {
            MockTimelineCompressionRegion(height: timelineHeight, isCompressed: compressTimeline)

            EditorBottomChromeStack(
                plan: plan,
                activeParameterGroupId: $activeParameterGroupId,
                parameterValues: $parameterValues,
                onAction: onAction,
                dock: dock
            )
            .padding(.horizontal, .spacing(.sp3))
            .padding(.bottom, .spacing(.sp2))
        }
        .background(Color.ds.bg)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)
                .strokeBorder(Color.ds.border.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct MockTimelineCompressionRegion: View {
    let height: CGFloat
    let isCompressed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            HStack {
                Text("Timeline preview")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
                Spacer()
                Text(isCompressed ? "Compressed" : "Expanded")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }

            RoundedRectangle(cornerRadius: .spacing(.sp2), style: .continuous)
                .fill(Color.ds.surface.opacity(0.45))
                .frame(height: max(48, height - 28))
                .overlay(alignment: .leading) {
                    HStack(spacing: .spacing(.sp2)) {
                        timelineClip(width: 72, title: "Intro")
                        timelineClip(width: 96, title: "Demo")
                        if !isCompressed {
                            timelineClip(width: 64, title: "Outro")
                        }
                    }
                    .padding(.horizontal, .spacing(.sp3))
                }
        }
        .padding(.spacing(.sp3))
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.ds.surface.opacity(0.2))
    }

    private func timelineClip(width: CGFloat, title: String) -> some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1), style: .continuous)
            .fill(Color.ds.accentFg.opacity(0.35))
            .frame(width: width, height: 28)
            .overlay {
                Text(title)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.text)
                    .lineLimit(1)
            }
    }
}
