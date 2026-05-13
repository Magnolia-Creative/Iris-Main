import SwiftUI

/// Prompt tab bar slot for per-field confirmation after an `updateClipColorFilter` is applied.
struct TimelinePromptColorReviewSlot: View {
    let propertyTitle: String
    let sliderRange: ClosedRange<Float>
    let sliderValue: Binding<Float>
    let onReset: () -> Void
    let onConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            HStack(spacing: .spacing(.sp2)) {
                Text(propertyTitle)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(1)

                Spacer(minLength: .spacing(.sp2))

                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ds.textMuted)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2), style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Reset \(propertyTitle)"))

                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ds.accentFg)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2), style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Confirm \(propertyTitle)"))
            }

            Slider(value: sliderRangeBinding, in: Double(sliderRange.lowerBound)...Double(sliderRange.upperBound))
                .tint(Color.ds.accentFg)
                .frame(minWidth: 200)
        }
        .frame(minWidth: 280, alignment: .leading)
    }

    private var sliderRangeBinding: Binding<Double> {
        Binding(
            get: { Double(sliderValue.wrappedValue) },
            set: { sliderValue.wrappedValue = Float($0) }
        )
    }
}
