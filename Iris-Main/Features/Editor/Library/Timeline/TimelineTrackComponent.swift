import SwiftUI
import UIKit

struct TimelineTrackComponent: View, EditorLibraryComponentSpec {
    static let componentId: EditorComponentID = "timeline.track"
    static let category: EditorComponentCategory = .timeline
    static let supportedSizes: Set<EditorComponentSize> = [.compressed, .standard, .expanded]

    let model: TimelineTrackModel
    let pixelsPerSecond: CGFloat
    var minimumContentWidth: CGFloat?
    var viewportWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    @Binding var selectedSegmentId: String?
    var reviewFocusedSegmentIds: Set<String>
    var isReviewInteractionDisabled: Bool
    var promptFocusSegmentIds: Set<String>
    var promptActionPreview: TimelinePromptActionPreview?
    var isUserScrolling: Bool
    var onSelectSegment: ((String) -> Void)?
    var onMoveSegment: ((String, Int64, [String]) -> Void)?
    var onTrimSegment: ((String, TimeRange, TimeRange, Bool) -> Void)?
    var onAutoScroll: ((CGFloat) -> Void)?

    @State private var dragState: TimelineSegmentDragState?
    @State private var trimState: TimelineSegmentTrimState?
    @State private var previewOrder: [String]?

    init(
        model: TimelineTrackModel,
        pixelsPerSecond: CGFloat,
        minimumContentWidth: CGFloat? = nil,
        viewportWidth: CGFloat = 0,
        scrollOffset: CGFloat = 0,
        selectedSegmentId: Binding<String?> = .constant(nil),
        reviewFocusedSegmentIds: Set<String> = [],
        isReviewInteractionDisabled: Bool = false,
        promptFocusSegmentIds: Set<String> = [],
        promptActionPreview: TimelinePromptActionPreview? = nil,
        isUserScrolling: Bool = false,
        onSelectSegment: ((String) -> Void)? = nil,
        onMoveSegment: ((String, Int64, [String]) -> Void)? = nil,
        onTrimSegment: ((String, TimeRange, TimeRange, Bool) -> Void)? = nil,
        onAutoScroll: ((CGFloat) -> Void)? = nil
    ) {
        self.model = model
        self.pixelsPerSecond = pixelsPerSecond
        self.minimumContentWidth = minimumContentWidth
        self.viewportWidth = viewportWidth
        self.scrollOffset = scrollOffset
        self._selectedSegmentId = selectedSegmentId
        self.reviewFocusedSegmentIds = reviewFocusedSegmentIds
        self.isReviewInteractionDisabled = isReviewInteractionDisabled
        self.promptFocusSegmentIds = promptFocusSegmentIds
        self.promptActionPreview = promptActionPreview
        self.isUserScrolling = isUserScrolling
        self.onSelectSegment = onSelectSegment
        self.onMoveSegment = onMoveSegment
        self.onTrimSegment = onTrimSegment
        self.onAutoScroll = onAutoScroll
    }

    private var layout: TimelineComponentLayout {
        TimelineComponentLayout.preset(model.size)
    }

    private var trackHeight: CGFloat {
        layout.trackHeight(for: model.kind)
    }

    private var contentWidth: CGFloat {
        let maxEnd = model.segments.map(\.rangeUs.end).max() ?? 0
        return max(minimumContentWidth ?? 1, CGFloat(maxEnd) / 1_000_000 * pixelsPerSecond)
    }

    private var orderedSegments: [TimelineSegmentModel] {
        model.segments.sorted { $0.rangeUs.start < $1.rangeUs.start }
    }

