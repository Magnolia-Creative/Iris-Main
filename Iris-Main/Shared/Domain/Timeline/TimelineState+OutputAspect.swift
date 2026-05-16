import Foundation

extension TimelineState {
    /// Recomputes `derivedOutputAspect` from the earliest visual clip (video/overlay) with known media dimensions.
    mutating func refreshDerivedOutputAspect() {
        derivedOutputAspect = Self.computeDerivedOutputAspect(
            clips: clips,
            tracks: tracks,
            mediaById: mediaById
        )
    }

    static func computeDerivedOutputAspect(
        clips: [Clip],
        tracks: [Track],
        mediaById: [String: Media]
    ) -> OutputAspectRatio? {
        let trackKindById = Dictionary(uniqueKeysWithValues: tracks.map { ($0.trackId, $0.kind) })
        let visualKinds: Set<TrackKind> = [.video, .overlay]

        let visualClips: [(Clip, TrackKind)] = clips.compactMap { clip in
            guard let kind = trackKindById[clip.trackId], visualKinds.contains(kind) else { return nil }
            return (clip, kind)
        }

        let sorted = visualClips.sorted { lhs, rhs in
            if lhs.0.timelineRange.start == rhs.0.timelineRange.start {
                return lhs.0.clipId < rhs.0.clipId
            }
            return lhs.0.timelineRange.start < rhs.0.timelineRange.start
        }

        for (clip, _) in sorted {
            guard let media = mediaById[clip.mediaId] else { continue }
            guard let w = media.spec.width, let h = media.spec.height, w > 0, h > 0 else { continue }
            return OutputAspectRatio(width: w, height: h)
        }
        return nil
    }
}
