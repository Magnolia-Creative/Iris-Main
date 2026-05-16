import CoreGraphics
import Testing
@testable import Iris_Main

struct VideoLabRenderEngineLayoutTests {
    @Test func captionLayerLayoutScalesToVisibleVideoRect() {
        let layout = VideoLabRenderEngine.captionLayerLayout(
            captionRenderSize: CGSize(width: 1920, height: 1080),
            visibleVideoRect: CGRect(x: 20, y: 40, width: 960, height: 540)
        )

        #expect(layout.bounds == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(layout.position == CGPoint(x: 20, y: 40))
        #expect(layout.transform == CGAffineTransform(scaleX: 0.5, y: 0.5))
    }

    @Test func captionLayerLayoutUpdatesForPortraitVideoRect() {
        let layout = VideoLabRenderEngine.captionLayerLayout(
            captionRenderSize: CGSize(width: 1080, height: 1920),
            visibleVideoRect: CGRect(x: 100, y: 10, width: 270, height: 480)
        )

        #expect(layout.bounds == CGRect(x: 0, y: 0, width: 1080, height: 1920))
        #expect(layout.position == CGPoint(x: 100, y: 10))
        #expect(layout.transform == CGAffineTransform(scaleX: 0.25, y: 0.25))
    }
}
