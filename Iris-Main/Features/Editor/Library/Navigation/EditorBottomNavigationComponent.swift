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
        HStack(spacing: .spacing(.sp3)) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activeItemId = item.id
                    }
                } label: {
                    Image(systemName: activeItemId == item.id ? item.selectedIconName : item.unselectedIconName)
                        .font(.system(size: iconSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.white)
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer, options: .nonRepeating))
                        .frame(width: tabItemWidth, height: tabRowHeight)
                        .background {
                            if activeItemId == item.id {
                                RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous)
                                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22))
                                    .matchedGeometryEffect(id: "navIndicator", in: tabNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.title))
            }
        }
        .padding(.horizontal, .spacing(.sp2))
        .padding(.vertical, .spacing(.sp2))
        .modifier(NavigationChromeStyleModifier(style: style, colorScheme: colorScheme))
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeItemId)
    }

    private var iconSize: CGFloat {
        switch size {
        case .compressed: 18
        case .standard: 21
        case .expanded: 24
        }
    }
}

private struct NavigationChromeStyleModifier: ViewModifier {
    let style: EditorBottomNavigationStyle
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            content
                .editorRegularGlassEffect(
                    tint: Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12),
                    in: RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous),
                    interactive: true
                )
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous)
                        .stroke(Color.ds.border, lineWidth: 1)
                )
        case .flat:
            content
                .background(Color.ds.surface.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
        }
    }
}
