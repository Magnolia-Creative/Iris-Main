import SwiftUI

enum JITTimelinePresentation {
    case full
    case primaryTrackOnly
    case focusedClipStrip
    case hidden
}

@MainActor
struct EditorJITContextFactory {
    let activeSpace: EditorSpace
    let reviewFocusedClipIds: Set<String>
    let isReviewInteractionDisabled: Bool
    let promptActionPreview: TimelinePromptActionPreview?
    let onAddSelection: ((TrackKind, ImportSource) -> Void)?

    var allowsTimelineAdditions: Bool {
        activeSpace == .edit && !isReviewInteractionDisabled
    }

    var previewComponentSize: EditorComponentSize {
        switch activeSpace {
        case .importMedia:
            return .compressed
        case .edit, .export:
            return .standard
        }
    }

    func timelineLayout(for presentation: JITTimelinePresentation) -> TimelineLayout {
        switch presentation {
        case .focusedClipStrip, .primaryTrackOnly:
            return .compressed
        case .full:
            return activeSpace == .edit ? .expanded : .compressed
        case .hidden:
            return .compressed
        }
    }

    func timelineContext(
        state: TimelineState,
        controller: TimelineController,
        captionsFlow: CaptionsFlowController,
        pixelsPerSecond: CGFloat,
        isAddMenuOpen: Binding<Bool>,
        selectedCaptionCueId: Binding<String?>,
        presentation: JITTimelinePresentation
    ) -> EditorTimelineContext {
        let layout = timelineLayout(for: presentation)
        let canAddToTimeline = layout == .expanded && allowsTimelineAdditions
        let highlight = captionsFlow.highlightRangeUs(playheadUs: state.currentTimeAtCenter)
        let playheadTint = captionsFlow.playheadUsesAccentTint ? Color.ds.accentFg : Color.ds.text

        return EditorTimelineContext(
            tracks: displayTracks(state: state, presentation: presentation),
            clipsByTrackId: clipsByTrackId(state: state, presentation: presentation),
            mediaById: state.mediaById,
            captionGroups: state.captionGroups,
            captionCues: state.captionCues,
            layoutSize: layout.componentSize,
            pixelsPerSecond: pixelsPerSecond,
            timelineDurationUs: state.calculatedTimelineDurationUs,
            scrollableDurationUs: state.scrollableDurationUs,
            playbackState: state.playbackState,
            reviewFocusedClipIds: reviewFocusedClipIds,
            isReviewInteractionDisabled: isReviewInteractionDisabled,
            promptActionPreview: promptActionPreview,
            captionHighlightRangeUs: highlight,
            playheadTint: playheadTint,
            showAddButton: canAddToTimeline,
            currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
            scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
            selectedClipId: controller.binding(\.selectedClipId),
            selectedCaptionCueId: selectedCaptionCueId,
            isAddMenuOpen: isAddMenuOpen
        )
    }

    func timelineActions(
        controller: TimelineController,
        captionsFlow: CaptionsFlowController,
        renderBridge: TimelineRenderBridge,
        layout: TimelineLayout,
        presentation _: JITTimelinePresentation
    ) -> EditorTimelineActions {
        EditorTimelineActions(
            onAddSelection: timelineAddSelection(
                layout: layout,
                fallback: controller.handleAddSelection(kind:source:)
            ),
            onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
            onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
            onDropImportedSegmentAtTime: activeSpace == .importMedia ? { item, timeUs in
                controller.insertClipSegment(
                    mediaId: item.mediaId,
                    sourceRange: item.sourceRange,
                    at: timeUs
                )
            } : nil,
            onPreviewScrub: { timeUs, velocity in
                renderBridge.handleScroll(timeUs: timeUs, velocity: velocity)
            },
            onCaptionCueSelected: { cueId in
                controller.clearSelection()
                captionsFlow.openStyleEditor(forCueId: cueId)
            },
            onClipSelected: {
                captionsFlow.cancelStyleEditing()
            }
        )
    }

    func playbackContext(
        controller: TimelineController,
        playback: PlaybackController,
        showAspectSettings: Binding<Bool>
    ) -> EditorPlaybackContext {
        EditorPlaybackContext(
            isPlaying: playback.isPlaying(),
            canUndo: controller.canUndo,
            canRedo: controller.canRedo,
            previewAspect: controller.state.effectiveOutputAspect?.aspectCGFloat,
            viewerSize: previewComponentSize,
            showAspectSettings: showAspectSettings
        )
    }

    func playbackActions(
        controller: TimelineController,
        playback: PlaybackController,
        showAspectSettings: Binding<Bool>
    ) -> EditorPlaybackActions {
        EditorPlaybackActions(
            onPlay: { playback.play() },
            onPause: { playback.pause() },
            onJumpToStart: { playback.jumpToStart() },
            onJumpToEnd: { playback.jumpToEnd() },
            onUndo: { controller.undoLastActionGroup() },
            onRedo: { controller.redoLastActionGroup() },
            onToggleAspectSettings: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showAspectSettings.wrappedValue.toggle()
                }
            }
        )
    }

    func timelineAddSelection(
        layout: TimelineLayout,
        fallback: @escaping (TrackKind, ImportSource) -> Void
    ) -> ((TrackKind, ImportSource) -> Void)? {
        guard layout == .expanded, allowsTimelineAdditions else { return nil }
        return onAddSelection ?? fallback
    }

    func displayTracks(state: TimelineState, presentation: JITTimelinePresentation) -> [Track] {
        let tracks = state.editorDisplayTracks
        switch presentation {
        case .focusedClipStrip, .primaryTrackOnly:
            return tracks.filter { $0.kind == .video || $0.kind == .captions }
        case .full, .hidden:
            return tracks
        }
    }

    func clipsByTrackId(state: TimelineState, presentation: JITTimelinePresentation) -> [String: [Clip]] {
        switch presentation {
        case .focusedClipStrip, .primaryTrackOnly:
            let focusIds = focusedClipIds(state: state)
            guard !focusIds.isEmpty else { return state.clipsByTrackId }
            var filtered: [String: [Clip]] = [:]
            for (trackId, clips) in state.clipsByTrackId {
                let kept = clips.filter { focusIds.contains($0.clipId) }
                if !kept.isEmpty {
                    filtered[trackId] = kept
                }
            }
            return filtered.isEmpty ? state.clipsByTrackId : filtered
        case .full, .hidden:
            return state.clipsByTrackId
        }
    }

    private func focusedClipIds(state: TimelineState) -> Set<String> {
        if !reviewFocusedClipIds.isEmpty {
            return reviewFocusedClipIds
        }
        if let selectedClipId = state.selectedClipId {
            return [selectedClipId]
        }
        return []
    }
}

extension TimelineLayout {
    var componentSize: EditorComponentSize {
        self == .expanded ? .expanded : .compressed
    }
}
