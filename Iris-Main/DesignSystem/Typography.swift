import SwiftUI

enum Typography {
    case bodySmall
    case action
    case body
    case heading
    case title
    
    var font: Font {
        switch self {
        case .bodySmall:
            return Font(createManropeFont(size: 12, weight: 400))
        case .action:
            return Font(createManropeFont(size: 16, weight: 500))
        case .body:
            return Font(createManropeFont(size: 16, weight: 300))
        case .heading:
            return Font(createManropeFont(size: 24, weight: 300))
        case .title:
            return Font(createManropeFont(size: 40, weight: 300))
        }
    }
    
    var lineHeight: CGFloat {
        switch self {
        case .bodySmall, .action:
            return 16
        case .body:
            return 24
        case .heading:
            return 28
        case .title:
            return 36
        }
    }
    
    var letterSpacing: CGFloat {
        switch self {
        case .bodySmall:
            return -0.02
        case .action, .body:
            return -0.03 // -5% = -0.05 of font size
        case .heading, .title:
            return -0.04 // -3% = -0.03 of font size
        }
    }
    
    var fontSize: CGFloat {
        switch self {
        case .bodySmall, .action:
            return 12
        case .body:
            return 16
        case .heading:
            return 24
        case .title:
            return 32
        }
    }
}

// Helper function to create Manrope variable font
private func createManropeFont(size: CGFloat, weight: CGFloat) -> UIFont {
    let descriptor = UIFontDescriptor(name: "Manrope", size: size)
    
    let variationDescriptor = descriptor.addingAttributes([
        kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [
            2003265652: weight  // 'wght' axis
        ]
    ])
    
    return UIFont(descriptor: variationDescriptor, size: size)
}


extension Text {
    func typography(_ style: Typography) -> some View {
        self
            .font(style.font)
            .lineSpacing(style.lineHeight - style.fontSize)
            .tracking(style.letterSpacing * style.fontSize)
    }
}

extension View {
    func typographyStyle(_ style: Typography) -> some View {
        self
            .font(style.font)
            .lineSpacing(style.lineHeight - style.fontSize)
            .tracking(style.letterSpacing * style.fontSize)
    }
}
