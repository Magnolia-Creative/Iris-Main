import AVFoundation
import CoreGraphics
import Foundation
import UIKit
import VideoLab

enum VideoLabTimelineAdapter {
    static func makeVideoLab(from input: RenderTimelineInput, frameRate: Int = 30) -> VideoLab {
        VideoLab(renderComposition: makeRenderComposition(from: input, frameRate: frameRate))
    }

    /// Builds a `VideoLab` instance after loading each `AVAssetSource` so tracks/duration are available, then restores
    /// per-clip `selectedTimeRange` (VideoLab’s `load` overwrites it with the full asset span).
    static func makeVideoLabAsync(from input: RenderTimelineInput, frameRate: Int = 30) async -> VideoLab {
        let composition = await makeRenderCompositionAsync(from: input, frameRate: frameRate)
        return VideoLab(renderComposition: composition)
    }

    static func makeRenderComposition(from input: RenderTimelineInput, frameRate: Int = 30) -> RenderComposition {
        let composition = RenderComposition()
        composition.renderSize = input.outputSize
        let timescale = max(1, Int32(frameRate))
        composition.frameDuration = CMTime(value: 1, timescale: timescale)
        composition.backgroundColor = .black

        var layers: [RenderLayer] = []
        var levelCounter = 0

        let visualTracks = input.tracks.filter { $0.zOrder >= 0 }.sorted { $0.zOrder < $1.zOrder }
        for track in visualTracks {
            let sortedClips = track.clips.sorted { $0.timelineRange.lowerBound < $1.timelineRange.lowerBound }
            for clip in sortedClips {
                if let layer = makeClipLayer(clip: clip, level: levelCounter) {
                    layers.append(layer)
                    levelCounter += 1
                }
            }
        }

        let audioTracks = input.tracks.filter { $0.zOrder < 0 }.sorted { $0.zOrder < $1.zOrder }
        for track in audioTracks {
            let sortedClips = track.clips.sorted { $0.timelineRange.lowerBound < $1.timelineRange.lowerBound }
            for clip in sortedClips {
                if let layer = makeClipLayer(clip: clip, level: levelCounter) {
                    layers.append(layer)
                    levelCounter += 1
                }
            }
        }

        composition.layers = layers
        if !input.captions.isEmpty {
            composition.animationLayer = VideoLabCaptionLayerFactory.makeAnimationLayer(
                cues: input.captions,
                timelineDuration: max(input.duration, 0.01),
                renderSize: input.outputSize
            )
        }
        return composition
    }

    static func makeRenderCompositionAsync(from input: RenderTimelineInput, frameRate: Int = 30) async -> RenderComposition {
        let composition = RenderComposition()
        composition.renderSize = input.outputSize
        let timescale = max(1, Int32(frameRate))
        composition.frameDuration = CMTime(value: 1, timescale: timescale)
        composition.backgroundColor = .black

        var layers: [RenderLayer] = []
        var levelCounter = 0
#if DEBUG
        var loadedSourceCount = 0
#endif

        let visualTracks = input.tracks.filter { $0.zOrder >= 0 }.sorted { $0.zOrder < $1.zOrder }
        for track in visualTracks {
            let sortedClips = track.clips.sorted { $0.timelineRange.lowerBound < $1.timelineRange.lowerBound }
            for clip in sortedClips {
                if let layer = await makeClipLayerAsync(clip: clip, level: levelCounter) {
                    layers.append(layer)
                    levelCounter += 1
#if DEBUG
                    loadedSourceCount += 1
#endif
                }
            }
        }

        let audioTracks = input.tracks.filter { $0.zOrder < 0 }.sorted { $0.zOrder < $1.zOrder }
        for track in audioTracks {
            let sortedClips = track.clips.sorted { $0.timelineRange.lowerBound < $1.timelineRange.lowerBound }
            for clip in sortedClips {
                if let layer = await makeClipLayerAsync(clip: clip, level: levelCounter) {
                    layers.append(layer)
                    levelCounter += 1
#if DEBUG
                    loadedSourceCount += 1
#endif
                }
            }
        }

        composition.layers = layers
        if !input.captions.isEmpty {
            composition.animationLayer = VideoLabCaptionLayerFactory.makeAnimationLayer(
                cues: input.captions,
                timelineDuration: max(input.duration, 0.01),
                renderSize: input.outputSize
            )
        }

#if DEBUG
        VideoLabPreviewDiagnostics.logVideoLabSourcesPrepared(count: loadedSourceCount)
#endif
        return composition
    }

