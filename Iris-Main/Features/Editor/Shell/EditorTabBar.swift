import SwiftUI

struct EditorTabBar<PromptBar: View, SpaceExtension: View>: View {
    @Binding var activeSpace: EditorSpace
    let isClipSelected: Bool
    let promptBarIsTakingOver: Bool
    let selectedClipColorFilter: ClipColorFilter
    let onSplitClip: () -> Void
    let onDeleteClip: () -> Void
    let onSetClipColorFilter: (ClipColorFilter) -> Void
    let onResetClipColorFilter: () -> Void
    let promptBar: (Bool, Namespace.ID, @escaping () -> Void) -> PromptBar
    let spaceExtension: SpaceExtension

    @Environment(\.colorScheme) private var colorScheme

    @Namespace private var tabNamespace
    @Namespace private var toolNamespace
    @Namespace private var promptNamespace
    @State private var expandedToolId: Int = -1

    private let tabItemWidth: CGFloat = 62
    private let tabRowHeight: CGFloat = 48
    private let toolItemWidth: CGFloat = 48
    private let outerCornerRadius: CGFloat = 24
    private let navCornerRadius: CGFloat = .spacing(.sp4)
    private let shellInset: CGFloat = 10

    init(
        activeSpace: Binding<EditorSpace>,
        isClipSelected: Bool,
        promptBarIsTakingOver: Bool,
        selectedClipColorFilter: ClipColorFilter = .neutral,
        onSplitClip: @escaping () -> Void,
        onDeleteClip: @escaping () -> Void,
        onSetClipColorFilter: @escaping (ClipColorFilter) -> Void = { _ in },
        onResetClipColorFilter: @escaping () -> Void = {},
        @ViewBuilder promptBar: @escaping (Bool, Namespace.ID, @escaping () -> Void) -> PromptBar,
        @ViewBuilder spaceExtension: () -> SpaceExtension
    ) {
        self._activeSpace = activeSpace
        self.isClipSelected = isClipSelected
        self.promptBarIsTakingOver = promptBarIsTakingOver
        self.selectedClipColorFilter = selectedClipColorFilter
        self.onSplitClip = onSplitClip
        self.onDeleteClip = onDeleteClip
        self.onSetClipColorFilter = onSetClipColorFilter
        self.onResetClipColorFilter = onResetClipColorFilter
        self.promptBar = promptBar
        self.spaceExtension = spaceExtension()
    }

    private var navWidth: CGFloat {
        let count = CGFloat(EditorSpace.allCases.count)
        let hPad = CGFloat.spacing(.sp2) * 2
        return count * tabItemWidth + (count - 1) * CGFloat.spacing(.sp3) + hPad
    }

    private var shellWidth: CGFloat {
        navWidth + shellInset * 2
    }

    private var editShellWidth: CGFloat? {
        isClipSelected ? nil : shellWidth
    }

    private var rowMaxWidth: CGFloat? {
        // When a clip is selected and the prompt bar is in its compact idle
        // layout, let the entire row size to content so the card pill hugs the
        // mic/chat + divider + clip tools tightly. In every other case the row
        // should expand so the prompt bar can center properly.
        if isClipSelected && !promptBarIsTakingOver {
            return nil
        }
        return .infinity
    }

    var body: some View {
        GlassEffectContainer(spacing: shellInset * 2) {
            VStack(spacing: 0) {
                Group {
                    if activeSpace == .edit {
                        toolsRow
                    } else {
                        spaceExtension
                    }
                }
                .padding(.horizontal, .spacing(.sp3))
                .padding(.top, .spacing(.sp3))
                .padding(.bottom, .spacing(.sp2))

                navCard
                    .padding(.horizontal, shellInset)
                    .padding(.bottom, shellInset)
            }
            .frame(width: activeSpace == .edit ? editShellWidth : nil)
            .glassEffect(
                .regular.tint(shellTint),
                in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
            )
            .shadow(color: outerShadowColor, radius: 20, x: 0, y: 14)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: activeSpace)
            .onChange(of: isClipSelected) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
            .onChange(of: activeSpace) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
            .onChange(of: promptBarIsTakingOver) { _, isTakingOver in
                guard isTakingOver else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
        }
    }

