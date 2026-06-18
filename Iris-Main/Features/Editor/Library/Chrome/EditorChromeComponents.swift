import SwiftUI

struct EditorToolbarItem: Identifiable {
    let id: String
    let category: EditorComponentCategory
    var placementPriority: Int
    var isVisible: Bool
    let content: AnyView

    init<Content: View>(
        id: String,
        category: EditorComponentCategory,
        placementPriority: Int = 0,
        isVisible: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.category = category
        self.placementPriority = placementPriority
        self.isVisible = isVisible
        self.content = AnyView(content())
    }
}

struct EditorChromeSurfaceComponent<Content: View>: View {
    var cornerRadius: CGFloat = 24
    let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp3))
            .editorRegularGlassEffect(
                tint: Color.white.opacity(colorScheme == .dark ? 0.02 : 0.08),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.55) : Color.black.opacity(0.12),
                radius: 20,
                x: 0,
                y: 14
            )
    }
}

struct EditorComponentToolbar: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "toolbar.collection"
    static let category: EditorComponentCategory = .chrome
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let axis: EditorComponentAxis
    let items: [EditorToolbarItem]

    private var visibleItems: [EditorToolbarItem] {
        items.filter(\.isVisible).sorted { $0.placementPriority > $1.placementPriority }
    }

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .spacing(.sp2)) {
                        ForEach(visibleItems) { item in
                            item.content
                        }
                    }
                }
            case .vertical:
                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    ForEach(visibleItems) { item in
                        item.content
                    }
                }
            }
        }
        .frame(minHeight: .spacing(.sp8))
    }
}

private struct EditorChromeToolbarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct EditorChromeNavigationSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct EditorBottomChromeAssemblyComponent<Navigation: View>: View {
    let showsNavigation: Bool
    let navigation: () -> Navigation
    let toolbarItems: [EditorToolbarItem]
    let toolbarAxis: EditorComponentAxis

    @State private var toolbarHeight: CGFloat = 0
    @State private var navigationSize: CGSize = .zero

    init(
        showsNavigation: Bool = true,
        toolbarItems: [EditorToolbarItem] = [],
        toolbarAxis: EditorComponentAxis = .horizontal,
        @ViewBuilder navigation: @escaping () -> Navigation
    ) {
        self.showsNavigation = showsNavigation
        self.toolbarItems = toolbarItems
        self.toolbarAxis = toolbarAxis
        self.navigation = navigation
    }

    private var visibleToolbarItems: [EditorToolbarItem] {
        toolbarItems.filter(\.isVisible).sorted { $0.placementPriority > $1.placementPriority }
    }

    private var showsSubchrome: Bool {
        !visibleToolbarItems.isEmpty
    }

    private var subchromeTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom))
    }

    private var navigationCutoutSize: CGSize {
        CGSize(
            width: navigationSize.width + .spacing(.sp3),
            height: navigationSize.height + .spacing(.sp2)
        )
    }

    private var navigationCutoutOffsetY: CGFloat {
        toolbarHeight + .spacing(.sp2) - .spacing(.sp1)
    }

    var body: some View {
        VStack(spacing: .spacing(.sp2)) {
            if showsSubchrome {
                EditorComponentToolbar(axis: toolbarAxis, items: visibleToolbarItems)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: EditorChromeToolbarHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showsNavigation {
                navigation()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: EditorChromeNavigationSizePreferenceKey.self,
                                value: proxy.size
                            )
                        }
                    }
            }
        }
        .padding(.bottom, showsSubchrome ? .spacing(.sp2) : 0)
        .background {
            if showsSubchrome {
                EditorChromeSurfaceComponent {
                    Color.clear
                }
                .mask {
                    ZStack(alignment: .top) {
                        Rectangle().fill(Color.white)

                        if showsNavigation, navigationSize != .zero {
                            RoundedRectangle(
                                cornerRadius: navigationCutoutSize.height / 2,
                                style: .continuous
                            )
                            .fill(Color.white)
                            .frame(width: navigationCutoutSize.width, height: navigationCutoutSize.height)
                            .offset(y: navigationCutoutOffsetY)
                            .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
                .transition(subchromeTransition)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showsSubchrome)
        .onPreferenceChange(EditorChromeToolbarHeightPreferenceKey.self) { toolbarHeight = $0 }
        .onPreferenceChange(EditorChromeNavigationSizePreferenceKey.self) { navigationSize = $0 }
    }
}
