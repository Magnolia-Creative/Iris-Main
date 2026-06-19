import SwiftUI

struct EditorImmediateActionsRow: View {
    let actions: [EditorChromeActionItem]
    var isDismissable: Bool = false
    var onDismiss: () -> Void = {}
    let onAction: (EditorChromeActionItem) -> Void

    var body: some View {
        if actions.isEmpty, !isDismissable {
            EmptyView()
        } else {
            HStack(spacing: .spacing(.sp2)) {
                if isDismissable {
                    EditorToolCloseButtonComponent(title: "Dismiss chrome", action: onDismiss)

                    EditorToolDividerComponent()
                }

                actionButtons
            }
            .frame(maxWidth: .infinity, minHeight: .spacing(.sp8), alignment: .center)
        }
    }

    private var actionButtons: some View {
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
