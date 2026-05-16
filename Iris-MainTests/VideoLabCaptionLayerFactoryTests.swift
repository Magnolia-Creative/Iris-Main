import AVFoundation
import QuartzCore
import Testing
import UIKit
import VideoLab
@testable import Iris_Main

struct VideoLabCaptionLayerFactoryTests {
    @Test func keepsShortCaptionTextOnOneLine() throws {
        let cue = makeCue(text: "one two three four five six seven eight nine ten")

        let layer = VideoLabCaptionLayerFactory.makeAnimationLayer(
            cues: [cue],
            timelineDuration: 5,
            renderSize: CGSize(width: 1920, height: 1080)
        )

        let textLayer = try #require(layer.sublayers?.first as? CATextLayer)
        let text = try #require(textLayer.string as? NSAttributedString).string

        #expect(text == "one two three four five six seven eight nine ten")
    }

    @Test func positionsCaptionAtBottomCenterOfRenderSpace() throws {
        try assertCaptionPosition(
            renderSize: CGSize(width: 1920, height: 1080),
            expected: CGPoint(x: 960, y: 1026)
        )
        try assertCaptionPosition(
            renderSize: CGSize(width: 1080, height: 1920),
            expected: CGPoint(x: 540, y: 1824)
        )
    }

    private func assertCaptionPosition(renderSize: CGSize, expected: CGPoint) throws {
        let cue = makeCue(position: SIMD2<Float>(0.5, 0.95))
        let layer = VideoLabCaptionLayerFactory.makeAnimationLayer(
            cues: [cue],
            timelineDuration: 5,
            renderSize: renderSize
        )

        let textLayer = try #require(layer.sublayers?.first as? CATextLayer)

        #expect(abs(textLayer.position.x - expected.x) < 0.001)
        #expect(abs(textLayer.position.y - expected.y) < 0.001)
        #expect(abs(textLayer.anchorPoint.x - 0.5) < 0.001)
        #expect(abs(textLayer.anchorPoint.y - 1.0) < 0.001)
    }

    @Test func scalesCaptionFontFromRenderSize() throws {
        let layer = VideoLabCaptionLayerFactory.makeAnimationLayer(
            cues: [makeCue()],
            timelineDuration: 5,
            renderSize: CGSize(width: 1920, height: 1080)
        )

        let textLayer = try #require(layer.sublayers?.first as? CATextLayer)
        let attributed = try #require(textLayer.string as? NSAttributedString)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)

        #expect(abs(font.pointSize - 81) < 0.001)
        #expect(abs(textLayer.cornerRadius - 45) < 0.001)
    }

    @Test func usesExportSafeTimelineOpacityAnimation() throws {
        let cue = makeCue(startTime: 12.25, endTime: 14.0, opacity: 0.75)

        let layer = VideoLabCaptionLayerFactory.makeAnimationLayer(
            cues: [cue],
            timelineDuration: 20,
            renderSize: CGSize(width: 1920, height: 1080)
        )

        let textLayer = try #require(layer.sublayers?.first as? CATextLayer)
        let opacity = try #require(textLayer.animation(forKey: "captionOpacity") as? CAKeyframeAnimation)

        let keyTimes = try #require(opacity.keyTimes)
        let values = try #require(opacity.values as? [Float])

        #expect(abs(opacity.beginTime - AVCoreAnimationBeginTimeAtZero) < 0.001)
        #expect(abs(opacity.duration - 20) < 0.001)
        #expect(opacity.calculationMode == .discrete)
        #expect(opacity.fillMode == .both)
        #expect(opacity.isRemovedOnCompletion == false)
        #expect(keyTimes.map(\.doubleValue) == [0, 0.6125, 0.7, 1])
        #expect(values == [0, 0.75, 0, 0])
        #expect(textLayer.opacity == 0)
    }

    @Test func renderCompositionCarriesCaptionAnimationLayer() throws {
        let cue = makeCue()
        let input = RenderTimelineInput(
            tracks: [],
            captions: [cue],
            outputSize: CGSize(width: 1920, height: 1080),
            duration: 5
        )

        let composition = VideoLabTimelineAdapter.makeRenderComposition(from: input)

        #expect(composition.animationLayer != nil)
        #expect(composition.animationLayer?.bounds.size == CGSize(width: 1920, height: 1080))
    }

    @Test func renderCompositionCaptionLayerFollowsOutputSize() throws {
        let cue = makeCue()
        let landscape = makeCaptionInput(cue: cue, outputSize: CGSize(width: 1920, height: 1080))
        let portrait = makeCaptionInput(cue: cue, outputSize: CGSize(width: 1080, height: 1920))

        let landscapeComposition = VideoLabTimelineAdapter.makeRenderComposition(from: landscape)
        let portraitComposition = VideoLabTimelineAdapter.makeRenderComposition(from: portrait)

        #expect(landscapeComposition.animationLayer?.bounds.size == CGSize(width: 1920, height: 1080))
        #expect(portraitComposition.animationLayer?.bounds.size == CGSize(width: 1080, height: 1920))
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

    private func makeCaptionInput(cue: RenderCaptionCueInput, outputSize: CGSize) -> RenderTimelineInput {
        RenderTimelineInput(
            tracks: [],
            captions: [cue],
            outputSize: outputSize,
            duration: 5
        )
    }
}
