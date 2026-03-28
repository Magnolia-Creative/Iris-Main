import AVFoundation
import SwiftUI

enum ImportTransitionKey {
    static let promptCard = "import-prompt-card"
}

enum ImportPromptCardMetrics {
    static let minHeight: CGFloat = 144
    static let compactMaxWidth: CGFloat = 360
}

extension View {
    func importPromptCardTransition(in namespace: Namespace.ID, isSource: Bool) -> some View {
        matchedGeometryEffect(
            id: ImportTransitionKey.promptCard,
            in: namespace,
            properties: .frame,
            anchor: .topLeading,
            isSource: isSource
        )
    }
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

struct ImportedVideoTile: View {
    let videoURL: URL
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: .spacing(.sp3))
                        .fill(Color.ds.surface.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: .spacing(.sp3))
                                .stroke(Color.ds.border, lineWidth: 1.5)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.ds.border, lineWidth: 1.5)
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 136)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        .task(id: videoURL) {
            thumbnail = await Self.generateThumbnail(for: videoURL)
        }
    }

    private static func generateThumbnail(for videoURL: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            let requestTime = CMTime(seconds: 0.1, preferredTimescale: 600)

            return await withCheckedContinuation { continuation in
                generator.generateCGImageAsynchronously(for: requestTime) { image, _, error in
                    continuation.resume(returning: error == nil ? image : nil)
                }
            }
        }.value
    }
}
