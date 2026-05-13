import Foundation

// MARK: - Action classification

extension Action {
    /// Sequence edits that require an in-editor preview before commit when produced by the prompt bar.
    var isPromptSequenceReviewable: Bool {
        switch payload {
        case .splitClip, .trimClip, .removeClipRanges:
            return true
        default:
            return false
        }
    }
}

// MARK: - Review session

struct TimelinePromptActionReviewSession: Equatable {
    let originalPrompt: String
    let actions: [Action]
    var currentIndex: Int

    var currentAction: Action? {
        guard currentIndex >= 0, currentIndex < actions.count else { return nil }
        return actions[currentIndex]
    }

    var totalCount: Int { actions.count }

    var displayPosition: Int { min(currentIndex + 1, max(totalCount, 1)) }
}

// MARK: - Preview for timeline overlays

enum TimelinePromptActionPreviewKind: Equatable {
    case split
    case trim
    case removeRanges
}

struct TimelinePromptActionOverlayRange: Equatable {
    let clipId: String
    let trackId: String
    /// Region on the timeline (microseconds) to darken.
    let timelineRange: TimeRange
}

struct TimelinePromptActionPreview: Equatable {
    let kind: TimelinePromptActionPreviewKind
    let title: String
    let subtitle: String?
    let focusClipIds: Set<String>
    let overlayRanges: [TimelinePromptActionOverlayRange]
    /// Absolute timeline time for a vertical split marker, if any.
    let splitMarkerTimeUs: Int64?
    /// Time to center the viewport on when focusing this preview.
    let scrollFocusTimeUs: Int64
}

// MARK: - Building previews from live timeline + pending action

enum TimelinePromptActionPreviewBuilder {
    /// Returns a preview for `action` against the current timeline, or `nil` if the action cannot be previewed (missing clip, invalid geometry).
    static func makePreview(state: TimelineState, action: Action) -> TimelinePromptActionPreview? {
        switch action.payload {
        case let .splitClip(clipId, atTimeUs):
            return splitPreview(state: state, clipId: clipId, atTimeUs: atTimeUs)
        case let .trimClip(clipId, sourceRange):
            return trimPreview(state: state, clipId: clipId, newSourceRange: sourceRange)
        case let .removeClipRanges(clipId, sourceRanges):
            return removeRangesPreview(state: state, clipId: clipId, sourceRanges: sourceRanges)
        default:
            return nil
        }
    }

    private static func splitPreview(state: TimelineState, clipId: String, atTimeUs: Int64) -> TimelinePromptActionPreview? {
        guard let clip = state.clips.first(where: { $0.clipId == clipId }) else { return nil }
        guard atTimeUs > clip.timelineRange.start, atTimeUs < clip.timelineRange.end else { return nil }
        return TimelinePromptActionPreview(
            kind: .split,
            title: "Split clip",
            subtitle: nil,
            focusClipIds: [clipId],
            overlayRanges: [],
            splitMarkerTimeUs: atTimeUs,
            scrollFocusTimeUs: atTimeUs
        )
    }

    private static func trimPreview(state: TimelineState, clipId: String, newSourceRange: TimeRange) -> TimelinePromptActionPreview? {
        guard let clip = state.clips.first(where: { $0.clipId == clipId }) else { return nil }
        guard newSourceRange.duration > 0 else { return nil }

        let old = clip.sourceRange
        var removedSource: [TimeRange] = []
        if newSourceRange.start > old.start {
            removedSource.append(TimeRange(start: old.start, end: min(newSourceRange.start, old.end)))
        }
        if newSourceRange.end < old.end {
            removedSource.append(TimeRange(start: max(newSourceRange.end, old.start), end: old.end))
        }
        let overlays = removedSource.compactMap { sourceRange -> TimelinePromptActionOverlayRange? in
            guard sourceRange.duration > 0 else { return nil }
            let tlStart = clip.timelineRange.start + (sourceRange.start - old.start)
            let tlEnd = clip.timelineRange.start + (sourceRange.end - old.start)
            guard tlEnd > tlStart else { return nil }
            return TimelinePromptActionOverlayRange(
                clipId: clipId,
                trackId: clip.trackId,
                timelineRange: TimeRange(start: tlStart, end: tlEnd)
            )
        }

        let focusTime: Int64 = {
            if let first = overlays.first?.timelineRange {
                if overlays.count == 1 {
                    return (first.start + first.end) / 2
                }
                let unionStart = overlays.map(\.timelineRange.start).min() ?? first.start
                let unionEnd = overlays.map(\.timelineRange.end).max() ?? first.end
                return (unionStart + unionEnd) / 2
            }
            return (clip.timelineRange.start + clip.timelineRange.end) / 2
        }()

        return TimelinePromptActionPreview(
            kind: .trim,
            title: "Trim clip",
            subtitle: nil,
            focusClipIds: [clipId],
            overlayRanges: overlays,
            splitMarkerTimeUs: nil,
            scrollFocusTimeUs: focusTime
        )
    }

    private static func removeRangesPreview(state: TimelineState, clipId: String, sourceRanges: [TimeRange]) -> TimelinePromptActionPreview? {
        guard let clip = state.clips.first(where: { $0.clipId == clipId }) else { return nil }
        let normalized = normalizedRemovalRanges(sourceRanges, within: clip.sourceRange)
        guard !normalized.isEmpty else { return nil }

        let old = clip.sourceRange
        let overlays: [TimelinePromptActionOverlayRange] = normalized.compactMap { range in
            guard range.duration > 0 else { return nil }
            let tlStart = clip.timelineRange.start + (range.start - old.start)
            let tlEnd = clip.timelineRange.start + (range.end - old.start)
            guard tlEnd > tlStart else { return nil }
            return TimelinePromptActionOverlayRange(
                clipId: clipId,
                trackId: clip.trackId,
                timelineRange: TimeRange(start: tlStart, end: tlEnd)
            )
        }
        guard !overlays.isEmpty else { return nil }

        let unionStart = overlays.map(\.timelineRange.start).min()!
        let unionEnd = overlays.map(\.timelineRange.end).max()!
        let focusTime = (unionStart + unionEnd) / 2

        return TimelinePromptActionPreview(
            kind: .removeRanges,
            title: "Remove ranges",
            subtitle: nil,
            focusClipIds: [clipId],
            overlayRanges: overlays,
            splitMarkerTimeUs: nil,
            scrollFocusTimeUs: focusTime
        )
    }

    private static func normalizedRemovalRanges(_ ranges: [TimeRange], within sourceRange: TimeRange) -> [TimeRange] {
        let bounded = ranges.compactMap { range -> TimeRange? in
            let start = max(sourceRange.start, range.start)
            let end = min(sourceRange.end, range.end)
            guard end > start else { return nil }
            return TimeRange(start: start, end: end)
        }
        .sorted { left, right in
            left.start == right.start ? left.end < right.end : left.start < right.start
        }

        return bounded.reduce(into: [TimeRange]()) { merged, range in
            guard let last = merged.last else {
                merged.append(range)
                return
            }
            if range.start <= last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
    }
}
