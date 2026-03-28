import SwiftUI

enum ImportTransitionKey {
    static let promptCard = "import-prompt-card"
}

struct PromptCardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            content
        }
        .padding(.sp3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }
}

struct AgentSurfaceCard<Content: View>: View {
    let minHeight: CGFloat
    let content: Content

    init(minHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: .spacing(.sp4))
                .fill(
                    LinearGradient(
                        colors: [
                            Color.ds.surface.opacity(0.96),
                            Color.ds.surface.opacity(0.76)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing(.sp4))
                        .stroke(Color.ds.border.opacity(0.95), lineWidth: 1)
                )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.sp3)
        }
        .frame(minHeight: minHeight)
    }
}