    var body: some View {
        let baseSegments = orderedSegments
        let baseOrderIds = baseSegments.map(\.id)
        let orderIds = previewOrder ?? baseOrderIds
        let segmentById = Dictionary(uniqueKeysWithValues: model.segments.map { ($0.id, $0) })
        let previewSegments = orderIds.compactMap { segmentById[$0] }
        let packedStartsById = packedStarts(for: previewSegments)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .fill(Color.ds.surface.opacity(0.28))
                .frame(width: max(contentWidth, 1), height: trackHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing(.sp1))
                        .stroke(Color.ds.border.opacity(0.55), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSegmentId = nil
                }

            ForEach(baseSegments) { segment in
                let isActiveDrag = dragState?.segmentId == segment.id
                let displayStartUs = displayStartTimeUs(
                    for: segment,
                    isActiveDrag: isActiveDrag,
                    packedStartsById: packedStartsById
                )
                let width = segmentWidth(segment)
                let dragOffsetX = dragOffset(for: segment)

                segmentView(segment)
                    .frame(width: width, height: trackHeight)
                    .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
                    .overlay {
                        promptPreviewOverlay(for: segment, segmentWidth: width)
                    }
                    .overlay(alignment: .leading) {
                        if isSelectedClipSegment(segment) {
                            TimelineSegmentTrimHandleView()
                                .highPriorityGesture(trimGesture(for: segment, edge: .leading))
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if isSelectedClipSegment(segment) {
                            TimelineSegmentTrimHandleView()
                                .highPriorityGesture(trimGesture(for: segment, edge: .trailing))
                        }
                    }
                    .offset(x: timeToPixels(displayStartUs) + dragOffsetX)
                    .animation(
                        isActiveDrag ? nil : .spring(response: 0.3, dampingFraction: 0.85),
                        value: orderIds
                    )
                    .zIndex(isActiveDrag || trimState?.segmentId == segment.id ? 2 : 0)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            guard !isUserScrolling, !isReviewInteractionDisabled else { return }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedSegmentId = segment.id
                                onSelectSegment?(segment.id)
                            }
                        }
                    )
                    .gesture(
                        dragGesture(
                            for: segment,
                            currentOrder: previewSegments,
                            baseOrderIds: baseOrderIds
                        ),
                        including: canMoveSegment(segment) ? .all : .none
                    )
            }
        }
        .frame(width: contentWidth, height: trackHeight, alignment: .leading)
        .clipped()
        .onChange(of: dragState?.segmentId) { _, newValue in
            if newValue == nil {
                onAutoScroll?(0)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: TimelineSegmentModel) -> some View {
        let isSelected = selectedSegmentId == segment.id
        let isReviewDimmed = !reviewFocusedSegmentIds.isEmpty && !reviewFocusedSegmentIds.contains(segment.id)
        let isPromptFocused = promptFocusSegmentIds.contains(segment.id)
        switch model.kind {
        case .video:
            TimelineVideoSegmentView(
                segment: segment,
                isSelected: isSelected,
                isReviewDimmed: isReviewDimmed,
                isPromptFocused: isPromptFocused
            )
        case .audio:
            TimelineAudioSegmentView(
                segment: segment,
                isSelected: isSelected,
                isReviewDimmed: isReviewDimmed,
                isPromptFocused: isPromptFocused
            )
        case .caption:
            TimelineCaptionSegmentView(
                segment: segment,
                isSelected: isSelected,
                isReviewDimmed: isReviewDimmed,
                isPromptFocused: isPromptFocused
            )
        }
    }

    private func segmentX(_ segment: TimelineSegmentModel) -> CGFloat {
        CGFloat(segment.rangeUs.start) / 1_000_000 * pixelsPerSecond
    }

    private func segmentWidth(_ segment: TimelineSegmentModel) -> CGFloat {
        max(layout.minimumSegmentWidth, CGFloat(segment.durationUs) / 1_000_000 * pixelsPerSecond)
    }

    private func displayStartTimeUs(
        for segment: TimelineSegmentModel,
        isActiveDrag: Bool,
        packedStartsById: [String: Int64]
    ) -> Int64 {
        if isActiveDrag, let dragState {
            return dragState.startTimeUs
        }
        if previewOrder != nil, let packedStart = packedStartsById[segment.id] {
            return packedStart
        }
        return segment.rangeUs.start
    }

    private func dragOffset(for segment: TimelineSegmentModel) -> CGFloat {
        guard let dragState, dragState.segmentId == segment.id else { return 0 }
        return dragState.translation.width + (scrollOffset - dragState.startScrollOffset)
    }

    private func isSelectedClipSegment(_ segment: TimelineSegmentModel) -> Bool {
        model.kind != .caption && selectedSegmentId == segment.id && onTrimSegment != nil
    }

    private func canMoveSegment(_ segment: TimelineSegmentModel) -> Bool {
        model.kind != .caption
            && selectedSegmentId == segment.id
            && !isUserScrolling
            && !isReviewInteractionDisabled
            && onMoveSegment != nil
    }

    private func dragGesture(
        for segment: TimelineSegmentModel,
        currentOrder: [TimelineSegmentModel],
        baseOrderIds: [String]
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragState?.segmentId != segment.id {
                    dragState = TimelineSegmentDragState(
                        segmentId: segment.id,
                        startTimeUs: segment.rangeUs.start,
                        translation: value.translation,
                        startScrollOffset: scrollOffset
                    )
                } else {
                    dragState?.translation = value.translation
                }

                updatePreviewOrder(
                    segmentId: segment.id,
                    translationWidth: value.translation.width,
                    startScrollOffset: dragState?.startScrollOffset ?? scrollOffset,
                    currentScrollOffset: scrollOffset,
                    currentOrder: currentOrder,
                    baseOrderIds: baseOrderIds
                )
                onAutoScroll?(autoScrollDirection(for: value.location.x))
            }
            .onEnded { _ in
                guard let dragState, dragState.segmentId == segment.id else { return }
                let finalOrderIds = previewOrder ?? baseOrderIds
                let segmentById = Dictionary(uniqueKeysWithValues: model.segments.map { ($0.id, $0) })
                let finalSegments = finalOrderIds.compactMap { segmentById[$0] }
                let finalStarts = packedStarts(for: finalSegments)
                let resolvedStart = finalStarts[segment.id] ?? segment.rangeUs.start

                onMoveSegment?(segment.id, resolvedStart, finalOrderIds)
                self.dragState = nil
                previewOrder = nil
                onAutoScroll?(0)
            }
    }

    private func trimGesture(for segment: TimelineSegmentModel, edge: TimelineSegmentTrimEdge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if selectedSegmentId != segment.id {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedSegmentId = segment.id
                    }
                }
                if trimState?.segmentId != segment.id || trimState?.edge != edge {
                    trimState = TimelineSegmentTrimState(
                        segmentId: segment.id,
                        edge: edge,
                        startTimelineRange: segment.rangeUs,
                        startSourceRange: resolvedSourceRange(for: segment),
                        translation: value.translation,
                        startScrollOffset: scrollOffset
                    )
                    dragState = nil
                } else {
                    trimState?.translation = value.translation
                }

                guard let trimState else { return }
                let adjustedTranslation = trimState.translation.width + (scrollOffset - trimState.startScrollOffset)
                let resolved = resolvedTrimRanges(
                    for: segment,
                    edge: edge,
                    startTimelineRange: trimState.startTimelineRange,
                    startSourceRange: trimState.startSourceRange,
                    translationWidth: adjustedTranslation
                )
                onTrimSegment?(segment.id, resolved.sourceRange, resolved.timelineRange, false)
                onAutoScroll?(autoScrollDirection(for: value.location.x))
            }
            .onEnded { value in
                guard let trimState, trimState.segmentId == segment.id, trimState.edge == edge else { return }
                let adjustedTranslation = value.translation.width + (scrollOffset - trimState.startScrollOffset)
                let resolved = resolvedTrimRanges(
                    for: segment,
                    edge: edge,
                    startTimelineRange: trimState.startTimelineRange,
                    startSourceRange: trimState.startSourceRange,
                    translationWidth: adjustedTranslation
                )
                onTrimSegment?(segment.id, resolved.sourceRange, resolved.timelineRange, true)
                self.trimState = nil
                onAutoScroll?(0)
            }
    }

    private func updatePreviewOrder(
        segmentId: String,
        translationWidth: CGFloat,
        startScrollOffset: CGFloat,
        currentScrollOffset: CGFloat,
        currentOrder: [TimelineSegmentModel],
        baseOrderIds: [String]
    ) {
        guard let dragState, dragState.segmentId == segmentId, pixelsPerSecond > 0 else { return }
        guard let currentIndex = currentOrder.firstIndex(where: { $0.id == segmentId }) else { return }

        let adjustedTranslation = translationWidth + (currentScrollOffset - startScrollOffset)
        guard adjustedTranslation != 0 else { return }

        let durationPx = timeToPixels(currentOrder[currentIndex].durationUs)
        let proposedStartPx = timeToPixels(dragState.startTimeUs) + adjustedTranslation
        var updatedOrder = currentOrder
        var targetIndex = currentIndex
        let swapThresholdPx: CGFloat = 75

        if adjustedTranslation > 0 {
            while targetIndex + 1 < updatedOrder.count {
                let packed = packedStarts(for: updatedOrder)
                let next = updatedOrder[targetIndex + 1]
                let nextStartPx = timeToPixels(packed[next.id] ?? next.rangeUs.start)
                let overlapPx = (proposedStartPx + durationPx) - nextStartPx
                guard overlapPx >= swapThresholdPx else { break }
                updatedOrder.swapAt(targetIndex, targetIndex + 1)
                targetIndex += 1
            }
        } else {
            while targetIndex > 0 {
                let packed = packedStarts(for: updatedOrder)
                let previous = updatedOrder[targetIndex - 1]
                let previousStartPx = timeToPixels(packed[previous.id] ?? previous.rangeUs.start)
                let previousEndPx = previousStartPx + timeToPixels(previous.durationUs)
                let overlapPx = previousEndPx - proposedStartPx
                guard overlapPx >= swapThresholdPx else { break }
                updatedOrder.swapAt(targetIndex, targetIndex - 1)
                targetIndex -= 1
            }
        }

        let updatedIds = updatedOrder.map(\.id)
        if updatedIds == baseOrderIds {
            guard previewOrder != nil else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                previewOrder = nil
            }
            return
        }

        if updatedIds != previewOrder {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                previewOrder = updatedIds
            }
        }
    }

    private func packedStarts(for orderedSegments: [TimelineSegmentModel]) -> [String: Int64] {
        var cursor: Int64 = 0
        var starts: [String: Int64] = [:]
        for segment in orderedSegments {
            starts[segment.id] = cursor
            cursor += segment.durationUs
        }
        return starts
    }

    private func resolvedSourceRange(for segment: TimelineSegmentModel) -> TimeRange {
        segment.sourceRangeUs ?? TimeRange(start: 0, end: segment.durationUs)
    }

    private func resolvedTrimRanges(
        for segment: TimelineSegmentModel,
        edge: TimelineSegmentTrimEdge,
        startTimelineRange: TimeRange,
        startSourceRange: TimeRange,
        translationWidth: CGFloat
    ) -> (sourceRange: TimeRange, timelineRange: TimeRange) {
        guard pixelsPerSecond > 0 else { return (startSourceRange, startTimelineRange) }
        let isPhoto = segment.mediaKind == .photo
        let minDurationUs = min(startTimelineRange.duration, 200_000)
        let deltaUs = Int64((translationWidth / pixelsPerSecond) * 1_000_000)
        let mediaDurationUs: Int64? = {
            guard !isPhoto, let seconds = segment.mediaDurationSeconds, seconds > 0 else { return nil }
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
            }

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

        case .trailing:
            let minEnd = startTimelineRange.start + minDurationUs
            let maxEnd = mediaDurationUs.map { startTimelineRange.end + ($0 - startSourceRange.end) } ?? Int64.max
            let proposedEnd = startTimelineRange.end + deltaUs
            let clampedEnd = clamp(proposedEnd, minEnd, maxEnd)
            let newTimelineRange = TimeRange(start: startTimelineRange.start, end: clampedEnd)

            if isPhoto {
                return (TimeRange(start: 0, end: max(0, newTimelineRange.duration)), newTimelineRange)
            }

            let sourceDelta = clampedEnd - startTimelineRange.end
            return (TimeRange(start: startSourceRange.start, end: startSourceRange.end + sourceDelta), newTimelineRange)
        }
    }

    private func autoScrollDirection(for locationX: CGFloat) -> CGFloat {
        guard viewportWidth > 0 else { return 0 }
        let edgeThreshold = min(.spacing(.sp10), max(0, viewportWidth / 2 - .spacing(.sp3)))
        if locationX < edgeThreshold { return -1 }
        if locationX > viewportWidth - edgeThreshold { return 1 }
        return 0
    }

    private func timeToPixels(_ timeUs: Int64) -> CGFloat {
        CGFloat(timeUs) / 1_000_000 * pixelsPerSecond
    }

    private func clamp(_ value: Int64, _ minValue: Int64, _ maxValue: Int64) -> Int64 {
        guard maxValue >= minValue else { return minValue }
        return min(maxValue, max(minValue, value))
    }

    @ViewBuilder
    private func promptPreviewOverlay(for segment: TimelineSegmentModel, segmentWidth: CGFloat) -> some View {
        if let preview = promptActionPreview,
           preview.focusClipIds.contains(segment.id) {
            ZStack(alignment: .leading) {
                let ranges = preview.overlayRanges.filter { $0.clipId == segment.id && $0.trackId == model.id }
                ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                    let x = timeToPixels(range.timelineRange.start - segment.rangeUs.start)
                    let width = timeToPixels(range.timelineRange.duration)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.black.opacity(0.52))
                        .frame(width: max(0, width), height: trackHeight)
                        .offset(x: x)
                }

                if preview.kind == .split,
                   let splitUs = preview.splitMarkerTimeUs,
                   splitUs > segment.rangeUs.start,
                   splitUs < segment.rangeUs.end {
                    let x = timeToPixels(splitUs - segment.rangeUs.start)
                    Rectangle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 2, height: trackHeight)
                        .offset(x: x - 1)
                }
            }
            .frame(width: segmentWidth, height: trackHeight, alignment: .leading)
            .allowsHitTesting(false)
        }
    }
}

