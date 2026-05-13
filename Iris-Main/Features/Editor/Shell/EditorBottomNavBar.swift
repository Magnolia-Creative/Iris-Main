import SwiftUI

/// Permanently pinned 3-icon navigation row that selects the active editor
/// space. Frame, padding, and glass shell are constant — only the highlight
/// indicator slides and icon symbols swap fill states.
///
/// Lives as a sibling of `EditorTabBar` (the top chrome) so that selected
/// clip / prompt / tab transitions on the chrome cannot re-lay out this row.
struct EditorBottomNavBar: View {
    @Binding var activeSpace: EditorSpace

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace

    private let tabItemWidth: CGFloat = 62
    private let tabRowHeight: CGFloat = 48
    private let navCornerRadius: CGFloat = .spacing(.sp4)
    private let shellInset: CGFloat = 10

    private var navWidth: CGFloat {
        let count = CGFloat(EditorSpace.allCases.count)
        let hPad = CGFloat.spacing(.sp2) * 2
        return count * tabItemWidth + (count - 1) * CGFloat.spacing(.sp3) + hPad
    }

    /// Outer container width = nav row + symmetrical shell insets. Constant.
    private var containerWidth: CGFloat {
        navWidth + shellInset * 2
    }

    var body: some View {
        navCard
            .padding(.horizontal, shellInset)
            .padding(.vertical, shellInset)
            .frame(width: containerWidth)
    }

    private var navCard: some View {
        navigationRow
            .frame(width: navWidth)
            .glassEffect(
                .regular.tint(navTint).interactive(),
                in: RoundedRectangle(cornerRadius: navCornerRadius, style: .continuous)
            )
            .shadow(color: navInnerShadowColor, radius: 8, x: 0, y: 4)
    }

    private var navigationRow: some View {
        HStack(spacing: .spacing(.sp3)) {
            ForEach(EditorSpace.allCases) { space in
                Button {
                    let transitionMark = "space-transition-\(space.rawValue)"
                    let appearanceMark = "space-content-\(space.rawValue)"
                    EditorDebugTrace.begin(
                        transitionMark,
                        scope: "EditorBottomNavBar",
                        message: "tap from=\(activeSpace.rawValue) to=\(space.rawValue)"
                    )
                    EditorDebugTrace.begin(
                        appearanceMark,
                        scope: "EditorBottomNavBar",
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
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer, options: .nonRepeating))
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
                .buttonStyle(EditorBottomNavPressButtonStyle())
                .accessibilityLabel(Text(space.rawValue))
            }
        }
        .padding(.horizontal, .spacing(.sp2))
        .padding(.vertical, .spacing(.sp2))
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeSpace)
    }

    private var navTint: Color {
        Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12)
    }

    private var navInnerShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color.black.opacity(0.1)
    }
}

/// Springy press feedback for the pinned bottom-nav tabs.
private struct EditorBottomNavPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
