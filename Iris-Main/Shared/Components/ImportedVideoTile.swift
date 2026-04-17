import SwiftUI

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
            thumbnail = await VideoAssetPreviewLoader.generateThumbnail(for: videoURL)
        }
    }
}
