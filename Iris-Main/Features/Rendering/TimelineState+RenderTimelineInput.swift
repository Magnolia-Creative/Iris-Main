import AVFoundation
import Foundation

extension TimelineState {
    func makeRenderTimelineInput() -> RenderTimelineInput {
        var renderTracks: [RenderTrackInput] = []
        let colorFiltersByClipId = Self.clipColorFiltersByClipId(from: effects)
        let volumesByClipId = Self.clipVolumesByClipId(from: effects)

        for track in orderedTracks where track.kind != .captions {
            let trackClips = clips.filter { $0.trackId == track.trackId }
            let renderClips = trackClips.compactMap { clip -> RenderClipInput? in
                guard let media = mediaById[clip.mediaId] else { return nil }

                let assetURL: URL
                if let assetRef = try? DatabaseManager.shared.getAssetReference(assetRefId: media.assetRefId),
                   let resolved = AppSandboxFileURI.resolveFileURL(storedURI: assetRef.uri) {
                    assetURL = resolved
                } else {
                    return nil
                }

                let timelineStart = Double(clip.timelineRange.start) / 1_000_000.0
                let timelineEnd = Double(clip.timelineRange.end) / 1_000_000.0
                let sourceStart = Double(clip.sourceRange.start) / 1_000_000.0
                let sourceEnd = Double(clip.sourceRange.end) / 1_000_000.0

                let clipVolume = volumesByClipId[clip.clipId] ?? .neutral
                return RenderClipInput(
                    id: UUID(uuidString: clip.clipId) ?? UUID(),
                    assetURL: assetURL,
                    timelineRange: timelineStart...timelineEnd,
                    sourceRange: sourceStart...sourceEnd,
                    colorAdjustments: RenderColorAdjustmentsInput(
                        clipColorFilter: colorFiltersByClipId[clip.clipId] ?? .neutral
                    ),
                    audio: RenderAudioInput(volume: clipVolume.gain)
                )
            }

            let zOrder: Int = {
                switch track.kind {
                case .video: return 0
                case .overlay: return 1
                case .audio: return -1
                case .captions:
                    // `orderedTracks` loop excludes captions; keep exhaustiveness for `TrackKind`.
                    return 0
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
            captions: makeRenderCaptionInputs(),
            outputSize: effectiveOutputPixelSize,
            duration: timelineDurationSeconds
        )
    }

    private func makeRenderCaptionInputs() -> [RenderCaptionCueInput] {
        var result: [RenderCaptionCueInput] = []
        for group in captionGroups {
            let style = group.style.renderCaptionStyle(textColorHex: group.textColor, hasBackground: group.hasBackground)
            let groupCues = captionCues.filter { $0.groupId == group.groupId }
            for cue in groupCues {
                let start = Double(cue.timelineStartUs) / 1_000_000.0
                let end = Double(cue.timelineEndUs) / 1_000_000.0
                guard end > start else { continue }
                result.append(
                    RenderCaptionCueInput(
                        id: UUID(uuidString: cue.cueId) ?? UUID(),
                        startTime: start,
                        endTime: end,
                        text: cue.text,
                        style: style,
                        position: SIMD2<Float>(0.5, 0.95),
                        opacity: 1.0
                    )
                )
            }
        }
        result.sort { $0.startTime < $1.startTime }
        return result
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

    private static func clipVolumesByClipId(from effects: [Effect]) -> [String: ClipVolume] {
        let latestVolumes = effects.reduce(into: [String: (updatedAt: Date, volume: ClipVolume)]()) { result, effect in
            guard let volume = effect.clipVolume else { return }
            if let existing = result[effect.targetId], existing.updatedAt > effect.updatedAt {
                return
            }
            result[effect.targetId] = (effect.updatedAt, volume)
        }

        return latestVolumes.mapValues(\.volume)
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
