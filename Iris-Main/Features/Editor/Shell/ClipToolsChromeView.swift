import SwiftUI

struct ClipToolsChromeView: View {
    @Binding var expandedToolId: Int
    let selectedClipColorFilter: ClipColorFilter
    let selectedClipVolume: ClipVolume
    let onSplitClip: () -> Void
    let onDeleteClip: () -> Void
    let onSetClipColorFilter: (ClipColorFilter) -> Void
    let onResetClipColorFilter: () -> Void
    let onSetClipVolume: (ClipVolume) -> Void
    let onResetClipVolume: () -> Void
    let onDeselectClip: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var toolNamespace
    @State private var activeColorProperty: ClipColorProperty = .temperature

    static func isSliderExpandedTool(id: Int) -> Bool {
        id == ClipToolID.color || id == ClipToolID.volume
    }

    private var isSliderExpanded: Bool {
        Self.isSliderExpandedTool(id: expandedToolId)
    }

    var body: some View {
        HStack(spacing: .spacing(.sp2)) {
            if !isSliderExpanded {
                clipDeselectButton
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
                    )

                EditorToolDivider()
                    .transition(.opacity)
            }

            if let selected = clipTools.first(where: { $0.id == expandedToolId }) {
                clipToolsExpandedCluster(selected: selected)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    clipToolsCollapsedStrip
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var clipDeselectButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                expandedToolId = -1
                onDeselectClip()
            }
        } label: {
            EditorToolCloseLabel(title: "Deselect clip")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Deselect clip"))
        .accessibilityHint(Text("Returns to the full voice prompt bar."))
    }