    // MARK: - Nav Card (raised inner element)

    private var navCard: some View {
        navigationRow
            .frame(width: navWidth)
            .glassEffect(
                .regular.tint(navTint).interactive(),
                in: RoundedRectangle(cornerRadius: navCornerRadius, style: .continuous)
            )
            .shadow(color: navInnerShadowColor, radius: 8, x: 0, y: 4)
    }

    private var navTint: Color {
        Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12)
    }

    private var navInnerShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color.black.opacity(0.1)
    }

    // MARK: - Outer Shell

    private var shellTint: Color {
        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.08)
    }

    private var outerShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.55)
            : Color.black.opacity(0.12)
    }

    // MARK: - Navigation Row

    private var navigationRow: some View {
        HStack(spacing: .spacing(.sp3)) {
            ForEach(EditorSpace.allCases) { space in
                Button {
                    let transitionMark = "space-transition-\(space.rawValue)"
                    let appearanceMark = "space-content-\(space.rawValue)"
                    EditorDebugTrace.begin(
                        transitionMark,
                        scope: "EditorTabBar",
                        message: "tap from=\(activeSpace.rawValue) to=\(space.rawValue)"
                    )
                    EditorDebugTrace.begin(
                        appearanceMark,
                        scope: "EditorTabBar",
                        message: "waiting for content appearance space=\(space.rawValue)"
                    )
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activeSpace = space
                    }
                } label: {
                    Image(systemName: activeSpace == space ? space.selectedIconName : space.unselectedIconName)
                        .font(.system(size: 21, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.white)
                        .frame(width: tabItemWidth, height: tabRowHeight)
                        .background {
                            if activeSpace == space {
                                RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous)
                                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22))
                                    .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(space.rawValue))
            }
        }
        .padding(.horizontal, .spacing(.sp2))
        .padding(.vertical, .spacing(.sp2))
    }

    // MARK: - Edit Tools Row

    @ViewBuilder
    private var toolsRow: some View {
        HStack(spacing: .spacing(.sp2)) {
            promptBar(isClipSelected, promptNamespace) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    expandedToolId = -1
                }
            }
                .layoutPriority(isClipSelected && !promptBarIsTakingOver ? 0 : 1)

            if isClipSelected && !promptBarIsTakingOver {
                promptDivider
                    .transition(.opacity)
                if let selected = clipTools.first(where: { $0.id == expandedToolId }) {
                    clipToolsExpandedCluster(selected: selected)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        clipToolsCollapsedStrip
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: rowMaxWidth)
        .frame(minHeight: .spacing(.sp8))
        .frame(
            maxWidth: .infinity,
            alignment: (isClipSelected && !promptBarIsTakingOver) ? .leading : .center
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expandedToolId)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isClipSelected)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: promptBarIsTakingOver)
    }

    private var promptDivider: some View {
        RoundedRectangle(cornerRadius: 0.75, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.20))
            .frame(width: 1.5, height: 28)
            .padding(.horizontal, .spacing(.sp1))
            .accessibilityHidden(true)
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
    private func clipToolsExpandedCluster(selected: ToolItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
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

                switch selected.kind {
                case let .expandable(subItems):
                    ForEach(subItems) { sub in
                        Button { sub.action() } label: {
                            Image(systemName: sub.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color.ds.textMuted)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(sub.title))
                    }
                case .colorFilters:
                    colorFilterControls
                case .action:
                    EmptyView()
                }
            }
        }
    }

    private func toolLabel(
        systemImage: String,
        title: String,
        foreground: Color,
        matchedId: String? = nil
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .medium))
            .modifier(ToolIconMatchModifier(id: matchedId, namespace: toolNamespace))
            .foregroundColor(foreground)
            .frame(width: toolItemWidth, height: toolItemWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(title))
    }

    private func handleToolTap(_ item: ToolItem) {
        if case let .action(action) = item.kind {
            action()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expandedToolId = expandedToolId == item.id ? -1 : item.id
        }
    }

    private var colorFilterControls: some View {
        HStack(spacing: .spacing(.sp2)) {
            filterSlider(
                title: "Temp",
                systemImage: "thermometer.medium",
                value: selectedClipColorFilter.temperature,
                range: ClipColorFilter.normalizedRange
            ) { value in
                updateSelectedClipFilter { $0.temperature = value }
            }

            filterSlider(
                title: "Tint",
                systemImage: "eyedropper.halffull",
                value: selectedClipColorFilter.tint,
                range: ClipColorFilter.normalizedRange
            ) { value in
                updateSelectedClipFilter { $0.tint = value }
            }

            filterSlider(
                title: "Exposure",
                systemImage: "plusminus.circle",
                value: selectedClipColorFilter.exposure,
                range: ClipColorFilter.exposureRange
            ) { value in
                updateSelectedClipFilter { $0.exposure = value }
            }

            filterSlider(
                title: "Bright",
                systemImage: "sun.max",
                value: selectedClipColorFilter.brightness,
                range: ClipColorFilter.normalizedRange
            ) { value in
                updateSelectedClipFilter { $0.brightness = value }
            }

            filterSlider(
                title: "Sat",
                systemImage: "camera.filters",
                value: selectedClipColorFilter.saturation,
                range: ClipColorFilter.normalizedRange
            ) { value in
                updateSelectedClipFilter { $0.saturation = value }
            }

            Button { onResetClipColorFilter() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.ds.textMuted)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Reset filters"))
        }
        .transition(.opacity)
    }

    private func filterSlider(
        title: String,
        systemImage: String,
        value: Float,
        range: ClosedRange<Float>,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        VStack(spacing: .spacing(.sp1)) {
            HStack(spacing: .spacing(.sp1)) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .typography(.bodySmall)
                    .lineLimit(1)
            }
            .foregroundColor(Color.ds.textMuted)

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Float($0)) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .frame(width: 92)
            .tint(Color.ds.accentFg)
        }
        .frame(width: 108)
        .padding(.horizontal, .spacing(.sp2))
        .padding(.vertical, .spacing(.sp2))
        .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
    }

    private func updateSelectedClipFilter(_ mutate: (inout ClipColorFilter) -> Void) {
        var filter = selectedClipColorFilter
        mutate(&filter)
        onSetClipColorFilter(filter)
    }
}

