import SwiftUI

enum EditorBottomNavigationStyle: String, CaseIterable {
    case glass
    case flat
}

struct EditorBottomNavigationItem: Identifiable, Equatable {
    let id: String
    let title: String
    let selectedIconName: String
    let unselectedIconName: String
}

struct EditorBottomNavigationComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "navigation.bottomBar"
    static let category: EditorComponentCategory = .navigation
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let size: EditorComponentSize
    let style: EditorBottomNavigationStyle
    let items: [EditorBottomNavigationItem]
    @Binding var activeItemId: String

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace

    static var defaultEditorItems: [EditorBottomNavigationItem] {
        EditorSpace.allCases.map { space in
            EditorBottomNavigationItem(
                id: space.rawValue,
                title: space.rawValue,
                selectedIconName: space.selectedIconName,
                unselectedIconName: space.unselectedIconName
            )
        }
    }

    private var tabItemWidth: CGFloat {
        switch size {
        case .compressed: 52
        case .standard: 62
        case .expanded: 72
        }
    }

    private var tabRowHeight: CGFloat {
        switch size {
        case .compressed: 40
        case .standard: 48
        case .expanded: 52
        }
    }

    var body: some View {
        EditorGlassEffectContainer(spacing: tabSpacing) {
            HStack(spacing: tabSpacing) {
                ForEach(items) { item in
                    Button {
                        selectItem(item.id)
                    } label: {
                        Image(systemName: activeItemId == item.id ? item.selectedIconName : item.unselectedIconName)
                            .font(.system(size: iconSize, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color.white)
                            .contentTransition(.symbolEffect(.replace.downUp.byLayer, options: .nonRepeating))
                            .frame(width: tabItemWidth, height: tabRowHeight)
                            .background {
                                if activeItemId == item.id {
                                    selectionBubble
                                        .matchedGeometryEffect(id: "navIndicator", in: tabNamespace)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(item.title))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .modifier(NavigationChromeStyleModifier(style: style, colorScheme: colorScheme))
            .simultaneousGesture(navigationDragGesture)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeItemId)
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .compressed: 18
        case .standard: 21
        case .expanded: 24
        }
    }

    private var tabSpacing: CGFloat { .spacing(.sp3) }

    private var horizontalPadding: CGFloat { .spacing(.sp2) }

    private var verticalPadding: CGFloat { .spacing(.sp2) }

    private var indicatorCornerRadius: CGFloat { .spacing(.sp3) }

    private var selectionBubble: some View {
        let shape = RoundedRectangle(cornerRadius: indicatorCornerRadius, style: .continuous)

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
                selectItem(at: value.location.x)
            }
    }

    private func selectItem(_ id: String) {
        guard activeItemId != id else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            activeItemId = id
        }
    }

    private func selectItem(at locationX: CGFloat) {
        guard let item = item(closestTo: locationX) else { return }
        selectItem(item.id)
    }

    private func item(closestTo locationX: CGFloat) -> EditorBottomNavigationItem? {
        guard let index = items.indices.min(by: {
            abs(tabCenterX(for: $0) - locationX) < abs(tabCenterX(for: $1) - locationX)
        }) else {
            return nil
        }

        return items[index]
    }

    private func tabCenterX(for index: Int) -> CGFloat {
        horizontalPadding + CGFloat(index) * (tabItemWidth + tabSpacing) + tabItemWidth / 2
    }
}

private struct NavigationChromeStyleModifier: ViewModifier {
    let style: EditorBottomNavigationStyle
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)

        switch style {
        case .glass:
            content
                .editorRegularGlassEffect(
                    tint: Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15),
                    in: shape
                )
                .overlay(
                    shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.36), lineWidth: 0.75)
                )
                .overlay(
                    shape.stroke(Color.ds.border.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.42 : 0.12), radius: 16, x: 0, y: 10)
        case .flat:
            content
                .background(Color.ds.surface.opacity(0.9))
                .clipShape(shape)
        }
    }
}
