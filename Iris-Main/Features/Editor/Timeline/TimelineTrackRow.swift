import SwiftUI

struct TimelineTrackRow: View {
    let track: Track
    let clips: [Clip]
    let mediaById: [String: Media]
    let layout: TimelineLayout
    let pixelsPerSecond: CGFloat
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    let viewportWidth: CGFloat
    let scrollOffset: CGFloat
    @Binding var selectedClipId: String?
    let onAutoScroll: (CGFloat) -> Void
    let isUserScrolling: Bool
    let reviewFocusedClipIds: Set<String>
    let isReviewInteractionDisabled: Bool

    private var trackHeight: CGFloat { layout.trackHeight(for: track.kind) }
    private let swapThresholdPx: CGFloat = 75

    @State private var dragState: DragState?
    @State private var trimState: TrimState?
    @State private var previewOrder: [String]?

    var body: some View {
        let baseOrder = clips.sorted { $0.timelineRange.start < $1.timelineRange.start }
        let baseOrderIds = baseOrder.map(\.clipId)
        let orderIds = previewOrder ?? baseOrderIds
        let clipById = Dictionary(uniqueKeysWithValues: clips.map { ($0.clipId, $0) })
        let orderedClips = orderIds.compactMap { clipById[$0] }
        let packedStartsById = packedStarts(for: orderedClips)

        ZStack(alignment: .leading) {
            Color.clear
                .frame(height: trackHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                        selectedClipId = nil
                    }
                }

            ForEach(clips, id: \.clipId) { clip in
                let displayStartUs: Int64 = {
                    if let dragState, dragState.clipId == clip.clipId {
                        return dragState.startTimeUs
                    } else if previewOrder != nil, let packedStart = packedStartsById[clip.clipId] {
                        return packedStart
                    } else {
                        return clip.timelineRange.start
                    }
                }()
                let startX = CGFloat(displayStartUs) / 1_000_000.0 * pixelsPerSecond
                let clipWidth = CGFloat(clip.duration) / 1_000_000.0 * pixelsPerSecond
                let dragOffsetX: CGFloat = {
                    if let dragState, dragState.clipId == clip.clipId {
                        return dragState.translation.width + (scrollOffset - dragState.startScrollOffset)
                    }
                    return 0
                }()

                TimelineClipView(
                    clip: clip, trackKind: track.kind, media: mediaById[clip.mediaId],
                    isSelected: selectedClipId == clip.clipId,
                    isDragging: dragState?.clipId == clip.clipId,
                    width: max(clipWidth, 20), height: trackHeight,
                    isReviewDimmed: !reviewFocusedClipIds.isEmpty && !reviewFocusedClipIds.contains(clip.clipId)
                )
                .frame(width: max(clipWidth, 20), height: trackHeight)
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    if selectedClipId == clip.clipId {
                        TrimHandleView()
                            .highPriorityGesture(trimGesture(for: clip, edge: .leading))
                    }
                }
                .overlay(alignment: .trailing) {
                    if selectedClipId == clip.clipId {
                        TrimHandleView()
                            .highPriorityGesture(trimGesture(for: clip, edge: .trailing))
                    }
                }
                .offset(x: startX + dragOffsetX)
                .animation(
                    dragState?.clipId == clip.clipId ? nil : .spring(response: 0.3, dampingFraction: 0.85),
                    value: orderIds
                )
                .zIndex(dragState?.clipId == clip.clipId || trimState?.clipId == clip.clipId ? 2 : 0)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        guard !isUserScrolling, !isReviewInteractionDisabled else { return }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedClipId = clip.clipId
                        }
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("timelineScroll"))
                        .onChanged { value in
                            if dragState?.clipId != clip.clipId {
                                dragState = DragState(
                                    clipId: clip.clipId, startTimeUs: clip.timelineRange.start,
                                    translation: value.translation, startScrollOffset: scrollOffset
                                )
                            } else {
                                dragState?.translation = value.translation
                            }
                            updatePreviewOrder(
                                clipId: clip.clipId, translationWidth: value.translation.width,
                                startScrollOffset: dragState?.startScrollOffset ?? scrollOffset,
                                currentScrollOffset: scrollOffset, currentOrder: orderedClips,
                                baseOrderIds: baseOrderIds
                            )
                            onAutoScroll(autoScrollDirection(for: value.location.x))
                        }
                        .onEnded { _ in
                            guard let dragState, dragState.clipId == clip.clipId else { return }
                            let finalOrderIds = previewOrder ?? baseOrderIds
                            let finalClips = finalOrderIds.compactMap { clipById[$0] }
                            let finalStarts = packedStarts(for: finalClips)
                            let resolvedStart = finalStarts[clip.clipId] ?? clip.timelineRange.start
                            onMoveClip(clip.clipId, resolvedStart, finalOrderIds)
                            self.dragState = nil
                            self.previewOrder = nil
                            onAutoScroll(0)
                        },
                    including: selectedClipId == clip.clipId && !isUserScrolling && !isReviewInteractionDisabled ? .all : .none
                )
            }
        }
        .frame(height: trackHeight)
        .onChange(of: dragState?.clipId) { _, newValue in
            if newValue == nil { onAutoScroll(0) }
        }
    }

    private func autoScrollDirection(for locationX: CGFloat) -> CGFloat {
        let edgeThreshold = min(.spacing(.sp10), max(0, viewportWidth / 2 - .spacing(.sp3)))
        if locationX < edgeThreshold { return -1 }
        if locationX > viewportWidth - edgeThreshold { return 1 }
        return 0
    }

    private func updatePreviewOrder(
        clipId: String, translationWidth: CGFloat,
        startScrollOffset: CGFloat, currentScrollOffset: CGFloat,
        currentOrder: [Clip], baseOrderIds: [String]
    ) {
        guard let dragState, dragState.clipId == clipId, pixelsPerSecond > 0 else { return }
        guard let currentIndex = currentOrder.firstIndex(where: { $0.clipId == clipId }) else { return }

        let adjustedTranslation = translationWidth + (currentScrollOffset - startScrollOffset)
        guard adjustedTranslation != 0 else { return }

        let durationPx = timeToPixels(currentOrder[currentIndex].duration)
        let proposedStartPx = timeToPixels(dragState.startTimeUs) + adjustedTranslation
        var updatedOrder = currentOrder
        var targetIndex = currentIndex

        if adjustedTranslation > 0 {
            while targetIndex + 1 < updatedOrder.count {
                let packed = packedStarts(for: updatedOrder)
                let next = updatedOrder[targetIndex + 1]
                let nextStartPx = timeToPixels(packed[next.clipId] ?? next.timelineRange.start)
                let overlapPx = (proposedStartPx + durationPx) - nextStartPx
                guard overlapPx >= swapThresholdPx else { break }
                updatedOrder.swapAt(targetIndex, targetIndex + 1)
                targetIndex += 1
            }
        } else {
            while targetIndex > 0 {
                let packed = packedStarts(for: updatedOrder)
                let prev = updatedOrder[targetIndex - 1]
                let prevStartPx = timeToPixels(packed[prev.clipId] ?? prev.timelineRange.start)
                let prevEndPx = prevStartPx + timeToPixels(prev.duration)
                let overlapPx = prevEndPx - proposedStartPx
                guard overlapPx >= swapThresholdPx else { break }
                updatedOrder.swapAt(targetIndex, targetIndex - 1)
                targetIndex -= 1
            }
        }

        let updatedIds = updatedOrder.map(\.clipId)
        if updatedIds == baseOrderIds {
            guard previewOrder != nil else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { previewOrder = nil }
            return
        }
        if updatedIds != previewOrder {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { previewOrder = updatedIds }
        }
    }

    private func packedStarts(for orderedClips: [Clip]) -> [String: Int64] {
        var cursor: Int64 = 0
        var starts: [String: Int64] = [:]
        for clip in orderedClips {
            starts[clip.clipId] = cursor
            cursor += clip.duration
        }
        return starts
    }

    private func timeToPixels(_ timeUs: Int64) -> CGFloat {
        CGFloat(timeUs) / 1_000_000.0 * pixelsPerSecond
    }

    private func trimGesture(for clip: Clip, edge: TrimEdge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("timelineScroll"))
            .onChanged { value in
                if selectedClipId != clip.clipId {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { selectedClipId = clip.clipId }
                }
                if trimState?.clipId != clip.clipId || trimState?.edge != edge {
                    trimState = TrimState(
                        clipId: clip.clipId, edge: edge,
                        startTimelineRange: clip.timelineRange, startSourceRange: clip.sourceRange,
                        translation: value.translation, startScrollOffset: scrollOffset
                    )
                    dragState = nil
                } else {
                    trimState?.translation = value.translation
                }
                guard let trimState else { return }
                let adjustedTranslation = trimState.translation.width + (scrollOffset - trimState.startScrollOffset)
                let resolved = resolvedTrimRanges(
                    for: clip, edge: edge,
                    startTimelineRange: trimState.startTimelineRange,
                    startSourceRange: trimState.startSourceRange,
                    translationWidth: adjustedTranslation
                )
                onTrimClip(clip.clipId, resolved.sourceRange, resolved.timelineRange, false)
                onAutoScroll(autoScrollDirection(for: value.location.x))
            }
            .onEnded { value in
                guard let trimState, trimState.clipId == clip.clipId, trimState.edge == edge else { return }
                let adjustedTranslation = value.translation.width + (scrollOffset - trimState.startScrollOffset)
                let resolved = resolvedTrimRanges(
                    for: clip, edge: edge,
                    startTimelineRange: trimState.startTimelineRange,
                    startSourceRange: trimState.startSourceRange,
                    translationWidth: adjustedTranslation
                )
                onTrimClip(clip.clipId, resolved.sourceRange, resolved.timelineRange, true)
                self.trimState = nil
                onAutoScroll(0)
            }
    }

    private func resolvedTrimRanges(
        for clip: Clip, edge: TrimEdge,
        startTimelineRange: TimeRange, startSourceRange: TimeRange,
        translationWidth: CGFloat
    ) -> (sourceRange: TimeRange, timelineRange: TimeRange) {
        guard pixelsPerSecond > 0 else { return (startSourceRange, startTimelineRange) }
        let isPhoto = mediaById[clip.mediaId]?.kind == .photo
        let minDurationUs = min(startTimelineRange.duration, 200_000)
        let deltaSeconds = translationWidth / pixelsPerSecond
        let deltaUs = Int64(deltaSeconds * 1_000_000)
        let mediaDurationUs: Int64? = {
            guard !isPhoto, let media = mediaById[clip.mediaId], let seconds = media.spec.duration, seconds > 0 else { return nil }
            return Int64(seconds * 1_000_000)
        }()

        switch edge {
        case .leading:
            if isPhoto {
                let proposedDuration = startTimelineRange.duration - deltaUs
                let maxDuration = max(minDurationUs, startTimelineRange.end)
                let clampedDuration = min(maxDuration, max(minDurationUs, proposedDuration))
                return (
                    TimeRange(start: 0, end: max(0, clampedDuration)),
                    TimeRange(start: startTimelineRange.end - clampedDuration, end: startTimelineRange.end)
                )
            } else {
                let proposedSourceStart = startSourceRange.start + deltaUs
                let maxSourceStart = startSourceRange.end - minDurationUs
                let clampedSourceStart = clamp(proposedSourceStart, 0, maxSourceStart)
                let newDuration = startSourceRange.end - clampedSourceStart
                let maxDuration = max(minDurationUs, startTimelineRange.end)
                let clampedDuration = min(newDuration, maxDuration)
                let newSourceStart = startSourceRange.end - clampedDuration
                return (
                    TimeRange(start: max(0, newSourceStart), end: startSourceRange.end),
                    TimeRange(start: startTimelineRange.end - clampedDuration, end: startTimelineRange.end)
                )
            }
        case .trailing:
            let minEnd = startTimelineRange.start + minDurationUs
            let maxEnd: Int64 = mediaDurationUs.map { md in
                startTimelineRange.end + (md - startSourceRange.end)
            } ?? Int64.max
            let proposedEnd = startTimelineRange.end + deltaUs
            let clampedEnd = clamp(proposedEnd, minEnd, maxEnd)
            let newTimelineRange = TimeRange(start: startTimelineRange.start, end: clampedEnd)
            if isPhoto {
                return (TimeRange(start: 0, end: max(0, newTimelineRange.duration)), newTimelineRange)
            } else {
                let sourceDelta = clampedEnd - startTimelineRange.end
                return (TimeRange(start: startSourceRange.start, end: startSourceRange.end + sourceDelta), newTimelineRange)
            }
        }
    }

    private func clamp(_ value: Int64, _ minValue: Int64, _ maxValue: Int64) -> Int64 {
        guard maxValue >= minValue else { return minValue }
        return min(maxValue, max(minValue, value))
    }
}

private struct DragState {
    let clipId: String
    let startTimeUs: Int64
    var translation: CGSize
    let startScrollOffset: CGFloat
}

private struct TrimState {
    let clipId: String
    let edge: TrimEdge
    let startTimelineRange: TimeRange
    let startSourceRange: TimeRange
    var translation: CGSize
    let startScrollOffset: CGFloat
}

private enum TrimEdge {
    case leading
    case trailing
}

private struct TrimHandleView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .fill(Color.ds.accentFg)
            .frame(width: .spacing(.sp1))
            .frame(maxHeight: .infinity)
            .padding(.vertical, .spacing(.sp1))
            .frame(width: .spacing(.sp4))
            .background(Color.ds.accentBg.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
    }
}
