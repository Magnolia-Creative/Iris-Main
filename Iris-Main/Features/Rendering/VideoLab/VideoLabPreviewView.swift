import SwiftUI
import UIKit
import AVFoundation

/// Hosts preview video in the layer hierarchy using `AVPlayerLayer` as the view's backing layer.
final class PlayerHostView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

struct VideoLabPreviewView: UIViewRepresentable {
    let engine: VideoLabRenderEngine

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.backgroundColor = .black
        engine.bindPlayerHost(view)
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        engine.layoutPlayerHost()
    }
}
