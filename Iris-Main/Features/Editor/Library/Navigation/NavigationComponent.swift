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
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let size: EditorComponentSize
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

    static func shellInset(for size: EditorComponentSize) -> CGFloat {
        switch size {
        case .compressed: 8
        case .standard: 10
        case .expanded: 12
        }
    }

    static func navWidth(for size: EditorComponentSize, itemCount: Int = 3) -> CGFloat {
        let count = CGFloat(max(itemCount, 1))
        let hPad = horizontalPadding * 2
        return count * tabItemWidth(for: size) + (count - 1) * tabSpacing + hPad
    }

    static func containerWidth(for size: EditorComponentSize, itemCount: Int = 3) -> CGFloat {
        navWidth(for: size, itemCount: itemCount) + shellInset(for: size) * 2
    }

    static func totalHeight(for size: EditorComponentSize) -> CGFloat {
        let rowInnerVertical = verticalPadding * 2
        return tabRowHeight(for: size) + rowInnerVertical + shellInset(for: size) * 2
    }

    static func tabItemWidth(for size: EditorComponentSize) -> CGFloat {
        switch size {
        case .compressed: 52
        case .standard: 62
        case .expanded: 72
        }
    }

    static func tabRowHeight(for size: EditorComponentSize) -> CGFloat {
        switch size {
        case .compressed: 40
        case .standard: 48
        case .expanded: 52
        }
    }

    private static let tabSpacing: CGFloat = .spacing(.sp3)
    private static let horizontalPadding: CGFloat = .spacing(.sp2)
    private static let verticalPadding: CGFloat = .spacing(.sp2)

    private var tabItemWidth: CGFloat { Self.tabItemWidth(for: size) }
    private var tabRowHeight: CGFloat { Self.tabRowHeight(for: size) }

    var body: some View {
        navCard
            .padding(.horizontal, Self.shellInset(for: size))
            .padding(.vertical, Self.shellInset(for: size))
            .frame(
                width: Self.containerWidth(for: size, itemCount: items.count),
                height: Self.totalHeight(for: size)
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
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .modifier(NavigationChromeStyleModifier(style: style, colorScheme: colorScheme))
            .simultaneousGesture(isSuppressedByIntelligence ? nil : navigationDragGesture)
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
        Self.horizontalPadding + CGFloat(index) * (tabItemWidth + tabSpacing) + tabItemWidth / 2
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
