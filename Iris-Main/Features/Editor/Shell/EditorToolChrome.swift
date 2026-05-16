import SwiftUI

enum EditorToolChromeMetrics {
    static let toolItemWidth: CGFloat = 48
    static let roundedButtonSize: CGFloat = 40
}

struct EditorToolDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 0.75, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.20))
            .frame(width: 1.5, height: 28)
            .padding(.horizontal, .spacing(.sp1))
            .accessibilityHidden(true)
    }
}

struct EditorToolIconLabel: View {
    let systemImage: String
    let title: String
    var foreground: Color = Color.ds.textMuted
    var matchedId: String?
    var namespace: Namespace.ID?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .medium))
            .modifier(EditorToolIconMatchModifier(id: matchedId, namespace: namespace))
            .foregroundColor(foreground)
            .frame(width: EditorToolChromeMetrics.toolItemWidth, height: EditorToolChromeMetrics.toolItemWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(title))
    }
}

struct EditorToolCloseLabel: View {
    let title: String

    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(Color.ds.textMuted)
            .frame(width: EditorToolChromeMetrics.toolItemWidth, height: EditorToolChromeMetrics.toolItemWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(title))
    }
}

struct EditorToolRoundedIconLabel: View {
    let systemImage: String
    let title: String
    var foreground: Color = Color.ds.textMuted

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(foreground)
            .frame(width: EditorToolChromeMetrics.roundedButtonSize, height: EditorToolChromeMetrics.roundedButtonSize)
            .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
            .accessibilityLabel(Text(title))
    }
}

struct EditorToolBackButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EditorToolRoundedIconLabel(systemImage: "chevron.left", title: accessibilityLabel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct EditorToolPillLabel: View {
    let title: String
    let selected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .typography(.bodySmall)
            .foregroundColor(selected ? Color.ds.accentFg : Color.ds.text)
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp2))
            .editorRegularGlassEffect(
                tint: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.ds.accentFg : Color.ds.border, lineWidth: selected ? 2 : 1)
            )
    }
}

/// Applies `matchedGeometryEffect` only when `id` and `namespace` are non-nil.
private struct EditorToolIconMatchModifier: ViewModifier {
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
