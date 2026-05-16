import SwiftUI

struct PreviewSection: View {
    @ObservedObject var controller: PlaybackController
    var renderBridge: TimelineRenderBridge?
    var previewAspect: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let fittedRect = PreviewAspectLayout.fittedRect(
                in: geometry.size,
                aspect: resolvedAspect
            )

            ZStack {
                Color.clear
                previewCanvas(size: fittedRect.size)
                    .frame(width: fittedRect.width, height: fittedRect.height)
                    .position(x: fittedRect.midX, y: fittedRect.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 2, minHeight: 2)
    }

    private var resolvedAspect: CGFloat {
        previewAspect ?? controller.state?.effectiveOutputAspect?.aspectCGFloat ?? (16.0 / 9.0)
    }

    private func previewCanvas(size: CGSize) -> some View {
        ZStack {
            if let bridge = renderBridge {
                VideoLabPreviewView(engine: bridge.engine)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.ds.surface)
                    .overlay(
                        VStack(spacing: .spacing(.sp2)) {
                            Text("Preview")
                                .typography(.body)
                                .foregroundColor(Color.ds.text)
                            Text("Playhead: \(controller.state?.currentTimeAtCenter ?? 0) us")
                                .typography(.bodySmall)
                                .foregroundColor(Color.ds.textMuted)
                        }
                    )
            }

            if let state = controller.state {
                CaptionPreviewOverlay(state: state, canvasSize: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

enum PreviewAspectLayout {
    static func fittedRect(in containerSize: CGSize, aspect: CGFloat) -> CGRect {
        guard containerSize.width > 0,
              containerSize.height > 0,
              aspect.isFinite,
              aspect > 0
        else {
            return .zero
        }

        let containerAspect = containerSize.width / containerSize.height
        let fittedSize: CGSize
        if containerAspect > aspect {
            let height = containerSize.height
            fittedSize = CGSize(width: height * aspect, height: height)
        } else {
            let width = containerSize.width
            fittedSize = CGSize(width: width, height: width / aspect)
        }

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}
