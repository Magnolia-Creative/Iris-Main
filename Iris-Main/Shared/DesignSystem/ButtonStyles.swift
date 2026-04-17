import SwiftUI

enum IrisButtonStyle {
    case primary
    case secondary
    case tertiary
}

// MARK: - Button Style Implementations
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typographyStyle(.action)
            .foregroundColor(.white)
            .padding(.horizontal, .spacing(.sp3))
            .frame(height: 32)
            .background(Color.ds.accentBg)
            .cornerRadius(.spacing(.sp1))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typographyStyle(.action)
            .foregroundColor(Color.ds.accentFg)
            .padding(.horizontal, .spacing(.sp3))
            .frame(height: 32)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.accentFg, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typographyStyle(.action)
            .foregroundColor(Color.ds.accentFg)
            .padding(.horizontal, .spacing(.sp3))
            .frame(height: 32)
            .underline()
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - View Extension for Convenience
extension View {
    func buttonStyle(_ style: IrisButtonStyle) -> some View {
        switch style {
        case .primary:
            return AnyView(self.buttonStyle(PrimaryButtonStyle()))
        case .secondary:
            return AnyView(self.buttonStyle(SecondaryButtonStyle()))
        case .tertiary:
            return AnyView(self.buttonStyle(TertiaryButtonStyle()))
        }
    }
}
