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

struct EditorBottomChromeAssemblyComponent<Navigation: View>: View {
    let showsNavigation: Bool
    let navigation: () -> Navigation
    let toolbarItems: [EditorToolbarItem]
    let toolbarAxis: EditorComponentAxis

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

    var body: some View {
        VStack(spacing: .spacing(.sp2)) {
            if showsSubchrome {
                EditorChromeSurfaceComponent {
                    EditorComponentToolbar(axis: toolbarAxis, items: toolbarItems)
                }
            }

            if showsNavigation {
                navigation()
            }
        }
    }
}
