import SwiftUI

/// Permanently pinned 3-icon navigation row that selects the active editor
/// space. Frame, padding, and glass shell are constant — only the liquid
/// glass bubble slides and icon symbols swap fill states.
///
/// Lives as a sibling of `EditorTabBar` (the top chrome) so that selected
/// clip / prompt / tab transitions on the chrome cannot re-lay out this row.
struct EditorBottomNavBar: View {
    @Binding var activeSpace: EditorSpace

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace

    fileprivate static let tabItemWidth: CGFloat = 62
    fileprivate static let tabRowHeight: CGFloat = 48
    fileprivate static let tabSpacing: CGFloat = .spacing(.sp3)
    fileprivate static let horizontalPadding: CGFloat = .spacing(.sp2)
    fileprivate static let verticalPadding: CGFloat = .spacing(.sp2)
    fileprivate static let navCornerRadius: CGFloat = .spacing(.sp4)
    fileprivate static let indicatorCornerRadius: CGFloat = .spacing(.sp3)
    fileprivate static let shellInset: CGFloat = 10

    /// Total laid-out height including the surrounding shell insets. Callers
    /// (e.g. `EditorContainerView`) use this to reserve overlap space inside
    /// the top chrome so the nav bar can float in front of it in z.
    static var totalHeight: CGFloat {
        let rowInnerVertical = verticalPadding * 2
        return tabRowHeight + rowInnerVertical + shellInset * 2
    }

    /// Width of the nav card (3-icon row + its inner padding), without the
    /// surrounding shell insets.
    static var navWidth: CGFloat {
        let count = CGFloat(EditorSpace.allCases.count)
        let hPad = horizontalPadding * 2
        return count * tabItemWidth + (count - 1) * tabSpacing + hPad
    }

    /// Outer container width = nav card + symmetrical shell insets. Constant.
    static var containerWidth: CGFloat {
        navWidth + shellInset * 2
    }

    var body: some View {
        navCard
            .padding(.horizontal, Self.shellInset)
            .padding(.vertical, Self.shellInset)
            .frame(width: Self.containerWidth, height: Self.totalHeight)
    }

    private var navCard: some View {
        EditorGlassEffectContainer(spacing: Self.tabSpacing) {
            navigationRow
                .frame(width: Self.navWidth)
                .editorRegularGlassEffect(
                    tint: navTint,
                    in: navShape
                )
                .overlay(
                    navShape.stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.36), lineWidth: 0.75)
                )
                .overlay(
                    navShape.stroke(Color.ds.border.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: navInnerShadowColor, radius: 8, x: 0, y: 4)
                .simultaneousGesture(navigationDragGesture)
        }
    }

    private var navigationRow: some View {
        HStack(spacing: Self.tabSpacing) {
            ForEach(EditorSpace.allCases) { space in
                Button {
                    selectSpace(space, source: "tap")
                } label: {
                    Image(systemName: activeSpace == space ? space.selectedIconName : space.unselectedIconName)
                        .font(.system(size: 21, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.white)
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer, options: .nonRepeating))
                        .frame(width: Self.tabItemWidth, height: Self.tabRowHeight)
                        .background {
                            if activeSpace == space {
                                selectionBubble
                                    .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(space.rawValue))
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeSpace)
    }

    private var navShape: some Shape {
        RoundedRectangle(cornerRadius: Self.navCornerRadius, style: .continuous)
    }

    private var selectionBubble: some View {
        let shape = RoundedRectangle(cornerRadius: Self.indicatorCornerRadius, style: .continuous)

        return shape
            .fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18))
            .editorRegularGlassEffect(
                tint: Color.white.opacity(colorScheme == .dark ? 0.08 : 0.2),
                in: shape
            )
            .overlay(
                shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.42), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.12), radius: 7, x: 0, y: 4)
    }

    private var navigationDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                selectSpace(at: value.location.x)
            }
    }

    private var navTint: Color {
        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15)
    }

    private var navInnerShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color.black.opacity(0.1)
    }

    private func selectSpace(_ space: EditorSpace, source: String) {
        guard activeSpace != space else { return }

        let transitionMark = "space-transition-\(space.rawValue)"
        let appearanceMark = "space-content-\(space.rawValue)"
        EditorDebugTrace.begin(
            transitionMark,
            scope: "EditorBottomNavBar",
            message: "\(source) from=\(activeSpace.rawValue) to=\(space.rawValue)"
        )
        EditorDebugTrace.begin(
            appearanceMark,
            scope: "EditorBottomNavBar",
            message: "waiting for content appearance space=\(space.rawValue)"
        )

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            activeSpace = space
        }
    }

    private func selectSpace(at locationX: CGFloat) {
        let spaces = EditorSpace.allCases
        guard let index = spaces.indices.min(by: {
            abs(tabCenterX(for: $0) - locationX) < abs(tabCenterX(for: $1) - locationX)
        }) else {
            return
        }

        selectSpace(spaces[index], source: "drag")
    }

    private func tabCenterX(for index: Int) -> CGFloat {
        Self.horizontalPadding + CGFloat(index) * (Self.tabItemWidth + Self.tabSpacing) + Self.tabItemWidth / 2
    }
}
