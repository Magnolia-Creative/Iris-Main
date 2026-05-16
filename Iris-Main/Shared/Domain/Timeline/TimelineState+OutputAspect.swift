import CoreGraphics
import Foundation

extension TimelineState {
    /// Recomputes `derivedOutputAspect` from the earliest visual clip (video/overlay) with known media dimensions.
    mutating func refreshDerivedOutputAspect() {
        derivedOutputPixelSize = Self.computeDerivedOutputPixelSize(
            clips: clips,
            tracks: tracks,
            mediaById: mediaById
        )
        derivedOutputAspect = derivedOutputPixelSize.map {
            OutputAspectRatio(width: Int($0.width), height: Int($0.height))
        }
    }

    var effectiveOutputPixelSize: CGSize {
        if let manualOutputAspect {
            return manualOutputAspect.pixelSize(longSide: 1920)
        }
        if let derivedOutputPixelSize {
            return derivedOutputPixelSize
        }
        return CGSize(width: 1920, height: 1080)
    }

    static func computeDerivedOutputAspect(
        clips: [Clip],
        tracks: [Track],
        mediaById: [String: Media]
    ) -> OutputAspectRatio? {
        computeDerivedOutputPixelSize(clips: clips, tracks: tracks, mediaById: mediaById).map {
            OutputAspectRatio(width: Int($0.width), height: Int($0.height))
        }
    }

    static func computeDerivedOutputPixelSize(
        clips: [Clip],
        tracks: [Track],
        mediaById: [String: Media]
    ) -> CGSize? {
        let trackKindById = Dictionary(uniqueKeysWithValues: tracks.map { ($0.trackId, $0.kind) })
        let visualKinds: Set<TrackKind> = [.video, .overlay]

        let visualClips: [Clip] = clips.compactMap { clip in
            guard let kind = trackKindById[clip.trackId], visualKinds.contains(kind) else { return nil }
            return clip
        }

        let sorted = visualClips.sorted { lhs, rhs in
            if lhs.timelineRange.start == rhs.timelineRange.start {
                return lhs.clipId < rhs.clipId
            }
            return lhs.timelineRange.start < rhs.timelineRange.start
        }

        for clip in sorted {
            guard let media = mediaById[clip.mediaId] else { continue }
            guard let w = media.spec.width, let h = media.spec.height, w > 0, h > 0 else { continue }
            return CGSize(width: w, height: h)
        }
        return nil
    }
}
