import SwiftUI

struct IrisChipPickerButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .irisChipPickerAppearance(isSelected: isSelected, isPressed: configuration.isPressed)
    }
}

enum IrisConnectedOptionPosition {
    case single
    case leading
    case middle
    case trailing
}

struct IrisConnectedOptionButtonStyle: ButtonStyle {
    let isSelected: Bool
    let position: IrisConnectedOptionPosition

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(
                IrisConnectedOptionAppearanceModifier(
                    isSelected: isSelected,
                    isPressed: configuration.isPressed,
                    position: position
                )
            )
    }
}

extension ButtonStyle where Self == IrisChipPickerButtonStyle {
    static func irisChipPicker(isSelected: Bool) -> IrisChipPickerButtonStyle {
        IrisChipPickerButtonStyle(isSelected: isSelected)
    }
}

extension ButtonStyle where Self == IrisConnectedOptionButtonStyle {
    static func irisConnectedOption(
        isSelected: Bool,
        position: IrisConnectedOptionPosition
    ) -> IrisConnectedOptionButtonStyle {
        IrisConnectedOptionButtonStyle(isSelected: isSelected, position: position)
    }
}

extension View {
    func irisChipPickerAppearance(isSelected: Bool, isPressed: Bool = false) -> some View {
        modifier(IrisChipPickerAppearanceModifier(isSelected: isSelected, isPressed: isPressed))
    }
}

private struct IrisChipPickerAppearanceModifier: ViewModifier {
    let isSelected: Bool
    let isPressed: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .typographyStyle(.bodySmall)
            .foregroundColor(isSelected ? Color.ds.accentFg : Color.ds.text)
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp2))
            .editorRegularGlassEffect(
                tint: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isPressed ? 0.8 : 1)
    }
}

private struct IrisConnectedOptionAppearanceModifier: ViewModifier {
    let isSelected: Bool
    let isPressed: Bool
    let position: IrisConnectedOptionPosition

    @Environment(\.colorScheme) private var colorScheme

    private var shape: IrisConnectedOptionSegmentShape {
        IrisConnectedOptionSegmentShape(position: position)
    }

    func body(content: Content) -> some View {
        content
            .typographyStyle(.bodySmall)
            .foregroundColor(isSelected ? Color.ds.accentFg : Color.ds.text)
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp1))
            .frame(minHeight: 28)
            .editorRegularGlassEffect(
                tint: Color.white.opacity(colorScheme == .dark ? 0.04 : 0.10),
                in: shape
            )
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.ds.accentFg : Color.ds.border.opacity(0.85),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .contentShape(shape)
            .opacity(isPressed ? 0.8 : 1)
    }
}

private struct IrisConnectedOptionSegmentShape: InsettableShape {
    let position: IrisConnectedOptionPosition
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(14, rect.height / 2)
        let corners: UIRectCorner

        switch position {
        case .single:
            corners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .leading:
            corners = [.topLeft, .bottomLeft]
        case .middle:
            corners = []
        case .trailing:
            corners = [.topRight, .bottomRight]
        }

        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
