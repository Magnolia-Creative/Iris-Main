import ClerkKitUI
import SwiftUI

extension ClerkTheme {
    /// ClerkKitUI appearance aligned with Iris `Color.ds`, Manrope, and button corner radius.
    @MainActor
    static var iris: ClerkTheme {
        ClerkTheme(
            colors: .init(
                primary: Color.ds.accentBg,
                background: Color.ds.bg,
                input: Color.ds.surface,
                danger: Color.ds.danger,
                success: Color(light: Color(hex: "#34C759"), dark: Color(hex: "#32D74B")),
                warning: Color(light: Color(hex: "#FFCC00"), dark: Color(hex: "#FFD60A")),
                foreground: Color.ds.text,
                mutedForeground: Color.ds.textMuted,
                primaryForeground: .white,
                inputForeground: Color.ds.text,
                neutral: Color.ds.textMuted,
                ring: Color.ds.accentFg,
                muted: Color.ds.surface,
                shadow: Color.black.opacity(0.18),
                border: Color.ds.border
            ),
            fonts: .init(
                largeTitle: Typography.title.font,
                title: Typography.heading.font,
                title2: Typography.action.font,
                headline: Typography.action.font,
                subheadline: Typography.body.font,
                body: Typography.body.font,
                callout: Typography.body.font,
                footnote: Typography.bodySmall.font,
                caption: Typography.bodySmall.font,
                caption2: Typography.bodySmall.font
            ),
            design: .init(borderRadius: CGFloat.spacing(.sp1))
        )
    }
}
