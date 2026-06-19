import SwiftUI

enum ToolButtonShape: String, CaseIterable {
    case icon
    case roundedIcon
    case pill
}

enum ToolSemanticRole: String, CaseIterable {
    case neutral
    case destructive
    case accent
}

enum ToolMetrics {
    static let toolItemWidth: CGFloat = 48
    static let roundedButtonSize: CGFloat = 40
}

struct ToolDividerComponent: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 0.75, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.20))
            .frame(width: 1.5, height: 28)
            .frame(height: ToolMetrics.toolItemWidth)
            .padding(.horizontal, .spacing(.sp1))
            .accessibilityHidden(true)
    }
}

struct ToolButtonComponent: View {
    let systemImage: String
    let title: String
    var shape: ToolButtonShape = .icon
    var role: ToolSemanticRole = .neutral
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
            ToolIconLabelComponent(
                systemImage: systemImage,
                title: title,
                foreground: foreground,
                matchedId: matchedId,
                namespace: namespace
            )
        case .roundedIcon:
            ToolRoundedIconLabelComponent(
                systemImage: systemImage,
                title: title,
                foreground: foreground
            )
        case .pill:
            ToolPillComponent(title: title, selected: role == .accent)
        }
    }
}

struct ToolIconLabelComponent: View {
    let systemImage: String
    let title: String
    var foreground: Color = Color.ds.textMuted
    var matchedId: String?
    var namespace: Namespace.ID?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .medium))
            .modifier(ToolIconMatchModifier(id: matchedId, namespace: namespace))
            .foregroundColor(foreground)
            .frame(width: ToolMetrics.toolItemWidth, height: ToolMetrics.toolItemWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(title))
    }
}

struct ToolCloseButtonComponent: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
                .frame(width: ToolMetrics.toolItemWidth, height: ToolMetrics.toolItemWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

struct ToolBackButtonComponent: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolIconLabelComponent(systemImage: "chevron.left", title: accessibilityLabel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct ToolRoundedIconLabelComponent: View {
    let systemImage: String
    let title: String
    var foreground: Color = Color.ds.textMuted

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(foreground)
            .frame(width: ToolMetrics.roundedButtonSize, height: ToolMetrics.roundedButtonSize)
            .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
            .accessibilityLabel(Text(title))
    }
}

struct ToolPillComponent: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .irisChipPickerAppearance(isSelected: selected)
    }
}

struct ExpandableToolTrayComponent<ExpandedToolID: Equatable, Leading: View, Collapsed: View, Expanded: View>: View {
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
                ToolDividerComponent()
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

private struct ToolIconMatchModifier: ViewModifier {
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
