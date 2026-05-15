import SwiftUI

/// Groups sibling liquid-glass surfaces on iOS 26+. On earlier OS versions passes
/// children through unchanged (each child should apply its own frosted styling).
struct EditorGlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder private let content: () -> Content

    init(spacing: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    /// Mirrors `.glassEffect(.regular.tint(...))` / `.interactive()` using material blur
    /// when liquid glass APIs are unavailable.
    @ViewBuilder
    func editorRegularGlassEffect<S: Shape>(
        tint: Color,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            frostedGlassBackground(tint: tint, shape: shape)
        }
    }

    /// Standard editor frosted backdrop (regular material + tint), clipped.
    func editorFrostedGlassBackground<S: Shape>(tint: Color, in shape: S) -> some View {
        frostedGlassBackground(tint: tint, shape: shape)
    }
}

private extension View {
    func frostedGlassBackground<S: Shape>(tint: Color, shape: S) -> some View {
        background {
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(tint)
            }
        }
        .clipShape(shape)
    }
}
