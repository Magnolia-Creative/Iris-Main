import SwiftUI

struct TimelineToolbar: View {
    private struct ToolbarItem: Identifiable {
        let id: Int
        let systemImage: String
        let title: String
        let kind: ToolbarItemKind
    }

    private struct ToolbarSubItem: Identifiable {
        let id: Int
        let systemImage: String
        let title: String
        let action: () -> Void
    }

    private enum ToolbarItemKind {
        case expandable(subItems: [ToolbarSubItem])
        case action(action: () -> Void)
    }

    private let mainItems: [ToolbarItem] = [
        ToolbarItem(id: 0, systemImage: "character.textbox", title: "Format",
            kind: .expandable(subItems: [
                ToolbarSubItem(id: 0, systemImage: "textformat.size", title: "Size", action: {}),
                ToolbarSubItem(id: 1, systemImage: "bold", title: "Weight", action: {}),
                ToolbarSubItem(id: 2, systemImage: "textformat", title: "Style", action: {})
            ])),
        ToolbarItem(id: 1, systemImage: "eyedropper", title: "Colours",
            kind: .expandable(subItems: [
                ToolbarSubItem(id: 0, systemImage: "paintpalette", title: "Palette", action: {}),
                ToolbarSubItem(id: 1, systemImage: "drop", title: "Fill", action: {}),
                ToolbarSubItem(id: 2, systemImage: "circle.lefthalf.filled", title: "Stroke", action: {})
            ])),
        ToolbarItem(id: 3, systemImage: "sparkles", title: "Effects",
            kind: .expandable(subItems: [
                ToolbarSubItem(id: 0, systemImage: "sparkle", title: "Glow", action: {}),
                ToolbarSubItem(id: 1, systemImage: "shadow", title: "Shadow", action: {}),
                ToolbarSubItem(id: 2, systemImage: "circle.dotted", title: "Blur", action: {})
            ])),
        ToolbarItem(id: 2, systemImage: "gearshape", title: "Settings", kind: .action(action: {})),
        ToolbarItem(id: 4, systemImage: "square.and.arrow.up", title: "Upload", kind: .action(action: {}))
    ]

    let isClipSelected: Bool
    let onDeleteSelectedClip: () -> Void
    let onSplitSelectedClip: () -> Void

    @State private var selectedMainIndex = -1
    @Namespace private var iconNamespace

    private var clipItems: [ToolbarItem] {
        [
            ToolbarItem(id: 0, systemImage: "scissors", title: "Trim",
                kind: .action(action: {
                    onSplitSelectedClip()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedMainIndex = -1 }
                })),
            ToolbarItem(id: 1, systemImage: "speedometer", title: "Speed", kind: .action(action: {})),
            ToolbarItem(id: 2, systemImage: "speaker.wave.2.fill", title: "Audio",
                kind: .expandable(subItems: [
                    ToolbarSubItem(id: 0, systemImage: "speaker.wave.1", title: "Fade", action: {}),
                    ToolbarSubItem(id: 1, systemImage: "waveform", title: "Normalize", action: {}),
                    ToolbarSubItem(id: 2, systemImage: "mic.fill", title: "Replace", action: {})
                ]))
        ]
    }

    var body: some View {
        let items = isClipSelected ? clipItems : mainItems
        let selectedItem = items.first { $0.id == selectedMainIndex }
        let isExpandable: Bool = {
            guard let selectedItem else { return false }
            if case .expandable = selectedItem.kind { return true }
            return false
        }()
        let isExpanded = selectedItem != nil
        let buttonHPad: CGFloat = .spacing(.sp3)
        let buttonVPad: CGFloat = .spacing(.sp2)
        let toolbarHeight: CGFloat = .spacing(.sp9)
        let subItemWidth: CGFloat = 40

        HStack(spacing: .spacing(.sp1)) {
            if isClipSelected && !isExpanded {
                Button { onDeleteSelectedClip() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 24))
                        .foregroundColor(Color.ds.text)
                        .padding(.horizontal, buttonHPad).padding(.vertical, buttonVPad)
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

            if !isExpanded {
                ForEach(isClipSelected ? clipItems : mainItems) { item in
                    Button { handleSelection(item) } label: {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 24))
                            .foregroundColor(Color.ds.text)
                            .matchedGeometryEffect(id: "icon-\(item.id)", in: iconNamespace)
                            .padding(.horizontal, buttonHPad).padding(.vertical, buttonVPad)
                            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }
            } else if let selectedItem {
                Button { handleSelection(selectedItem) } label: {
                    HStack(spacing: .spacing(.sp2)) {
                        Image(systemName: selectedItem.systemImage)
                            .font(.system(size: 20)).foregroundColor(Color.ds.text)
                            .matchedGeometryEffect(id: "icon-\(selectedItem.id)", in: iconNamespace)
                        Text(selectedItem.title).typography(.body).foregroundColor(Color.ds.text)
                    }
                    .padding(.horizontal, buttonHPad).padding(.vertical, buttonVPad)
                    .background(Color.ds.accentBg)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))

                if case let .expandable(subItems) = selectedItem.kind {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: .spacing(.sp2)) {
                            ForEach(subItems) { subItem in
                                Button { subItem.action() } label: {
                                    VStack(spacing: .spacing(.sp1)) {
                                        Image(systemName: subItem.systemImage).font(.system(size: 16, weight: .semibold)).foregroundColor(Color.ds.text)
                                        Text(subItem.title).typography(.action).foregroundColor(Color.ds.text).multilineTextAlignment(.center)
                                    }
                                    .frame(width: subItemWidth)
                                    .padding(.horizontal, buttonHPad).padding(.vertical, buttonVPad)
                                    .background(Color.ds.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, .spacing(.sp2))
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: isExpandable ? .infinity : nil, alignment: isExpandable ? .leading : .center)
        .fixedSize(horizontal: !isExpandable, vertical: false)
        .frame(height: toolbarHeight, alignment: .center)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedMainIndex)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isClipSelected)
        .padding(.horizontal, .spacing(.sp2)).padding(.vertical, .spacing(.sp2))
        .background(Color.ds.surface)
        .cornerRadius(.spacing(.sp4))
        .padding(.horizontal, .spacing(.sp3))
        .onChange(of: isClipSelected) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selectedMainIndex = -1 }
        }
    }

    private func handleSelection(_ item: ToolbarItem) {
        if case let .action(action) = item.kind { action(); return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedMainIndex = selectedMainIndex == item.id ? -1 : item.id
        }
    }
}
