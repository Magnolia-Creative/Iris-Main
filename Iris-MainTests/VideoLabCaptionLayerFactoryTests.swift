import QuartzCore
import Testing
@testable import Iris_Main

struct VideoLabCaptionLayerFactoryTests {
    @Test func wrapsCaptionTextEveryEightWords() throws {
        let cue = makeCue(text: "one two three four five six seven eight nine ten")

        let layer = VideoLabCaptionLayerFactory.makeAnimationLayer(
            cues: [cue],
            timelineDuration: 5,
            renderSize: CGSize(width: 1920, height: 1080)
        )

        let textLayer = try #require(layer.sublayers?.first as? CATextLayer)
        let text = try #require(textLayer.string as? NSAttributedString).string

        #expect(text == "one two three four five six seven eight\nnine ten")
    }

    @Test func positionsCaptionAtBottomCenterOfRenderSpace() throws {
        let renderSize = CGSize(width: 1920, height: 1080)
        let cue = makeCue(position: SIMD2<Float>(0.5, 0.95))

        let layer = VideoLabCaptionLayerFactory.makeAnimationLayer(
            cues: [cue],
            timelineDuration: 5,
            renderSize: renderSize
        )

        let textLayer = try #require(layer.sublayers?.first as? CATextLayer)

        #expect(abs(textLayer.position.x - 960) < 0.001)
        #expect(abs(textLayer.position.y - 1026) < 0.001)
        #expect(abs(textLayer.anchorPoint.x - 0.5) < 0.001)
        #expect(abs(textLayer.anchorPoint.y - 1.0) < 0.001)
    }

    @Test func usesAbsoluteCueTimingForOpacityAnimation() throws {
        let cue = makeCue(startTime: 12.25, endTime: 14.0, opacity: 0.75)

        let layer = VideoLabCaptionLayerFactory.makeAnimationLayer(
            cues: [cue],
            timelineDuration: 20,
            renderSize: CGSize(width: 1920, height: 1080)
        )

        let textLayer = try #require(layer.sublayers?.first as? CATextLayer)
        let opacity = try #require(textLayer.animation(forKey: "captionOpacity") as? CABasicAnimation)

        #expect(abs(opacity.beginTime - 12.25) < 0.001)
        #expect(abs(opacity.duration - 1.75) < 0.001)
        #expect(opacity.fromValue as? Float == 0.75)
        #expect(opacity.toValue as? Float == 0.75)
        #expect(textLayer.opacity == 0)
    }

    private func makeCue(
        startTime: Double = 1,
        endTime: Double = 3,
        text: String = "caption text",
        position: SIMD2<Float> = SIMD2<Float>(0.5, 0.95),
        opacity: Float = 1.0
    ) -> RenderCaptionCueInput {
        RenderCaptionCueInput(
            startTime: startTime,
            endTime: endTime,
            text: text,
            style: RenderCaptionStyle(
                fontName: "",
                fontSize: 18,
                fontWeight: 500,
                textColor: SIMD4<Float>(1, 1, 1, 1),
                backgroundColor: SIMD4<Float>(0, 0, 0, 0),
                cornerRadius: 10
            ),
            position: position,
            opacity: opacity
        )
    }
}
