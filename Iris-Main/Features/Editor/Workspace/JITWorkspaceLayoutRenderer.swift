import SwiftUI

enum JITTimelinePresentation {
    case full
    case primaryTrackOnly
    case focusedClipStrip
    case hidden
}

struct JITWorkspaceLayoutRenderer<Preview: View, Timeline: View, Panel: View, ToolbarSlot: View>: View {
    let plan: UIWorkspacePlan
    let transitionPlans: [JITWorkspaceTransitionPlan]
    let timelinePresentation: JITTimelinePresentation
    let preview: () -> Preview
    let timeline: (JITTimelinePresentation) -> Timeline
    let panel: (String) -> Panel
    let toolbarSlot: () -> ToolbarSlot

    var body: some View {
        VStack(spacing: 0) {
            render(node: plan.layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            toolbarSlot()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: plan.workspaceId)
    }

    private func render(node: UILayoutNode) -> AnyView {
        switch node.type {
        case .vstack:
            return AnyView(
                VStack(spacing: spacing(for: node)) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        render(node: child)
                            .frame(maxWidth: .infinity, maxHeight: heightWeight(child), alignment: .top)
                    }
                }
            )
        case .hstack:
            return AnyView(
                HStack(spacing: spacing(for: node)) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        render(node: child)
                            .frame(maxWidth: .infinity, maxHeight: heightWeight(child), alignment: .top)
                    }
                }
            )
        case .zstack:
            return AnyView(
                ZStack(alignment: .top) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        render(node: child)
                    }
                }
            )
        case .widget:
            if let widget = node.widget {
                return AnyView(
                    widgetView(widget)
                        .transition(transition(for: widget.widgetId))
                )
            }
            return AnyView(EmptyView())
        case .toolbar:
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private func widgetView(_ placement: UIWidgetPlacement) -> some View {
        switch placement.widgetId {
        case "playback.viewer", "playback.beforeAfterViewer":
            preview()
                .frame(height: previewHeight(for: placement))
        case "timeline.full":
            if timelinePresentation != .hidden {
                timeline(timelinePresentation)
            }
        case "timeline.primaryTrack", "timeline.focusedClipStrip":
            timeline(.focusedClipStrip)
        case "audio.levelsMeter":
            audioLevelsPlaceholder(for: placement)
        case "panel.importBrowser":
            panel("panel.importBrowser")
        case "panel.exportSettings":
            panel("panel.exportSettings")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func audioLevelsPlaceholder(for placement: UIWidgetPlacement) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Audio Levels")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .fill(Color.ds.accentFg.opacity(0.35))
                .frame(height: placement.prominence == .primary ? 48 : 28)
        }
        .padding(.horizontal, .sp3)
    }

    private func previewHeight(for placement: UIWidgetPlacement) -> CGFloat {
        if placement.variant == "large" || placement.prominence == .primary {
            return 260
        }
        return 180
    }

    private func heightWeight(_ node: UILayoutNode) -> CGFloat? {
        let weight = node.size?.weight ?? node.widget?.size?.weight
        guard let weight, weight > 0 else { return nil }
        return max(weight, 0.05)
    }

    private func spacing(for node: UILayoutNode) -> CGFloat {
        node.widget?.prominence == .compact ? .spacing(.sp1) : .spacing(.sp2)
    }

    private func transition(for widgetId: String) -> AnyTransition {
        guard let plan = transitionPlans.first(where: { $0.widgetId == widgetId }) else {
            return .opacity
        }
        switch plan.style {
        case .persist, .resize:
            return .opacity
        case .replace:
            return .opacity.combined(with: .scale(scale: 0.98))
        case .enter:
            return .opacity.combined(with: .move(edge: .bottom))
        case .exit:
            return .opacity
        }
    }
}

struct JITWorkspaceParameterControlsView: View {
    let placement: UIWidgetPlacement
    let values: [String: Double]
    let onValueChange: (String, Double) -> Void

    private var supportedControls: [UIParameterControl] {
        placement.controls.filter { UIWorkspaceCatalog.isSupportedWorkspaceParameter($0.parameterId) }
    }

    var body: some View {
        Group {
            if placement.variant == "sliderGroup" {
                sliderGroupBody
            } else {
                verticalControlsBody
            }
        }
        .padding(.horizontal, .spacing(.sp2))
    }

    private var sliderGroupBody: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp3)) {
                ForEach(supportedControls) { control in
                    parameterControlCard(control)
                        .frame(width: 132)
                }
            }
            .padding(.vertical, .spacing(.sp1))
        }
    }

    private var verticalControlsBody: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            ForEach(supportedControls) { control in
                parameterControlCard(control)
            }
        }
    }

    private func parameterControlCard(_ control: UIParameterControl) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(control.label ?? control.parameterId)
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
                .lineLimit(1)
            Slider(
                value: binding(for: control),
                in: sliderRange(for: control)
            )
            .tint(Color.ds.accentFg)
        }
    }

    private func binding(for control: UIParameterControl) -> Binding<Double> {
        Binding(
            get: { values[control.parameterId] ?? control.defaultValue ?? 0 },
            set: { onValueChange(control.parameterId, $0) }
        )
    }

    private func sliderRange(for control: UIParameterControl) -> ClosedRange<Double> {
        let lower = control.minValue ?? 0
        let upper = control.maxValue ?? 1
        return lower...max(upper, lower + 0.01)
    }
}

struct JITWorkspaceReviewActionsView: View {
    let onApply: () -> Void
    let onCancel: () -> Void
    let onRefine: () -> Void
    let showsNextSlice: Bool

    var body: some View {
        HStack(spacing: .spacing(.sp2)) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundColor(Color.ds.textMuted)
            Spacer()
            Button("Refine", action: onRefine)
                .buttonStyle(.plain)
                .foregroundColor(Color.ds.textMuted)
            Button(showsNextSlice ? "Next" : "Apply", action: onApply)
                .buttonStyle(.primary)
        }
        .padding(.horizontal, .spacing(.sp2))
    }
}
