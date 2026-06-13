import SwiftUI

@MainActor
enum EditorComponentShowcaseSamples {
    static let timelineId = "showcase-timeline"

    static var sampleTracks: [Track] {
        [
            Track(timelineId: timelineId, kind: .video, sortIndex: 0),
            Track(timelineId: timelineId, kind: .captions, sortIndex: 1)
        ]
    }

    static var sampleClips: [Clip] {
        let videoTrackId = sampleTracks[0].trackId
        return [
            Clip(
                trackId: videoTrackId,
                mediaId: "media-1",
                sourceRange: TimeRange(start: 0, end: 4_000_000),
                timelineRange: TimeRange(start: 0, end: 4_000_000)
            ),
            Clip(
                trackId: videoTrackId,
                mediaId: "media-2",
                sourceRange: TimeRange(start: 0, end: 3_000_000),
                timelineRange: TimeRange(start: 4_000_000, end: 7_000_000)
            )
        ]
    }

    static var sampleMediaById: [String: Media] {
        [
            "media-1": Media(
                mediaId: "media-1",
                mediaLibraryId: "lib-showcase",
                kind: .video,
                assetRefId: "asset-1",
                spec: MediaSpec(duration: 10, width: 1920, height: 1080)
            ),
            "media-2": Media(
                mediaId: "media-2",
                mediaLibraryId: "lib-showcase",
                kind: .video,
                assetRefId: "asset-2",
                spec: MediaSpec(duration: 8, width: 1920, height: 1080)
            )
        ]
    }

    static var sampleCaptionGroup: CaptionGroup {
        CaptionGroup(
            groupId: "group-1",
            trackId: sampleTracks[1].trackId,
            timelineId: timelineId,
            style: .modern,
            hasBackground: true
        )
    }

    static var sampleCaptionCues: [CaptionCue] {
        [
            CaptionCue(
                cueId: "cue-1",
                groupId: sampleCaptionGroup.groupId,
                clipId: sampleClips[0].clipId,
                text: "Hello showcase",
                timelineStartUs: 0,
                timelineEndUs: 2_000_000,
                sourceStartUs: 0,
                sourceEndUs: 2_000_000
            ),
            CaptionCue(
                cueId: "cue-2",
                groupId: sampleCaptionGroup.groupId,
                clipId: sampleClips[1].clipId,
                text: "Second line",
                timelineStartUs: 4_000_000,
                timelineEndUs: 6_500_000,
                sourceStartUs: 0,
                sourceEndUs: 2_500_000
            )
        ]
    }

    static func clipsByTrackId() -> [String: [Clip]] {
        Dictionary(grouping: sampleClips, by: \.trackId)
    }

    static func makeTimelineContext(
        size: EditorComponentSize,
        currentTime: Binding<Int64>,
        selectedClipId: Binding<String?>,
        selectedCaptionCueId: Binding<String?>,
        isAddMenuOpen: Binding<Bool>
    ) -> EditorTimelineContext {
        EditorTimelineContext(
            tracks: sampleTracks,
            clipsByTrackId: clipsByTrackId(),
            mediaById: sampleMediaById,
            captionGroups: [sampleCaptionGroup],
            captionCues: sampleCaptionCues,
            layoutSize: size,
            pixelsPerSecond: 100,
            timelineDurationUs: 7_000_000,
            scrollableDurationUs: 8_000_000,
            playbackState: .idle,
            reviewFocusedClipIds: [],
            isReviewInteractionDisabled: false,
            captionHighlightRangeUs: nil,
            playheadTint: Color.ds.text,
            showAddButton: true,
            currentTimeAtCenter: currentTime,
            scrollTargetTimeUs: .constant(nil),
            selectedClipId: selectedClipId,
            selectedCaptionCueId: selectedCaptionCueId,
            isAddMenuOpen: isAddMenuOpen
        )
    }

    static func makeToolContext(expandedToolId: Binding<Int?>) -> EditorToolContext {
        EditorToolContext(
            isClipSelected: true,
            selectedClipColorFilter: .neutral,
            selectedClipVolume: .neutral,
            expandedToolId: expandedToolId,
            isReviewActive: false
        )
    }

    static func makeCaptionToolContext(expandedToolId: Binding<String?>) -> EditorCaptionToolContext {
        EditorCaptionToolContext(
            groupId: sampleCaptionGroup.groupId,
            style: sampleCaptionGroup.style,
            hasBackground: sampleCaptionGroup.hasBackground,
            expandedToolId: expandedToolId,
            validationMessage: nil
        )
    }

    static func makePlaybackContext(
        size: EditorComponentSize,
        isPlaying: Bool,
        showAspectSettings: Binding<Bool>
    ) -> EditorPlaybackContext {
        EditorPlaybackContext(
            isPlaying: isPlaying,
            canUndo: true,
            canRedo: false,
            previewAspect: 16.0 / 9.0,
            viewerSize: size,
            showAspectSettings: showAspectSettings
        )
    }

    static func demoToolbarItems(
        showsClipTools: Bool,
        showsParameters: Bool,
        toolContext: EditorToolContext,
        toolActions: EditorToolActions,
        temperature: Binding<Double>,
        volume: Binding<Double>
    ) -> [EditorToolbarItem] {
        var items: [EditorToolbarItem] = []
        if showsClipTools {
            items.append(
                EditorToolbarItem(id: "clip-tools", category: .tools, placementPriority: 10) {
                    ComponentLibraryClipToolsDemo(context: toolContext, actions: toolActions)
                }
            )
        }
        if showsParameters {
            items.append(
                EditorToolbarItem(id: "temperature", category: .tools, placementPriority: 5) {
                    EditorParameterControlCardComponent(
                        title: "Temperature",
                        value: temperature,
                        bounds: EditorParameterBounds(lower: -1, upper: 1)
                    )
                    .frame(width: 140)
                }
            )
            items.append(
                EditorToolbarItem(id: "volume", category: .tools, placementPriority: 4) {
                    EditorParameterControlCardComponent(
                        title: "Volume",
                        value: volume,
                        bounds: EditorParameterBounds(lower: 0, upper: 2)
                    )
                    .frame(width: 140)
                }
            )
        }
        return items
    }
}
