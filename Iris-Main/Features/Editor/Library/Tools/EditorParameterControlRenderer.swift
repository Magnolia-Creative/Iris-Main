import SwiftUI

struct EditorParameterControlRenderer: View {
    let descriptor: EditorParameterDescriptor
    @Binding var value: EditorParameterValue
    var onScalarChange: ((Double) -> Void)?

    var body: some View {
        switch descriptor.kind {
        case .slider:
            scalarSliderBody
        case let .segmented(options):
            segmentedBody(options: options)
        case .toggle:
            toggleBody
        case let .spatialPlaceholder(title):
            spatialPlaceholderBody(title: title)
        }
    }

    @ViewBuilder
    private var scalarSliderBody: some View {
        if case .scalar(let scalar) = value {
            EditorParameterControlCardComponent(
                title: descriptor.title,
                value: Binding(
                    get: { scalar },
                    set: { newValue in
                        value = .scalar(newValue)
                        onScalarChange?(newValue)
                    }
                ),
                bounds: descriptor.bounds,
                display: descriptor.display
            )
        } else {
            unsupportedValueBody
        }
    }

    @ViewBuilder
    private func segmentedBody(options: [EditorSegmentedPillOption]) -> some View {
        if case .scalar = value {
            let selectionBinding = Binding<String>(
                get: {
                    if case .scalar(let scalar) = value {
                        return String(format: "%.2f", scalar)
                    }
                    return options.first?.id ?? ""
                },
                set: { newId in
                    if let index = options.firstIndex(where: { $0.id == newId }) {
                        if let numeric = Double(newId) {
                            value = .scalar(numeric)
                            onScalarChange?(numeric)
                        } else {
                            value = .scalar(Double(index))
                            onScalarChange?(Double(index))
                        }
                    }
                }
            )
            EditorSegmentedPillControlComponent(
                title: descriptor.title,
                options: options,
                selectionId: selectionBinding
            )
        } else {
            unsupportedValueBody
        }
    }

    @ViewBuilder
    private var toggleBody: some View {
        if case .scalar(let scalar) = value {
            Toggle(isOn: Binding(
                get: { scalar >= 0.5 },
                set: { newValue in
                    let next = newValue ? 1.0 : 0.0
                    value = .scalar(next)
                    onScalarChange?(next)
                }
            )) {
                Text(descriptor.title)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }
            .tint(Color.ds.accentFg)
        } else {
            unsupportedValueBody
        }
    }

    @ViewBuilder
    private func spatialPlaceholderBody(title: String) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(title)
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
            RoundedRectangle(cornerRadius: .spacing(.sp2), style: .continuous)
                .fill(Color.ds.surface.opacity(0.45))
                .frame(height: 88)
                .overlay {
                    Text("Spatial control")
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.textMuted)
                }
        }
        .padding(.horizontal, .spacing(.sp2))
        .padding(.vertical, .spacing(.sp1))
        .background(Color.ds.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
    }

    private var unsupportedValueBody: some View {
        Text("\(descriptor.title) unsupported value type")
            .typography(.bodySmall)
            .foregroundColor(Color.ds.textMuted)
    }
}
