import SwiftUI

struct IrisChipPickerButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .irisChipPickerAppearance(isSelected: isSelected, isPressed: configuration.isPressed)
    }
}

struct IrisConnectedOptionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(
                IrisConnectedOptionAppearanceModifier(
                    isSelected: isSelected,
                    isPressed: configuration.isPressed
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
    static func irisConnectedOption(isSelected: Bool) -> IrisConnectedOptionButtonStyle {
        IrisConnectedOptionButtonStyle(isSelected: isSelected)
    }
}

extension View {
    func irisChipPickerAppearance(isSelected: Bool, isPressed: Bool = false) -> some View {
        modifier(IrisChipPickerAppearanceModifier(isSelected: isSelected, isPressed: isPressed))
    }

    func irisConnectedOptionGroupBackground() -> some View {
        modifier(IrisConnectedOptionGroupBackgroundModifier())
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

    func body(content: Content) -> some View {
        content
            .typographyStyle(.bodySmall)
            .foregroundColor(isSelected ? Color.ds.accentFg : Color.ds.text)
            .padding(.horizontal, .spacing(.sp3))
            .padding(.vertical, .spacing(.sp1))
            .frame(maxWidth: .infinity, minHeight: 28)
            .lineLimit(1)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.ds.accentFg : Color.clear, lineWidth: 1.5)
                    .padding(1)
            )
            .contentShape(Rectangle())
            .opacity(isPressed ? 0.8 : 1)
    }
}

private struct IrisConnectedOptionGroupBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .editorRegularGlassEffect(
                tint: Color.white.opacity(colorScheme == .dark ? 0.04 : 0.10),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.ds.border.opacity(0.85), lineWidth: 1)
            )
    }
}