private struct TimelineSegmentDragState {
    let segmentId: String
    let startTimeUs: Int64
    var translation: CGSize
    let startScrollOffset: CGFloat
}

private struct TimelineSegmentTrimState {
    let segmentId: String
    let edge: TimelineSegmentTrimEdge
    let startTimelineRange: TimeRange
    let startSourceRange: TimeRange
    var translation: CGSize
    let startScrollOffset: CGFloat
}

private enum TimelineSegmentTrimEdge {
    case leading
    case trailing
}

private struct TimelineSegmentTrimHandleView: View {
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

private struct TimelineVideoSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool
    let isReviewDimmed: Bool
    let isPromptFocused: Bool

    @State private var thumbnailStrip: UIImage?
    @State private var waveformImage: UIImage?

    var body: some View {
        let clipRange = clipSourceUnits

        ZStack(alignment: .bottom) {
            if let thumbnailStrip, let clipRange {
                TimelineSegmentStripImageView(stripImage: thumbnailStrip, startUnit: clipRange.start, endUnit: clipRange.end)
            } else if let thumbnailStrip {
                Image(uiImage: thumbnailStrip)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color.ds.surface.opacity(0.95), Color.ds.bg.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: segment.mediaKind == .photo ? "photo.fill" : "video.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ds.accentFg)
                    .padding(.spacing(.sp2))
            }

            if let waveformImage, let clipRange {
                TimelineSegmentWaveformImageView(waveformImage: waveformImage, startUnit: clipRange.start, endUnit: clipRange.end)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .background(Color.black.opacity(0.4))
                    .frame(height: .spacing(.sp3) + 4)
            }
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: segment.mediaKind == .photo ? "photo.fill" : "video.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: .spacing(.sp1)).fill(Color.black.opacity(0.6)))
                .padding(.top, .spacing(.sp1))
                .padding(.leading, .spacing(.sp1))
        }
        .overlay(alignment: .topLeading) {
            if let title = segment.title, !title.isEmpty {
                Text(title)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(1)
                    .padding(.horizontal, .spacing(.sp2))
                    .padding(.vertical, .spacing(.sp1))
                    .background(Color.ds.bg.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
                    .padding(.spacing(.sp1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
        .overlay(baseStroke)
        .overlay(promptFocusStroke)
        .overlay(selectionStroke)
        .opacity(isReviewDimmed ? 0.32 : 1)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isReviewDimmed)
        .task(id: imageTaskId) {
            thumbnailStrip = loadImage(storedPath: segment.thumbnailStripPath)
            waveformImage = loadImage(storedPath: segment.waveformPath)
        }
    }

    private var baseStroke: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .stroke(Color.ds.border, lineWidth: 1)
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .stroke(Color.ds.accentFg, lineWidth: 2)
            .opacity(isSelected ? 1 : 0)
    }

    private var promptFocusStroke: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .stroke(Color.ds.accentFg.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .opacity(isPromptFocused ? 1 : 0)
    }

    private var imageTaskId: String {
        [
            segment.thumbnailStripPath ?? "nostrip",
            segment.waveformPath ?? "nowaveform",
            segment.sourceRangeUs.map { "\($0.start)-\($0.end)" } ?? "nosource"
        ].joined(separator: "::")
    }

    private var clipSourceUnits: (start: CGFloat, end: CGFloat)? {
        guard
            let duration = segment.mediaDurationSeconds,
            duration > 0,
            let sourceRangeUs = segment.sourceRangeUs
        else {
            return nil
        }

        let startSeconds = Double(sourceRangeUs.start) / 1_000_000.0
        let endSeconds = Double(sourceRangeUs.end) / 1_000_000.0
        let startUnit = max(0, min(1, startSeconds / duration))
        let endUnit = max(startUnit, min(1, endSeconds / duration))
        return (start: CGFloat(startUnit), end: CGFloat(endUnit))
    }
}

private struct TimelineSegmentStripImageView: View {
    let stripImage: UIImage
    let startUnit: CGFloat
    let endUnit: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let clampedStart = max(0, min(1, startUnit))
            let clampedEnd = max(clampedStart + 0.0001, min(1, endUnit))
            let range = clampedEnd - clampedStart
            let scaledWidth = geometry.size.width / range

            Image(uiImage: stripImage)
                .resizable()
                .scaledToFill()
                .frame(width: scaledWidth, height: geometry.size.height)
                .offset(x: -clampedStart * scaledWidth)
                .clipped()
        }
    }
}

private struct TimelineSegmentWaveformImageView: View {
    let waveformImage: UIImage
    let startUnit: CGFloat
    let endUnit: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let clampedStart = max(0, min(1, startUnit))
            let clampedEnd = max(clampedStart + 0.0001, min(1, endUnit))
            let range = clampedEnd - clampedStart
            let scaledWidth = geometry.size.width / range

