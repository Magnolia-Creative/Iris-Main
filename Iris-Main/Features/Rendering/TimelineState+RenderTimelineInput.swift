import AVFoundation
import Foundation

extension TimelineState {
    func makeRenderTimelineInput() -> RenderTimelineInput {
        var renderTracks: [RenderTrackInput] = []
        let colorFiltersByClipId = Self.clipColorFiltersByClipId(from: effects)

        for track in orderedTracks {
            let trackClips = clips.filter { $0.trackId == track.trackId }
            let renderClips = trackClips.compactMap { clip -> RenderClipInput? in
                guard let media = mediaById[clip.mediaId] else { return nil }

                let assetURL: URL
                if let assetRef = try? DatabaseManager.shared.getAssetReference(assetRefId: media.assetRefId) {
                    if assetRef.uri.hasPrefix("/") {
                        assetURL = URL(fileURLWithPath: assetRef.uri)
                    } else {
                        return nil
                    }
                } else {
                    return nil
                }

                let timelineStart = Double(clip.timelineRange.start) / 1_000_000.0
                let timelineEnd = Double(clip.timelineRange.end) / 1_000_000.0
                let sourceStart = Double(clip.sourceRange.start) / 1_000_000.0
                let sourceEnd = Double(clip.sourceRange.end) / 1_000_000.0

                return RenderClipInput(
                    id: UUID(uuidString: clip.clipId) ?? UUID(),
                    assetURL: assetURL,
                    timelineRange: timelineStart...timelineEnd,
                    sourceRange: sourceStart...sourceEnd,
                    colorAdjustments: RenderColorAdjustmentsInput(
                        clipColorFilter: colorFiltersByClipId[clip.clipId] ?? .neutral
                    )
                )
            }

            let zOrder: Int = {
                switch track.kind {
                case .video: return 0
                case .overlay: return 1
                case .audio: return -1
                }
            }()

            renderTracks.append(RenderTrackInput(
                id: UUID(uuidString: track.trackId) ?? UUID(),
                clips: renderClips,
                zOrder: zOrder
            ))
        }

        return RenderTimelineInput(
            tracks: renderTracks,
            captions: [],
            outputSize: CGSize(width: 1920, height: 1080),
            duration: timelineDurationSeconds
        )
    }

    private static func clipColorFiltersByClipId(from effects: [Effect]) -> [String: ClipColorFilter] {
        let latestFilters = effects.reduce(into: [String: (updatedAt: Date, filter: ClipColorFilter)]()) { result, effect in
            guard let filter = effect.clipColorFilter else { return }
            if let existing = result[effect.targetId], existing.updatedAt > effect.updatedAt {
                return
            }
            result[effect.targetId] = (effect.updatedAt, filter)
        }

        return latestFilters.mapValues(\.filter)
    }
}

private extension RenderColorAdjustmentsInput {
    init(clipColorFilter: ClipColorFilter) {
        self.init(
            temperature: clipColorFilter.temperature,
            tint: clipColorFilter.tint,
            exposure: clipColorFilter.exposure,
            brightness: clipColorFilter.brightness,
            contrast: clipColorFilter.contrast,
            saturation: clipColorFilter.saturation,
            highlights: clipColorFilter.highlights,
            shadows: clipColorFilter.shadows
        )
    }
}
