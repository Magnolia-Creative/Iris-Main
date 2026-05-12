import SwiftUI

struct EditorTabBar<PromptBar: View, SpaceExtension: View>: View {
    @Binding var activeSpace: EditorSpace
    let isClipSelected: Bool
    let promptBarIsTakingOver: Bool
    let onSplitClip: () -> Void
    let onDeleteClip: () -> Void
    let promptBar: (Bool, Namespace.ID) -> PromptBar
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
        onSplitClip: @escaping () -> Void,
        onDeleteClip: @escaping () -> Void,
        @ViewBuilder promptBar: @escaping (Bool, Namespace.ID) -> PromptBar,
        @ViewBuilder spaceExtension: () -> SpaceExtension
    ) {
        self._activeSpace = activeSpace
        self.isClipSelected = isClipSelected
        self.promptBarIsTakingOver = promptBarIsTakingOver
        self.onSplitClip = onSplitClip
        self.onDeleteClip = onDeleteClip
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
            promptBar(isClipSelected, promptNamespace)

            if isClipSelected && !promptBarIsTakingOver {
                Spacer(minLength: .spacing(.sp2))
                clipToolsCluster
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: .spacing(.sp8))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expandedToolId)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isClipSelected)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: promptBarIsTakingOver)
    }

    @ViewBuilder
    private var clipToolsCluster: some View {
        if let selected = clipTools.first(where: { $0.id == expandedToolId }) {
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

                    if case let .expandable(subItems) = selected.kind {
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
            }
        } else {
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
                ]))
        ]
    }
}
