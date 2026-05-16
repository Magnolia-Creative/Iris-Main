import Foundation

enum CaptionCueProjection {
    /// Returns the cue's current timeline range. Anchored cues are projected through
    /// the owning clip; legacy cues fall back to their persisted timeline range.
    static func currentTimelineRange(
        for cue: CaptionCue,
        clips: [String: Clip]
    ) -> (start: Int64, end: Int64)? {
        guard let clipId = cue.clipId, let sourceStartUs = cue.sourceStartUs, let sourceEndUs = cue.sourceEndUs else {
            return cue.timelineEndUs > cue.timelineStartUs
                ? (cue.timelineStartUs, cue.timelineEndUs)
                : nil
        }

        guard let clip = clips[clipId] else { return nil }
        guard clip.sourceRange.duration > 0, clip.timelineRange.duration > 0 else { return nil }

        let clippedSourceStart = max(sourceStartUs, clip.sourceRange.start)
        let clippedSourceEnd = min(sourceEndUs, clip.sourceRange.end)
        guard clippedSourceEnd > clippedSourceStart else { return nil }

        let start = project(sourceUs: clippedSourceStart, through: clip)
        let end = project(sourceUs: clippedSourceEnd, through: clip)
        let clippedStart = max(start, clip.timelineRange.start)
        let clippedEnd = min(end, clip.timelineRange.end)
        guard clippedEnd > clippedStart else { return nil }
        return (clippedStart, clippedEnd)
    }

    private static func project(sourceUs: Int64, through clip: Clip) -> Int64 {
        let sourceOffset = Double(sourceUs - clip.sourceRange.start)
        let timelineDuration = Double(clip.timelineRange.duration)
        let sourceDuration = Double(clip.sourceRange.duration)
        return clip.timelineRange.start + Int64(sourceOffset * timelineDuration / sourceDuration)
    }
}