    private var clipToolsCollapsedStrip: some View {
        HStack(spacing: .spacing(.sp1)) {
            Button { onDeleteClip() } label: {
                toolLabel(systemImage: "trash", title: "Delete", foreground: Color.ds.danger)
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale))

            ForEach(clipTools) { item in
                Button { handleToolTap(item) } label: {
                    toolLabel(
                        systemImage: item.systemImage,
                        title: item.title,
                        foreground: Color.ds.textMuted,
                        matchedId: "tool-\(item.id)"
                    )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    @ViewBuilder
    private func clipToolsExpandedCluster(selected: ClipToolItem) -> some View {
        switch selected.kind {
        case .colorFilters:
            colorFilterControls
        case .volume:
            volumeControls
        case let .expandable(subItems):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacing(.sp2)) {
                    expandedToolTitleButton(for: selected)

                    ForEach(subItems) { sub in
                        Button { sub.action() } label: {
                            EditorToolRoundedIconLabel(systemImage: sub.systemImage, title: sub.title)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(sub.title))
                    }
                }
            }
        case .action:
            EmptyView()
        }
    }

    private func expandedToolTitleButton(for selected: ClipToolItem) -> some View {
        Button { handleToolTap(selected) } label: {
            HStack(spacing: .spacing(.sp2)) {
                Image(systemName: selected.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .matchedGeometryEffect(id: "tool-\(selected.id)", in: toolNamespace)
                Text(selected.title)
                    .typography(.body)
                    .lineLimit(1)
            }
            .foregroundColor(Color.ds.textMuted)
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp2))
            .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private func toolLabel(
        systemImage: String,
        title: String,
        foreground: Color,
        matchedId: String? = nil
    ) -> some View {
        EditorToolIconLabel(
            systemImage: systemImage,
            title: title,
            foreground: foreground,
            matchedId: matchedId,
            namespace: toolNamespace
        )
    }

    private func handleToolTap(_ item: ClipToolItem) {
        if case let .action(action) = item.kind {
            action()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            let wasExpanded = expandedToolId == item.id
            expandedToolId = wasExpanded ? -1 : item.id
            if !wasExpanded, case .colorFilters = item.kind {
                activeColorProperty = .temperature
            }
        }
    }

    private var colorFilterControls: some View {
        HStack(spacing: .spacing(.sp2)) {
            backToToolsButton
            colorPropertyMenu
            Slider(
                value: activeColorBinding,
                in: Double(activeColorProperty.range.lowerBound)...Double(activeColorProperty.range.upperBound)
            )
            .tint(Color.ds.accentFg)
            .frame(maxWidth: .infinity)
            resetColorButton
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private var volumeControls: some View {
        HStack(spacing: .spacing(.sp2)) {
            backToToolsButton
            Slider(value: volumeBinding, in: 0.0...2.0)
                .tint(Color.ds.accentFg)
                .frame(maxWidth: .infinity)
            Text("\(Int((selectedClipVolume.gain * 100).rounded()))%")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
                .frame(minWidth: 44, alignment: .trailing)
                .monospacedDigit()
            resetVolumeButton
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(selectedClipVolume.gain) },
            set: { newValue in
                onSetClipVolume(ClipVolume(gain: Float(newValue)))
            }
        )
    }

    private var resetVolumeButton: some View {
        Button {
            onResetClipVolume()
        } label: {
            EditorToolRoundedIconLabel(systemImage: "arrow.counterclockwise", title: "Reset volume to 100%")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Reset volume to 100%"))
    }

    private var backToToolsButton: some View {
        EditorToolBackButton(accessibilityLabel: "Back to clip tools") {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedToolId = -1
            }
        }
    }

    private var colorPropertyMenu: some View {
        Menu {
            ForEach(ClipColorProperty.allCases) { property in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeColorProperty = property
                    }
                } label: {
                    Label(property.title, systemImage: property.systemImage)
                }
            }
        } label: {
            HStack(spacing: .spacing(.sp1)) {
                Image(systemName: activeColorProperty.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(Color.ds.textMuted)
            .padding(.horizontal, .spacing(.sp2))
            .frame(height: 40)
            .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
        }
        .menuStyle(.button)
        .accessibilityLabel(Text("Color property"))
        .accessibilityValue(Text(activeColorProperty.title))
    }

    private var resetColorButton: some View {
        Button {
            updateSelectedClipFilter { filter in
                activeColorProperty.set(0, on: &filter)
            }
        } label: {
            EditorToolRoundedIconLabel(systemImage: "arrow.counterclockwise", title: "Reset \(activeColorProperty.title)")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Reset \(activeColorProperty.title)"))
    }

    private var activeColorBinding: Binding<Double> {
        Binding(
            get: { Double(activeColorProperty.value(in: selectedClipColorFilter)) },
            set: { newValue in
                let floatValue = Float(newValue)
                updateSelectedClipFilter { filter in
                    activeColorProperty.set(floatValue, on: &filter)
                }
            }
        )
    }

    private func updateSelectedClipFilter(_ mutate: (inout ClipColorFilter) -> Void) {
        var filter = selectedClipColorFilter
        mutate(&filter)
        onSetClipColorFilter(filter)
    }

    private var clipTools: [ClipToolItem] {
        [
            ClipToolItem(id: ClipToolID.split, systemImage: "scissors", title: "Split",
                kind: .action(action: { [onSplitClip] in
                    onSplitClip()
                })),
            ClipToolItem(id: ClipToolID.color, systemImage: "camera.filters", title: "Color", kind: .colorFilters),
            ClipToolItem(id: ClipToolID.volume, systemImage: "speaker.wave.2", title: "Volume", kind: .volume)
        ]
    }
}

private enum ClipToolID {
    static let split = 0
    static let color = 3
    static let volume = 4
}

private enum ClipColorProperty: String, CaseIterable, Identifiable {
    case temperature
    case tint
    case exposure
    case brightness
    case saturation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: return "Temperature"
        case .tint: return "Tint"
        case .exposure: return "Exposure"
        case .brightness: return "Brightness"
        case .saturation: return "Saturation"
        }
    }

    var systemImage: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .tint: return "eyedropper.halffull"
        case .exposure: return "plusminus.circle"
        case .brightness: return "sun.max"
        case .saturation: return "camera.filters"
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .exposure:
            let bound = ClipColorFilter.exposureRange.upperBound / 2
            return -bound...bound
        case .brightness:
            let bound = ClipColorFilter.normalizedRange.upperBound / 2
            return -bound...bound
        default:
            return ClipColorFilter.normalizedRange
        }
    }

    func value(in filter: ClipColorFilter) -> Float {
        switch self {
        case .temperature: return filter.temperature
        case .tint: return filter.tint
        case .exposure: return filter.exposure
        case .brightness: return filter.brightness
        case .saturation: return filter.saturation
        }
    }

    func set(_ value: Float, on filter: inout ClipColorFilter) {
        switch self {
        case .temperature: filter.temperature = value
        case .tint: filter.tint = value
        case .exposure: filter.exposure = value
        case .brightness: filter.brightness = value
        case .saturation: filter.saturation = value
        }
    }
}

private struct ClipToolItem: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let kind: ClipToolKind
}

private struct ClipToolSubItem: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let action: () -> Void
}

private enum ClipToolKind {
    case expandable(subItems: [ClipToolSubItem])
    case colorFilters
    case volume
    case action(action: () -> Void)
}
