import SwiftUI

struct ChatDiffView: View {
    @ObservedObject var controller: TimelineController
    let onApprove: () -> Void
    let onReprompt: () -> Void

    @State private var repromptText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ds.bg.ignoresSafeArea()

                VStack(spacing: .spacing(.sp4)) {
                    // Header actions
                    HStack {
                        Button { onApprove() } label: {
                            HStack(spacing: .spacing(.sp2)) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Approve All")
                                    .typography(.action)
                            }
                        }
                        .buttonStyle(.secondary)

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: .spacing(.sp2)) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color.ds.danger)
                                Text("Reject All")
                                    .typography(.action)
                            }
                        }
                        .buttonStyle(.secondary)
                    }
                    .padding(.horizontal, .sp4)

                    // Diff list placeholder
                    ScrollView {
                        VStack(spacing: .spacing(.sp3)) {
                            ForEach(controller.state.clips) { clip in
                                diffRow(for: clip)
                            }
                        }
                        .padding(.horizontal, .sp4)
                    }

                    // Reprompt input
                    HStack(spacing: .spacing(.sp3)) {
                        TextField("Describe changes...", text: $repromptText)
                            .typographyStyle(.body)
                            .padding(.spacing(.sp3))
                            .background(Color.ds.surface)
                            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                            .overlay(RoundedRectangle(cornerRadius: .spacing(.sp3)).stroke(Color.ds.border, lineWidth: 1))

                        Button {
                            onReprompt()
                        } label: {
                            Text("Reprompt")
                                .typography(.action)
                        }
                        .buttonStyle(.primary)
                        .disabled(repromptText.isEmpty)
                    }
                    .padding(.horizontal, .sp4)
                    .padding(.bottom, .sp4)
                }
            }
            .navigationTitle("Review Changes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func diffRow(for clip: Clip) -> some View {
        HStack(spacing: .spacing(.sp3)) {
            // Before thumbnail placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.ds.surface)
                .frame(width: 60, height: 40)
                .overlay(Text("Before").typography(.bodySmall).foregroundColor(Color.ds.textMuted))

            Image(systemName: "arrow.right")
                .foregroundColor(Color.ds.textMuted)

            // After thumbnail placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.ds.accentBg.opacity(0.2))
                .frame(width: 60, height: 40)
                .overlay(Text("After").typography(.bodySmall).foregroundColor(Color.ds.accentFg))

            Spacer()

            // Per-change actions
            HStack(spacing: .spacing(.sp2)) {
                Button {} label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }

                Button {} label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.ds.accentFg)
                }
            }
        }
        .padding(.sp3)
        .background(Color.ds.surface)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
        .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.border, lineWidth: 1))
    }
}
