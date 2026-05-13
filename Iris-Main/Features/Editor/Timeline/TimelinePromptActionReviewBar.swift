import SwiftUI

/// Inline approve / reject / reprompt controls for the editor tab bar prompt slot (no outer glass).
struct TimelinePromptActionReviewPromptSlot: View {
    let session: TimelinePromptActionReviewSession
    let preview: TimelinePromptActionPreview?
    let message: String?
    let onApprove: () -> Void
    let onReject: () -> Void
    let onReprompt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(headerTitle)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let message, !message.isEmpty {
                Text(message)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
                    .lineLimit(2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, .spacing(.sp2))
                .padding(.horizontal, .spacing(.sp3))
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
}
