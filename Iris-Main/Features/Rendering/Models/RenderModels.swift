import Foundation
import simd

// MARK: - Timeline Input Contracts

struct RenderTimelineInput {
    var tracks: [RenderTrackInput]
    var captions: [RenderCaptionCueInput]
    var outputSize: CGSize
    var duration: Double

    static let empty = RenderTimelineInput(
        tracks: [],
        captions: [],
        outputSize: CGSize(width: 1920, height: 1080),
        duration: 0
    )
}

struct RenderTrackInput: Identifiable {
    let id: UUID
    var clips: [RenderClipInput]
    var zOrder: Int

    init(id: UUID = UUID(), clips: [RenderClipInput] = [], zOrder: Int = 0) {
        self.id = id
        self.clips = clips
        self.zOrder = zOrder
    }
}

struct RenderClipInput: Identifiable {
    let id: UUID
    var assetURL: URL
    var timelineRange: ClosedRange<Double>
    var sourceRange: ClosedRange<Double>
    var transform: RenderTransformInput
    var colorAdjustments: RenderColorAdjustmentsInput
    var opacity: Float

    init(
        id: UUID = UUID(),
        assetURL: URL,
        timelineRange: ClosedRange<Double>,
        sourceRange: ClosedRange<Double>,
        transform: RenderTransformInput = .identity,
        colorAdjustments: RenderColorAdjustmentsInput = .neutral,
        opacity: Float = 1.0
    ) {
        self.id = id
        self.assetURL = assetURL
        self.timelineRange = timelineRange
        self.sourceRange = sourceRange
        self.transform = transform
        self.colorAdjustments = colorAdjustments
        self.opacity = opacity
    }
}

struct RenderTransformInput: Equatable {
    var position: SIMD2<Float>
    var scale: SIMD2<Float>
    var rotation: Float
    var anchor: SIMD2<Float>

    static let identity = RenderTransformInput(
        position: .zero,
        scale: SIMD2<Float>(1, 1),
        rotation: 0,
        anchor: SIMD2<Float>(0.5, 0.5)
    )
}

struct RenderColorAdjustmentsInput: Equatable {
    var temperature: Float
    var tint: Float
    var exposure: Float
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var highlights: Float
    var shadows: Float

    static let neutral = RenderColorAdjustmentsInput(
        temperature: 0,
        tint: 0,
        exposure: 0,
        brightness: 0,
        contrast: 0,
        saturation: 0,
        highlights: 0,
        shadows: 0
    )
}

struct RenderCaptionCueInput: Identifiable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var text: String
    var style: RenderCaptionStyle
    var position: SIMD2<Float>
    var opacity: Float

    init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        text: String,
        style: RenderCaptionStyle = .default,
        position: SIMD2<Float> = SIMD2<Float>(0.5, 0.85),
        opacity: Float = 1.0
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.style = style
        self.position = position
        self.opacity = opacity
    }
}

struct RenderCaptionStyle: Equatable {
    var fontSize: CGFloat
    var fontWeight: CGFloat
    var textColor: SIMD4<Float>
    var backgroundColor: SIMD4<Float>
    var cornerRadius: CGFloat

    static let `default` = RenderCaptionStyle(
        fontSize: 24,
        fontWeight: 400,
        textColor: SIMD4<Float>(1, 1, 1, 1),
        backgroundColor: SIMD4<Float>(0, 0, 0, 0.6),
        cornerRadius: 8
    )
}

enum RenderIntent {
    case playback
    case scrub(velocity: Double)
}

struct RenderMetrics {
    var frameLatencyMs: Double = 0
    var cacheHitRatio: Double = 0
    var droppedFrameCount: Int = 0
    var cachedFrameCount: Int = 0
    var totalFramesRendered: Int = 0
}
