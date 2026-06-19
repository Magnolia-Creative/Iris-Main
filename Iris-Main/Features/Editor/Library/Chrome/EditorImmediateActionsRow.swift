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
                    HStack {
                        Spacer(minLength: 0)
                        EditorToolCloseButtonComponent(title: "Dismiss chrome", action: onDismiss)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)

                    EditorToolDividerComponent()
                }

                HStack(spacing: .spacing(.sp1)) {
                    Spacer(minLength: 0)
                    actionButtons
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: .spacing(.sp8))
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
