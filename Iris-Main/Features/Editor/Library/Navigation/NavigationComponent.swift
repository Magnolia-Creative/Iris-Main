import SwiftUI

enum NavigationStyle: String, CaseIterable {
    case glass
    case flat
}

struct NavigationItem: Identifiable, Equatable {
    let id: String
    let title: String
    let selectedIconName: String
    let unselectedIconName: String
}

struct NavigationComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "navigation.bottomBar"
    static let category: EditorComponentCategory = .navigation
    static let supportedSizes: Set<EditorComponentSize> = [.standard]

    let style: NavigationStyle
    let items: [NavigationItem]
    @Binding var activeItemId: String
    var isSuppressedByIntelligence: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @GestureState private var isDraggingNavigation = false
    @Namespace private var tabNamespace

    static var defaultShowcaseItems: [NavigationItem] {
        [
            NavigationItem(
                id: "Import",
                title: "Import",
                selectedIconName: "square.and.arrow.down.fill",
                unselectedIconName: "square.and.arrow.down"
            ),
            NavigationItem(
                id: "Edit",
                title: "Edit",
                selectedIconName: "movieclapper.fill",
                unselectedIconName: "movieclapper"
            ),
            NavigationItem(
                id: "Export",
                title: "Export",
                selectedIconName: "square.and.arrow.up.fill",
                unselectedIconName: "square.and.arrow.up"
            )
        ]
    }

    static let shellInset: CGFloat = 10
    static let tabItemWidth: CGFloat = 62
    static let tabRowHeight: CGFloat = 48

    static func navWidth(itemCount: Int = 3) -> CGFloat {
        let count = CGFloat(max(itemCount, 1))
        let hPad = horizontalPadding * 2
        return count * tabItemWidth + (count - 1) * tabSpacing + hPad
    }

    static func containerWidth(itemCount: Int = 3) -> CGFloat {
        navWidth(itemCount: itemCount) + shellInset * 2
    }

    static func totalHeight() -> CGFloat {
        let rowInnerVertical = verticalPadding * 2
        return tabRowHeight + rowInnerVertical + shellInset * 2
    }

    private static let tabSpacing: CGFloat = .spacing(.sp3)
    private static let horizontalPadding: CGFloat = .spacing(.sp2)
    private static let verticalPadding: CGFloat = .spacing(.sp2)

    var body: some View {
        navCard
            .padding(.horizontal, Self.shellInset)
            .padding(.vertical, Self.shellInset)
            .frame(
                width: Self.containerWidth(itemCount: items.count),
                height: Self.totalHeight()
            )
            .opacity(isSuppressedByIntelligence ? 0 : 1)
            .scaleEffect(isSuppressedByIntelligence ? 0.92 : 1, anchor: .trailing)
            .allowsHitTesting(!isSuppressedByIntelligence)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSuppressedByIntelligence)
    }

    private var navCard: some View {
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
                            .frame(width: Self.tabItemWidth, height: Self.tabRowHeight)
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
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .modifier(NavigationChromeStyleModifier(style: style, colorScheme: colorScheme))
            .modifier(NavigationDragGestureModifier(
                isEnabled: !isSuppressedByIntelligence,
                gesture: navigationDragGesture
            ))
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeItemId)
        }
    }

    private var iconSize: CGFloat {
        21
    }

    private var tabSpacing: CGFloat { Self.tabSpacing }

    private var indicatorCornerRadius: CGFloat { .spacing(.sp3) }

    private var selectionBubble: some View {
        let shape = RoundedRectangle(cornerRadius: indicatorCornerRadius, style: .continuous)

        return shape
            .fill(Color.white.opacity(bubbleFillOpacity))
            .editorRegularGlassEffect(
                tint: Color.white.opacity(bubbleTintOpacity),
                in: shape,
                interactive: isDraggingNavigation
            )
            .overlay(
                shape.stroke(Color.white.opacity(bubbleStrokeOpacity), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(bubbleShadowOpacity), radius: isDraggingNavigation ? 10 : 7, x: 0, y: 4)
    }

    private var navigationDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isDraggingNavigation) { _, state, _ in
                state = true
            }
            .onChanged { value in
                selectItem(at: value.location.x)
            }
    }

    private var bubbleFillOpacity: Double {
        isDraggingNavigation
            ? (colorScheme == .dark ? 0.08 : 0.12)
            : (colorScheme == .dark ? 0.12 : 0.18)
    }

    private var bubbleTintOpacity: Double {
        isDraggingNavigation
            ? (colorScheme == .dark ? 0.16 : 0.28)
            : (colorScheme == .dark ? 0.08 : 0.2)
    }

    private var bubbleStrokeOpacity: Double {
        isDraggingNavigation
            ? (colorScheme == .dark ? 0.32 : 0.56)
            : (colorScheme == .dark ? 0.22 : 0.42)
    }

    private var bubbleShadowOpacity: Double {
        isDraggingNavigation
            ? (colorScheme == .dark ? 0.42 : 0.16)
            : (colorScheme == .dark ? 0.32 : 0.12)
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

    private func item(closestTo locationX: CGFloat) -> NavigationItem? {
        guard let index = items.indices.min(by: {
            abs(tabCenterX(for: $0) - locationX) < abs(tabCenterX(for: $1) - locationX)
        }) else {
            return nil
        }

        return items[index]
    }

    private func tabCenterX(for index: Int) -> CGFloat {
        Self.horizontalPadding + CGFloat(index) * (Self.tabItemWidth + tabSpacing) + Self.tabItemWidth / 2
    }
}

private struct NavigationDragGestureModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(gesture)
        } else {
            content
        }
    }
}

private struct NavigationChromeStyleModifier: ViewModifier {
    let style: NavigationStyle
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
