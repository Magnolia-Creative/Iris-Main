import SwiftUI

private enum LibraryCaptionTool: String, CaseIterable, Identifiable {
    case style
    case background

    var id: String { rawValue }

    var title: String {
        switch self {
        case .style: "Style"
        case .background: "Background"
        }
    }

    var systemImage: String {
        switch self {
        case .style: "textformat"
        case .background: "rectangle.fill.on.rectangle.fill"
        }
    }
}

struct ComponentLibraryCaptionToolsDemo: View {
    let context: EditorCaptionToolContext
    let actions: EditorCaptionToolActions

    @State private var style: CaptionStyle
    @State private var hasBackground: Bool
    @State private var showDeleteConfirmation = false

    init(context: EditorCaptionToolContext, actions: EditorCaptionToolActions) {
        self.context = context
        self.actions = actions
        _style = State(initialValue: context.style)
        _hasBackground = State(initialValue: context.hasBackground)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            if let message = context.validationMessage, !message.isEmpty {
                Text(message)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.danger)
            }

            EditorExpandableToolTrayComponent(
                expandedToolId: context.expandedToolId,
                includesTrailingSpacer: true,
                leading: {
                    EditorToolCloseButtonComponent(title: "Done editing caption style") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            actions.onFinishEditing()
                        }
                    }
                },
                collapsed: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: .spacing(.sp1)) {
                            EditorToolButtonComponent(
                                systemImage: "trash",
                                title: "Delete captions",
                                role: .destructive,
                                action: { showDeleteConfirmation = true }
                            )
                            ForEach(LibraryCaptionTool.allCases) { tool in
                                EditorToolButtonComponent(
                                    systemImage: tool.systemImage,
                                    title: tool.title,
                                    action: { toggleTool(tool) }
                                )
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                },
                expanded: { rawTool in
                    if let tool = LibraryCaptionTool(rawValue: rawTool) {
                        expandedRow(for: tool)
                    }
                }
            )
        }
        .alert("Delete all captions?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: actions.onDeleteCaptions)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove every caption in this group from your timeline.")
        }
        .onChange(of: context.style) { _, newValue in style = newValue }
        .onChange(of: context.hasBackground) { _, newValue in hasBackground = newValue }
    }

    private func toggleTool(_ tool: LibraryCaptionTool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            let current = context.expandedToolId.wrappedValue
            context.expandedToolId.wrappedValue = current == tool.rawValue ? nil : tool.rawValue
        }
    }

    @ViewBuilder
    private func expandedRow(for tool: LibraryCaptionTool) -> some View {
        HStack(spacing: .spacing(.sp2)) {
            EditorToolBackButtonComponent(accessibilityLabel: "Back to caption tools") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    context.expandedToolId.wrappedValue = nil
                }
            }

            switch tool {
            case .style:
                ParameterSegmentedPillControlComponent(
                    title: nil,
                    options: CaptionStyle.allCases.map {
                        ParameterSegmentedPillOption(id: $0.rawValue, title: $0.rawValue.capitalized)
                    },
                    selectionId: Binding(
                        get: { style.rawValue },
                        set: { raw in
                            if let option = CaptionStyle(rawValue: raw) {
                                style = option
                                actions.onUpdateStyle(option, hasBackground)
                            }
                        }
                    )
                )
            case .background:
                ParameterSegmentedPillControlComponent(
                    title: nil,
                    options: [
                        ParameterSegmentedPillOption(id: "off", title: "Off"),
                        ParameterSegmentedPillOption(id: "on", title: "On")
                    ],
                    selectionId: Binding(
                        get: { hasBackground ? "on" : "off" },
                        set: { raw in
                            hasBackground = raw == "on"
                            actions.onUpdateStyle(style, hasBackground)
                        }
                    )
                )
            }
        }
    }
}
