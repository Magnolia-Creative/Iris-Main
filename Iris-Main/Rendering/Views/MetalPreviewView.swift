import MetalKit
import SwiftUI

struct MetalPreviewView: UIViewRepresentable {
    let engine: RenderEngine

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        engine.bindPreview(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