    private static func makeClipLayer(clip: RenderClipInput, level: Int) -> RenderLayer? {
        let source = AVAssetSource(asset: AVURLAsset(url: clip.assetURL))
        guard let timeRange = timeRangeForClip(clip) else { return nil }
        applySelectedTimeRange(from: clip, to: source)
        let layer = RenderLayer(timeRange: timeRange, source: source)
        configure(layer: layer, clip: clip, level: level)
        return layer
    }

    private static func makeClipLayerAsync(clip: RenderClipInput, level: Int) async -> RenderLayer? {
        let source = AVAssetSource(asset: AVURLAsset(url: clip.assetURL))
        guard let timeRange = timeRangeForClip(clip) else { return nil }
        applySelectedTimeRange(from: clip, to: source)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            source.load { _ in
                continuation.resume()
            }
        }

        // `AVAssetSource.load` resets `selectedTimeRange` to the full loaded span; restore the editor trim.
        applySelectedTimeRange(from: clip, to: source)

        let layer = RenderLayer(timeRange: timeRange, source: source)
        configure(layer: layer, clip: clip, level: level)
        return layer
    }

    private static func timeRangeForClip(_ clip: RenderClipInput) -> CMTimeRange? {
        let timelineStart = clip.timelineRange.lowerBound
        let timelineEnd = clip.timelineRange.upperBound
        let timelineDuration = max(0, timelineEnd - timelineStart)
        guard timelineDuration > 0 else { return nil }
        return CMTimeRange(
            start: CMTime(seconds: timelineStart, preferredTimescale: 600),
            duration: CMTime(seconds: timelineDuration, preferredTimescale: 600)
        )
    }

    private static func applySelectedTimeRange(from clip: RenderClipInput, to source: AVAssetSource) {
        let sourceStart = clip.sourceRange.lowerBound
        let sourceEnd = clip.sourceRange.upperBound
        let sourceDuration = max(0, sourceEnd - sourceStart)
        guard sourceDuration > 0 else { return }
        source.selectedTimeRange = CMTimeRange(
            start: CMTime(seconds: sourceStart, preferredTimescale: 600),
            duration: CMTime(seconds: sourceDuration, preferredTimescale: 600)
        )
    }

    private static func configure(layer: RenderLayer, clip: RenderClipInput, level: Int) {
        layer.layerLevel = level
        layer.transform = transform(from: clip.transform)
        layer.blendOpacity = clip.opacity
        if let op = colorOperation(from: clip.colorAdjustments) {
            layer.operations = [op]
        }
    }

    private static func transform(from t: RenderTransformInput) -> Transform {
        let center = CGPoint(
            x: 0.5 + CGFloat(t.position.x) * 0.5,
            y: 0.5 - CGFloat(t.position.y) * 0.5
        )
        let uniformScale = max(0.01, max(t.scale.x, t.scale.y))
        return Transform(center: center, rotation: t.rotation, scale: uniformScale)
    }

    private static func colorOperation(from adjustments: RenderColorAdjustmentsInput) -> BasicOperation? {
        guard !adjustments.isNeutralForVideoLab else { return nil }
        let op = BrightnessAdjustment()
        let combined = adjustments.brightness + adjustments.exposure * 0.12
            + adjustments.contrast * 0.08
            + adjustments.saturation * 0.05
        op.brightness = max(-1, min(1, combined))
        return op
    }
}

private extension RenderColorAdjustmentsInput {
    var isNeutralForVideoLab: Bool {
        abs(temperature) < 0.001
            && abs(tint) < 0.001
            && abs(exposure) < 0.001
            && abs(brightness) < 0.001
            && abs(contrast) < 0.001
            && abs(saturation) < 0.001
            && abs(highlights) < 0.001
            && abs(shadows) < 0.001
    }
}
