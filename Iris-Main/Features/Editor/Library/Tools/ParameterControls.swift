import SwiftUI

struct ParameterSliderControlComponent: View {
    let title: String
    @Binding var value: Double
    var bounds: EditorParameterBounds<Double> = EditorParameterBounds(lower: nil, upper: nil)
    var display: EditorParameterDisplay = .slider
    var valueFormatter: ((Double) -> String)?

    private var sliderRange: ClosedRange<Double> {
        bounds.closedRange(defaultLower: 0, defaultUpper: 1)
    }

    var body: some View {
        switch display {
        case .slider:
            sliderColumn(showsHeaderValue: false)
        case .inlineValue:
            sliderColumn(showsHeaderValue: true)
        case .compact:
            sliderColumn(showsHeaderValue: false)
        }
    }

    @ViewBuilder
    private func sliderColumn(showsHeaderValue: Bool) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            HStack(alignment: .firstTextBaseline, spacing: .spacing(.sp2)) {
                Text(title)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
                    .lineLimit(1)
                Spacer(minLength: .spacing(.sp2))
                if showsHeaderValue, let valueFormatter {
                    Text(valueFormatter(value))
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.text)
                        .monospacedDigit()
                }
            }
            Slider(value: $value, in: sliderRange)
                .tint(Color.ds.accentFg)
        }
    }
}

struct ParameterSegmentedPillOption: Identifiable, Equatable {
    let id: String
    let title: String
}

struct ParameterSegmentedPillControlComponent: View {
    let title: String?
    let options: [ParameterSegmentedPillOption]
    @Binding var selectionId: String

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            if let title {
                Text(title)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacing(.sp2)) {
                    ForEach(options) { option in
                        Button {
                            selectionId = option.id
                        } label: {
                            EditorToolPillComponent(
                                title: option.title,
                                selected: selectionId == option.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectionId == option.id ? .isSelected : [])
                    }
                }
            }
        }
    }
}

struct ToolControlRowComponent: View {
    let axis: EditorComponentAxis
    let content: AnyView

    init<Content: View>(axis: EditorComponentAxis = .horizontal, @ViewBuilder content: () -> Content) {
        self.axis = axis
        self.content = AnyView(content())
    }

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                HStack(spacing: .spacing(.sp2)) { content }
            case .vertical:
                VStack(alignment: .leading, spacing: .spacing(.sp2)) { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ParameterControlCardComponent: View {
    let title: String
    @Binding var value: Double
    var bounds: EditorParameterBounds<Double>
    var display: EditorParameterDisplay = .compact

    var body: some View {
        ParameterSliderControlComponent(
            title: title,
            value: $value,
            bounds: bounds,
            display: display,
            valueFormatter: { String(format: "%.2f", $0) }
        )
        .padding(.horizontal, .spacing(.sp2))
        .padding(.vertical, .spacing(.sp1))
        .background(Color.ds.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
    }
}
