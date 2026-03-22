import SwiftUI

struct AppColors {
    // Text colors
    static let text = Color(light: Color(hex: "#000000"), dark: Color(hex: "#FFFFFF"))
    static let textMuted = Color(light: Color(hex: "#8D8D8D"), dark: Color(hex: "#B1B1B1"))
    
    // Accent colors
    static let accentBg = Color(light: Color(hex: "#9481FF"), dark: Color(hex: "#836FF2"))
    static let accentFg = Color(light: Color(hex: "#755DFF"), dark: Color(hex: "#9482FF"))
    
    // Surface colors
    static let bg = Color(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#101010"))
    static let surface = Color(light: Color(hex: "#F5F5F5"), dark: Color(hex: "#202020"))
    static let border = Color(light: Color(hex: "#D6D6D6"), dark: Color(hex: "#656565"))
    
    // Status colors
    static let danger = Color(light: Color(hex: "#FF7070"), dark: Color(hex: "#FF6060"))
}

extension Color {
    static let ds = AppColors.self
    
    // Helper initializer for hex colors
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // Helper initializer for adaptive colors
    init(light: Color, dark: Color) {
        self.init(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
}
