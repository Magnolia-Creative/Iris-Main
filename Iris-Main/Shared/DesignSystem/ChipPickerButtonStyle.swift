import SwiftUI

struct IrisChipPickerButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .irisChipPickerAppearance(isSelected: isSelected, isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == IrisChipPickerButtonStyle {
    static func irisChipPicker(isSelected: Bool) -> IrisChipPickerButtonStyle {
        IrisChipPickerButtonStyle(isSelected: isSelected)
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
