import SwiftUI
import UniformTypeIdentifiers

struct TimelineSectionView: View {
    fileprivate static let importedSegmentType = UTType(exportedAs: "com.iris.editor.imported-timeline-segment")

    let tracks: [Track]
    let clipsByTrackId: [String: [Clip]]
    let mediaById: [String: Media]
    let layout: TimelineLayout
    let pixelsPerSecond: CGFloat
    let timelineDurationUs: Int64
    let scrollableDurationUs: Int64
    @Binding var currentTimeAtCenter: Int64
    @Binding var scrollTargetTimeUs: Int64?
    @Binding var selectedClipId: String?
    var playbackState: TimelinePlaybackState = .idle
    let onAddSelection: (TrackKind, ImportSource) -> Void
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    var onDropImportedSegmentAtTime: ((ImportedTimelineSegment, Int64) -> Void)? = nil
    var showAddButton: Bool = true
    var rulerVerticalOffset: CGFloat = 0
    var reviewFocusedClipIds: Set<String> = []
    var isReviewInteractionDisabled = false
    var promptActionPreview: TimelinePromptActionPreview? = nil

    @State private var sharedScrollOffset: CGFloat = 0
    @State private var lastScrollOffsetX: CGFloat = 0
    @State private var lastScrollTime: Date = Date()
    @State private var isScrollingFast: Bool = false
    @State private var scrollIdleWorkItem: DispatchWorkItem?
    @State private var scrollActivityWorkItem: DispatchWorkItem?
    @State private var isUserScrolling: Bool = false
    @State private var isAutoScrolling: Bool = false
    @State private var isAddMenuOpen: Bool = false
    @State private var lastScrollUpdate: Date = Date()
    @State private var autoScrollDirection: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var lastScrollableDurationUs: Int64 = 0
    @State private var isJumpingToTarget: Bool = false
    @State private var jumpResetWorkItem: DispatchWorkItem?
    @State private var isImportedSegmentTargeted = false
    @State private var importedSegmentDropTimeUs: Int64?
    @State private var lastImportedSegmentDebugSummary: String?
    private let addButtonSize: CGFloat = .spacing(.sp8)

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let stackHeight = layout.trackStackHeight(for: tracks)
            let timelineWidth = CGFloat(max(0, scrollableDurationUs)) / 1_000_000 * pixelsPerSecond
            let addButtonTopOffset = addButtonTopOffset(for: tracks)

            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 0) {
                                TimelineRuler(
                                    pixelsPerSecond: pixelsPerSecond,
                                    durationUs: scrollableDurationUs,
                                    currentTime: $currentTimeAtCenter
                                )
                                .frame(height: layout.rulerHeight)
                                .frame(minWidth: timelineWidth, alignment: .leading)
                                .offset(y: rulerVerticalOffset)

                                TimelineTracksContent(
                                    tracks: tracks, clipsByTrackId: clipsByTrackId,
                                    mediaById: mediaById, layout: layout, pixelsPerSecond: pixelsPerSecond,
                                    onMoveClip: onMoveClip, onTrimClip: onTrimClip,
                                    viewportWidth: geometry.size.width, contentWidth: timelineWidth,
                                    scrollOffset: $sharedScrollOffset, selectedClipId: $selectedClipId,
                                    onAutoScroll: updateAutoScroll(direction:),
                                    isUserScrolling: isUserScrolling,
                                    reviewFocusedClipIds: reviewFocusedClipIds,
                                    isReviewInteractionDisabled: isReviewInteractionDisabled,
                                    promptActionPreview: promptActionPreview
                                )
                                .padding(.top, layout.trackTopOffset)
                                .transaction { transaction in
                                    transaction.animation = nil
                                }
                            }
                            .padding(.leading, centerX)
                            .padding(.trailing, centerX)

                            ScrollTargetMarkerView(
                                targetTimeUs: activeScrollTargetTimeUs,
                                pixelsPerSecond: pixelsPerSecond,
                                centerX: centerX
                            )
                        }
                        .frame(minWidth: geometry.size.width)
                    }
                    .coordinateSpace(name: "timelineScroll")
                    .onScrollGeometryChange(for: CGFloat.self) { geo in
                        geo.contentOffset.x
                    } action: { _, x in
                        sharedScrollOffset = x
                        if isJumpingToTarget {
                            lastScrollOffsetX = x
                            lastScrollTime = Date()
                            return
                        }
                        let now = Date()
                        if !isProgrammaticScrolling, scrollTargetTimeUs != nil {
                            scrollTargetTimeUs = nil
                        }
                        let minInterval: TimeInterval = 1.0 / 120
                        if now.timeIntervalSince(lastScrollUpdate) >= minInterval {
                            let timeUs = Int64((x / pixelsPerSecond) * 1_000_000)
                            currentTimeAtCenter = max(0, timeUs)
                            lastScrollUpdate = now
                        }

                        let deltaX = x - lastScrollOffsetX
                        let deltaT = now.timeIntervalSince(lastScrollTime)
                        if deltaT > 0 {
                            if !isProgrammaticScrolling { markUserScrolling() }
                            let velocity = abs(deltaX) / deltaT
                            if velocity > 450 && !isScrollingFast {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isScrollingFast = true }
                            }
                            scheduleShowAddButton()
                            lastScrollOffsetX = x
                            lastScrollTime = now
                        }
                    }
                    .onChange(of: scrollTargetTimeUs) { _, targetTimeUs in
                        guard targetTimeUs != nil else { return }
                        isJumpingToTarget = true
                        isAutoScrolling = true
                        isUserScrolling = false
                        scrollActivityWorkItem?.cancel()
                        jumpResetWorkItem?.cancel()
                        let workItem = DispatchWorkItem {
                            isJumpingToTarget = false
                            isAutoScrolling = false
                        }
                        jumpResetWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                proxy.scrollTo(ScrollTargetMarkerView.markerId, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: currentTimeAtCenter) { _, _ in
                        guard playbackState == .playing else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(ScrollTargetMarkerView.markerId, anchor: .center)
                        }
                    }
                    .onChange(of: playbackState) { _, newState in
                        guard newState == .playing else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(ScrollTargetMarkerView.markerId, anchor: .center)
                        }
                    }
                }

                // Track kind icons
                ZStack(alignment: .topLeading) {
                    ForEach(Array(tracks.enumerated()), id: \.element.trackId) { index, track in
                        let trackHeight = layout.trackHeight(for: track.kind)
                        iconView(for: track.kind, trackHeight: trackHeight)
                            .position(
                                x: trackIconX(for: geometry.size.width),
                                y: iconYPosition(for: index, in: tracks)
                            )
                    }
                }
                .padding(.top, layout.rulerHeight + layout.trackTopOffset)
                .frame(height: stackHeight + layout.rulerHeight + layout.trackTopOffset, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .transaction { transaction in
                    transaction.animation = nil
                }

                // Time display
                HStack(alignment: .top, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 0) {
                        Text(TimeFormatter.formatTime(currentTimeAtCenter))
                            .typography(.body)
                            .foregroundColor(Color.ds.text)
                            .frame(width: 41)
                        Text(TimeFormatter.calcCentiSeconds(currentTimeAtCenter))
                            .typography(.bodySmall)
                            .foregroundColor(Color.ds.text)
                            .padding(.bottom, 0.5)
                            .frame(width: 15)
                        Text(" / ")
                            .typography(.bodySmall)
                            .foregroundColor(Color.ds.textMuted)
                        Text(TimeFormatter.formatTime(timelineDurationUs))
                            .typography(.body)
                            .foregroundColor(Color.ds.textMuted)
                            .frame(width: 41)
                    }
                    .padding(.leading, .sp3)
                    .padding(.top, 4)
                    .background(Color.ds.bg)

                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.ds.bg, location: 0.0),
                            .init(color: Color.ds.bg.opacity(0), location: 1.0)
                        ]),
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: .spacing(.sp5), height: 64)
                }
                .offset(y: rulerVerticalOffset)

                PlayheadView()
                    .padding(.top, 27)
                    .offset(y: rulerVerticalOffset)

                HStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.ds.bg.opacity(0), location: 0.0),
                            .init(color: Color.ds.bg, location: 1.0)
                        ]),
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: .spacing(.sp4), height: layout.rulerHeight)
                }
                .offset(y: rulerVerticalOffset)

                if isAddMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { isAddMenuOpen = false }
                        }
                        .ignoresSafeArea()
                }

                if showAddButton {
                    AddClipButton(onSelect: onAddSelection, isMenuOpen: $isAddMenuOpen)
                        .padding(.top, addButtonTopOffset)
                        .padding(.trailing, .spacing(.sp6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: isScrollingFast ? .spacing(.sp8) : 0)
                        .opacity(isScrollingFast ? 0 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrollingFast)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(
                        isImportedSegmentTargeted ? Color.ds.accentFg : Color.clear,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .padding(.horizontal, .sp3)
                    .animation(.easeOut(duration: 0.18), value: isImportedSegmentTargeted)
            }
            .overlay(alignment: .topLeading) {
                if let insertionGapPreview {
                    ImportedSegmentInsertionIndicator(color: Color.ds.accentFg, height: stackHeight + layout.trackTopOffset)
                        .offset(
                            x: insertionIndicatorX(
                                for: insertionGapPreview.startUs,
                                viewportWidth: geometry.size.width
                            ) - 7,
                            y: rulerVerticalOffset + layout.rulerHeight
                        )
                        .allowsHitTesting(false)
                }
            }
            .onDrop(
                of: [Self.importedSegmentType],
                delegate: ImportedSegmentDropDelegate(
                    isEnabled: onDropImportedSegmentAtTime != nil,
                    isTargeted: $isImportedSegmentTargeted,
                    dropTimeUs: $importedSegmentDropTimeUs,
                    onDropImportedSegmentAtTime: onDropImportedSegmentAtTime,
                    resolveDropTimeUs: { dropX in
                        resolvedDropTimeUs(dropX: dropX, viewportWidth: geometry.size.width)
                    }
                )
            )
        }
        .onChange(of: isImportedSegmentTargeted) { _, isTargeted in
            if !isTargeted {
                importedSegmentDropTimeUs = nil
                lastImportedSegmentDebugSummary = nil
            }
            EditorDebugTrace.log(
                "TimelineSectionView",
                "semantic drag target active=\(isTargeted)"
            )
            logImportedSegmentDragStateIfNeeded()
        }
        .onChange(of: importedSegmentDropTimeUs) { _, _ in
            logImportedSegmentDragStateIfNeeded()
        }
        .onDisappear {
            scrollActivityWorkItem?.cancel()
            jumpResetWorkItem?.cancel()
            autoScrollTask?.cancel()
            importedSegmentDropTimeUs = nil
            isImportedSegmentTargeted = false
            lastImportedSegmentDebugSummary = nil
        }
        .onAppear { lastScrollableDurationUs = scrollableDurationUs }
        .onChange(of: scrollableDurationUs) { _, newValue in
            defer { lastScrollableDurationUs = newValue }
            guard newValue < lastScrollableDurationUs else { return }
            let maxTime = max(0, newValue)
            let currentOffsetUs = Int64((sharedScrollOffset / pixelsPerSecond) * 1_000_000)
            if currentOffsetUs > maxTime || currentTimeAtCenter > maxTime {
                requestScrollTo(timeUs: maxTime)
            }
        }
    }

    private func iconName(for kind: TrackKind) -> String {
        switch kind {
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .overlay: return "textformat"
        }
    }

    private func iconView(for kind: TrackKind, trackHeight: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: .spacing(.sp1))
            .fill(Color.ds.bg.opacity(0.75))
            .frame(width: layout.iconSize, height: trackHeight)
            .overlay(RoundedRectangle(cornerRadius: .spacing(.sp1)).stroke(Color.ds.textMuted.opacity(0.75), lineWidth: 1))
            .overlay(
                Image(systemName: iconName(for: kind))
                    .font(.system(size: min(14, trackHeight * 0.7), weight: .semibold))
                    .foregroundColor(Color.ds.textMuted.opacity(0.75))
            )
    }

    private func trackIconX(for width: CGFloat) -> CGFloat {
        let centerX = width / 2
        let desiredCenter = centerX - .spacing(.sp3) - layout.iconSize / 2 - sharedScrollOffset
        let minCenter: CGFloat = .spacing(.sp3) + layout.iconSize / 2
        let maxCenter = centerX - .spacing(.sp3) - layout.iconSize / 2
        return min(maxCenter, max(minCenter, desiredCenter))
    }

    private func iconYPosition(for index: Int, in tracks: [Track]) -> CGFloat {
        let priorHeights = tracks.prefix(index).map { layout.trackHeight(for: $0.kind) }.reduce(0, +)
        let spacingTotal = CGFloat(index) * layout.trackSpacing
        let trackHeight = layout.trackHeight(for: tracks[index].kind)
        return priorHeights + spacingTotal + trackHeight / 2
    }

    private func scheduleShowAddButton() {
        scrollIdleWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isScrollingFast = false }
        }
        scrollIdleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func markUserScrolling() {
        isUserScrolling = true
        scrollActivityWorkItem?.cancel()
        let workItem = DispatchWorkItem { isUserScrolling = false }
        scrollActivityWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func updateAutoScroll(direction: CGFloat) {
        guard direction != 0 else {
            autoScrollDirection = 0
            autoScrollTask?.cancel()
            autoScrollTask = nil
            isAutoScrolling = false
            return
        }
        if autoScrollDirection == direction, autoScrollTask != nil { return }
        autoScrollDirection = direction
        isAutoScrolling = true
        autoScrollTask?.cancel()
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                let stepUs = Int64(0.2 * 1_000_000)
                let targetTimeUs = currentTimeAtCenter + Int64(direction) * stepUs
                requestScrollTo(timeUs: clampScrollTime(targetTimeUs))
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    @MainActor
    private func requestScrollTo(timeUs: Int64) {
        scrollTargetTimeUs = nil
        DispatchQueue.main.async { scrollTargetTimeUs = clampScrollTime(timeUs) }
    }

    private func clampScrollTime(_ timeUs: Int64) -> Int64 {
        min(max(0, scrollableDurationUs), max(0, timeUs))
    }

    private var activeScrollTargetTimeUs: Int64? {
        if let scrollTargetTimeUs {
            return clampScrollTime(scrollTargetTimeUs)
        }
        return clampScrollTime(currentTimeAtCenter)
    }

    private var isProgrammaticScrolling: Bool {
        isAutoScrolling || isJumpingToTarget || playbackState == .playing
    }

    private func addButtonTopOffset(for tracks: [Track]) -> CGFloat {
        let preferredTrackIndex = tracks.firstIndex(where: { $0.kind == .video }) ?? 0
        let trackCenterY: CGFloat

        if tracks.indices.contains(preferredTrackIndex) {
            trackCenterY = iconYPosition(for: preferredTrackIndex, in: tracks)
        } else {
            trackCenterY = layout.videoTrackHeight / 2
        }

        return max(
            0,
            rulerVerticalOffset + layout.rulerHeight + layout.trackTopOffset + trackCenterY - addButtonSize / 2
        )
    }

    private func resolvedDropTimeUs(dropX: CGFloat, viewportWidth: CGFloat) -> Int64 {
        let centerX = viewportWidth / 2
        let contentX = max(0, dropX + sharedScrollOffset - centerX)
        let timeUs = Int64((contentX / pixelsPerSecond) * 1_000_000)
        return clampScrollTime(timeUs)
    }

    private var importedSegmentTrackClips: [Clip] {
        guard let videoTrack = tracks.first(where: { $0.kind == .video }) else {
            return []
        }

        return (clipsByTrackId[videoTrack.trackId] ?? [])
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
    }

    private func insertionIndicatorX(for timeUs: Int64, viewportWidth: CGFloat) -> CGFloat {
        let centerX = viewportWidth / 2
        let contentX = CGFloat(timeUs) / 1_000_000 * pixelsPerSecond
        return centerX + contentX - sharedScrollOffset
    }

    private var insertionGapPreview: ImportedSegmentGapPreview? {
        guard
            isImportedSegmentTargeted,
            let snapshot = importedSegmentDebugSnapshot,
            snapshot.shouldInsertBeforeClip,
            let nearestClipStartUs = snapshot.nearestClipStartUs
        else {
            return nil
        }

        return ImportedSegmentGapPreview(startUs: nearestClipStartUs)
    }

    private var importedSegmentDebugSnapshot: ImportedSegmentDropDebugSnapshot? {
        guard
            let importedSegmentDropTimeUs
        else {
            return nil
        }

        return importedSegmentDropDebugSnapshot(heldAtUs: importedSegmentDropTimeUs)
    }

    private func importedSegmentDropDebugSnapshot(
        heldAtUs: Int64
    ) -> ImportedSegmentDropDebugSnapshot {
        let trackClips = importedSegmentTrackClips
        guard let nearestClip = nearestClipStart(to: heldAtUs, clips: trackClips) else {
            return ImportedSegmentDropDebugSnapshot(
                heldAtUs: heldAtUs,
                nearestClipStartUs: nil,
                distanceUs: nil,
                shouldInsertBeforeClip: false,
                reason: "no-target-clip"
            )
        }

        let distanceUs = abs(nearestClip.timelineRange.start - heldAtUs)
        let shouldInsertBeforeClip = distanceUs <= 500_000

        return ImportedSegmentDropDebugSnapshot(
            heldAtUs: heldAtUs,
            nearestClipStartUs: nearestClip.timelineRange.start,
            distanceUs: distanceUs,
            shouldInsertBeforeClip: shouldInsertBeforeClip,
            reason: shouldInsertBeforeClip ? "insert-before-nearest-start" : "append-to-end"
        )
    }

    private func nearestClipStart(to heldAtUs: Int64, clips: [Clip]) -> Clip? {
        guard !clips.isEmpty else { return nil }

        var low = 0
        var high = clips.count
        while low < high {
            let mid = (low + high) / 2
            if clips[mid].timelineRange.start < heldAtUs {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let candidateIndices = [max(0, low - 1), min(clips.count - 1, low)]
        let uniqueIndices = Array(Set(candidateIndices)).sorted()
        return uniqueIndices.min(by: { left, right in
            let leftDistance = abs(clips[left].timelineRange.start - heldAtUs)
            let rightDistance = abs(clips[right].timelineRange.start - heldAtUs)
            if leftDistance == rightDistance {
                return clips[left].timelineRange.start < clips[right].timelineRange.start
            }
            return leftDistance < rightDistance
        }).map { clips[$0] }
    }

    private func logImportedSegmentDragStateIfNeeded() {
        guard isImportedSegmentTargeted else { return }

        guard let snapshot = importedSegmentDebugSnapshot else {
            let summary = "semantic drag no-clip-start-target held=\(formatDebugTime(importedSegmentDropTimeUs))"
            guard summary != lastImportedSegmentDebugSummary else { return }
            lastImportedSegmentDebugSummary = summary
            EditorDebugTrace.log("TimelineSectionView", summary)
            return
        }

        let summary = [
            "semantic drag",
            "held=\(formatDebugTime(snapshot.heldAtUs))",
            "nearest-start=\(formatDebugTime(snapshot.nearestClipStartUs))",
            "distance=\(formatDebugTime(snapshot.distanceUs))",
            "insert-before=\(snapshot.shouldInsertBeforeClip)",
            "reason=\(snapshot.reason)"
        ].joined(separator: " ")

        guard summary != lastImportedSegmentDebugSummary else { return }
        lastImportedSegmentDebugSummary = summary
        EditorDebugTrace.log("TimelineSectionView", summary)
    }

    private func formatDebugTime(_ timeUs: Int64?) -> String {
        guard let timeUs else { return "nil" }
        return String(format: "%.3fs", Double(timeUs) / 1_000_000)
    }
}

private struct ScrollTargetMarkerView: View {
    static let markerId = "scrollTargetMarker"
    let targetTimeUs: Int64?
    let pixelsPerSecond: CGFloat
    let centerX: CGFloat

    var body: some View {
        Group {
            if let targetTimeUs {
                let targetX = max(0, CGFloat(targetTimeUs) / 1_000_000 * pixelsPerSecond)
                let markerPosition = targetX + centerX
                Color.clear
                    .frame(width: markerPosition + 1, height: 1)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: markerPosition, height: 1)
                            Color.clear.frame(width: 1, height: 1).id(Self.markerId)
                        }
                    }
            } else {
                Color.clear.frame(width: 1, height: 1).id(Self.markerId)
            }
        }
        .task(id: targetTimeUs) {}
    }
}

