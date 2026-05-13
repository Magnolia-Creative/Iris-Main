import SwiftUI

struct TimelinePromptActionReviewBar: View {
    let session: TimelinePromptActionReviewSession
    let preview: TimelinePromptActionPreview?
    let message: String?
    let onApprove: () -> Void
    let onReject: () -> Void
    let onReprompt: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text(headerTitle)
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)

                if let message, !message.isEmpty {
                    Text(message)
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.danger)
                }

                HStack(spacing: .spacing(.sp2)) {
                    outlinedButton(
                        title: "Approve",
                        foreground: Color.ds.accentFg,
                        border: Color.ds.accentFg,
                        action: onApprove
                    )

                    outlinedButton(
                        title: "Reject",
                        foreground: Color.ds.danger,
                        border: Color.ds.danger,
                        action: onReject
                    )

                    outlinedButton(
                        title: "Reprompt",
                        foreground: Color.ds.accentFg,
                        border: Color.ds.accentFg,
                        action: onReprompt
                    )
                }
            }
            .padding(.horizontal, .spacing(.sp4))
            .padding(.top, .spacing(.sp4))
            .padding(.bottom, .spacing(.sp3))
            .glassEffect(
                .regular.tint(shellTint),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: outerShadowColor, radius: 20, x: 0, y: 14)
        }
    }

    private var headerTitle: String {
        let step = "\(session.displayPosition) of \(session.totalCount)"
        if let preview {
            return "\(preview.title) (\(step))"
        }
        return "Preview edit (\(step))"
    }

    private func outlinedButton(
        title: String,
        foreground: Color,
        border: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, .spacing(.sp2))
                .padding(.horizontal, .spacing(.sp2))
        }
        .buttonStyle(.plain)
        .typographyStyle(.action)
        .foregroundStyle(foreground)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp1), style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1), style: .continuous))
    }

    private var shellTint: Color {
        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.08)
    }

    private var outerShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.55)
            : Color.black.opacity(0.12)
    }
}
