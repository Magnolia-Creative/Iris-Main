import SwiftUI

struct AddClipButton: View {
    let onSelect: (TrackKind, ImportSource) -> Void
    @Binding var isMenuOpen: Bool
    private let size: CGFloat = .spacing(.sp8)
    private let menuWidth: CGFloat = .spacing(.sp7) * 4
    @State private var activeMenuOption: MenuOption?

    var body: some View {
        VStack(alignment: .trailing, spacing: .spacing(.sp2)) {
            if isMenuOpen {
                VStack(spacing: 0) {
                    if let activeMenuOption {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { self.activeMenuOption = nil }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                                Text("Back").typography(.action)
                            }
                            .foregroundColor(Color.ds.accentFg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, .sp3).padding(.vertical, .sp2)
                            .background(Color.ds.bg.opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        Divider().background(Color.ds.border)

                        ForEach(activeMenuOption.submenuOptions, id: \.self) { option in
                            Button {
                                onSelect(activeMenuOption.kind, option.source)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    isMenuOpen = false
                                    self.activeMenuOption = nil
                                }
                            } label: {
                                HStack {
                                    Image(systemName: option.iconName).font(.system(size: 14, weight: .medium))
                                    Text(option.label).typography(.action)
                                }
                                .foregroundColor(Color.ds.accentFg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, .sp3).padding(.vertical, .sp2)
                                .background(Color.ds.bg.opacity(0.5))
                            }
                            .buttonStyle(.plain)

                            if option != activeMenuOption.submenuOptions.last {
                                Divider().background(Color.ds.border)
                            }
                        }
                    } else {
                        ForEach(MenuOption.allCases, id: \.self) { option in
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { activeMenuOption = option }
                            } label: {
                                HStack {
                                    Image(systemName: option.iconName).font(.system(size: 14, weight: .medium))
                                    Text(option.label).typography(.action)
                                }
                                .foregroundColor(Color.ds.accentFg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, .sp3).padding(.vertical, .sp2)
                                .background(Color.ds.bg.opacity(0.5))
                            }
                            .buttonStyle(.plain)

                            if option != MenuOption.allCases.last {
                                Divider().background(Color.ds.border)
                            }
                        }
                    }
                }
                .frame(width: menuWidth)
                .background(Color.ds.bg.opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.accentFg, lineWidth: 2))
                .cornerRadius(.spacing(.sp2))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            } else {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { isMenuOpen = true }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: .spacing(.sp2))
                            .fill(Color.ds.bg.opacity(0.75))
                            .frame(width: size, height: size)
                            .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.accentFg, lineWidth: 2))
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Color.ds.accentFg)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: isMenuOpen) { _, isOpen in
            if !isOpen { activeMenuOption = nil }
        }
    }
}

private enum MenuOption: CaseIterable, Equatable {
    case text, video, audio

    var label: String {
        switch self { case .text: "Add Text"; case .video: "Add Video"; case .audio: "Add Audio" }
    }

    var iconName: String {
        switch self { case .text: "textformat"; case .video: "video"; case .audio: "waveform" }
    }

    var kind: TrackKind {
        switch self { case .text: .overlay; case .video: .video; case .audio: .audio }
    }

    var submenuOptions: [SubmenuOption] {
        switch self {
        case .text: [.textBox, .caption]
        case .video, .audio: [.photos, .files]
        }
    }
}

private enum SubmenuOption: CaseIterable, Equatable {
    case textBox, caption, photos, files

    var label: String {
        switch self { case .textBox: "Text Box"; case .caption: "Caption"; case .photos: "Photos"; case .files: "Files" }
    }

    var iconName: String {
        switch self { case .textBox: "text.cursor"; case .caption: "captions.bubble"; case .photos: "photo"; case .files: "doc" }
    }

    var source: ImportSource {
        switch self { case .textBox: .textBox; case .caption: .caption; case .photos: .photos; case .files: .files }
    }
}
