import SwiftUI

enum ImportPromptCardMetrics {
    static let minHeight: CGFloat = 144
    static let compactMaxWidth: CGFloat = 360
}

struct PromptCardContainer<Content: View>: View {
    let fillsWidth: Bool
    let content: Content

    init(
        fillsWidth: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.fillsWidth = fillsWidth
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            content
        }
        .padding(.sp3)
        .frame(
            maxWidth: fillsWidth ? .infinity : ImportPromptCardMetrics.compactMaxWidth,
            alignment: .leading
        )
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }
}

struct ImportPromptDisplayCard: View {
    let text: String

    var body: some View {
        PromptCardContainer(fillsWidth: false) {
            Text(text)
                .typography(.body)
                .foregroundStyle(Color.ds.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
