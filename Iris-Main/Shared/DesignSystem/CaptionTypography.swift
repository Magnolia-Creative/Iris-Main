import Foundation
import simd
import UIKit

enum IrisCaptionFont {
    /// Names suitable for `UIFont(name:size:)` on iOS.
    static func uiFontName(for style: CaptionStyle) -> String {
        switch style {
        case .classic:
            return "Georgia"
        case .modern:
            return "HelveticaNeue"
        case .neo:
            return "Menlo"
        }
    }
}

extension CaptionStyle {
    func renderCaptionStyle(textColorHex: String, hasBackground: Bool) -> RenderCaptionStyle {
        let rgba = Self.parseHexColor(textColorHex)
        let bg: SIMD4<Float> = hasBackground
            ? SIMD4<Float>(0, 0, 0, 0.55)
            : SIMD4<Float>(0, 0, 0, 0)
        return RenderCaptionStyle(
            fontName: IrisCaptionFont.uiFontName(for: self),
            fontSize: 26,
            fontWeight: 500,
            textColor: rgba,
            backgroundColor: bg,
            cornerRadius: 10
        )
    }

    private static func parseHexColor(_ hex: String) -> SIMD4<Float> {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt32(s, radix: 16) else {
            return SIMD4<Float>(1, 1, 1, 1)
        }
        let r: Float
        let g: Float
        let b: Float
        let a: Float
        if s.count == 8 {
            a = Float((value & 0xFF00_0000) >> 24) / 255.0
            r = Float((value & 0x00FF_0000) >> 16) / 255.0
            g = Float((value & 0x0000_FF00) >> 8) / 255.0
            b = Float(value & 0x0000_00FF) / 255.0
        } else {
            a = 1
            r = Float((value & 0xFF_0000) >> 16) / 255.0
            g = Float((value & 0x00_FF00) >> 8) / 255.0
            b = Float(value & 0x0000_FF) / 255.0
        }
        return SIMD4<Float>(r, g, b, a)
    }
}
