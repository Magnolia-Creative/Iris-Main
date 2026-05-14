import SwiftUI
import UIKit

struct VideoLabPreviewView: UIViewRepresentable {
    let engine: VideoLabRenderEngine

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        engine.bindPlayerHost(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        engine.layoutPlayerHost()
    }
}