            Image(uiImage: waveformImage)
                .resizable()
                .scaledToFill()
                .frame(width: scaledWidth, height: geometry.size.height)
                .offset(x: -clampedStart * scaledWidth)
                .clipped()
                .opacity(0.85)
        }
    }
}

private struct TimelineAudioSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool
    let isReviewDimmed: Bool
    let isPromptFocused: Bool

    @State private var waveformImage: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .fill(Color.ds.surface.opacity(0.72))

            if let waveformImage {
                Image(uiImage: waveformImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.8)
                    .clipped()
            } else {
                TimelineWaveformPlaceholder(seed: segment.id)
                    .padding(.horizontal, .spacing(.sp2))
                    .padding(.vertical, .spacing(.sp1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp1)))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .stroke(Color.ds.accentFg.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .opacity(isPromptFocused ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp1))
                .stroke(Color.ds.accentFg, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .opacity(isReviewDimmed ? 0.32 : 1)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isReviewDimmed)
        .task(id: segment.waveformPath) {
            waveformImage = loadImage(storedPath: segment.waveformPath)
        }
    }
}

private struct TimelineCaptionSegmentView: View {
    let segment: TimelineSegmentModel
    let isSelected: Bool
    let isReviewDimmed: Bool
    let isPromptFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .fill(Color.ds.surface.opacity(0.95))
            .overlay(
                Text(segment.captionText ?? segment.title ?? "")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.border, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.accentFg.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .opacity(isPromptFocused ? 1 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .stroke(Color.ds.accentFg, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
            .opacity(isReviewDimmed ? 0.32 : 1)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .animation(.easeInOut(duration: 0.18), value: isReviewDimmed)
    }
}

private struct TimelineWaveformPlaceholder: View {
    let seed: String

    private let barCount = 22

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = max(1, geometry.size.height)

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.ds.accentFg.opacity(0.72))
                        .frame(width: 2, height: barHeight(at: index, availableHeight: availableHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barHeight(at index: Int, availableHeight: CGFloat) -> CGFloat {
        let scalar = abs(sin(Double(index + seed.count) * 0.73))
        return max(2, availableHeight * (0.25 + CGFloat(scalar) * 0.75))
    }
}

private func loadImage(storedPath: String?) -> UIImage? {
    guard
        let storedPath,
        let url = AppSandboxFileURI.resolveFileURL(storedURI: storedPath)
    else {
        return nil
    }
    return UIImage(contentsOfFile: url.path)
}
