import SwiftUI

enum EditorToolButtonShape: String, CaseIterable {
    case icon
    case roundedIcon
    case pill
}

enum EditorToolSemanticRole: String, CaseIterable {
    case neutral
    case destructive
    case accent
}

enum EditorLibraryToolChromeMetrics {
    static let toolItemWidth: CGFloat = 48
    static let roundedButtonSize: CGFloat = 40
}

struct EditorToolDividerComponent: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 0.75, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.20))
            .frame(width: 1.5, height: 28)
            .frame(height: EditorLibraryToolChromeMetrics.toolItemWidth)
            .padding(.horizontal, .spacing(.sp1))
            .accessibilityHidden(true)
    }
}

struct EditorToolButtonComponent: View {
    let systemImage: String
    let title: String
    var shape: EditorToolButtonShape = .icon
    var role: EditorToolSemanticRole = .neutral
    var matchedId: String?
    var namespace: Namespace.ID?
    let action: () -> Void

    private var foreground: Color {
        switch role {
        case .neutral: Color.ds.textMuted
        case .destructive: Color.ds.danger
        case .accent: Color.ds.accentFg
        }
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    @ViewBuilder
    private var label: some View {
        switch shape {
        case .icon:
            EditorToolIconLabelComponent(
                systemImage: systemImage,
                title: title,
                foreground: foreground,
                matchedId: matchedId,
                namespace: namespace
            )
        case .roundedIcon:
            EditorToolRoundedIconLabelComponent(
                systemImage: systemImage,
                title: title,
                foreground: foreground
            )
        case .pill:
            EditorToolPillComponent(title: title, selected: role == .accent)
        }
    }
}

struct EditorToolIconLabelComponent: View {
    let systemImage: String
    let title: String
    var foreground: Color = Color.ds.textMuted
    var matchedId: String?
    var namespace: Namespace.ID?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .medium))
            .modifier(EditorLibraryToolIconMatchModifier(id: matchedId, namespace: namespace))
            .foregroundColor(foreground)
            .frame(width: EditorLibraryToolChromeMetrics.toolItemWidth, height: EditorLibraryToolChromeMetrics.toolItemWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(title))
    }
}

struct EditorToolCloseButtonComponent: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
                .frame(width: EditorLibraryToolChromeMetrics.toolItemWidth, height: EditorLibraryToolChromeMetrics.toolItemWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

struct EditorToolBackButtonComponent: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EditorToolIconLabelComponent(systemImage: "chevron.left", title: accessibilityLabel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct EditorToolRoundedIconLabelComponent: View {
    let systemImage: String
    let title: String
    var foreground: Color = Color.ds.textMuted

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(foreground)
            .frame(width: EditorLibraryToolChromeMetrics.roundedButtonSize, height: EditorLibraryToolChromeMetrics.roundedButtonSize)
            .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
            .accessibilityLabel(Text(title))
    }
}

struct EditorToolPillComponent: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .irisChipPickerAppearance(isSelected: selected)
    }
}

struct EditorExpandableToolTrayComponent<ExpandedToolID: Equatable, Leading: View, Collapsed: View, Expanded: View>: View {
    @Binding var expandedToolId: ExpandedToolID?
    var showsLeadingWhenExpanded: Bool = true
    var includesTrailingSpacer: Bool = false
    let leading: () -> Leading
    let collapsed: () -> Collapsed
    let expanded: (ExpandedToolID) -> Expanded

    init(
        expandedToolId: Binding<ExpandedToolID?>,
        showsLeadingWhenExpanded: Bool = true,
        includesTrailingSpacer: Bool = false,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder collapsed: @escaping () -> Collapsed,
        @ViewBuilder expanded: @escaping (ExpandedToolID) -> Expanded
    ) {
        self._expandedToolId = expandedToolId
        self.showsLeadingWhenExpanded = showsLeadingWhenExpanded
        self.includesTrailingSpacer = includesTrailingSpacer
        self.leading = leading
        self.collapsed = collapsed
        self.expanded = expanded
    }

    private var isExpanded: Bool {
        expandedToolId != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: .spacing(.sp2)) {
            if !isExpanded || showsLeadingWhenExpanded {
                leading()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                EditorToolDividerComponent()
                    .transition(.opacity)
            }

            ZStack(alignment: .leading) {
                if let expandedToolId {
                    expanded(expandedToolId)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                } else {
                    collapsed()
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)

            if includesTrailingSpacer {
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: .spacing(.sp8), alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
    }
}

private struct EditorLibraryToolIconMatchModifier: ViewModifier {
    let id: String?
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id, let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
