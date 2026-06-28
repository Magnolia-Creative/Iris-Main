import SwiftUI

struct EditorTimelineContext {
    let tracks: [Track]
    let clipsByTrackId: [String: [Clip]]
    let mediaById: [String: Media]
    let captionGroups: [CaptionGroup]
    let captionCues: [CaptionCue]
    let layoutSize: EditorComponentSize
    let pixelsPerSecond: CGFloat
    let timelineDurationUs: Int64
    let scrollableDurationUs: Int64
    var playbackState: TimelinePlaybackState
    var reviewFocusedClipIds: Set<String>
    var isReviewInteractionDisabled: Bool
    var promptActionPreview: TimelinePromptActionPreview?
    var captionHighlightRangeUs: ClosedRange<Int64>?
    var playheadTint: Color
    var showAddButton: Bool

    @Binding var currentTimeAtCenter: Int64
    @Binding var scrollTargetTimeUs: Int64?
    @Binding var selectedClipId: String?
    @Binding var selectedCaptionCueId: String?
    @Binding var isAddMenuOpen: Bool
}

struct EditorTimelineActions {
    var onAddSelection: ((TrackKind, ImportSource) -> Void)?
    var onMoveClip: (String, Int64, [String]) -> Void
    var onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    var onDropImportedSegmentAtTime: ((ImportedTimelineSegment, Int64) -> Void)?
    var onPreviewScrub: ((Int64, Double) -> Void)?
    var onCaptionCueSelected: ((String) -> Void)?
    var onClipSelected: (() -> Void)?

    static let noop = EditorTimelineActions(
        onMoveClip: { _, _, _ in },
        onTrimClip: { _, _, _, _ in }
    )
}

struct EditorToolContext {
    var isClipSelected: Bool
    var selectedClipColorFilter: ClipColorFilter
    var selectedClipVolume: ClipVolume
    var expandedToolId: Binding<Int?>
    var isReviewActive: Bool
}

struct EditorToolActions {
    var onSplitClip: () -> Void
    var onDeleteClip: () -> Void
    var onSetClipColorFilter: (ClipColorFilter) -> Void
    var onResetClipColorFilter: () -> Void
    var onSetClipVolume: (ClipVolume) -> Void
    var onResetClipVolume: () -> Void
    var onDeselectClip: () -> Void

    static let noop = EditorToolActions(
        onSplitClip: {},
        onDeleteClip: {},
        onSetClipColorFilter: { _ in },
        onResetClipColorFilter: {},
        onSetClipVolume: { _ in },
        onResetClipVolume: {},
        onDeselectClip: {}
    )
}

struct EditorCaptionToolContext {
    var groupId: String
    var style: CaptionStyle
    var hasBackground: Bool
    var expandedToolId: Binding<String?>
    var validationMessage: String?
}

struct EditorCaptionToolActions {
    var onUpdateStyle: (CaptionStyle, Bool) -> Void
    var onDeleteCaptions: () -> Void
    var onFinishEditing: () -> Void

    static let noop = EditorCaptionToolActions(
        onUpdateStyle: { _, _ in },
        onDeleteCaptions: {},
        onFinishEditing: {}
    )
}

struct EditorPlaybackContext {
    var isPlaying: Bool
    var canUndo: Bool
    var canRedo: Bool
    var previewAspect: CGFloat?
    var viewerSize: EditorComponentSize
    var showAspectSettings: Binding<Bool>
}

struct EditorPlaybackActions {
    var onPlay: () -> Void
    var onPause: () -> Void
    var onJumpToStart: () -> Void
    var onJumpToEnd: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onToggleAspectSettings: () -> Void

    static let noop = EditorPlaybackActions(
        onPlay: {},
        onPause: {},
        onJumpToStart: {},
        onJumpToEnd: {},
        onUndo: {},
        onRedo: {},
        onToggleAspectSettings: {}
    )
}