/// Applies `matchedGeometryEffect` only when `id` is non-nil.
private struct ToolIconMatchModifier: ViewModifier {
    let id: String?
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Tool Item Models

private struct ToolItem: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let kind: ToolKind
}

private struct SubItem: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let action: () -> Void
}

private enum ToolKind {
    case expandable(subItems: [SubItem])
    case colorFilters
    case action(action: () -> Void)
}

// MARK: - Tool Definitions

private extension EditorTabBar {
    var clipTools: [ToolItem] {
        [
            ToolItem(id: 0, systemImage: "scissors", title: "Split",
                kind: .action(action: { [onSplitClip] in
                    onSplitClip()
                })),
            ToolItem(id: 1, systemImage: "speedometer", title: "Speed",
                kind: .action(action: {})),
            ToolItem(id: 2, systemImage: "speaker.wave.2.fill", title: "Audio",
                kind: .expandable(subItems: [
                    SubItem(id: 0, systemImage: "speaker.wave.1", title: "Fade", action: {}),
                    SubItem(id: 1, systemImage: "waveform", title: "Normalize", action: {}),
                    SubItem(id: 2, systemImage: "mic.fill", title: "Replace", action: {})
                ])),
            ToolItem(id: 3, systemImage: "camera.filters", title: "Color", kind: .colorFilters)
        ]
    }
}
