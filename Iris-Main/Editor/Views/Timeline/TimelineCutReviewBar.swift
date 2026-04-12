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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                if review.isRepromptComposerPresented {
                    repromptComposer
                } else {
                    actionButtons
                }

                Button(action: onApproveAll) {
                    Text(isSending ? "Submitting..." : "Approve All")
                        .typography(.heading)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .spacing(.sp3))
                        .padding(.horizontal, .spacing(.sp3))
                        .background(Color.ds.accentBg)
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .opacity(isSending ? 0.75 : 1)
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

    private var actionButtons: some View {
        HStack(spacing: .spacing(.sp2)) {
            outlinedButton(
                title: "Approve",
                foreground: Color.ds.accentFg,
                border: Color.ds.accentFg,
                action: onApprove
            )

            outlinedButton(
                title: "Reprompt",
                foreground: Color.ds.accentFg,
                border: Color.ds.accentFg,
                action: onShowRepromptComposer
            )

            if let onCancelCut {
                outlinedButton(
                    title: "Cancel",
                    foreground: Color.ds.danger,
                    border: Color.ds.danger,
                    action: onCancelCut
                )
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
                outlinedButton(
                    title: "Back",
                    foreground: Color.ds.accentFg,
                    border: Color.ds.accentFg,
                    action: onHideRepromptComposer
                )

                Button(action: onSubmitReprompt) {
                    Text(isSending ? "Sending..." : "Send")
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .spacing(.sp2))
                }
                .buttonStyle(.plain)
                .background(Color.ds.accentBg)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1), style: .continuous))
                .disabled(isSending || review.repromptDraft.trimmedForTransport.isEmpty)
                .opacity(isSending || review.repromptDraft.trimmedForTransport.isEmpty ? 0.6 : 1)
            }
        }
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
        .disabled(isSending)
        .opacity(isSending ? 0.6 : 1)
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
