import SwiftUI

struct TimelineTrackComponentConfig: Equatable {
    var size: EditorComponentSize = .standard
    var interaction: EditorTrackInteractionMode = .editable
    var showsTrimHandles: Bool = true
    var showsReviewOverlay: Bool = true
}

struct TimelineClipTrackComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.track"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let config: TimelineTrackComponentConfig
    let track: Track
    let clips: [Clip]
    let mediaById: [String: Media]
    let pixelsPerSecond: CGFloat
    let viewportWidth: CGFloat
    let scrollOffset: CGFloat
    @Binding var selectedClipId: String?
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    let onAutoScroll: (CGFloat) -> Void
    let isUserScrolling: Bool
    var reviewFocusedClipIds: Set<String> = []
    var promptActionPreview: TimelinePromptActionPreview? = nil
    var onClipSelected: (() -> Void)? = nil

    private var layout: TimelineLayout {
        TimelineLayout(from: TimelineComponentLayout.preset(config.size))
    }

    private var isInteractionEnabled: Bool {
        config.interaction == .editable && !isUserScrolling
    }

    var body: some View {
        TimelineTrackRow(
            track: track,
            clips: clips,
            mediaById: mediaById,
            layout: layout,
            pixelsPerSecond: pixelsPerSecond,
            onMoveClip: config.interaction == .editable ? onMoveClip : { _, _, _ in },
            onTrimClip: config.interaction == .editable ? onTrimClip : { _, _, _, _ in },
            viewportWidth: viewportWidth,
            scrollOffset: scrollOffset,
            selectedClipId: $selectedClipId,
            onAutoScroll: onAutoScroll,
            isUserScrolling: isUserScrolling || config.interaction != .editable,
            reviewFocusedClipIds: config.showsReviewOverlay ? reviewFocusedClipIds : [],
            isReviewInteractionDisabled: config.interaction == .review,
            promptActionPreview: config.showsReviewOverlay ? promptActionPreview : nil,
            onClipSelected: onClipSelected
        )
    }
}

struct TimelineCaptionsTrackComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.captionsTrack"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let config: TimelineTrackComponentConfig
    let track: Track
    let cues: [CaptionCue]
    let clipsById: [String: Clip]
    let pixelsPerSecond: CGFloat
    @Binding var selectedCaptionCueId: String?
    let onSelectCue: (String) -> Void

    private var layout: TimelineLayout {
        TimelineLayout(from: TimelineComponentLayout.preset(config.size))
    }

    var body: some View {
        TimelineCaptionsTrackRow(
            track: track,
            cues: cues,
            clipsById: clipsById,
            layout: layout,
            pixelsPerSecond: pixelsPerSecond,
            selectedCaptionCueId: $selectedCaptionCueId,
            onSelectCue: config.interaction == .readOnly ? { _ in } : onSelectCue
        )
    }
}

struct TimelineTrackStackComponent: View {
    let config: TimelineTrackComponentConfig
    let tracks: [Track]
    let clipsByTrackId: [String: [Clip]]
    let mediaById: [String: Media]
    let captionGroups: [CaptionGroup]
    let captionCues: [CaptionCue]
    let pixelsPerSecond: CGFloat
    let viewportWidth: CGFloat
    let scrollOffset: CGFloat
    @Binding var selectedClipId: String?
    @Binding var selectedCaptionCueId: String?
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    let onAutoScroll: (CGFloat) -> Void
    let isUserScrolling: Bool
    var reviewFocusedClipIds: Set<String> = []
    var promptActionPreview: TimelinePromptActionPreview? = nil
    var onSelectCaptionCue: ((String) -> Void)? = nil
    var onClipSelected: (() -> Void)? = nil

    private var layout: TimelineComponentLayout {
        TimelineComponentLayout.preset(config.size)
    }

    private var displayTracks: [Track] {
        let hasOverlayClips = tracks.contains { track in
            track.kind == .overlay && !(clipsByTrackId[track.trackId] ?? []).isEmpty
        }
        return tracks.filter { track in
            track.kind != .overlay || hasOverlayClips
        }
    }

    var body: some View {
        VStack(spacing: layout.trackSpacing) {
            ForEach(displayTracks) { track in
                if track.kind == .captions {
                    let groupIds = Set(captionGroups.filter { $0.trackId == track.trackId }.map(\.groupId))
                    let cues = captionCues.filter { groupIds.contains($0.groupId) }
                    TimelineCaptionsTrackComponent(
                        config: config,
                        track: track,
                        cues: cues,
                        clipsById: Dictionary(uniqueKeysWithValues: clipsByTrackId.values.flatMap { $0 }.map { ($0.clipId, $0) }),
                        pixelsPerSecond: pixelsPerSecond,
                        selectedCaptionCueId: $selectedCaptionCueId,
                        onSelectCue: { id in onSelectCaptionCue?(id) }
                    )
                } else {
                    TimelineClipTrackComponent(
                        config: config,
                        track: track,
                        clips: clipsByTrackId[track.trackId] ?? [],
                        mediaById: mediaById,
                        pixelsPerSecond: pixelsPerSecond,
                        viewportWidth: viewportWidth,
                        scrollOffset: scrollOffset,
                        selectedClipId: $selectedClipId,
                        onMoveClip: onMoveClip,
                        onTrimClip: onTrimClip,
                        onAutoScroll: onAutoScroll,
                        isUserScrolling: isUserScrolling,
                        reviewFocusedClipIds: reviewFocusedClipIds,
                        promptActionPreview: promptActionPreview,
                        onClipSelected: onClipSelected
                    )
                }
            }
        }
    }
}
