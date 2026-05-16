import SwiftUI

struct CaptionsChromeView: View {
    @ObservedObject var flow: CaptionsFlowController
    @ObservedObject var controller: TimelineController

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            if let message = flow.validationMessage, !message.isEmpty {
                Text(message)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.danger)
            }

            switch flow.phase {
            case .idle:
                EmptyView()
            case .processing:
                ProgressView()
                Text("Generating captions…")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            case .editingStyle(let groupId):
                CaptionStyleEditorView(flow: flow, controller: controller, groupId: groupId)
            }
        }
    }
}

private struct CaptionStyleEditorView: View {
    @ObservedObject var flow: CaptionsFlowController
    @ObservedObject var controller: TimelineController
    let groupId: String

    @Environment(\.colorScheme) private var colorScheme

    @State private var style: CaptionStyle = .modern
    @State private var hasBackground: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private let toolItemWidth: CGFloat = 48

    private var expandedTool: CaptionTool? {
        guard let raw = flow.expandedStyleTool else { return nil }
        return CaptionTool(rawValue: raw)
    }

    var body: some View {
        HStack(spacing: .spacing(.sp2)) {
            deselectButton

            promptDivider

            ZStack(alignment: .leading) {
                if let tool = expandedTool {
                    expandedRow(for: tool)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                } else {
                    collapsedToolsStrip
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                }
            }
            .contentTransition(.opacity)

            Spacer(minLength: 0)
        }
        .frame(minHeight: .spacing(.sp8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: flow.expandedStyleTool)
        .onAppear { syncFromState() }
        .onChange(of: flow.phase) { _, _ in syncFromState() }
        .alert("Delete all captions?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteAllCaptions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove every caption in this group from your timeline. This action cannot be undone.")
        }
    }

    // MARK: - Leading

    private var deselectButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                flow.finishStyleEditing()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
                .frame(width: toolItemWidth, height: toolItemWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Done editing caption style"))
    }

    private var promptDivider: some View {
        RoundedRectangle(cornerRadius: 0.75, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.20))
            .frame(width: 1.5, height: 28)
            .padding(.horizontal, .spacing(.sp1))
            .accessibilityHidden(true)
    }

    // MARK: - Collapsed tools

    private var collapsedToolsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp1)) {
                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color.ds.danger)
                        .frame(width: toolItemWidth, height: toolItemWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete captions"))
                .transition(.opacity.combined(with: .scale))

                ForEach(CaptionTool.allCases) { tool in
                    Button { handleToolTap(tool) } label: {
                        toolLabel(systemImage: tool.systemImage, title: tool.title)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func toolLabel(
        systemImage: String,
        title: String
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(Color.ds.textMuted)
            .frame(width: toolItemWidth, height: toolItemWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(title))
    }

    private func handleToolTap(_ tool: CaptionTool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            flow.expandedStyleTool = (expandedTool == tool) ? nil : tool.rawValue
        }
    }

    // MARK: - Expanded rows

    @ViewBuilder
    private func expandedRow(for tool: CaptionTool) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            backToToolsButton

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacing(.sp2)) {
                    switch tool {
                    case .style:
                        ForEach(CaptionStyle.allCases, id: \.self) { option in
                            stylePill(option)
                        }
                    case .background:
                        backgroundPill(on: false)
                        backgroundPill(on: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .transition(.opacity)
    }

    private var backToToolsButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                flow.expandedStyleTool = nil
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back to caption tools"))
    }

    // MARK: - Option pills

    private func stylePill(_ option: CaptionStyle) -> some View {
        let selected = style == option
        return Button {
            style = option
            flow.updateEditingGroup(style: option, hasBackground: hasBackground)
        } label: {
            pillLabel(option.rawValue.capitalized, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.rawValue.capitalized))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func backgroundPill(on: Bool) -> some View {
        let selected = hasBackground == on
        return Button {
            hasBackground = on
            flow.updateEditingGroup(style: style, hasBackground: on)
        } label: {
            pillLabel(on ? "On" : "Off", selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(on ? "Background on" : "Background off"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pillLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .typography(.bodySmall)
            .foregroundColor(selected ? Color.ds.accentFg : Color.ds.text)
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp2))
            .editorRegularGlassEffect(
                tint: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.ds.accentFg : Color.ds.border, lineWidth: selected ? 2 : 1)
            )
    }

    // MARK: - State sync

    private func syncFromState() {
        guard let g = controller.state.captionGroups.first(where: { $0.groupId == groupId }) else { return }
        style = g.style
        hasBackground = g.hasBackground
    }

    private func deleteAllCaptions() {
        do {
            try controller.deleteCaptionGroup(groupId: groupId)
        } catch {
            print("[CaptionsChrome] failed to delete caption group \(groupId): \(error)")
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            flow.finishStyleEditing()
        }
    }
}

private enum CaptionTool: String, CaseIterable, Identifiable {
    case style
    case background

    var id: String { rawValue }

    var title: String {
        switch self {
        case .style: return "Style"
        case .background: return "Background"
        }
    }

    var systemImage: String {
        switch self {
        case .style: return "textformat"
        case .background: return "rectangle.fill.on.rectangle.fill"
        }
    }
}
