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

    @State private var style: CaptionStyle = .modern
    @State private var hasBackground: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private var expandedTool: CaptionTool? {
        guard let raw = flow.expandedStyleTool else { return nil }
        return CaptionTool(rawValue: raw)
    }

    var body: some View {
        EditorExpandableToolRow(
            expandedToolId: $flow.expandedStyleTool,
            includesTrailingSpacer: true,
            leading: {
                deselectButton
            },
            collapsed: {
                collapsedToolsStrip
            },
            expanded: { rawTool in
                if let tool = CaptionTool(rawValue: rawTool) {
                    expandedRow(for: tool)
                }
            }
        )
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
            EditorToolCloseLabel(title: "Done editing caption style")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Done editing caption style"))
    }

    // MARK: - Collapsed tools

    private var collapsedToolsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp1)) {
                Button { showDeleteConfirmation = true } label: {
                    EditorToolIconLabel(systemImage: "trash", title: "Delete captions", foreground: Color.ds.danger)
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
        EditorToolIconLabel(systemImage: systemImage, title: title)
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
        EditorToolBackButton(accessibilityLabel: "Back to caption tools") {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                flow.expandedStyleTool = nil
            }
        }
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
        EditorToolPillLabel(title: title, selected: selected)
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
