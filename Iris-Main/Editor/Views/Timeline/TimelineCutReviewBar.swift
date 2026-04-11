import SwiftUI

struct TimelineCutReviewBar: View {
    let review: TimelineCutReviewSession
    let isSending: Bool
    let onApprove: () -> Void
    let onApproveAll: () -> Void
    let onCancelCut: (() -> Void)?
    let onShowRepromptComposer: () -> Void
    let onHideRepromptComposer: () -> Void
    let onRepromptTextChange: (String) -> Void
    let onSubmitReprompt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            if review.isRepromptComposerPresented {
                repromptComposer
            } else {
                actionSummary
                actionButtons
            }

            Button(action: onApproveAll) {
                Text(isSending ? "Submitting..." : "Approve All")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(isSending)
        }
        .padding(.spacing(.sp4))
        .background(Color.ds.surface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp4))
                .stroke(Color.ds.border, lineWidth: 1)
        )
    }

    private var actionSummary: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(review.progressLabel)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            Text(summaryText)
                .typography(.body)
                .foregroundStyle(Color.ds.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: .spacing(.sp2)) {
            Button(action: onApprove) {
                Text("Approve")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondary)
            .disabled(isSending)

            Button(action: onShowRepromptComposer) {
                Text("Reprompt")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondary)
            .disabled(isSending)

            if let onCancelCut {
                Button(action: onCancelCut) {
                    Text("Cancel Cut")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .disabled(isSending)
            }
        }
    }

    private var repromptComposer: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Reprompt this section")
                .typography(.body)
                .foregroundStyle(Color.ds.text)

            TextField(
                "Describe how Iris should change this cut...",
                text: Binding(
                    get: { review.repromptDraft },
                    set: onRepromptTextChange
                ),
                axis: .vertical
            )
            .typographyStyle(.body)
            .lineLimit(1...4)
            .padding(.spacing(.sp3))
            .background(Color.ds.bg.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.ds.border, lineWidth: 1)
            )

            HStack(spacing: .spacing(.sp2)) {
                Button(action: onHideRepromptComposer) {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .disabled(isSending)

                Button(action: onSubmitReprompt) {
                    Text(isSending ? "Sending..." : "Send")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(isSending || review.repromptDraft.trimmedForTransport.isEmpty)
            }
        }
    }

    private var summaryText: String {
        guard let currentItem = review.currentItem else {
            return "Review each cut from left to right."
        }

        if currentItem.canCancel {
            return "Approve to keep this cut, or cancel it to merge the original section back in."
        }

        return "This cut joins different source clips, so it can only be approved or changed with a reprompt."
    }
}
