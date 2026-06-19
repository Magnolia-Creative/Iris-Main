import SwiftUI

struct EditorImmediateActionsRow: View {
    let actions: [EditorChromeActionItem]
    let onAction: (EditorChromeActionItem) -> Void

    var body: some View {
        if actions.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacing(.sp1)) {
                    ForEach(actions) { action in
                        EditorToolButtonComponent(
                            systemImage: action.systemImage,
                            title: action.title,
                            role: action.role.toolRole,
                            action: { onAction(action) }
                        )
                        .disabled(!action.isEnabled)
                        .opacity(action.isEnabled ? 1 : 0.45)
                    }
                }
            }
            .frame(minHeight: .spacing(.sp8))
        }
    }
}

private extension EditorChromeActionRole {
    var toolRole: EditorToolSemanticRole {
        switch self {
        case .neutral: return .neutral
        case .destructive: return .destructive
        case .accent: return .accent
        }
    }
}
