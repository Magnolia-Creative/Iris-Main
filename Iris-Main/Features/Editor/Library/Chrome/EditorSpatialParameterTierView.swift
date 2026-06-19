import SwiftUI

struct EditorSpatialParameterTierView: View {
    let descriptors: [EditorSpatialParameterDescriptor]
    let density: EditorBottomChromeDensity

    var body: some View {
        if descriptors.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: density.tierVerticalSpacing) {
                ForEach(descriptors) { descriptor in
                    spatialCard(for: descriptor)
                }
            }
        }
    }

    private func spatialCard(for descriptor: EditorSpatialParameterDescriptor) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(descriptor.title)
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)

            ZStack {
                RoundedRectangle(cornerRadius: .spacing(.sp3), style: .continuous)
                    .fill(Color.ds.surface.opacity(0.35))
                    .frame(height: 112)

                VStack(spacing: .spacing(.sp1)) {
                    Image(systemName: "scope")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color.ds.textMuted)
                    Text(descriptor.placeholderMessage)
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, .spacing(.sp3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
