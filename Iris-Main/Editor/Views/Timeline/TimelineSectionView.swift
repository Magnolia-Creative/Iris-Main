import SwiftUI

struct TimelineSectionView: View {
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
    let onAddSelection: (TrackKind, ImportSource) -> Void
    let onMoveClip: (String, Int64, [String]) -> Void
    let onTrimClip: (String, TimeRange, TimeRange, Bool) -> Void
    var showAddButton: Bool = true

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

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let stackHeight = layout.trackStackHeight(for: tracks)
            let timelineWidth = CGFloat(max(0, scrollableDurationUs)) / 1_000_000 * pixelsPerSecond

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

                                TimelineTracksContent(
                                    tracks: tracks, clipsByTrackId: clipsByTrackId,
                                    mediaById: mediaById, layout: layout, pixelsPerSecond: pixelsPerSecond,
                                    onMoveClip: onMoveClip, onTrimClip: onTrimClip,
                                    viewportWidth: geometry.size.width, contentWidth: timelineWidth,
                                    scrollOffset: $sharedScrollOffset, selectedClipId: $selectedClipId,
                                    onAutoScroll: updateAutoScroll(direction:),
                                    isUserScrolling: isUserScrolling
                                )
                                .padding(.top, layout.trackTopOffset)
                            }
                            .padding(.leading, centerX)
                            .padding(.trailing, centerX)

                            ScrollTargetMarkerView(
                                targetTimeUs: scrollTargetTimeUs,
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
                        if !isAutoScrolling, scrollTargetTimeUs != nil {
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
                            if !isAutoScrolling { markUserScrolling() }
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

                PlayheadView().padding(.top, 27)

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

                if isAddMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { isAddMenuOpen = false }
                        }
                        .ignoresSafeArea()
                }

                if showAddButton {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            AddClipButton(onSelect: onAddSelection, isMenuOpen: $isAddMenuOpen)
                                .padding(.trailing, .spacing(.sp6))
                                .offset(x: isScrollingFast ? .spacing(.sp8) : 0)
                                .opacity(isScrollingFast ? 0 : 1)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrollingFast)
                        }
                        Spacer()
                    }
                }
            }
        }
        .onDisappear {
            scrollActivityWorkItem?.cancel()
            jumpResetWorkItem?.cancel()
            autoScrollTask?.cancel()
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
