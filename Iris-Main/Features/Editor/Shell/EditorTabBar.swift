import SwiftUI

/// Top chrome pill that sits above the pinned `EditorBottomNavBar`. Houses the
/// prompt bar, clip tools (when a clip is selected in Edit), or the
/// space-specific extension content for Import/Export. This view is free to
/// resize horizontally — the bottom nav row lives in a separate sibling view
/// so it is never affected by changes here.
struct EditorTabBar<PromptBar: View, SpaceExtension: View>: View {
    @Binding var activeSpace: EditorSpace
    let isClipSelected: Bool
    let promptBarIsTakingOver: Bool
    let selectedClipColorFilter: ClipColorFilter
    let onSplitClip: () -> Void
    let onDeleteClip: () -> Void
    let onSetClipColorFilter: (ClipColorFilter) -> Void
    let onResetClipColorFilter: () -> Void
    let onDeselectClip: () -> Void
    /// When true, `promptActionReviewReplacement` is shown instead of the normal prompt bar.
    let isPromptActionReviewActive: Bool
    /// When set, replaces the prompt bar (mic / typing / chat) with this content while keeping the tab bar shell.
    let promptActionReviewReplacement: AnyView?
    /// Extra space reserved inside the glass shell at the bottom so the pinned
    /// nav bar can overlap the chrome in z without changing its layout.
    let bottomReservedSpace: CGFloat
    /// Maximum width for the top chrome glass shell. When `nil`, the chrome
    /// fills the proposed width as before. When set, the chrome is capped at
    /// this width (unless `hugChromeToContent` is true — clip tools always
    /// hug their intrinsic content width).
    let chromeMaxWidth: CGFloat?
    let promptBar: (Bool, Namespace.ID) -> PromptBar
    let spaceExtension: SpaceExtension

    @Environment(\.colorScheme) private var colorScheme

    @Namespace private var toolNamespace
    @Namespace private var promptNamespace
    @State private var expandedToolId: Int = -1
    @State private var activeColorProperty: ColorProperty = .temperature

    private let toolItemWidth: CGFloat = 48
    private let outerCornerRadius: CGFloat = 24

    init(
        activeSpace: Binding<EditorSpace>,
        isClipSelected: Bool,
        promptBarIsTakingOver: Bool,
        selectedClipColorFilter: ClipColorFilter = .neutral,
        onSplitClip: @escaping () -> Void,
        onDeleteClip: @escaping () -> Void,
        onSetClipColorFilter: @escaping (ClipColorFilter) -> Void = { _ in },
        onResetClipColorFilter: @escaping () -> Void = {},
        onDeselectClip: @escaping () -> Void = {},
        isPromptActionReviewActive: Bool = false,
        promptActionReviewReplacement: AnyView? = nil,
        bottomReservedSpace: CGFloat = 0,
        chromeMaxWidth: CGFloat? = nil,
        @ViewBuilder promptBar: @escaping (Bool, Namespace.ID) -> PromptBar,
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
        self.onDeselectClip = onDeselectClip
        self.isPromptActionReviewActive = isPromptActionReviewActive
        self.promptActionReviewReplacement = promptActionReviewReplacement
        self.bottomReservedSpace = bottomReservedSpace
        self.chromeMaxWidth = chromeMaxWidth
        self.promptBar = promptBar
        self.spaceExtension = spaceExtension()
    }

    private var rowMaxWidth: CGFloat? {
        // When a clip is selected and the prompt bar is in its compact idle
        // layout, or when prompt-action review replaces the prompt slot, let the
        // entire row size to content so the glass pill hugs tightly. Otherwise
        // expand so the prompt bar can center properly.
        if isPromptActionReviewActive {
            return nil
        }
        if isClipSelected && !promptBarIsTakingOver {
            return nil
        }
        return .infinity
    }

    /// Clip idle or prompt-action review: shell sizes to content; the pinned
    /// nav bar below is unaffected by this hug.
    private var hugChromeToContent: Bool {
        activeSpace == .edit
            && expandedToolId != 3
            && (
                isPromptActionReviewActive
                    || (isClipSelected && !promptBarIsTakingOver)
            )
    }

    private var isColorToolExpanded: Bool {
        expandedToolId == 3
    }

    var body: some View {
        topChrome
            .modifier(ChromeMaxWidthModifier(
                maxWidth: (hugChromeToContent || isColorToolExpanded) ? nil : chromeMaxWidth
            ))
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
            .onChange(of: isPromptActionReviewActive) { _, active in
                guard active else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
    }

    private var topChrome: some View {
        Group {
            if activeSpace == .edit {
                toolsRow
            } else {
                spaceExtension
            }
        }
        .padding(.horizontal, .spacing(.sp3))
        .padding(.top, .spacing(.sp3))
        .padding(.bottom, .spacing(.sp3) + bottomReservedSpace)
        .modifier(HorizontalHugWhenEnabled(enabled: hugChromeToContent))
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

    // MARK: - Edit Tools Row

    @ViewBuilder
    private var toolsRow: some View {
        let clipIdle = isClipSelected && !promptBarIsTakingOver
        let leadingCompact = clipIdle || isPromptActionReviewActive
        HStack(spacing: .spacing(.sp2)) {
            if !isColorToolExpanded {
                Group {
                    if let promptActionReviewReplacement {
                        promptActionReviewReplacement
                            .fixedSize(horizontal: true, vertical: false)
                    } else if clipIdle {
                        clipDeselectButton
                    } else {
                        promptBar(isClipSelected, promptNamespace)
                    }
                }
                .layoutPriority(leadingCompact ? 0 : 1)
            }

            if clipIdle {
                if !isColorToolExpanded {
                    promptDivider
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
        .frame(maxWidth: rowMaxWidth)
        .frame(minHeight: .spacing(.sp8))
        .frame(
            maxWidth: leadingCompact ? nil : .infinity,
            alignment: leadingCompact ? .leading : .center
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expandedToolId)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isClipSelected)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: promptBarIsTakingOver)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPromptActionReviewActive)
    }

    private var promptDivider: some View {
        RoundedRectangle(cornerRadius: 0.75, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.20))
            .frame(width: 1.5, height: 28)
            .padding(.horizontal, .spacing(.sp1))
            .accessibilityHidden(true)
    }

    private var clipDeselectButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                expandedToolId = -1
                onDeselectClip()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
                .frame(width: toolItemWidth, height: toolItemWidth)
                .contentShape(Rectangle())
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
    private func clipToolsExpandedCluster(selected: ToolItem) -> some View {
        switch selected.kind {
        case .colorFilters:
            colorFilterControls
        case let .expandable(subItems):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacing(.sp2)) {
                    expandedToolTitleButton(for: selected)

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
                }
            }
        case .action:
            EmptyView()
        }
    }

    private func expandedToolTitleButton(for selected: ToolItem) -> some View {
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

    private var backToToolsButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedToolId = -1
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back to clip tools"))
    }

    private var colorPropertyMenu: some View {
        Menu {
            ForEach(ColorProperty.allCases) { property in
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
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
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
}

// MARK: - Color Property

private enum ColorProperty: String, CaseIterable, Identifiable {
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

/// Lets the top chrome shrink to intrinsic width when clip tools are shown.
private struct HorizontalHugWhenEnabled: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.fixedSize(horizontal: true, vertical: false)
        } else {
            content
        }
    }
}

/// Caps the chrome to a maximum width when provided; passes through otherwise.
private struct ChromeMaxWidthModifier: ViewModifier {
    let maxWidth: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let maxWidth {
            content.frame(maxWidth: maxWidth, alignment: .center)
        } else {
            content
        }
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