private struct ImportedSegmentInsertionIndicator: View {
    let color: Color
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)

            Rectangle()
                .fill(color)
                .frame(width: 3, height: max(0, height - 10))
                .shadow(color: color.opacity(0.35), radius: 3)
        }
        .frame(width: 14, height: height, alignment: .top)
    }
}

private struct ImportedSegmentGapPreview {
    let startUs: Int64
}

private struct ImportedSegmentDropDebugSnapshot {
    let heldAtUs: Int64
    let nearestClipStartUs: Int64?
    let distanceUs: Int64?
    let shouldInsertBeforeClip: Bool
    let reason: String
}

private struct ImportedSegmentDropDelegate: DropDelegate {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    @Binding var dropTimeUs: Int64?
    let onDropImportedSegmentAtTime: ((ImportedTimelineSegment, Int64) -> Void)?
    let resolveDropTimeUs: (CGFloat) -> Int64

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && info.hasItemsConforming(to: [TimelineSectionView.importedSegmentType])
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        isTargeted = true
        dropTimeUs = resolveDropTimeUs(info.location.x)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return nil }
        isTargeted = true
        dropTimeUs = resolveDropTimeUs(info.location.x)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        dropTimeUs = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard
            isEnabled,
            let onDropImportedSegmentAtTime,
            let provider = info.itemProviders(for: [TimelineSectionView.importedSegmentType]).first
        else {
            isTargeted = false
            dropTimeUs = nil
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: TimelineSectionView.importedSegmentType.identifier) { data, _ in
            guard
                let data,
                let item = try? JSONDecoder().decode(ImportedTimelineSegment.self, from: data)
            else { return }

            let resolvedTimeUs = resolveDropTimeUs(info.location.x)

            DispatchQueue.main.async {
                onDropImportedSegmentAtTime(item, resolvedTimeUs)
            }
        }

        isTargeted = false
        dropTimeUs = nil
        return true
    }
}
